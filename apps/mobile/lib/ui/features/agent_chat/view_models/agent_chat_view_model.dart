import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../data/services/agent_chat_cache_store.dart';
import '../../../../data/services/agent_chat_session_store.dart';
import '../../../../data/services/audio_recorder_service.dart';
import '../../../core/user_visible_error.dart';

enum AgentChatToolStatus { running, completed, failed, interrupted }

enum AgentChatEntryKind { user, assistant, tool }

enum AgentChatProposalActionState { idle, saving, succeeded, failed }

enum AgentChatProposalActionType { commit, correct }

class AgentChatProposalAction {
  const AgentChatProposalAction({
    required this.type,
    required this.conversationId,
    required this.entryId,
    required this.sourceToolCallId,
    required this.proposalId,
  });

  final AgentChatProposalActionType type;
  final String conversationId;
  final String entryId;
  final String sourceToolCallId;
  final String proposalId;
}

class AgentChatEntry {
  const AgentChatEntry({
    required this.id,
    required this.kind,
    this.text = '',
    this.toolCall,
    this.toolStatus,
    this.result,
    this.execution,
    this.error,
    this.errorCode,
    this.suggestions = const [],
    this.completionMessage,
  });

  final String id;
  final AgentChatEntryKind kind;
  final String text;
  final AgentToolCallFeedback? toolCall;
  final AgentChatToolStatus? toolStatus;
  final AgentRunResult? result;
  final AgentToolExecutionSnapshot? execution;
  final String? error;
  final String? errorCode;
  final List<AgentChatSuggestion> suggestions;
  final String? completionMessage;

  AgentChatEntry copyWith({
    String? text,
    AgentToolCallFeedback? toolCall,
    AgentChatToolStatus? toolStatus,
    AgentRunResult? result,
    AgentToolExecutionSnapshot? execution,
    String? error,
    String? errorCode,
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
      execution: execution ?? this.execution,
      error: error ?? this.error,
      errorCode: errorCode ?? this.errorCode,
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
  final Set<String> _deletedConversationIds = {};
  final Map<String, AgentChatProposalActionState> _proposalActionStates = {};
  final Map<String, String> _proposalMutationIds = {};
  final Set<String> _committedProposalIds = {};
  String? _correctionProposalId;
  List<AgentChatEntry> get entries => List.unmodifiable(_entries);

  String? conversationId;
  bool isSending = false;
  bool isRecording = false;
  bool isStoppingRecording = false;
  bool isLoadingHistory = false;
  bool isRefreshingHistory = false;
  bool isLoadingConversation = false;
  String? errorMessage;
  String? errorCode;
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

  bool get isBusy =>
      isSending ||
      isStoppingRecording ||
      _proposalActionStates.values.contains(
        AgentChatProposalActionState.saving,
      );

  AgentChatProposalActionState proposalActionState(String proposalId) =>
      _proposalActionStates[proposalId] ?? AgentChatProposalActionState.idle;

  bool isProposalCommitted(String proposalId) =>
      _committedProposalIds.contains(proposalId);

  bool get isCorrectingProposal => _correctionProposalId != null;
  List<AgentConversationSummary> get conversations =>
      List.unmodifiable(_conversations);

  String? get activeProposalId {
    final correction = _correctionProposalId;
    if (correction != null && !_committedProposalIds.contains(correction)) {
      return correction;
    }
    for (final entry in _entries.reversed) {
      final result = entry.result;
      if (result == null) continue;
      if (result.kind == 'meal_committed' ||
          result.kind == 'meal_deleted' ||
          result.kind == 'confirmation_required') {
        return null;
      }
      final proposal = result.proposal;
      if (proposal != null && !_committedProposalIds.contains(proposal.id)) {
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
    final shouldCancelRecording = isRecording || isStoppingRecording;
    _typingTimer?.cancel();
    _typingTimer = null;
    _typingCompleter = null;
    _pendingAssistantText = '';
    _entries.clear();
    _deletedConversationIds.clear();
    _conversations.clear();
    conversationId = null;
    isSending = false;
    isRecording = false;
    isStoppingRecording = false;
    isLoadingHistory = false;
    isRefreshingHistory = false;
    isLoadingConversation = false;
    errorMessage = null;
    errorCode = null;
    statusMessage = null;
    _activeAssistantEntryId = null;
    _entryCounter = 0;
    _proposalActionStates.clear();
    _proposalMutationIds.clear();
    _committedProposalIds.clear();
    _correctionProposalId = null;
    notifyListeners();
    if (shouldCancelRecording) {
      unawaited(_cancelRecordingForLogout());
    }
  }

  Future<void> _cancelRecordingForLogout() async {
    try {
      await _audioRecorderService.cancel();
    } on Object {
      // Recorder cleanup is independent from authentication state teardown.
    }
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
      final visible = await _cacheStore?.excludeDeletedConversations(fresh) ??
          fresh
              .where((item) => !_deletedConversationIds.contains(item.id))
              .toList();
      _replaceConversations(visible);
      await _cacheStore?.writeConversationSummaries(visible);
    } catch (error) {
      if (_conversations.isEmpty) {
        _captureError(error, context: UserErrorContext.voiceAgent);
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
    errorCode = null;
    errorMessage = null;
    notifyListeners();
    try {
      final cached = await _cacheStore?.readConversationDetail(id);
      if (cached != null) {
        _applyConversationDetail(cached);
        notifyListeners();
      }
      final fresh = await _nutritionRepository.getAgentConversation(id);
      if (_deletedConversationIds.contains(id) ||
          await (_cacheStore?.isConversationDeleted(id) ??
              Future.value(false))) {
        return;
      }
      await _cacheStore?.writeConversationDetail(fresh);
      _applyConversationDetail(fresh);
      await _saveActiveSession(unfinished: _isCurrentConversationUnfinished());
    } catch (error) {
      _captureError(error, context: UserErrorContext.voiceAgent);
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
    errorMessage = null;
    errorCode = null;
    if (isRecording) {
      try {
        await _audioRecorderService.cancel();
      } on Object {
        // Continue deletion: recorder cleanup is best-effort and the backend
        // tombstone remains the authoritative privacy operation.
      }
      isRecording = false;
    }
    AgentConversationSummary? summary;
    for (final conversation in _conversations) {
      if (conversation.id == id) {
        summary = conversation;
        break;
      }
    }
    _deletedConversationIds.add(id);
    await _cacheStore?.removeConversation(id);
    _conversations.removeWhere((conversation) => conversation.id == id);
    if (conversationId == id) {
      _clearCurrentConversationState();
      await _sessionStore?.clearActiveSession();
    }
    notifyListeners();
    try {
      await _nutritionRepository.deleteAgentConversation(id);
    } catch (error) {
      _deletedConversationIds.remove(id);
      await _cacheStore?.restoreConversationAfterFailedDeletion(id, summary);
      if (summary != null &&
          !_conversations.any((conversation) => conversation.id == id)) {
        _conversations.add(summary);
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
      _captureError(error, context: UserErrorContext.voiceAgent);
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

  void beginProposalCorrection(AgentChatProposalAction action) {
    if (action.type != AgentChatProposalActionType.correct ||
        isBusy ||
        _committedProposalIds.contains(action.proposalId)) {
      return;
    }
    _correctionProposalId = action.proposalId;
    errorMessage = null;
    errorCode = null;
    statusMessage = null;
    notifyListeners();
  }

  void cancelProposalCorrection() {
    if (_correctionProposalId == null) return;
    _correctionProposalId = null;
    notifyListeners();
  }

  Future<void> commitProposalAction(AgentChatProposalAction action) async {
    if (action.type != AgentChatProposalActionType.commit ||
        proposalActionState(action.proposalId) ==
            AgentChatProposalActionState.saving ||
        _committedProposalIds.contains(action.proposalId)) {
      return;
    }
    _proposalActionStates[action.proposalId] =
        AgentChatProposalActionState.saving;
    errorMessage = null;
    errorCode = null;
    notifyListeners();
    final clientMutationId = _proposalMutationIds.putIfAbsent(
      action.proposalId,
      _newClientMutationId,
    );
    try {
      final committed = await _nutritionRepository.commitAgentChatProposal(
        conversationId: action.conversationId,
        proposalId: action.proposalId,
        sourceToolCallId: action.sourceToolCallId,
        clientMutationId: clientMutationId,
      );
      _committedProposalIds.add(committed.sourceProposalId);
      _proposalActionStates[action.proposalId] =
          AgentChatProposalActionState.succeeded;
      _correctionProposalId = null;
      final result = AgentRunResult(
        kind: 'meal_committed',
        message: 'Meal logged.',
        meal: committed.meal,
        sourceProposalId: committed.sourceProposalId,
      );
      if (!_entries.any(
        (entry) => entry.id == committed.conversationMessage.id,
      )) {
        _entries.add(
          AgentChatEntry(
            id: committed.conversationMessage.id,
            kind: AgentChatEntryKind.tool,
            toolCall: AgentToolCallFeedback(
              id:
                  committed.conversationMessage.toolCallId ??
                  committed.conversationMessage.id,
              actionId: 'commit_meal',
              label: 'Commit meal',
              summary: committed.conversationMessage.content,
            ),
            toolStatus: AgentChatToolStatus.completed,
            result: result,
          ),
        );
      }
      AgentConversationSummary? conversation;
      for (final item in _conversations) {
        if (item.id == action.conversationId) {
          conversation = item;
          break;
        }
      }
      if (conversation != null) {
        await _cacheStore?.upsertConversationMessage(
          conversation,
          committed.conversationMessage,
        );
      }
      await _saveActiveSession(unfinished: false);
    } catch (error) {
      _proposalActionStates[action.proposalId] =
          AgentChatProposalActionState.failed;
      _captureError(error, context: UserErrorContext.voiceCommit);
    } finally {
      notifyListeners();
    }
  }

  String _newClientMutationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
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
    errorCode = null;
    statusMessage = null;
    notifyListeners();
    try {
      await _audioRecorderService.start();
      isRecording = true;
    } on RecorderException catch (error) {
      if (error.code == 'permission_denied') {
        errorCode = 'microphone_permission_denied';
      } else {
        errorMessage = userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceRecording,
        );
      }
    } catch (error) {
      _captureError(error, context: UserErrorContext.voiceRecording);
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording) return;
    isRecording = false;
    isStoppingRecording = true;
    errorCode = null;
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
      _captureError(error, context: UserErrorContext.voiceMeal);
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
    errorCode = null;
    statusMessage = 'Thinking...';
    _activeAssistantEntryId = _nextEntryId('assistant');
    _removeAssistantPlaceholder();
    notifyListeners();
    try {
      await for (final event in stream) {
        _applyEvent(event);
      }
    } catch (error) {
      _captureError(error, context: UserErrorContext.voiceAgent);
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
    final eventConversationId = event.conversationId;
    if (eventConversationId != null &&
        _deletedConversationIds.contains(eventConversationId)) {
      return;
    }
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
      case 'tool_call_completed':
      case 'tool_call_failed':
        final execution = event.execution;
        if (execution != null) {
          _applyToolExecutionSnapshot(execution);
          final cacheStore = _cacheStore;
          if (cacheStore != null && execution.status != 'started') {
            unawaited(cacheStore.mergeToolExecution(execution));
          }
          break;
        }
        final toolCall = event.toolCall;
        if (toolCall == null) break;
        _updateToolEntry(
          toolCall,
          status: event.type == 'tool_call_started'
              ? AgentChatToolStatus.running
              : event.type == 'tool_call_completed'
                  ? AgentChatToolStatus.completed
                  : AgentChatToolStatus.failed,
          result: event.result,
          error: event.error?.message,
          errorCode: event.error?.code,
        );
        break;
      case 'error':
        errorCode = event.error?.code ?? 'internal_error';
        errorMessage = event.error?.message ??
            'We could not complete that request. Try again.';
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

  void _applyToolExecutionSnapshot(
    AgentToolExecutionSnapshot execution, {
    bool rehydrated = false,
  }) {
    final status = switch (execution.status) {
      'completed' => AgentChatToolStatus.completed,
      'failed' => AgentChatToolStatus.failed,
      'interrupted' => AgentChatToolStatus.interrupted,
      _ when rehydrated => AgentChatToolStatus.interrupted,
      _ => AgentChatToolStatus.running,
    };
    _updateToolEntry(
      execution.toolCall,
      status: status,
      result: execution.result,
      error: execution.error?.message,
      errorCode: execution.error?.code,
      execution: execution,
    );
  }

  void _updateToolEntry(
    AgentToolCallFeedback? toolCall, {
    required AgentChatToolStatus status,
    AgentRunResult? result,
    AgentToolExecutionSnapshot? execution,
    String? error,
    String? errorCode,
  }) {
    if (toolCall == null) return;
    final index = _entries.indexWhere(
      (entry) => entry.id == 'tool_${toolCall.id}',
    );
    if (index < 0) {
      _entries.add(
        AgentChatEntry(
          id: 'tool_${toolCall.id}',
          kind: AgentChatEntryKind.tool,
          toolCall: toolCall,
          toolStatus: status,
          result: result,
          execution: execution,
          error: error,
          errorCode: errorCode,
        ),
      );
      return;
    }
    _entries[index] = _entries[index].copyWith(
      toolCall: toolCall,
      toolStatus: status,
      result: result,
      execution: execution,
      error: error,
      errorCode: errorCode,
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
    errorCode = null;
    statusMessage = null;
    _activeAssistantEntryId = null;
    _pendingAssistantText = '';
    _typingTimer?.cancel();
    _typingTimer = null;
    _typingCompleter = null;
    _entryCounter = 0;
    _proposalActionStates.clear();
    _proposalMutationIds.clear();
    _committedProposalIds.clear();
    _correctionProposalId = null;
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
      ..addAll(
        _entriesFromStoredMessages(detail.messages, detail.toolExecutions),
      );
    _entryCounter = _entries.length;
    _committedProposalIds
      ..clear()
      ..addAll(
        _entries
            .map((entry) => entry.result?.sourceProposalId)
            .whereType<String>(),
      );
    _proposalActionStates
      ..clear()
      ..addEntries(
        _committedProposalIds.map(
          (proposalId) => MapEntry(
            proposalId,
            AgentChatProposalActionState.succeeded,
          ),
        ),
      );
    _correctionProposalId = null;
    errorMessage = null;
    errorCode = null;
    statusMessage = null;
    _activeAssistantEntryId = null;
  }

  void _captureError(Object error, {required UserErrorContext context}) {
    errorCode = publicAiErrorCode(error);
    errorMessage = userVisibleErrorMessage(error, context: context);
  }

  List<AgentChatEntry> _entriesFromStoredMessages(
    List<AgentConversationMessage> messages,
    List<AgentToolExecutionSnapshot> executions,
  ) {
    final executionsByToolCall = {
      for (final execution in executions) execution.toolCallId: execution,
    };
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
          final execution = message.toolCallId == null
              ? null
              : executionsByToolCall[message.toolCallId];
          final toolCall =
              execution?.toolCall ?? _toolFeedbackFromStoredMessage(message);
          final status = execution == null
              ? (message.metadata is Map &&
                      (message.metadata as Map)['error'] != null
                  ? AgentChatToolStatus.failed
                  : AgentChatToolStatus.completed)
              : _statusForExecution(execution, rehydrated: true);
          entries.add(
            AgentChatEntry(
              id: 'tool_${message.toolCallId ?? message.id}',
              kind: AgentChatEntryKind.tool,
              toolCall: toolCall,
              toolStatus: status,
              result:
                  execution?.result ?? _resultFromStoredToolMessage(message),
              execution: execution,
              error: execution?.error?.message ??
                  (message.metadata is Map
                      ? (message.metadata as Map)['error'] as String?
                      : null),
              errorCode: execution?.error?.code,
            ),
          );
          break;
      }
    }
    final insertionOffsets = <String, int>{};
    for (final execution in executions) {
      if (entries.any((entry) => entry.id == 'tool_${execution.toolCallId}') ||
          _isPresentationlessCompletedExecution(execution)) {
        continue;
      }
      // A stream can stop after `started` was persisted but before its compact
      // tool transcript is written. Keep it visible without a perpetual loader.
      final assistantIndex = entries.indexWhere(
        (entry) => entry.id == execution.assistantMessageId,
      );
      final offset = insertionOffsets[execution.assistantMessageId] ?? 0;
      final index =
          assistantIndex < 0 ? entries.length : assistantIndex + 1 + offset;
      entries.insert(
        index,
        AgentChatEntry(
          id: 'tool_${execution.toolCallId}',
          kind: AgentChatEntryKind.tool,
          toolCall: execution.toolCall,
          toolStatus: _statusForExecution(execution, rehydrated: true),
          result: execution.result,
          execution: execution,
          error: execution.error?.message,
          errorCode: execution.error?.code,
        ),
      );
      insertionOffsets[execution.assistantMessageId] = offset + 1;
    }
    return entries;
  }

  bool _isPresentationlessCompletedExecution(
    AgentToolExecutionSnapshot execution,
  ) =>
      execution.status == 'completed' &&
      execution.result == null &&
      execution.error == null;

  AgentChatToolStatus _statusForExecution(
    AgentToolExecutionSnapshot execution, {
    required bool rehydrated,
  }) =>
      switch (execution.status) {
        'completed' => AgentChatToolStatus.completed,
        'failed' => AgentChatToolStatus.failed,
        'interrupted' => AgentChatToolStatus.interrupted,
        _ when rehydrated => AgentChatToolStatus.interrupted,
        _ => AgentChatToolStatus.running,
      };

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
    final metadata = message.metadata;
    // Rehydration is presentation-only. It deliberately does not call the
    // repository reconciler, so opening an old conversation cannot replay a
    // historical mutation into currently visible data.
    final persisted = metadata is Map ? metadata['uiResult'] : null;
    final content = _jsonObjectOrNull(message.content);
    final result = persisted ?? content?['result'];
    if (result is Map) {
      try {
        return agentRunResultFromJson(
          result.map((key, value) => MapEntry(key.toString(), value)),
        );
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
        .map(
          (item) => AgentChatSuggestion.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where(
          (suggestion) =>
              suggestion.label.isNotEmpty && suggestion.value.isNotEmpty,
        )
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
