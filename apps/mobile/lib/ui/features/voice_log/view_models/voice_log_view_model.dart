import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../data/services/audio_recorder_service.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../core/user_visible_error.dart';

enum VoiceLogState {
  idle,
  requestingPermission,
  ready,
  recording,
  stopping,
  transcribing,
  transcriptReady,
  agentRunning,
  proposalReady,
  autoCommitted,
  resultReady,
  clarificationRequired,
  error,
}

class VoiceLogUiState {
  const VoiceLogUiState({
    this.phase = VoiceLogState.idle,
    this.errorMessage,
    this.message,
    this.transcript = '',
    this.transcriptFromVoice = false,
    this.recordingDuration = Duration.zero,
    this.proposal,
    this.autoCommittedMeal,
    this.summary,
    this.remaining,
    this.meals,
    this.items,
    this.resolvedItems,
    this.templates,
    this.template,
    this.deleted,
    this.confirmationActionId,
    this.confirmationInput,
    this.clarificationOptions,
    this.candidateGroups,
    this.selectedCandidateItems = const {},
    this.showProposalChangeSuccess = false,
  });

  final VoiceLogState phase;
  final String? errorMessage;
  final String? message;
  final String transcript;
  final bool transcriptFromVoice;
  final Duration recordingDuration;
  final MealProposal? proposal;
  final Meal? autoCommittedMeal;
  final DailySummary? summary;
  final NutritionSnapshot? remaining;
  final List<Meal>? meals;
  final List<MealItem>? items;
  final List<MealItem>? resolvedItems;
  final List<MealTemplate>? templates;
  final MealTemplate? template;
  final bool? deleted;
  final String? confirmationActionId;
  final Object? confirmationInput;
  final List<FoodCandidateGroup>? clarificationOptions;
  final List<FoodCandidateGroup>? candidateGroups;
  final Map<String, MealItem> selectedCandidateItems;
  final bool showProposalChangeSuccess;

  bool get isLoading =>
      phase == VoiceLogState.transcribing ||
      phase == VoiceLogState.agentRunning ||
      phase == VoiceLogState.stopping;

  VoiceLogUiState copyWith({
    VoiceLogState? phase,
    Object? errorMessage = _unchanged,
    Object? message = _unchanged,
    String? transcript,
    bool? transcriptFromVoice,
    Duration? recordingDuration,
    Object? proposal = _unchanged,
    Object? autoCommittedMeal = _unchanged,
    Object? summary = _unchanged,
    Object? remaining = _unchanged,
    Object? meals = _unchanged,
    Object? items = _unchanged,
    Object? resolvedItems = _unchanged,
    Object? templates = _unchanged,
    Object? template = _unchanged,
    Object? deleted = _unchanged,
    Object? confirmationActionId = _unchanged,
    Object? confirmationInput = _unchanged,
    Object? clarificationOptions = _unchanged,
    Object? candidateGroups = _unchanged,
    Map<String, MealItem>? selectedCandidateItems,
    bool? showProposalChangeSuccess,
  }) {
    return VoiceLogUiState(
      phase: phase ?? this.phase,
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
      message:
          identical(message, _unchanged) ? this.message : message as String?,
      transcript: transcript ?? this.transcript,
      transcriptFromVoice: transcriptFromVoice ?? this.transcriptFromVoice,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      proposal: identical(proposal, _unchanged)
          ? this.proposal
          : proposal as MealProposal?,
      autoCommittedMeal: identical(autoCommittedMeal, _unchanged)
          ? this.autoCommittedMeal
          : autoCommittedMeal as Meal?,
      summary: identical(summary, _unchanged)
          ? this.summary
          : summary as DailySummary?,
      remaining: identical(remaining, _unchanged)
          ? this.remaining
          : remaining as NutritionSnapshot?,
      meals: identical(meals, _unchanged) ? this.meals : meals as List<Meal>?,
      items:
          identical(items, _unchanged) ? this.items : items as List<MealItem>?,
      resolvedItems: identical(resolvedItems, _unchanged)
          ? this.resolvedItems
          : resolvedItems as List<MealItem>?,
      templates: identical(templates, _unchanged)
          ? this.templates
          : templates as List<MealTemplate>?,
      template: identical(template, _unchanged)
          ? this.template
          : template as MealTemplate?,
      deleted: identical(deleted, _unchanged) ? this.deleted : deleted as bool?,
      confirmationActionId: identical(confirmationActionId, _unchanged)
          ? this.confirmationActionId
          : confirmationActionId as String?,
      confirmationInput: identical(confirmationInput, _unchanged)
          ? this.confirmationInput
          : confirmationInput,
      clarificationOptions: identical(clarificationOptions, _unchanged)
          ? this.clarificationOptions
          : clarificationOptions as List<FoodCandidateGroup>?,
      candidateGroups: identical(candidateGroups, _unchanged)
          ? this.candidateGroups
          : candidateGroups as List<FoodCandidateGroup>?,
      selectedCandidateItems:
          selectedCandidateItems ?? this.selectedCandidateItems,
      showProposalChangeSuccess:
          showProposalChangeSuccess ?? this.showProposalChangeSuccess,
    );
  }
}

const Object _unchanged = Object();

class VoiceLogViewModel extends ChangeNotifier {
  VoiceLogViewModel({
    required NutritionRepository nutritionRepository,
    AudioRecorderService? audioRecorderService,
    DateTime Function()? now,
  })  : _nutritionRepository = nutritionRepository,
        _audioRecorderService = audioRecorderService ?? AudioRecorderService(),
        _now = now ?? DateTime.now;

  static const proposalChangeSuccessDuration = Duration(milliseconds: 2500);

  final NutritionRepository _nutritionRepository;
  final AudioRecorderService _audioRecorderService;
  final DateTime Function() _now;

  VoiceLogUiState _uiState = const VoiceLogUiState();
  VoiceLogUiState get uiState => _uiState;

  VoiceLogState get state => _uiState.phase;

  String? get errorMessage => _uiState.errorMessage;

  String? get message => _uiState.message;

  String get transcript => _uiState.transcript;

  bool get hasVoiceTranscript =>
      _uiState.transcriptFromVoice && _uiState.transcript.trim().isNotEmpty;

  Duration get recordingDuration => _uiState.recordingDuration;

  Timer? _durationTimer;
  Timer? _proposalChangeSuccessTimer;
  DateTime? _recordingStartedAt;

  MealProposal? get proposal => _uiState.proposal;

  Meal? get autoCommittedMeal => _uiState.autoCommittedMeal;

  DailySummary? get summary => _uiState.summary;

  NutritionSnapshot? get remaining => _uiState.remaining;

  List<Meal>? get meals => _uiState.meals;

  List<MealItem>? get items => _uiState.items;

  List<MealItem>? get resolvedItems => _uiState.resolvedItems;

  List<MealTemplate>? get templates => _uiState.templates;

  MealTemplate? get template => _uiState.template;

  List<FoodCandidateGroup>? get candidateGroups => _uiState.candidateGroups;

  List<FoodCandidateGroup>? get clarificationOptions =>
      _uiState.clarificationOptions;

  bool get showProposalChangeSuccess => _uiState.showProposalChangeSuccess;

  MealItem? selectedCandidateFor(FoodCandidateGroup group) {
    return _uiState.selectedCandidateItems[_candidateGroupKey(group)];
  }

  bool isCandidateSelected(FoodCandidateGroup group, MealItem candidate) {
    final selected = selectedCandidateFor(group);
    if (selected == null) return false;
    if (identical(selected, candidate)) return true;
    if (selected.externalId != null && candidate.externalId != null) {
      return selected.externalId == candidate.externalId &&
          selected.externalSource == candidate.externalSource;
    }
    return selected.name == candidate.name &&
        selected.source == candidate.source &&
        selected.quantity == candidate.quantity &&
        selected.unit == candidate.unit;
  }

  bool get isLoading => _uiState.isLoading;

  bool get canStartRecording => _canStartRecording;

  bool get canStopRecording => state == VoiceLogState.recording;

  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 10,
  }) {
    return _nutritionRepository.searchFoods(query, limit: limit);
  }

  Future<void> toggleRecording({bool submitAfterTranscription = false}) async {
    if (_canStartRecording) {
      await startRecording();
    } else if (state == VoiceLogState.recording) {
      await stopRecording(submitAfterTranscription: submitAfterTranscription);
    }
  }

  Future<void> startRecording() {
    if (!_canStartRecording) return Future.value();
    return _startRecording();
  }

  Future<void> stopRecording({bool submitAfterTranscription = false}) {
    if (state != VoiceLogState.recording) return Future.value();
    return _stopRecording(submitAfterTranscription: submitAfterTranscription);
  }

  Future<void> toggleGlobalRecording() {
    return toggleRecording(submitAfterTranscription: true);
  }

  bool get _canStartRecording =>
      state == VoiceLogState.idle ||
      state == VoiceLogState.ready ||
      state == VoiceLogState.transcriptReady ||
      state == VoiceLogState.error ||
      state == VoiceLogState.proposalReady ||
      state == VoiceLogState.autoCommitted ||
      state == VoiceLogState.resultReady ||
      state == VoiceLogState.clarificationRequired;

  Future<void> _startRecording() async {
    if (!_canStartRecording) return;
    _cancelRecordingTimer();
    final activeProposal = _uiState.proposal;
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.requestingPermission,
        transcript: '',
        transcriptFromVoice: false,
        errorMessage: null,
        message: null,
        proposal: activeProposal,
        autoCommittedMeal: null,
        summary: null,
        remaining: null,
        meals: null,
        items: null,
        resolvedItems: null,
        templates: null,
        template: null,
        deleted: null,
        confirmationActionId: null,
        confirmationInput: null,
        clarificationOptions: null,
        candidateGroups:
            activeProposal == null ? null : _uiState.candidateGroups,
        selectedCandidateItems:
            activeProposal == null ? const {} : _uiState.selectedCandidateItems,
        showProposalChangeSuccess: false,
      ),
    );
    try {
      await _audioRecorderService.start();
      _recordingStartedAt = _now();
      _setUiState(
        _uiState.copyWith(
          phase: VoiceLogState.recording,
          recordingDuration: Duration.zero,
        ),
      );
      _durationTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _syncRecordingDuration(),
      );
    } on RecorderException catch (e) {
      _cancelRecordingTimer();
      if (e.code == 'permission_denied') {
        _setError('Microphone permission is required to record voice logs.');
      } else {
        _setError(
          e.message ??
              userVisibleErrorMessage(
                e,
                context: UserErrorContext.voiceRecording,
              ),
        );
      }
    } catch (e) {
      _cancelRecordingTimer();
      _setError(
        userVisibleErrorMessage(e, context: UserErrorContext.voiceRecording),
      );
    }
  }

  Future<void> _stopRecording({bool submitAfterTranscription = false}) async {
    _cancelRecordingTimer();
    _setState(VoiceLogState.stopping);
    try {
      final audio = await _audioRecorderService.stop();
      if (audio != null) {
        await _transcribe(
          audio.path,
          submitAfterTranscription: submitAfterTranscription,
        );
      } else {
        _setError('No audio file was created.');
      }
    } on RecorderException catch (e) {
      _setError(
        e.message ??
            userVisibleErrorMessage(
              e,
              context: UserErrorContext.voiceRecording,
            ),
      );
    } catch (e) {
      _setError(
        userVisibleErrorMessage(e, context: UserErrorContext.voiceRecording),
      );
    }
  }

  Future<void> _transcribe(
    String path, {
    bool submitAfterTranscription = false,
  }) async {
    _setState(VoiceLogState.transcribing);
    final activeProposal = _uiState.proposal;
    try {
      if (submitAfterTranscription) {
        final voiceResult = activeProposal == null
            ? await _nutritionRepository.logAudio(File(path))
            : await _nutritionRepository.logAudio(
                File(path),
                activeProposalId: activeProposal.id,
              );
        _setUiState(
          _uiState.copyWith(
            transcript: voiceResult.transcript,
            transcriptFromVoice: true,
            errorMessage: null,
          ),
        );
        _applyAgentRunResult(
          voiceResult.result,
          fallbackProposal: activeProposal,
        );
      } else {
        final transcript = await _nutritionRepository.transcribeAudio(
          File(path),
        );
        _setUiState(
          _uiState.copyWith(
            transcript: transcript,
            transcriptFromVoice: true,
            errorMessage: null,
          ),
        );
        _setState(VoiceLogState.transcriptReady);
      }
    } catch (e) {
      _setError(
        submitAfterTranscription
            ? userVisibleErrorMessage(e, context: UserErrorContext.voiceMeal)
            : userVisibleErrorMessage(
                e,
                context: UserErrorContext.voiceTranscription,
              ),
      );
    } finally {
      try {
        await File(path).delete();
      } catch (_) {
        // ignore cleanup errors
      }
    }
  }

  void updateTranscript(String value) {
    _setUiState(
      _uiState.copyWith(transcript: value, transcriptFromVoice: false),
    );
  }

  Future<void> submitText([String? overrideText]) async {
    final text = (overrideText ?? _uiState.transcript).trim();
    if (text.isEmpty) return;
    final activeProposal = _uiState.proposal;
    final keepVoiceTranscript = overrideText == null &&
        _uiState.transcriptFromVoice &&
        text == _uiState.transcript.trim();
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.agentRunning,
        transcript: text,
        transcriptFromVoice: keepVoiceTranscript,
        errorMessage: null,
        message: null,
        proposal: activeProposal,
        autoCommittedMeal: null,
        summary: null,
        remaining: null,
        meals: null,
        items: null,
        resolvedItems: null,
        templates: null,
        template: null,
        deleted: null,
        confirmationActionId: null,
        confirmationInput: null,
        clarificationOptions: null,
        candidateGroups:
            activeProposal == null ? null : _uiState.candidateGroups,
        selectedCandidateItems:
            activeProposal == null ? const {} : _uiState.selectedCandidateItems,
        showProposalChangeSuccess: false,
      ),
    );
    try {
      final result = activeProposal == null
          ? await _nutritionRepository.logText(text)
          : await _nutritionRepository.logText(
              text,
              activeProposalId: activeProposal.id,
            );
      _applyAgentRunResult(result, fallbackProposal: activeProposal);
    } catch (error) {
      _setError(
        userVisibleErrorMessage(error, context: UserErrorContext.voiceAgent),
      );
    }
  }

  void _applyAgentRunResult(
    AgentRunResult result, {
    MealProposal? fallbackProposal,
  }) {
    final activeProposalBeforeResult = fallbackProposal ?? _uiState.proposal;
    VoiceLogState nextState;
    switch (result.kind) {
      case 'meal_committed':
        nextState = VoiceLogState.autoCommitted;
        break;
      case 'proposal':
        nextState = VoiceLogState.proposalReady;
        break;
      case 'clarification_required':
      case 'confirmation_required':
        nextState = VoiceLogState.clarificationRequired;
        break;
      case 'summary':
      case 'remaining_targets':
      case 'history':
      case 'food_memory':
      case 'nutrition_search':
      case 'templates':
      case 'template_saved':
      case 'template_deleted':
      case 'meal_deleted':
      case 'meal_corrected':
        nextState = VoiceLogState.resultReady;
        break;
      default:
        nextState = VoiceLogState.clarificationRequired;
    }
    final visibleOptions = result.clarificationOptions ??
        (result.kind == 'clarification_required'
            ? result.candidateGroups
            : null);
    final incomingCandidateGroups = result.candidateGroups ?? visibleOptions;
    final shouldPreserveCandidateGroups = _uiState.proposal != null ||
        fallbackProposal != null ||
        result.proposal != null;
    final candidateGroups = shouldPreserveCandidateGroups
        ? _mergeCandidateGroups(
            _uiState.candidateGroups, incomingCandidateGroups)
        : incomingCandidateGroups;
    final resolvedItemsForSelection =
        result.resolvedItems ?? result.proposal?.items;
    final selectedCandidateItems = {
      if (shouldPreserveCandidateGroups) ..._uiState.selectedCandidateItems,
      ..._defaultCandidateSelections(
        groups: candidateGroups,
        resolvedItems: resolvedItemsForSelection,
      ),
    };
    final proposal = result.proposal ??
        (result.kind == 'clarification_required' ? fallbackProposal : null);
    final showProposalChangeSuccess = result.kind == 'proposal' &&
        activeProposalBeforeResult != null &&
        result.proposal != null;
    _setUiState(
      _uiState.copyWith(
        phase: nextState,
        proposal: proposal,
        autoCommittedMeal: result.meal,
        summary: result.summary,
        remaining: result.remaining,
        meals: result.meals,
        items: result.items,
        resolvedItems: result.resolvedItems,
        templates: result.templates,
        template: result.template,
        deleted: result.deleted,
        message: result.message,
        errorMessage: null,
        confirmationActionId: result.actionId,
        confirmationInput: result.input,
        clarificationOptions: visibleOptions,
        candidateGroups: candidateGroups,
        selectedCandidateItems: selectedCandidateItems,
        showProposalChangeSuccess: showProposalChangeSuccess,
      ),
    );
    if (showProposalChangeSuccess) _scheduleProposalChangeSuccessDismissal();
  }

  Future<void> commitProposal({MealLabel? mealLabel}) async {
    final proposal = _uiState.proposal;
    if (proposal == null) return;
    _proposalChangeSuccessTimer?.cancel();
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.agentRunning,
        showProposalChangeSuccess: false,
      ),
    );
    try {
      final meal = await _nutritionRepository.commitProposal(
        proposal.id,
        mealLabel: mealLabel,
      );
      _setUiState(
        _uiState.copyWith(
          phase: VoiceLogState.autoCommitted,
          autoCommittedMeal: meal,
          proposal: null,
          message: 'Meal logged.',
          errorMessage: null,
          showProposalChangeSuccess: false,
        ),
      );
    } catch (error) {
      _setError(
        userVisibleErrorMessage(error, context: UserErrorContext.voiceCommit),
      );
    }
  }

  Future<void> updateProposalItems(List<MealItem> items) async {
    final proposal = _uiState.proposal;
    if (proposal == null) return;
    _setState(VoiceLogState.agentRunning);
    try {
      final updated = await _nutritionRepository.updateProposalItems(
        proposal.id,
        items,
      );
      final hasChanges = !_mealProposalsMateriallyEqual(proposal, updated);
      _setUiState(
        _uiState.copyWith(
          phase: VoiceLogState.proposalReady,
          proposal: updated,
          message: hasChanges ? 'Proposal updated.' : null,
          errorMessage: null,
          showProposalChangeSuccess: hasChanges,
        ),
      );
      if (hasChanges) {
        _scheduleProposalChangeSuccessDismissal();
      } else {
        _proposalChangeSuccessTimer?.cancel();
      }
    } catch (error) {
      _setError(
        userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceProposalEdit,
        ),
      );
    }
  }

  Future<void> createProposalFromManualItems(List<MealItem> items) async {
    if (items.isEmpty) return;
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.agentRunning,
        transcript: '',
        transcriptFromVoice: false,
        errorMessage: null,
        message: null,
        proposal: null,
        autoCommittedMeal: null,
        summary: null,
        remaining: null,
        meals: null,
        items: null,
        resolvedItems: null,
        templates: null,
        template: null,
        deleted: null,
        confirmationActionId: null,
        confirmationInput: null,
        clarificationOptions: null,
        candidateGroups: null,
        selectedCandidateItems: const {},
        showProposalChangeSuccess: false,
      ),
    );
    try {
      final proposal = await _nutritionRepository.createProposalFromItems(
        phrase: _manualFoodPhrase(items),
        items: items,
      );
      _setUiState(
        _uiState.copyWith(
          phase: VoiceLogState.proposalReady,
          proposal: proposal,
          message: 'Meal proposal created.',
          errorMessage: null,
        ),
      );
    } catch (error) {
      _setError(
        userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceProposalEdit,
        ),
      );
    }
  }

  Future<void> selectCandidate(
    FoodCandidateGroup group,
    MealItem candidate,
  ) async {
    final groups = _uiState.candidateGroups ?? const <FoodCandidateGroup>[];
    final visibleGroups =
        _uiState.clarificationOptions ?? const <FoodCandidateGroup>[];
    final previousSelection = selectedCandidateFor(group);
    final selections = Map<String, MealItem>.of(_uiState.selectedCandidateItems)
      ..[_candidateGroupKey(group)] = candidate;
    _setUiState(_uiState.copyWith(selectedCandidateItems: selections));
    if (previousSelection != null &&
        _sameMealItem(previousSelection, candidate)) {
      return;
    }

    final requiredGroups =
        visibleGroups.where(_needsCandidateSelection).toList();
    if (!requiredGroups.every(
      (group) => selections.containsKey(_candidateGroupKey(group)),
    )) {
      return;
    }

    final selectedItems = _itemsWithCandidateSelections(
      groups: groups,
      selections: selections,
    );
    final activeProposal = _uiState.proposal;
    _setState(VoiceLogState.agentRunning);
    try {
      final proposal = activeProposal == null
          ? await _nutritionRepository.createProposalFromItems(
              phrase: _uiState.transcript,
              items: selectedItems,
            )
          : await _nutritionRepository.updateProposalItems(
              activeProposal.id,
              _proposalItemsWithCandidateSelections(
                proposalItems: activeProposal.items,
                groups: groups,
                selections: selections,
              ),
            );
      _setUiState(
        _uiState.copyWith(
          phase: VoiceLogState.proposalReady,
          proposal: proposal,
          message: activeProposal == null
              ? 'Meal proposal created.'
              : 'Proposal updated.',
          errorMessage: null,
          resolvedItems: null,
          clarificationOptions: null,
          candidateGroups: groups,
          selectedCandidateItems: selections,
          showProposalChangeSuccess: activeProposal != null,
        ),
      );
      if (activeProposal != null) _scheduleProposalChangeSuccessDismissal();
    } catch (error) {
      _setError(
        userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceCandidateSelection,
        ),
      );
    }
  }

  void clearResult() {
    _proposalChangeSuccessTimer?.cancel();
    _setUiState(const VoiceLogUiState());
  }

  void retry() {
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.idle,
        errorMessage: null,
        showProposalChangeSuccess: false,
      ),
    );
  }

  void _setState(VoiceLogState value) {
    _setUiState(_uiState.copyWith(phase: value));
  }

  void _setError(String message) {
    _proposalChangeSuccessTimer?.cancel();
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.error,
        errorMessage: message,
        showProposalChangeSuccess: false,
      ),
    );
  }

  void _scheduleProposalChangeSuccessDismissal() {
    _proposalChangeSuccessTimer?.cancel();
    _proposalChangeSuccessTimer = Timer(proposalChangeSuccessDuration, () {
      if (!_uiState.showProposalChangeSuccess) return;
      _setUiState(_uiState.copyWith(showProposalChangeSuccess: false));
    });
  }

  void _setUiState(VoiceLogUiState value) {
    final wasRecording = _uiState.phase == VoiceLogState.recording;
    final isRecording = value.phase == VoiceLogState.recording;
    if (wasRecording && !isRecording) {
      _cancelRecordingTimer();
    }
    _uiState = value;
    notifyListeners();
  }

  void _syncRecordingDuration() {
    final startedAt = _recordingStartedAt;
    if (startedAt == null || _uiState.phase != VoiceLogState.recording) {
      return;
    }
    final elapsed = _now().difference(startedAt);
    if (elapsed.isNegative) return;
    _setUiState(_uiState.copyWith(recordingDuration: elapsed));
  }

  void _cancelRecordingTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _recordingStartedAt = null;
  }

  Map<String, MealItem> _defaultCandidateSelections({
    required List<FoodCandidateGroup>? groups,
    required List<MealItem>? resolvedItems,
  }) {
    if (groups == null || resolvedItems == null) return const {};
    final selections = <String, MealItem>{};
    for (final group in groups) {
      final resolvedItem = _resolvedItemForGroup(group, resolvedItems);
      if (resolvedItem == null) continue;
      final candidate = _matchingCandidateForResolvedItem(group, resolvedItem);
      if (candidate != null) {
        selections[_candidateGroupKey(group)] = candidate;
      }
    }
    return selections;
  }

  List<MealItem> _itemsWithCandidateSelections({
    required List<FoodCandidateGroup> groups,
    required Map<String, MealItem> selections,
  }) {
    final resolvedItems = _uiState.resolvedItems ?? const <MealItem>[];
    final selectedItems = <MealItem>[];
    final representedGroupKeys = <String>{};

    for (final item in resolvedItems) {
      final group = _groupForResolvedItem(item, groups);
      if (group == null) {
        selectedItems.add(item);
        continue;
      }

      final key = _candidateGroupKey(group);
      representedGroupKeys.add(key);
      selectedItems.add(selections[key] ?? item);
    }

    for (final group in groups) {
      final key = _candidateGroupKey(group);
      if (representedGroupKeys.contains(key)) continue;
      final selected = selections[key];
      if (selected != null) selectedItems.add(selected);
    }

    return selectedItems;
  }

  List<MealItem> _proposalItemsWithCandidateSelections({
    required List<MealItem> proposalItems,
    required List<FoodCandidateGroup> groups,
    required Map<String, MealItem> selections,
  }) {
    final items = [...proposalItems];
    for (final group in groups) {
      final selected = selections[_candidateGroupKey(group)];
      if (selected == null) continue;
      final index =
          items.indexWhere((item) => _resolvedItemMatchesGroup(item, group));
      if (index >= 0) {
        items[index] = selected;
      } else if (!items.any((item) => _sameMealItem(item, selected))) {
        items.add(selected);
      }
    }
    return items;
  }

  bool _needsCandidateSelection(FoodCandidateGroup group) {
    if (group.candidates.isEmpty) return true;
    return _resolvedItemForGroup(
          group,
          _uiState.resolvedItems ?? const <MealItem>[],
        ) ==
        null;
  }

  MealItem? _resolvedItemForGroup(
    FoodCandidateGroup group,
    List<MealItem> resolvedItems,
  ) {
    for (final item in resolvedItems) {
      if (_resolvedItemMatchesGroup(item, group)) return item;
    }
    return null;
  }

  FoodCandidateGroup? _groupForResolvedItem(
    MealItem item,
    List<FoodCandidateGroup> groups,
  ) {
    for (final group in groups) {
      if (_resolvedItemMatchesGroup(item, group)) return group;
    }
    return null;
  }

  bool _resolvedItemMatchesGroup(MealItem item, FoodCandidateGroup group) {
    return item.canonicalName == group.mention.canonicalName &&
        item.quantity == group.mention.quantity &&
        item.unit == group.mention.unit;
  }

  MealItem? _matchingCandidateForResolvedItem(
    FoodCandidateGroup group,
    MealItem resolvedItem,
  ) {
    for (final candidate in group.candidates) {
      if (_sameMealItem(candidate, resolvedItem)) return candidate;
    }
    return null;
  }

  bool _sameMealItem(MealItem a, MealItem b) {
    if (a.externalId != null && b.externalId != null) {
      return a.externalId == b.externalId &&
          a.externalSource == b.externalSource;
    }
    return a.name == b.name &&
        a.source == b.source &&
        a.quantity == b.quantity &&
        a.unit == b.unit;
  }

  bool _mealProposalsMateriallyEqual(MealProposal a, MealProposal b) {
    return _normalizedText(a.title) == _normalizedText(b.title) &&
        a.nutrition.calories == b.nutrition.calories &&
        _sameNumber(a.nutrition.proteinGrams, b.nutrition.proteinGrams) &&
        _sameNumber(a.nutrition.carbsGrams, b.nutrition.carbsGrams) &&
        _sameNumber(a.nutrition.fatGrams, b.nutrition.fatGrams) &&
        _mealItemListsMateriallyEqual(a.items, b.items);
  }

  bool _mealItemListsMateriallyEqual(List<MealItem> a, List<MealItem> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!_mealItemsMateriallyEqual(a[index], b[index])) return false;
    }
    return true;
  }

  bool _mealItemsMateriallyEqual(MealItem a, MealItem b) {
    final hasExternalIdentity = a.externalId != null ||
        b.externalId != null ||
        a.externalSource != null ||
        b.externalSource != null;
    if (hasExternalIdentity &&
        (a.externalId != b.externalId ||
            a.externalSource != b.externalSource)) {
      return false;
    }
    return _normalizedText(a.name) == _normalizedText(b.name) &&
        _normalizedText(a.unit) == _normalizedText(b.unit) &&
        _sameNumber(a.quantity, b.quantity) &&
        a.calories == b.calories &&
        _sameNumber(a.proteinGrams, b.proteinGrams) &&
        _sameNumber(a.carbsGrams, b.carbsGrams) &&
        _sameNumber(a.fatGrams, b.fatGrams);
  }

  String _normalizedText(String value) => value.trim().toLowerCase();

  bool _sameNumber(double a, double b) => (a - b).abs() < 0.05;

  String _manualFoodPhrase(List<MealItem> items) {
    return items
        .map(
          (item) =>
              '${_formatQuantityForPhrase(item.quantity)} ${item.unit} ${item.name}',
        )
        .join(', ');
  }

  String _formatQuantityForPhrase(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  }

  List<FoodCandidateGroup>? _mergeCandidateGroups(
    List<FoodCandidateGroup>? existing,
    List<FoodCandidateGroup>? incoming,
  ) {
    if (existing == null || existing.isEmpty) return incoming;
    if (incoming == null || incoming.isEmpty) return existing;
    final merged = <String, FoodCandidateGroup>{
      for (final group in existing) _candidateGroupKey(group): group,
    };
    for (final group in incoming) {
      merged[_candidateGroupKey(group)] = group;
    }
    return merged.values.toList(growable: false);
  }

  String _candidateGroupKey(FoodCandidateGroup group) {
    final mention = group.mention;
    return [
      mention.originalText,
      mention.canonicalName,
      mention.quantity.toStringAsFixed(3),
      mention.unit,
    ].join('|');
  }

  @override
  void dispose() {
    _audioRecorderService.dispose();
    _cancelRecordingTimer();
    _proposalChangeSuccessTimer?.cancel();
    super.dispose();
  }
}
