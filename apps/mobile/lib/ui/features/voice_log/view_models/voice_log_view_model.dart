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
    this.candidateGroups,
    this.selectedCandidateItems = const {},
  });

  final VoiceLogState phase;
  final String? errorMessage;
  final String? message;
  final String transcript;
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
  final List<FoodCandidateGroup>? candidateGroups;
  final Map<String, MealItem> selectedCandidateItems;

  bool get isLoading =>
      phase == VoiceLogState.transcribing ||
      phase == VoiceLogState.agentRunning ||
      phase == VoiceLogState.stopping;

  VoiceLogUiState copyWith({
    VoiceLogState? phase,
    Object? errorMessage = _unchanged,
    Object? message = _unchanged,
    String? transcript,
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
    Object? candidateGroups = _unchanged,
    Map<String, MealItem>? selectedCandidateItems,
  }) {
    return VoiceLogUiState(
      phase: phase ?? this.phase,
      errorMessage: identical(errorMessage, _unchanged)
          ? this.errorMessage
          : errorMessage as String?,
      message: identical(message, _unchanged)
          ? this.message
          : message as String?,
      transcript: transcript ?? this.transcript,
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
      items: identical(items, _unchanged)
          ? this.items
          : items as List<MealItem>?,
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
      candidateGroups: identical(candidateGroups, _unchanged)
          ? this.candidateGroups
          : candidateGroups as List<FoodCandidateGroup>?,
      selectedCandidateItems:
          selectedCandidateItems ?? this.selectedCandidateItems,
    );
  }
}

const Object _unchanged = Object();

class VoiceLogViewModel extends ChangeNotifier {
  VoiceLogViewModel({
    required NutritionRepository nutritionRepository,
    AudioRecorderService? audioRecorderService,
  }) : _nutritionRepository = nutritionRepository,
       _audioRecorderService = audioRecorderService ?? AudioRecorderService();

  final NutritionRepository _nutritionRepository;
  final AudioRecorderService _audioRecorderService;

  VoiceLogUiState _uiState = const VoiceLogUiState();
  VoiceLogUiState get uiState => _uiState;

  VoiceLogState get state => _uiState.phase;

  String? get errorMessage => _uiState.errorMessage;

  String? get message => _uiState.message;

  String get transcript => _uiState.transcript;

  Duration get recordingDuration => _uiState.recordingDuration;

  Timer? _durationTimer;

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

  Future<void> toggleRecording({bool submitAfterTranscription = false}) async {
    if (_canStartRecording) {
      await startRecording();
    } else if (state == VoiceLogState.recording) {
      await stopRecording(submitAfterTranscription: submitAfterTranscription);
    }
  }

  Future<void> startRecording() => _startRecording();

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
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.requestingPermission,
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
        candidateGroups: null,
        selectedCandidateItems: const {},
      ),
    );
    try {
      await _audioRecorderService.start();
      _setUiState(_uiState.copyWith(recordingDuration: Duration.zero));
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _setUiState(
          _uiState.copyWith(
            recordingDuration:
                _uiState.recordingDuration + const Duration(seconds: 1),
          ),
        );
      });
      _setState(VoiceLogState.recording);
    } on RecorderException catch (e) {
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
      _setError(
        userVisibleErrorMessage(e, context: UserErrorContext.voiceRecording),
      );
    }
  }

  Future<void> _stopRecording({bool submitAfterTranscription = false}) async {
    _durationTimer?.cancel();
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
    try {
      if (submitAfterTranscription) {
        final voiceResult = await _nutritionRepository.logAudio(File(path));
        _setUiState(
          _uiState.copyWith(
            transcript: voiceResult.transcript,
            errorMessage: null,
          ),
        );
        _applyAgentRunResult(voiceResult.result);
      } else {
        final transcript = await _nutritionRepository.transcribeAudio(
          File(path),
        );
        _setUiState(
          _uiState.copyWith(transcript: transcript, errorMessage: null),
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
    _setUiState(_uiState.copyWith(transcript: value));
  }

  Future<void> submitText([String? overrideText]) async {
    final text = (overrideText ?? _uiState.transcript).trim();
    if (text.isEmpty) return;
    _setUiState(
      _uiState.copyWith(
        phase: VoiceLogState.agentRunning,
        transcript: text,
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
        candidateGroups: null,
        selectedCandidateItems: const {},
      ),
    );
    try {
      final result = await _nutritionRepository.logText(text);
      _applyAgentRunResult(result);
    } catch (error) {
      _setError(
        userVisibleErrorMessage(error, context: UserErrorContext.voiceAgent),
      );
    }
  }

  void _applyAgentRunResult(AgentRunResult result) {
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
    final selectedCandidateItems = _defaultCandidateSelections(
      groups: result.candidateGroups,
      resolvedItems: result.resolvedItems,
    );
    _setUiState(
      _uiState.copyWith(
        phase: nextState,
        proposal: result.proposal,
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
        candidateGroups: result.candidateGroups,
        selectedCandidateItems: selectedCandidateItems,
      ),
    );
  }

  Future<void> commitProposal({MealLabel? mealLabel}) async {
    final proposal = _uiState.proposal;
    if (proposal == null) return;
    _setState(VoiceLogState.agentRunning);
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
      _setUiState(
        _uiState.copyWith(
          phase: VoiceLogState.proposalReady,
          proposal: updated,
          message: 'Proposal updated.',
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
    final previousSelection = selectedCandidateFor(group);
    final selections = Map<String, MealItem>.of(_uiState.selectedCandidateItems)
      ..[_candidateGroupKey(group)] = candidate;
    _setUiState(_uiState.copyWith(selectedCandidateItems: selections));
    if (previousSelection != null &&
        _sameMealItem(previousSelection, candidate)) {
      return;
    }

    final selectableGroups = groups
        .where((group) => group.candidates.isNotEmpty)
        .toList();
    final requiredGroups = selectableGroups
        .where(_needsCandidateSelection)
        .toList();
    if (selectableGroups.isEmpty ||
        !requiredGroups.every(
          (group) => selections.containsKey(_candidateGroupKey(group)),
        )) {
      return;
    }

    final selectedItems = _itemsWithCandidateSelections(
      groups: groups,
      selections: selections,
    );
    _setState(VoiceLogState.agentRunning);
    try {
      final proposal = await _nutritionRepository.createProposalFromItems(
        phrase: _uiState.transcript,
        items: selectedItems,
      );
      _setUiState(
        _uiState.copyWith(
          phase: VoiceLogState.proposalReady,
          proposal: proposal,
          message: 'Meal proposal created.',
          errorMessage: null,
          resolvedItems: null,
          candidateGroups: groups,
          selectedCandidateItems: selections,
        ),
      );
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
    _setUiState(const VoiceLogUiState());
  }

  void retry() {
    _setUiState(
      _uiState.copyWith(phase: VoiceLogState.idle, errorMessage: null),
    );
  }

  void _setState(VoiceLogState value) {
    _setUiState(_uiState.copyWith(phase: value));
  }

  void _setError(String message) {
    _setUiState(
      _uiState.copyWith(phase: VoiceLogState.error, errorMessage: message),
    );
  }

  void _setUiState(VoiceLogUiState value) {
    _uiState = value;
    notifyListeners();
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

  bool _needsCandidateSelection(FoodCandidateGroup group) {
    if (group.candidates.isEmpty) return false;
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
    _durationTimer?.cancel();
    super.dispose();
  }
}
