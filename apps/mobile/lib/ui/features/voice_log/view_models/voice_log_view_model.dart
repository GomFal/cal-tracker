import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../data/services/audio_recorder_service.dart';
import '../../../../data/services/client_telemetry_service.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../generated/api/cal_tracker_api.dart';
import '../../../core/user_visible_error.dart';
import 'voice_log_helpers.dart';
import 'voice_log_timers.dart';

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
    this.usualFoodDraft,
    this.usualMealDraft,
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
  final UsualFoodDraft? usualFoodDraft;
  final UsualMealDraft? usualMealDraft;
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
    Object? usualFoodDraft = _unchanged,
    Object? usualMealDraft = _unchanged,
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
      usualFoodDraft: identical(usualFoodDraft, _unchanged)
          ? this.usualFoodDraft
          : usualFoodDraft as UsualFoodDraft?,
      usualMealDraft: identical(usualMealDraft, _unchanged)
          ? this.usualMealDraft
          : usualMealDraft as UsualMealDraft?,
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
    bool ownsAudioRecorderService = true,
    ClientTelemetryService? telemetryService,
    DateTime Function()? now,
  })  : _nutritionRepository = nutritionRepository,
        _audioRecorderService = audioRecorderService ?? AudioRecorderService(),
        _ownsAudioRecorderService =
            audioRecorderService == null || ownsAudioRecorderService,
        _telemetryService = telemetryService,
        _now = now ?? DateTime.now {
    _timers = VoiceLogTimers(
      onRecordingDurationTick: _onRecordingDurationTick,
      onProposalChangeSuccessExpired: _onProposalChangeSuccessExpired,
      now: _now,
    );
  }

  static const proposalChangeSuccessDuration = Duration(milliseconds: 2500);

  final NutritionRepository _nutritionRepository;
  final AudioRecorderService _audioRecorderService;
  final bool _ownsAudioRecorderService;
  final ClientTelemetryService? _telemetryService;
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

  late final VoiceLogTimers _timers;

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

  UsualFoodDraft? get usualFoodDraft => _uiState.usualFoodDraft;

  UsualMealDraft? get usualMealDraft => _uiState.usualMealDraft;

  bool get showProposalChangeSuccess => _uiState.showProposalChangeSuccess;

  MealItem? selectedCandidateFor(FoodCandidateGroup group) {
    return _uiState.selectedCandidateItems[candidateGroupKey(group)];
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

  Future<FoodSearchResult> searchFoods(String query, {int limit = 10}) {
    return _nutritionRepository.searchFoods(query, limit: limit);
  }

  Future<AgentRunResult?> toggleRecording({
    bool submitAfterTranscription = false,
  }) async {
    if (_canStartRecording) {
      await startRecording();
      return null;
    } else if (state == VoiceLogState.recording) {
      return stopRecording(submitAfterTranscription: submitAfterTranscription);
    }
    return null;
  }

  Future<void> startRecording() {
    if (!_canStartRecording) return Future.value();
    return _startRecording();
  }

  Future<AgentRunResult?> stopRecording({
    bool submitAfterTranscription = false,
  }) {
    if (state != VoiceLogState.recording) return Future.value();
    return _stopRecording(submitAfterTranscription: submitAfterTranscription);
  }

  Future<AgentRunResult?> toggleGlobalRecording() {
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
    _timers.stopRecordingDuration();
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
        usualFoodDraft: null,
        usualMealDraft: null,
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
      _timers.startRecordingDuration(_now());
      _setUiState(
        _uiState.copyWith(
          phase: VoiceLogState.recording,
          recordingDuration: Duration.zero,
        ),
      );
    } on RecorderException catch (e) {
      _timers.stopRecordingDuration();
      _recordVoiceFailure(
        kind: 'recording_start_failed',
        error: e,
        errorCode: e.code,
        extra: <String, Object?>{'stage': 'start'},
      );
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
      _timers.stopRecordingDuration();
      _recordVoiceFailure(
        kind: 'recording_start_failed',
        error: e,
        extra: <String, Object?>{'stage': 'start'},
      );
      _setError(
        userVisibleErrorMessage(e, context: UserErrorContext.voiceRecording),
      );
    }
  }

  Future<AgentRunResult?> _stopRecording({
    bool submitAfterTranscription = false,
  }) async {
    _timers.stopRecordingDuration();
    _setState(VoiceLogState.stopping);
    try {
      final audio = await _audioRecorderService.stop();
      if (audio != null) {
        return await _transcribe(
          audio.path,
          submitAfterTranscription: submitAfterTranscription,
        );
      } else {
        _recordVoiceFailure(
          kind: 'recording_stop_failed',
          error: 'No audio file was created.',
          errorCode: 'no_audio_file',
          extra: <String, Object?>{'stage': 'stop'},
        );
        _setError('No audio file was created.');
      }
    } on RecorderException catch (e) {
      _recordVoiceFailure(
        kind: 'recording_stop_failed',
        error: e,
        errorCode: e.code,
        extra: <String, Object?>{'stage': 'stop'},
      );
      _setError(
        e.message ??
            userVisibleErrorMessage(
              e,
              context: UserErrorContext.voiceRecording,
            ),
      );
    } catch (e) {
      _recordVoiceFailure(
        kind: 'recording_stop_failed',
        error: e,
        extra: <String, Object?>{'stage': 'stop'},
      );
      _setError(
        userVisibleErrorMessage(e, context: UserErrorContext.voiceRecording),
      );
    }
    return null;
  }

  Future<AgentRunResult?> _transcribe(
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
        return voiceResult.result;
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
      _recordVoiceFailure(
        kind: submitAfterTranscription
            ? 'meal_run_failed'
            : 'transcription_failed',
        error: e,
        errorCode: e is ApiException ? e.code : null,
        extra: <String, Object?>{
          'stage': submitAfterTranscription ? 'meal_run' : 'transcription',
        },
      );
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
    return null;
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
        usualFoodDraft: null,
        usualMealDraft: null,
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
      case 'usual_food_draft':
      case 'usual_meal_draft':
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
        ? mergeCandidateGroups(
            _uiState.candidateGroups,
            incomingCandidateGroups,
          )
        : incomingCandidateGroups;
    final resolvedItemsForSelection =
        result.resolvedItems ?? result.proposal?.items;
    final selectedCandidateItems = {
      if (shouldPreserveCandidateGroups) ..._uiState.selectedCandidateItems,
      ...defaultCandidateSelections(
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
        usualFoodDraft: result.usualFoodDraft,
        usualMealDraft: result.usualMealDraft,
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
    _timers.clearProposalChangeSuccess();
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
    if (proposal == null) {
      await createProposalFromManualItems(items);
      return;
    }
    _setState(VoiceLogState.agentRunning);
    try {
      final updated = await _nutritionRepository.updateProposalItems(
        proposal.id,
        items,
      );
      final hasChanges = !mealProposalsMateriallyEqual(proposal, updated);
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
        _timers.clearProposalChangeSuccess();
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
        usualFoodDraft: null,
        usualMealDraft: null,
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
        phrase: manualFoodPhrase(items),
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
      ..[candidateGroupKey(group)] = candidate;
    _setUiState(_uiState.copyWith(selectedCandidateItems: selections));
    if (previousSelection != null &&
        sameMealItem(previousSelection, candidate)) {
      return;
    }

    final resolvedItemsForCandidateSelection =
        _uiState.resolvedItems ?? const <MealItem>[];
    final requiredGroups = visibleGroups
        .where(
          (group) => needsCandidateSelection(
              group, resolvedItemsForCandidateSelection),
        )
        .toList();
    if (!requiredGroups.every(
      (group) => selections.containsKey(candidateGroupKey(group)),
    )) {
      return;
    }

    final selectedItems = itemsWithCandidateSelections(
      groups: groups,
      selections: selections,
      resolvedItems: resolvedItemsForCandidateSelection,
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
              proposalItemsWithCandidateSelections(
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
    _timers.clearProposalChangeSuccess();
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
    _timers.clearProposalChangeSuccess();
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.error,
        errorMessage: message,
        showProposalChangeSuccess: false,
      ),
    );
  }

  void _scheduleProposalChangeSuccessDismissal() {
    _timers.showProposalChangeSuccess(proposalChangeSuccessDuration);
  }

  void _setUiState(VoiceLogUiState value) {
    final wasRecording = _uiState.phase == VoiceLogState.recording;
    final isRecording = value.phase == VoiceLogState.recording;
    if (wasRecording && !isRecording) {
      _timers.stopRecordingDuration();
    }
    _uiState = value;
    notifyListeners();
  }

  void _onRecordingDurationTick(Duration elapsed) {
    _setUiState(_uiState.copyWith(recordingDuration: elapsed));
  }

  void _onProposalChangeSuccessExpired() {
    if (!_uiState.showProposalChangeSuccess) return;
    _setUiState(_uiState.copyWith(showProposalChangeSuccess: false));
  }

  void _recordVoiceFailure({
    required String kind,
    required Object error,
    String? errorCode,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final telemetry = _telemetryService;
    if (telemetry == null) return;
    telemetry.record(
      ClientTelemetryEvent(
        eventType: 'mobile.voice_$kind',
        flow: 'voice_meal',
        surface: 'mobile',
        severity: 'error',
        status: 'failure',
        errorCode: errorCode,
        errorMessage: error.toString(),
        metadata: extra,
      ),
    );
  }

  @visibleForTesting
  void setPhaseForTest(VoiceLogState phase) => _setState(phase);

  @override
  void dispose() {
    if (_ownsAudioRecorderService) {
      _audioRecorderService.dispose();
    }
    _timers.dispose();
    super.dispose();
  }
}
