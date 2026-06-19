import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/nutrition_repository.dart';
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
    DateTime Function()? now,
  })  : _nutritionRepository = nutritionRepository,
        _audioRecorderService = audioRecorderService,
        _now = now ?? DateTime.now;

  final NutritionRepository _nutritionRepository;
  final AudioRecorderService _audioRecorderService;
  final DateTime Function() _now;

  final List<AgentChatEntry> _entries = [];
  List<AgentChatEntry> get entries => List.unmodifiable(_entries);

  String? conversationId;
  bool isSending = false;
  bool isRecording = false;
  bool isStoppingRecording = false;
  String? errorMessage;
  String? statusMessage;
  int _entryCounter = 0;
  String? _activeAssistantEntryId;
  Timer? _typingTimer;
  String _pendingAssistantText = '';
  Completer<void>? _typingCompleter;

  static const _typingTick = Duration(milliseconds: 18);
  static const _typingCharsPerTick = 4;

  bool get isBusy => isSending || isStoppingRecording;

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
      notifyListeners();
    }
  }

  void _applyEvent(AgentChatStreamEvent event) {
    conversationId = event.conversationId ?? conversationId;
    switch (event.type) {
      case 'conversation_started':
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
        break;
      case 'done':
        statusMessage = null;
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
}
