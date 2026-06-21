import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../data/services/agent_chat_cache_store.dart';
import '../../../../data/services/agent_chat_session_store.dart';
import '../../../../data/services/audio_recorder_service.dart';
import '../../../core/user_visible_error.dart';

enum AgentChatToolStatus { running, completed, failed }

enum AgentChatEntryKind { user, assistant, tool }

class AgentChatEntry {
  const AgentChatEntry({
    required this.id,
    required this.kind,
    this.text = '',
    this.toolCall,
    this.toolStatus,
    this.result,
    this.error,
    this.suggestions = const [],
    this.completionMessage,
  });

  final String id;
  final AgentChatEntryKind kind;
  final String text;
  final AgentToolCallFeedback? toolCall;
  final AgentChatToolStatus? toolStatus;
  final AgentRunResult? result;
  final String? error;
  final List<AgentChatSuggestion> suggestions;
  final String? completionMessage;

  AgentChatEntry copyWith({
    String? text,
    AgentToolCallFeedback? toolCall,
    AgentChatToolStatus? toolStatus,
    AgentRunResult? result,
    String? error,
    List<AgentChatSuggestion>? suggestions,
    String? completionMessage,
  }) {
    return AgentChatEntry(
      id: id,
      kind: kind,
      text: text ?? this.text,
      toolCall: toolCall ?? this.toolCall,
      toolStatus: toolStatus ?? this.toolStatus,
      result: result ?? this.result,
      error: error ?? this.error,
      suggestions: suggestions ?? this.suggestions,
      completionMessage: completionMessage ?? this.completionMessage,
    );
  }
}

class AgentChatViewModel extends ChangeNotifier {
  AgentChatViewModel({
    required NutritionRepository nutritionRepository,
    required AudioRecorderService audioRecorderService,
    AgentChatSessionStore? sessionStore,
    AgentChatCacheStore? cacheStore,
    DateTime Function()? now,
  })  : _nutritionRepository = nutritionRepository,
        _audioRecorderService = audioRecorderService,
        _sessionStore = sessionStore,
        _cacheStore = cacheStore,
        _now = now ?? DateTime.now;

  final NutritionRepository _nutritionRepository;
  final AudioRecorderService _audioRecorderService;
  final AgentChatSessionStore? _sessionStore;
  final AgentChatCacheStore? _cacheStore;
  final DateTime Function() _now;

  final List<AgentChatEntry> _entries = [];
  List<AgentChatEntry> get entries => List.unmodifiable(_entries);

  String? conversationId;
  bool isSending = false;
  bool isRecording = false;
  bool isStoppingRecording = false;
  bool isLoadingHistory = false;
  bool isRefreshingHistory = false;
  bool isLoadingConversation = false;
  String? errorMessage;
  String? statusMessage;
  final List<AgentConversationSummary> _conversations = [];
  int _entryCounter = 0;
  String? _activeAssistantEntryId;
  Timer? _typingTimer;
  String _pendingAssistantText = '';
  Completer<void>? _typingCompleter;

  static const _typingTick = Duration(milliseconds: 18);
  static const _typingCharsPerTick = 4;
  static const inactivityTimeout = Duration(minutes: 2);

  bool get isBusy => isSending || isStoppingRecording;
  List<AgentConversationSummary> get conversations =>
      List.unmodifiable(_conversations);

  String? get activeProposalId {
    for (final entry in _entries.reversed) {
      final result = entry.result;
      if (result == null) continue;
      if (result.kind == 'meal_committed' ||
          result.kind == 'meal_deleted' ||
          result.kind == 'confirmation_required') {
        return null;
      }
      final proposal = result.proposal;
      if (proposal != null) {
        return proposal.id;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
  }

  void reset() {
    _typingTimer?.cancel();
    _typingTimer = null;
    _typingCompleter = null;
    _pendingAssistantText = '';
    _entries.clear();
    _conversations.clear();
    conversationId = null;
    isSending = false;
    isRecording = false;
    isStoppingRecording = false;
    isLoadingHistory = false;
    isRefreshingHistory = false;
    isLoadingConversation = false;
    errorMessage = null;
    statusMessage = null;
    _activeAssistantEntryId = null;
    _entryCounter = 0;
    notifyListeners();
  }

  Future<void> prepareForEntry() async {
    if (isBusy || isRecording) return;
    if (_sessionStore == null && _cacheStore == null) return;
    unawaited(refreshConversationHistory());
    final session = await _sessionStore?.readActiveSession();
    if (session == null) {
      _clearCurrentConversationState();
      notifyListeners();
      return;
    }
    if (_shouldResumeActiveSession(session, _now())) {
      await loadConversation(session.conversationId);
      return;
    }
    await startNewConversation();
  }

  Future<void> refreshConversationHistory() async {
    if (isRefreshingHistory || isLoadingHistory) return;
    final cached = await _cacheStore?.readConversationSummaries() ?? const [];
    if (cached.isNotEmpty) {
      _replaceConversations(cached);
      isRefreshingHistory = true;
    } else {
      isLoadingHistory = true;
    }
    notifyListeners();
    try {
      final fresh = await _nutritionRepository.listAgentConversations();
      _replaceConversations(fresh);
      await _cacheStore?.writeConversationSummaries(fresh);
    } catch (error) {
      if (_conversations.isEmpty) {
        errorMessage = userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceAgent,
        );
      }
    } finally {
      isLoadingHistory = false;
      isRefreshingHistory = false;
      notifyListeners();
    }
  }

  Future<void> loadConversation(String id) async {
    if (isBusy || isRecording) return;
    isLoadingConversation = true;
    errorMessage = null;
    notifyListeners();
    try {
      final cached = await _cacheStore?.readConversationDetail(id);
      if (cached != null) {
        _applyConversationDetail(cached);
        notifyListeners();
      }
      final fresh = await _nutritionRepository.getAgentConversation(id);
      await _cacheStore?.writeConversationDetail(fresh);
      _applyConversationDetail(fresh);
      await _saveActiveSession(unfinished: _isCurrentConversationUnfinished());
    } catch (error) {
      errorMessage = userVisibleErrorMessage(
        error,
        context: UserErrorContext.voiceAgent,
      );
    } finally {
      isLoadingConversation = false;
      notifyListeners();
    }
  }

  Future<void> startNewConversation() async {
    if (isBusy || isRecording) return;
    _clearCurrentConversationState();
    await _sessionStore?.clearActiveSession();
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    if (isBusy || isRecording) return;
    try {
      await _nutritionRepository.deleteAgentConversation(id);
      await _cacheStore?.removeConversation(id);
      _conversations.removeWhere((conversation) => conversation.id == id);
      if (conversationId == id) {
        _clearCurrentConversationState();
        await _sessionStore?.clearActiveSession();
      }
    } catch (error) {
      errorMessage = userVisibleErrorMessage(
        error,
        context: UserErrorContext.voiceAgent,
      );
    } finally {
      notifyListeners();
    }
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isBusy || isRecording) return;
    _entries.add(
      AgentChatEntry(
        id: _nextEntryId('user'),
        kind: AgentChatEntryKind.user,
        text: trimmed,
      ),
    );
    await _runStream(
      _nutritionRepository.streamAgentChat(
        trimmed,
        conversationId: conversationId,
        activeProposalId: activeProposalId,
      ),
    );
  }

  void dismissSuggestions(String entryId) {
    final index = _entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0 || _entries[index].suggestions.isEmpty) return;
    _entries[index] = _entries[index].copyWith(suggestions: const []);
    notifyListeners();
  }

  void markEntryCompleted(String entryId, String message) {
    final index = _entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) return;
    _entries[index] = _entries[index].copyWith(completionMessage: message);
    notifyListeners();
  }

  Future<void> toggleRecording() async {
    if (isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    if (isBusy || isRecording) return;
    errorMessage = null;
    statusMessage = null;
    notifyListeners();
    try {
      await _audioRecorderService.start();
      isRecording = true;
    } catch (error) {
      errorMessage = userVisibleErrorMessage(
        error,
        context: UserErrorContext.voiceRecording,
      );
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording) return;
    isRecording = false;
    isStoppingRecording = true;
    statusMessage = 'Preparing voice message...';
    notifyListeners();
    String? path;
    try {
      final audio = await _audioRecorderService.stop();
      path = audio?.path;
      if (path == null) throw const RecorderException('missing_audio');
      await _runStream(
        _nutritionRepository.streamAgentChatAudio(
          File(path),
          conversationId: conversationId,
          activeProposalId: activeProposalId,
        ),
      );
    } catch (error) {
      errorMessage = userVisibleErrorMessage(
        error,
        context: UserErrorContext.voiceMeal,
      );
    } finally {
      isStoppingRecording = false;
      statusMessage = null;
      await _saveActiveSession(unfinished: _isCurrentConversationUnfinished());
      notifyListeners();
      if (path != null) {
        try {
          await File(path).delete();
        } on Object {
          // Best-effort temporary audio cleanup.
        }
      }
    }
  }

  Future<void> _runStream(Stream<AgentChatStreamEvent> stream) async {
    isSending = true;
    errorMessage = null;
    statusMessage = 'Thinking...';
    _activeAssistantEntryId = _nextEntryId('assistant');
    _removeAssistantPlaceholder();
    notifyListeners();
    try {
      await for (final event in stream) {
        _applyEvent(event);
      }
    } catch (error) {
      errorMessage = userVisibleErrorMessage(
        error,
        context: UserErrorContext.voiceAgent,
      );
    } finally {
      await _waitForTypingToFinish();
      isSending = false;
      statusMessage = null;
      _removeEmptyAssistantPlaceholder();
      await _saveActiveSession(unfinished: _isCurrentConversationUnfinished());
      unawaited(refreshConversationHistory());
      notifyListeners();
    }
  }

  void _applyEvent(AgentChatStreamEvent event) {
    conversationId = event.conversationId ?? conversationId;
    switch (event.type) {
      case 'conversation_started':
        unawaited(_saveActiveSession(unfinished: true));
        break;
      case 'thinking':
        statusMessage = event.message ?? 'Thinking...';
        break;
      case 'transcription_completed':
        final transcript = event.transcript?.trim() ?? '';
        if (transcript.isNotEmpty) {
          _entries.add(
            AgentChatEntry(
              id: _nextEntryId('user'),
              kind: AgentChatEntryKind.user,
              text: transcript,
            ),
          );
        }
        break;
      case 'assistant_delta':
        final delta = event.delta ?? '';
        if (delta.isNotEmpty) _enqueueAssistantDelta(delta);
        break;
      case 'assistant_suggestions':
        if (event.suggestions.isNotEmpty) {
          _attachSuggestionsToAssistant(event.suggestions);
        }
        break;
      case 'tool_call_started':
        final toolCall = event.toolCall;
        if (toolCall != null) {
          _entries.add(
            AgentChatEntry(
              id: 'tool_${toolCall.id}',
              kind: AgentChatEntryKind.tool,
              toolCall: toolCall,
              toolStatus: AgentChatToolStatus.running,
            ),
          );
        }
        break;
      case 'tool_call_completed':
        _updateToolEntry(
          event.toolCall,
          status: AgentChatToolStatus.completed,
          result: event.result,
        );
        break;
      case 'tool_call_failed':
        _updateToolEntry(
          event.toolCall,
          status: AgentChatToolStatus.failed,
          error: event.error,
        );
        break;
      case 'error':
        errorMessage = event.error ?? 'The agent could not finish.';
        unawaited(_saveActiveSession(unfinished: true));
        break;
      case 'done':
        statusMessage = null;
        unawaited(
          _saveActiveSession(unfinished: _isCurrentConversationUnfinished()),
        );
        break;
    }
    notifyListeners();
  }

  void _enqueueAssistantDelta(String delta) {
    _pendingAssistantText += delta;
    _typingCompleter ??= Completer<void>();
    if (_typingTimer != null) return;
    _typingTimer = Timer.periodic(_typingTick, (_) => _flushTypingTick());
    _flushTypingTick();
  }

  void _flushTypingTick() {
    if (_pendingAssistantText.isEmpty) {
      _typingTimer?.cancel();
      _typingTimer = null;
      final completer = _typingCompleter;
      _typingCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      return;
    }
    final take = _pendingAssistantText.length < _typingCharsPerTick
        ? _pendingAssistantText.length
        : _typingCharsPerTick;
    final chunk = _pendingAssistantText.substring(0, take);
    _pendingAssistantText = _pendingAssistantText.substring(take);
    _appendAssistantDelta(chunk);
    notifyListeners();
  }

  Future<void> _waitForTypingToFinish() async {
    final completer = _typingCompleter;
    if (completer == null) return;
    await completer.future;
  }

  void _appendAssistantDelta(String delta) {
    final entryId = _activeAssistantEntryId ?? _nextEntryId('assistant');
    _activeAssistantEntryId = entryId;
    final last = _entries.isNotEmpty ? _entries.last : null;
    if (last != null && last.id == entryId) {
      _entries[_entries.length - 1] = last.copyWith(text: last.text + delta);
      return;
    }
    _entries.add(
      AgentChatEntry(
        id: entryId,
        kind: AgentChatEntryKind.assistant,
        text: delta,
      ),
    );
  }

  void _attachSuggestionsToAssistant(List<AgentChatSuggestion> suggestions) {
    final entryId = _activeAssistantEntryId;
    final index = entryId == null
        ? -1
        : _entries.indexWhere((entry) => entry.id == entryId);
    if (index >= 0) {
      _entries[index] = _entries[index].copyWith(suggestions: suggestions);
      return;
    }
    _entries.add(
      AgentChatEntry(
        id: entryId ?? _nextEntryId('assistant'),
        kind: AgentChatEntryKind.assistant,
        suggestions: suggestions,
      ),
    );
  }

  void _updateToolEntry(
    AgentToolCallFeedback? toolCall, {
    required AgentChatToolStatus status,
    AgentRunResult? result,
    String? error,
  }) {
    if (toolCall == null) return;
    final index =
        _entries.indexWhere((entry) => entry.id == 'tool_${toolCall.id}');
    if (index < 0) {
      _entries.add(
        AgentChatEntry(
          id: 'tool_${toolCall.id}',
          kind: AgentChatEntryKind.tool,
          toolCall: toolCall,
          toolStatus: status,
          result: result,
          error: error,
        ),
      );
      return;
    }
    _entries[index] = _entries[index].copyWith(
      toolCall: toolCall,
      toolStatus: status,
      result: result,
      error: error,
    );
  }

  void _removeAssistantPlaceholder() {
    final activeId = _activeAssistantEntryId;
    if (activeId == null) return;
    _entries.removeWhere(
      (entry) =>
          entry.id == activeId &&
          entry.text.trim().isEmpty &&
          entry.suggestions.isEmpty &&
          entry.completionMessage == null,
    );
  }

  void _removeEmptyAssistantPlaceholder() => _removeAssistantPlaceholder();

  String _nextEntryId(String prefix) =>
      '${prefix}_${_now().microsecondsSinceEpoch}_${_entryCounter++}';

  bool _shouldResumeActiveSession(AgentChatSession session, DateTime now) {
    if (session.unfinished) return true;
    return now.difference(session.lastInteractionAt) <= inactivityTimeout;
  }

  bool _isCurrentConversationUnfinished() {
    if (isSending || isRecording || isStoppingRecording) return true;
    for (final entry in _entries.reversed) {
      if (entry.kind == AgentChatEntryKind.assistant &&
          entry.suggestions.isNotEmpty) {
        return true;
      }
      final resultKind = entry.result?.kind;
      if (resultKind != null) return _isResultKindUnfinished(resultKind);
      if (entry.kind == AgentChatEntryKind.tool &&
          entry.toolStatus == AgentChatToolStatus.failed) {
        return true;
      }
    }
    return false;
  }

  bool _isResultKindUnfinished(String kind) {
    return {
      'proposal',
      'usual_food_draft',
      'usual_meal_draft',
      'confirmation_required',
      'clarification_required',
    }.contains(kind);
  }

  Future<void> _saveActiveSession({required bool unfinished}) async {
    final id = conversationId;
    if (id == null) return;
    final now = _now();
    await _sessionStore?.writeActiveSession(
      AgentChatSession(
        conversationId: id,
        lastInteractionAt: now,
        lastCompletedAt: unfinished ? null : now,
        unfinished: unfinished,
      ),
    );
  }

  void _clearCurrentConversationState() {
    _entries.clear();
    conversationId = null;
    errorMessage = null;
    statusMessage = null;
    _activeAssistantEntryId = null;
    _pendingAssistantText = '';
    _typingTimer?.cancel();
    _typingTimer = null;
    _typingCompleter = null;
    _entryCounter = 0;
  }

  void _replaceConversations(List<AgentConversationSummary> conversations) {
    _conversations
      ..clear()
      ..addAll(conversations);
  }

  void _applyConversationDetail(AgentConversationDetail detail) {
    conversationId = detail.conversation.id;
    _entries
      ..clear()
      ..addAll(_entriesFromStoredMessages(detail.messages));
    _entryCounter = _entries.length;
    errorMessage = null;
    statusMessage = null;
    _activeAssistantEntryId = null;
  }

  List<AgentChatEntry> _entriesFromStoredMessages(
    List<AgentConversationMessage> messages,
  ) {
    final entries = <AgentChatEntry>[];
    for (final message in messages) {
      switch (message.role) {
        case 'user':
          entries.add(
            AgentChatEntry(
              id: message.id,
              kind: AgentChatEntryKind.user,
              text: message.content,
            ),
          );
          break;
        case 'assistant':
          if (message.content.trim().isEmpty &&
              _suggestionsFromMetadata(message.metadata).isEmpty) {
            break;
          }
          entries.add(
            AgentChatEntry(
              id: message.id,
              kind: AgentChatEntryKind.assistant,
              text: message.content,
              suggestions: _suggestionsFromMetadata(message.metadata),
            ),
          );
          break;
        case 'tool':
          final toolCall = _toolFeedbackFromStoredMessage(message);
          entries.add(
            AgentChatEntry(
              id: 'tool_${message.toolCallId ?? message.id}',
              kind: AgentChatEntryKind.tool,
              toolCall: toolCall,
              toolStatus: message.metadata is Map &&
                      (message.metadata as Map)['error'] != null
                  ? AgentChatToolStatus.failed
                  : AgentChatToolStatus.completed,
              result: _resultFromStoredToolMessage(message),
              error: message.metadata is Map
                  ? (message.metadata as Map)['error'] as String?
                  : null,
            ),
          );
          break;
      }
    }
    return entries;
  }

  AgentToolCallFeedback _toolFeedbackFromStoredMessage(
    AgentConversationMessage message,
  ) {
    final metadata = message.metadata is Map ? message.metadata as Map : null;
    final content = _jsonObjectOrNull(message.content);
    final actionId = metadata?['actionId'] as String? ??
        content?['actionId'] as String? ??
        'agent_action';
    return AgentToolCallFeedback(
      id: message.toolCallId ?? message.id,
      actionId: actionId,
      label: _toolLabelForAction(actionId),
      summary: content?['error'] as String? ?? '',
      input: content?['input'],
    );
  }

  AgentRunResult? _resultFromStoredToolMessage(
    AgentConversationMessage message,
  ) {
    final content = _jsonObjectOrNull(message.content);
    final result = content?['result'];
    if (result is Map<String, Object?>) {
      try {
        return agentRunResultFromJson(result);
      } on Object {
        return null;
      }
    }
    return null;
  }

  List<AgentChatSuggestion> _suggestionsFromMetadata(Object? metadata) {
    if (metadata is! Map) return const [];
    final suggestions = metadata['suggestions'];
    if (suggestions is! List) return const [];
    return suggestions
        .whereType<Map>()
        .map((item) => AgentChatSuggestion.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .where((suggestion) =>
            suggestion.label.isNotEmpty && suggestion.value.isNotEmpty)
        .toList();
  }

  Map<String, Object?>? _jsonObjectOrNull(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      return decoded.map((key, nested) => MapEntry(key.toString(), nested));
    } on Object {
      return null;
    }
  }

  String _toolLabelForAction(String actionId) {
    return actionId
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
