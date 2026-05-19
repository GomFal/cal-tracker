import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../domain/models/nutrition_models.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../view_models/voice_log_view_model.dart';

class MealCreateScreen extends StatefulWidget {
  const MealCreateScreen({super.key});

  @override
  State<MealCreateScreen> createState() => _MealCreateScreenState();
}

class _MealCreateScreenState extends State<MealCreateScreen> {
  final _textController = TextEditingController();
  final _textFieldFocusNode = FocusNode();
  bool _transcriptReadyFocusQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final viewModel = context.read<VoiceLogViewModel>();
      if (viewModel.state == VoiceLogState.transcriptReady) {
        _requestTextFieldFocus();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<VoiceLogViewModel>();
    final showMealEntryControls = viewModel.proposal == null;
    if (_textController.text != viewModel.transcript) {
      _textController.value = TextEditingValue(
        text: viewModel.transcript,
        selection: TextSelection.collapsed(offset: viewModel.transcript.length),
      );
    }

    if (viewModel.state == VoiceLogState.transcriptReady) {
      if (!_transcriptReadyFocusQueued) {
        _transcriptReadyFocusQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || viewModel.state != VoiceLogState.transcriptReady) {
            return;
          }
          _requestTextFieldFocus();
        });
      }
    } else {
      _transcriptReadyFocusQueued = false;
    }

    return Scaffold(
      backgroundColor: FreshColors.screen,
      body: KeyedSubtree(
        key: const ValueKey('meal_create_screen'),
        child: ContentFrame(
          title: 'Create meal',
          subtitle: _stateLabel(viewModel.state),
          leading: FreshIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/dashboard'),
          ),
          actions: [
            if (viewModel.transcript.isNotEmpty ||
                viewModel.proposal != null ||
                viewModel.autoCommittedMeal != null)
              FreshIconButton(
                key: const ValueKey('voice_log_start_over_button'),
                icon: Icons.refresh_rounded,
                tooltip: 'Start over',
                onPressed: viewModel.clearResult,
              ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showMealEntryControls) ...[
                FreshCard(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    key: const ValueKey('meal_text_field'),
                    controller: _textController,
                    focusNode: _textFieldFocusNode,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Meal',
                      hintText: 'Tell me what you ate',
                      prefixIcon: Icon(Icons.restaurant_rounded),
                    ),
                    onChanged: viewModel.updateTranscript,
                    enabled: viewModel.state != VoiceLogState.transcribing &&
                        viewModel.state != VoiceLogState.agentRunning,
                  ),
                ),
                const SizedBox(height: FreshSpacing.md),
                _buildControls(context, viewModel),
                const SizedBox(height: FreshSpacing.lg),
              ],
              if (viewModel.isLoading)
                const LinearProgressIndicator(minHeight: 3),
              if (viewModel.state == VoiceLogState.recording) ...[
                _RecordingIndicator(duration: viewModel.recordingDuration),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.state == VoiceLogState.transcribing) ...[
                const FreshStatusBanner(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Transcribing...',
                  message: 'Listening back and preparing the text.',
                  color: FreshColors.water,
                ),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.errorMessage != null) ...[
                _ErrorBanner(
                  message: viewModel.errorMessage!,
                  onRetry: viewModel.retry,
                ),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.autoCommittedMeal != null) ...[
                _LoggedMealBanner(title: viewModel.autoCommittedMeal!.title),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.proposal != null) ...[
                _ProposalCard(
                  proposal: viewModel.proposal!,
                  onConfirm: () => _showMealLabelSheet(context, viewModel),
                  onEdit: () => _showProposalEditor(context, viewModel),
                ),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.state == VoiceLogState.clarificationRequired) ...[
                FreshStatusBanner(
                  icon: Icons.help_outline_rounded,
                  title: 'Needs a little more detail',
                  message: viewModel.message ??
                      'I am not sure what you would like to do. Could you rephrase?',
                  color: FreshColors.orange,
                ),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.candidateGroups != null &&
                  viewModel.proposal == null) ...[
                _ResolverClarificationCard(
                  groups: viewModel.candidateGroups!,
                  isCandidateSelected: viewModel.isCandidateSelected,
                  onCandidateSelected: viewModel.selectCandidate,
                  onPortionSelected: (choice) {
                    final actionText = choice.actionText;
                    if (actionText == null || actionText.isEmpty) return;
                    viewModel.submitText(actionText);
                  },
                ),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.state == VoiceLogState.resultReady &&
                  viewModel.message != null) ...[
                _InfoBanner(message: viewModel.message!),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.summary != null) ...[
                _SummaryCard(summary: viewModel.summary!),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.remaining != null) ...[
                _RemainingCard(remaining: viewModel.remaining!),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.meals != null) ...[
                _MealsCard(meals: viewModel.meals!),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.items != null) ...[
                _NutritionItemsCard(items: viewModel.items!),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.templates != null) ...[
                _TemplatesCard(templates: viewModel.templates!),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.template != null)
                _TemplatesCard(templates: [viewModel.template!]),
            ],
          ),
        ),
      ),
    );
  }

  void _requestTextFieldFocus() {
    if (!_textFieldFocusNode.canRequestFocus) return;
    _textFieldFocusNode.requestFocus();
  }

  Future<void> _showProposalEditor(
    BuildContext context,
    VoiceLogViewModel viewModel,
  ) async {
    final proposal = viewModel.proposal;
    if (proposal == null) return;
    final items = await showModalBottomSheet<List<MealItem>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProposalEditorSheet(
        proposal: proposal,
        candidateGroups: viewModel.candidateGroups ?? const [],
      ),
    );
    if (items == null || !context.mounted) return;
    await viewModel.updateProposalItems(items);
  }

  Future<void> _showMealLabelSheet(
    BuildContext context,
    VoiceLogViewModel viewModel,
  ) async {
    final selection = await showModalBottomSheet<_MealLabelSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _MealLabelSheet(),
    );
    if (!context.mounted || selection == null) return;
    await viewModel.commitProposal(mealLabel: selection.label);
  }

  Widget _buildControls(BuildContext context, VoiceLogViewModel viewModel) {
    final canSubmit = viewModel.state == VoiceLogState.idle ||
        viewModel.state == VoiceLogState.ready ||
        viewModel.state == VoiceLogState.transcriptReady ||
        viewModel.state == VoiceLogState.resultReady ||
        viewModel.state == VoiceLogState.error;

    return FilledButton.icon(
      key: const ValueKey('submit_meal_button'),
      icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
      onPressed: canSubmit && !viewModel.isLoading
          ? () => viewModel.submitText(_textController.text)
          : null,
      label: const Text('Submit meal'),
    );
  }
}

const _candidatePreviewCount = 3;
const _candidateDisplayLimit = 10;

class _ResolverClarificationCard extends StatefulWidget {
  const _ResolverClarificationCard({
    required this.groups,
    required this.isCandidateSelected,
    required this.onCandidateSelected,
    required this.onPortionSelected,
  });

  final List<FoodCandidateGroup> groups;
  final bool Function(FoodCandidateGroup group, MealItem candidate)
      isCandidateSelected;
  final Future<void> Function(FoodCandidateGroup group, MealItem candidate)
      onCandidateSelected;
  final ValueChanged<FoodPortionChoice> onPortionSelected;

  @override
  State<_ResolverClarificationCard> createState() =>
      _ResolverClarificationCardState();
}

class _ResolverClarificationCardState
    extends State<_ResolverClarificationCard> {
  final Set<String> _expandedGroups = <String>{};

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      key: const ValueKey('resolver_clarification_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FreshSectionTitle(title: 'Food matches'),
          const SizedBox(height: FreshSpacing.sm),
          for (final group in widget.groups) ...[
            Text(
              '${group.mention.originalText} -> ${group.mention.canonicalName}',
              style: textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            if (group.portionOptions?.isNotEmpty ?? false) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0;
                      index < group.portionOptions!.length;
                      index++)
                    _PortionChoiceChip(
                      key: ValueKey(
                        'portion_option_${group.mention.canonicalName}_$index',
                      ),
                      choice: group.portionOptions![index],
                      onSelected: widget.onPortionSelected,
                    ),
                ],
              ),
              const SizedBox(height: FreshSpacing.sm),
            ],
            if (group.candidates.isEmpty)
              Text(
                'No confident match yet',
                style: textTheme.bodyMedium?.copyWith(
                  color: FreshColors.inkMuted,
                ),
              )
            else
              _CandidateList(
                group: group,
                expanded: _expandedGroups.contains(_groupKey(group)),
                isCandidateSelected: widget.isCandidateSelected,
                onCandidateSelected: widget.onCandidateSelected,
                onToggleExpanded: () => _toggleExpanded(group),
              ),
            const SizedBox(height: FreshSpacing.md),
          ],
        ],
      ),
    );
  }

  void _toggleExpanded(FoodCandidateGroup group) {
    final key = _groupKey(group);
    setState(() {
      if (!_expandedGroups.add(key)) {
        _expandedGroups.remove(key);
      }
    });
  }

  String _groupKey(FoodCandidateGroup group) {
    final mention = group.mention;
    return [
      mention.originalText,
      mention.canonicalName,
      mention.quantity.toStringAsFixed(3),
      mention.unit,
    ].join('|');
  }
}

class _CandidateList extends StatelessWidget {
  const _CandidateList({
    required this.group,
    required this.expanded,
    required this.isCandidateSelected,
    required this.onCandidateSelected,
    required this.onToggleExpanded,
  });

  final FoodCandidateGroup group;
  final bool expanded;
  final bool Function(FoodCandidateGroup group, MealItem candidate)
      isCandidateSelected;
  final Future<void> Function(FoodCandidateGroup group, MealItem candidate)
      onCandidateSelected;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final candidates = group.candidates.take(_candidateDisplayLimit).toList();
    final visibleIndexes = _visibleCandidateIndexes(candidates);
    final hiddenCount = candidates.length - visibleIndexes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final index in visibleIndexes)
          _CandidateMealLine(
            key: ValueKey(
              'food_candidate_${group.mention.canonicalName}_$index',
            ),
            candidate: candidates[index],
            selected: isCandidateSelected(group, candidates[index]),
            onSelected: () => onCandidateSelected(group, candidates[index]),
          ),
        if (candidates.length > _candidatePreviewCount) ...[
          const SizedBox(height: FreshSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey(
                'food_candidate_toggle_${group.mention.canonicalName}',
              ),
              onPressed: onToggleExpanded,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
              label: Text(
                expanded
                    ? 'Show fewer'
                    : 'Show ${hiddenCount.clamp(0, candidates.length)} more',
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<int> _visibleCandidateIndexes(List<MealItem> candidates) {
    if (expanded) {
      return [for (var index = 0; index < candidates.length; index++) index];
    }

    final indexes = <int>{};
    for (var index = 0;
        index < candidates.length && index < _candidatePreviewCount;
        index++) {
      indexes.add(index);
    }

    for (var index = 0; index < candidates.length; index++) {
      if (isCandidateSelected(group, candidates[index])) {
        indexes.add(index);
        break;
      }
    }

    return indexes.toList()..sort();
  }
}

class _CandidateMealLine extends StatelessWidget {
  const _CandidateMealLine({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onSelected,
  });

  final MealItem candidate;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final metadata = _candidateMetadata(candidate);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected
            ? FreshColors.lime.withValues(alpha: 0.16)
            : FreshColors.surfaceSoft,
        borderRadius: BorderRadius.circular(FreshRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(FreshRadii.md),
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FreshIconChip(
                  icon: selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? FreshColors.limeDeep : FreshColors.inkMuted,
                  backgroundColor:
                      selected ? FreshColors.limeSoft : FreshColors.surface,
                  size: 36,
                ),
                const SizedBox(width: FreshSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.name,
                        style: textTheme.bodyLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (metadata.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 3,
                          children: [
                            for (final item in metadata)
                              Text(
                                item,
                                style: textTheme.labelMedium?.copyWith(
                                  color: FreshColors.inkMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: FreshSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 74),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${candidate.calories} Kcal',
                          textAlign: TextAlign.right,
                          style: textTheme.labelLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (candidate.confidence != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${(candidate.confidence! * 100).round()}%',
                          style: textTheme.labelSmall?.copyWith(
                            color: FreshColors.limeDeep,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _candidateMetadata(MealItem candidate) {
    final parts = <String>[];
    final source = candidate.externalSource ?? candidate.source;
    if (source.isNotEmpty) parts.add(source);
    final portion = candidate.portionDescription;
    if (portion != null && portion.isNotEmpty) {
      parts.add(portion);
    } else if (candidate.resolvedGrams != null) {
      parts.add('${_formatQuantity(candidate.resolvedGrams!)} g');
    }
    final license = candidate.license;
    if (license != null && license.isNotEmpty) parts.add(license);
    return parts;
  }
}

class _PortionChoiceChip extends StatelessWidget {
  const _PortionChoiceChip({
    super.key,
    required this.choice,
    required this.onSelected,
  });

  final FoodPortionChoice choice;
  final ValueChanged<FoodPortionChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final grams = choice.totalGrams ?? choice.gramWeight;
    final label = grams == null
        ? choice.label
        : '${choice.label} (${_formatQuantity(grams)} g)';
    final canSelect = choice.actionText?.isNotEmpty ?? false;
    return ActionChip(
      label: Text(label),
      avatar: Icon(canSelect ? Icons.check_rounded : Icons.edit_rounded),
      onPressed: canSelect ? () => onSelected(choice) : null,
    );
  }
}

// ignore: unused_element
class _VoiceCaptureCard extends StatelessWidget {
  const _VoiceCaptureCard({required this.viewModel});

  final VoiceLogViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final isRecording = viewModel.state == VoiceLogState.recording;
    final isDisabled = viewModel.state == VoiceLogState.stopping ||
        viewModel.state == VoiceLogState.transcribing ||
        viewModel.state == VoiceLogState.agentRunning;
    final textTheme = Theme.of(context).textTheme;
    final limeCardTextColor = FreshPalette.dark.limeWash;
    return FreshCard(
      color: isRecording
          ? FreshColors.coral.withValues(alpha: 0.12)
          : FreshColors.limeSoft,
      radius: FreshRadii.xl,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FreshIconChip(
                      icon: isRecording
                          ? Icons.fiber_manual_record_rounded
                          : Icons.bolt_rounded,
                      color: isRecording
                          ? FreshColors.coral
                          : FreshColors.limeDeep,
                      backgroundColor: FreshColors.surface,
                    ),
                    const SizedBox(width: FreshSpacing.sm),
                    Text(
                      isRecording ? 'Recording' : 'Voice intake',
                      style: textTheme.bodyMedium?.copyWith(
                        color:
                            isRecording ? FreshColors.ink : limeCardTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FreshSpacing.md),
                Text(
                  isRecording
                      ? 'Tap stop when you are done.'
                      : 'Say your meal naturally.',
                  style: textTheme.titleLarge?.copyWith(
                    color: isRecording ? null : limeCardTextColor,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: FreshSpacing.sm),
                Text(
                  'The meal will be filled with your voice.',
                  style: textTheme.bodyMedium?.copyWith(
                    color:
                        isRecording ? FreshColors.inkSoft : limeCardTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: FreshSpacing.lg),
          SizedBox.square(
            dimension: 76,
            child: IconButton(
              key: const ValueKey('mic_button'),
              tooltip: isRecording ? 'Stop recording' : 'Record voice',
              onPressed: isDisabled ? null : viewModel.toggleRecording,
              icon: Icon(isRecording ? Icons.stop_rounded : Icons.mic_rounded),
              style: IconButton.styleFrom(
                backgroundColor:
                    isRecording ? FreshColors.coral : FreshColors.lime,
                foregroundColor: FreshColors.ink,
                disabledBackgroundColor: FreshColors.surfaceMuted,
                disabledForegroundColor: FreshColors.inkMuted,
                shape: const CircleBorder(),
                iconSize: 34,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return FreshStatusBanner(
      icon: Icons.info_outline_rounded,
      title: 'Update',
      message: message,
      color: FreshColors.water,
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return FreshStatusBanner(
      icon: Icons.fiber_manual_record_rounded,
      title: '$minutes:$seconds',
      message: 'Recording voice input from the emulator microphone.',
      color: FreshColors.coral,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FreshStatusBanner(
      icon: Icons.error_outline_rounded,
      title: 'Something went wrong',
      message: message,
      color: FreshColors.coral,
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}

class _LoggedMealBanner extends StatelessWidget {
  const _LoggedMealBanner({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return FreshStatusBanner(
      icon: Icons.check_rounded,
      title: title,
      message: 'Logged. You can correct it from history.',
      color: FreshColors.limeDeep,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    return FreshCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FreshSectionTitle(title: 'Today'),
          const SizedBox(height: FreshSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MetricBlock(
                  label: 'Consumed',
                  value: '${summary.consumed.calories}',
                  unit: 'Kcal',
                  color: FreshColors.lime,
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: _MetricBlock(
                  label: 'Remaining',
                  value: '${summary.remaining.calories}',
                  unit: 'Kcal',
                  color: FreshColors.water,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealsCard extends StatelessWidget {
  const _MealsCard({required this.meals});

  final List<Meal> meals;

  @override
  Widget build(BuildContext context) {
    return FreshCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FreshSectionTitle(title: 'Meals'),
          const SizedBox(height: FreshSpacing.sm),
          if (meals.isEmpty)
            const FreshEmptyState(
              icon: Icons.restaurant_rounded,
              title: 'No meals yet',
              message: 'Logged meals will appear here.',
            )
          else
            for (final meal in meals)
              _MealLine(
                title: meal.title,
                subtitle: '${meal.items.length} items',
                calories: meal.nutrition.calories,
              ),
        ],
      ),
    );
  }
}

class _NutritionItemsCard extends StatelessWidget {
  const _NutritionItemsCard({required this.items});

  final List<MealItem> items;

  @override
  Widget build(BuildContext context) {
    return FreshCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FreshSectionTitle(title: 'Nutrition matches'),
          const SizedBox(height: FreshSpacing.sm),
          for (final item in items)
            _MealLine(
              title: item.name,
              subtitle: '${_formatQuantity(item.quantity)} ${item.unit}',
              calories: item.calories,
            ),
        ],
      ),
    );
  }
}

class _TemplatesCard extends StatelessWidget {
  const _TemplatesCard({required this.templates});

  final List<MealTemplate> templates;

  @override
  Widget build(BuildContext context) {
    return FreshCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FreshSectionTitle(title: 'Usual meals'),
          const SizedBox(height: FreshSpacing.sm),
          for (final template in templates)
            _MealLine(
              title: template.title,
              subtitle: template.aliases.join(', '),
              calories: template.nutrition.calories,
            ),
        ],
      ),
    );
  }
}

class _RemainingCard extends StatelessWidget {
  const _RemainingCard({required this.remaining});

  final NutritionSnapshot remaining;

  @override
  Widget build(BuildContext context) {
    return FreshCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FreshSectionTitle(title: 'Remaining'),
          const SizedBox(height: FreshSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MetricBlock(
                  label: 'Calories',
                  value: '${remaining.calories}',
                  unit: 'Kcal',
                  color: FreshColors.lime,
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: _MetricBlock(
                  label: 'Protein',
                  value: _formatQuantity(remaining.proteinGrams),
                  unit: 'g',
                  color: FreshColors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealLabelSelection {
  const _MealLabelSelection(this.label);

  final MealLabel? label;
}

class _MealLabelSheet extends StatefulWidget {
  const _MealLabelSheet();

  @override
  State<_MealLabelSheet> createState() => _MealLabelSheetState();
}

class _MealLabelSheetState extends State<_MealLabelSheet> {
  final _otherController = TextEditingController();
  bool _showOther = false;

  static const _fixedLabels = [
    MealLabel.breakfast,
    MealLabel.lunch,
    MealLabel.dinner,
    MealLabel.snack,
    MealLabel.preWorkout,
    MealLabel.postWorkout,
  ];

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        key: const ValueKey('meal_label_sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: FreshColors.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text(
            'Which type of meal is this?',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: FreshSpacing.sm),
          Text(
            'This helps your Home screen make today easier to scan.',
            style: textTheme.bodyMedium?.copyWith(color: FreshColors.inkMuted),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Wrap(
            spacing: FreshSpacing.sm,
            runSpacing: FreshSpacing.sm,
            children: [
              for (final label in _fixedLabels)
                ChoiceChip(
                  key: ValueKey('meal_label_${label.type}_option'),
                  label: Text(label.label),
                  selected: false,
                  onSelected: (_) => _select(label),
                ),
              ChoiceChip(
                key: const ValueKey('meal_label_other_option'),
                label: const Text('Other'),
                selected: _showOther,
                onSelected: (_) => setState(() => _showOther = true),
              ),
            ],
          ),
          if (_showOther) ...[
            const SizedBox(height: FreshSpacing.lg),
            TextField(
              key: const ValueKey('meal_label_other_field'),
              controller: _otherController,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Custom meal type',
                hintText: 'Brunch',
                prefixIcon: Icon(Icons.edit_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: FreshSpacing.sm),
            FilledButton.icon(
              key: const ValueKey('meal_label_other_save_button'),
              onPressed: _otherController.text.trim().isEmpty
                  ? null
                  : () => _select(MealLabel.other(_otherController.text)),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save label'),
            ),
          ],
          const SizedBox(height: FreshSpacing.md),
          Row(
            children: [
              TextButton(
                key: const ValueKey('meal_label_cancel_button'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              TextButton(
                key: const ValueKey('meal_label_skip_button'),
                onPressed: () =>
                    Navigator.of(context).pop(const _MealLabelSelection(null)),
                child: const Text('Skip'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _select(MealLabel label) {
    Navigator.of(context).pop(_MealLabelSelection(label));
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.onConfirm,
    required this.onEdit,
  });

  final MealProposal proposal;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      radius: FreshRadii.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FreshIconChip(
                icon: Icons.local_fire_department_rounded,
                color: FreshColors.orange,
                backgroundColor: FreshColors.yellow,
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(proposal.title, style: textTheme.titleLarge),
                    Text(
                      'Ready to log',
                      style: textTheme.bodyMedium?.copyWith(
                        color: FreshColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const FreshFoodStack(
                assets: [
                  'assets/images/meal_breakfast.webp',
                  'assets/images/meal_lunch.webp',
                ],
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.lg),
          _MetricBlock(
            label: 'Calories',
            value: '${proposal.nutrition.calories}',
            unit: 'Kcal',
            color: FreshColors.lime,
          ),
          const SizedBox(height: FreshSpacing.md),
          for (final item in proposal.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${_mealItemDisplayName(item)} ${_formatQuantity(item.quantity)} ${item.unit}',
                style: textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: FreshSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('confirm_proposal_button'),
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Confirm'),
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              FreshIconButton(
                key: const ValueKey('edit_proposal_button'),
                icon: Icons.edit_rounded,
                tooltip: 'Edit ingredients',
                onPressed: onEdit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProposalEditorSheet extends StatefulWidget {
  const _ProposalEditorSheet({
    required this.proposal,
    required this.candidateGroups,
  });

  final MealProposal proposal;
  final List<FoodCandidateGroup> candidateGroups;

  @override
  State<_ProposalEditorSheet> createState() => _ProposalEditorSheetState();
}

class _ProposalEditorSheetState extends State<_ProposalEditorSheet> {
  late final List<_EditableMealItem> _items;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final item in widget.proposal.items) _EditableMealItem(item),
    ];
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FreshColors.rule,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: FreshSpacing.lg),
              Text('Edit ingredients', style: textTheme.titleLarge),
              const SizedBox(height: FreshSpacing.md),
              for (var index = 0; index < _items.length; index++) ...[
                _EditableIngredientRow(
                  key: ValueKey('proposal_item_editor_$index'),
                  item: _items[index],
                  index: index,
                  candidates: _candidateOptionsFor(_items[index].original),
                  onCandidateSelected: (candidate) {
                    setState(() {
                      _items[index].replaceWith(candidate);
                    });
                  },
                  onNutritionEdit: () => _editNutrition(index),
                  onDelete: _items.length == 1
                      ? null
                      : () {
                          setState(() {
                            _items.removeAt(index).dispose();
                          });
                        },
                ),
                const SizedBox(height: FreshSpacing.md),
              ],
              OutlinedButton.icon(
                key: const ValueKey('add_proposal_item_button'),
                onPressed: () {
                  setState(() {
                    _items.add(_EditableMealItem.empty());
                  });
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add ingredient'),
              ),
              const SizedBox(height: FreshSpacing.md),
              FilledButton(
                key: const ValueKey('save_proposal_edits_button'),
                onPressed: _save,
                child: const Text('Save edits'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    final edited = <MealItem>[];
    for (final item in _items) {
      final name = item.nameController.text.trim();
      final quantity = double.tryParse(item.quantityController.text.trim());
      final unit = item.unitController.text.trim();
      if (name.isEmpty || quantity == null || quantity <= 0 || unit.isEmpty) {
        continue;
      }
      edited.add(item.toMealItem(name: name, quantity: quantity, unit: unit));
    }
    if (edited.isEmpty) return;
    Navigator.of(context).pop(edited);
  }

  Future<void> _editNutrition(int index) async {
    final edited = await showModalBottomSheet<_NutritionEdit>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _NutritionEditorSheet(item: _items[index]),
    );
    if (edited == null) return;
    setState(() {
      _items[index].setNutritionOverride(edited);
    });
  }

  List<MealItem> _candidateOptionsFor(MealItem item) {
    for (final group in widget.candidateGroups) {
      if (_itemMatchesCandidateGroup(item, group)) {
        return group.candidates.take(_candidateDisplayLimit).toList();
      }
    }
    return const [];
  }
}

class _EditableIngredientRow extends StatelessWidget {
  const _EditableIngredientRow({
    super.key,
    required this.item,
    required this.index,
    required this.candidates,
    required this.onCandidateSelected,
    required this.onNutritionEdit,
    required this.onDelete,
  });

  final _EditableMealItem item;
  final int index;
  final List<MealItem> candidates;
  final ValueChanged<MealItem> onCandidateSelected;
  final VoidCallback onNutritionEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nutrition = item.currentNutrition();
    return FreshCard(
      padding: const EdgeInsets.all(12),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (candidates.isNotEmpty) ...[
            _CandidateSwapStrip(
              index: index,
              candidates: candidates,
              selectedItem: item.original,
              onSelected: onCandidateSelected,
            ),
            const SizedBox(height: FreshSpacing.sm),
          ],
          TextField(
            key: ValueKey('proposal_item_name_$index'),
            controller: item.nameController,
            decoration: const InputDecoration(labelText: 'Ingredient'),
          ),
          const SizedBox(height: FreshSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('proposal_item_quantity_$index'),
                  controller: item.quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              SizedBox(
                width: 82,
                child: TextField(
                  key: ValueKey('proposal_item_unit_$index'),
                  controller: item.unitController,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              IconButton(
                key: ValueKey('delete_proposal_item_$index'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete ingredient',
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${nutrition.calories} Kcal · '
                  '${_formatMacro(nutrition.proteinGrams)}P · '
                  '${_formatMacro(nutrition.carbsGrams)}C · '
                  '${_formatMacro(nutrition.fatGrams)}F',
                  style: textTheme.labelMedium?.copyWith(
                    color: FreshColors.inkMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                key: ValueKey('edit_proposal_item_nutrition_$index'),
                onPressed: onNutritionEdit,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Nutrition'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CandidateSwapStrip extends StatefulWidget {
  const _CandidateSwapStrip({
    required this.index,
    required this.candidates,
    required this.selectedItem,
    required this.onSelected,
  });

  final int index;
  final List<MealItem> candidates;
  final MealItem selectedItem;
  final ValueChanged<MealItem> onSelected;

  @override
  State<_CandidateSwapStrip> createState() => _CandidateSwapStripState();
}

class _CandidateSwapStripState extends State<_CandidateSwapStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final candidates = widget.candidates.take(_candidateDisplayLimit).toList();
    final visibleIndexes = _visibleCandidateIndexes(candidates);
    final hiddenCount = candidates.length - visibleIndexes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Food match',
          style: textTheme.labelMedium?.copyWith(color: FreshColors.inkMuted),
        ),
        const SizedBox(height: FreshSpacing.xs),
        for (final candidateIndex in visibleIndexes)
          _CandidateMealLine(
            key: ValueKey(
              'proposal_item_${widget.index}_candidate_$candidateIndex',
            ),
            candidate: candidates[candidateIndex],
            selected: _sameMealItem(
              candidates[candidateIndex],
              widget.selectedItem,
            ),
            onSelected: () => widget.onSelected(candidates[candidateIndex]),
          ),
        if (candidates.length > _candidatePreviewCount) ...[
          const SizedBox(height: FreshSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('proposal_item_${widget.index}_candidate_toggle'),
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
              label: Text(
                _expanded
                    ? 'Show fewer'
                    : 'Show ${hiddenCount.clamp(0, candidates.length)} more',
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<int> _visibleCandidateIndexes(List<MealItem> candidates) {
    if (_expanded) {
      return [for (var index = 0; index < candidates.length; index++) index];
    }

    final indexes = <int>{};
    for (var index = 0;
        index < candidates.length && index < _candidatePreviewCount;
        index++) {
      indexes.add(index);
    }

    for (var index = 0; index < candidates.length; index++) {
      if (_sameMealItem(candidates[index], widget.selectedItem)) {
        indexes.add(index);
        break;
      }
    }

    return indexes.toList()..sort();
  }
}

class _NutritionEditorSheet extends StatefulWidget {
  const _NutritionEditorSheet({required this.item});

  final _EditableMealItem item;

  @override
  State<_NutritionEditorSheet> createState() => _NutritionEditorSheetState();
}

class _NutritionEditorSheetState extends State<_NutritionEditorSheet> {
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final nutrition = widget.item.currentNutrition();
    _caloriesController =
        TextEditingController(text: nutrition.calories.toString());
    _proteinController =
        TextEditingController(text: _formatMacro(nutrition.proteinGrams));
    _carbsController =
        TextEditingController(text: _formatMacro(nutrition.carbsGrams));
    _fatController =
        TextEditingController(text: _formatMacro(nutrition.fatGrams));
  }

  @override
  void dispose() {
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: FreshColors.rule,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: FreshSpacing.lg),
            Text('Edit nutrition', style: textTheme.titleLarge),
            const SizedBox(height: FreshSpacing.xs),
            Text(
              widget.item.nameController.text.trim().isEmpty
                  ? 'Manual ingredient'
                  : widget.item.nameController.text.trim(),
              style: textTheme.bodyMedium?.copyWith(
                color: FreshColors.inkMuted,
              ),
            ),
            const SizedBox(height: FreshSpacing.md),
            if (_error != null) ...[
              FreshStatusBanner(
                icon: Icons.error_outline_rounded,
                title: 'Check nutrition',
                message: _error!,
                color: FreshColors.coral,
              ),
              const SizedBox(height: FreshSpacing.md),
            ],
            TextField(
              key: const ValueKey('proposal_nutrition_calories'),
              controller: _caloriesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Calories'),
            ),
            const SizedBox(height: FreshSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('proposal_nutrition_protein'),
                    controller: _proteinController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Protein'),
                  ),
                ),
                const SizedBox(width: FreshSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('proposal_nutrition_carbs'),
                    controller: _carbsController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Carbs'),
                  ),
                ),
                const SizedBox(width: FreshSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('proposal_nutrition_fat'),
                    controller: _fatController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Fat'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FreshSpacing.md),
            FilledButton.icon(
              key: const ValueKey('save_proposal_nutrition_button'),
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save nutrition'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final calories = int.tryParse(_caloriesController.text.trim());
    final protein = double.tryParse(_proteinController.text.trim());
    final carbs = double.tryParse(_carbsController.text.trim());
    final fat = double.tryParse(_fatController.text.trim());
    if (calories == null ||
        calories < 0 ||
        protein == null ||
        protein < 0 ||
        carbs == null ||
        carbs < 0 ||
        fat == null ||
        fat < 0) {
      setState(() {
        _error = 'Use non-negative numbers for calories and macros.';
      });
      return;
    }
    Navigator.of(context).pop(
      _NutritionEdit(
        calories: calories,
        proteinGrams: _roundMacro(protein),
        carbsGrams: _roundMacro(carbs),
        fatGrams: _roundMacro(fat),
      ),
    );
  }
}

class _NutritionEdit {
  const _NutritionEdit({
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final int calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
}

class _EditableMealItem {
  _EditableMealItem(MealItem item) : original = item {
    nameController = TextEditingController(text: item.name);
    quantityController = TextEditingController(
      text: _formatQuantity(item.quantity),
    );
    unitController = TextEditingController(text: item.unit);
  }

  _EditableMealItem.empty()
      : original = const MealItem(
          name: '',
          quantity: 100,
          unit: 'g',
          calories: 0,
          proteinGrams: 0,
          carbsGrams: 0,
          fatGrams: 0,
          source: 'manual_edit',
        ) {
    nameController = TextEditingController();
    quantityController = TextEditingController(text: '100');
    unitController = TextEditingController(text: 'g');
  }

  MealItem original;
  _NutritionEdit? _nutritionOverride;
  late final TextEditingController nameController;
  late final TextEditingController quantityController;
  late final TextEditingController unitController;

  void replaceWith(MealItem item) {
    original = item;
    _nutritionOverride = null;
    nameController.text = item.name;
    quantityController.text = _formatQuantity(item.quantity);
    unitController.text = item.unit;
  }

  void setNutritionOverride(_NutritionEdit value) {
    _nutritionOverride = value;
  }

  _NutritionEdit currentNutrition() {
    final override = _nutritionOverride;
    if (override != null) return override;
    final quantity = double.tryParse(quantityController.text.trim());
    final factor = original.quantity > 0 && quantity != null && quantity > 0
        ? quantity / original.quantity
        : 1.0;
    return _NutritionEdit(
      calories: (original.calories * factor).round(),
      proteinGrams: _roundMacro(original.proteinGrams * factor),
      carbsGrams: _roundMacro(original.carbsGrams * factor),
      fatGrams: _roundMacro(original.fatGrams * factor),
    );
  }

  MealItem toMealItem({
    required String name,
    required double quantity,
    required String unit,
  }) {
    final nutrition = currentNutrition();
    return original.copyWith(
      name: name,
      quantity: quantity,
      unit: unit,
      calories: nutrition.calories,
      proteinGrams: nutrition.proteinGrams,
      carbsGrams: nutrition.carbsGrams,
      fatGrams: nutrition.fatGrams,
      source: original.source == 'manual_edit'
          ? 'manual_edit'
          : '${original.source}:manual_edit',
    );
  }

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    unitController.dispose();
  }
}

bool _itemMatchesCandidateGroup(MealItem item, FoodCandidateGroup group) {
  if (group.candidates.any((candidate) => _sameMealItem(candidate, item))) {
    return true;
  }
  return item.canonicalName == group.mention.canonicalName ||
      item.originalText == group.mention.originalText;
}

bool _sameMealItem(MealItem a, MealItem b) {
  if (a.externalId != null && b.externalId != null) {
    return a.externalId == b.externalId && a.externalSource == b.externalSource;
  }
  return a.name == b.name &&
      a.source == b.source &&
      a.quantity == b.quantity &&
      a.unit == b.unit;
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FreshRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelMedium),
          const SizedBox(height: FreshSpacing.sm),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 4,
            children: [
              Text(
                value,
                style: textTheme.headlineMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(unit, style: textTheme.bodyMedium),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealLine extends StatelessWidget {
  const _MealLine({
    required this.title,
    required this.subtitle,
    required this.calories,
  });

  final String title;
  final String subtitle;
  final int calories;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const FreshIconChip(
            icon: Icons.local_fire_department_rounded,
            color: FreshColors.orange,
            backgroundColor: FreshColors.yellow,
            size: 36,
          ),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.bodyLarge),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: textTheme.bodyMedium?.copyWith(
                      color: FreshColors.inkMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            '$calories Kcal',
            style: textTheme.labelLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _mealItemDisplayName(MealItem item) =>
    item.canonicalName?.isNotEmpty == true ? item.canonicalName! : item.name;

String _formatMacro(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

double _roundMacro(double value) => (value * 10).roundToDouble() / 10;

String _stateLabel(VoiceLogState state) {
  return switch (state) {
    VoiceLogState.recording => 'Listening',
    VoiceLogState.stopping => 'Saving audio',
    VoiceLogState.transcribing => 'Whisper transcription',
    VoiceLogState.transcriptReady => 'Transcript ready',
    VoiceLogState.agentRunning => 'Building proposal',
    VoiceLogState.proposalReady => 'Review meal',
    VoiceLogState.autoCommitted => 'Logged',
    VoiceLogState.resultReady => 'Result ready',
    VoiceLogState.clarificationRequired => 'Clarification',
    VoiceLogState.error => 'Needs attention',
    _ => 'Voice or text input',
  };
}
