import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../../../core/voice_action_button.dart';
import '../view_models/voice_log_view_model.dart';

class MealCreateScreen extends StatefulWidget {
  const MealCreateScreen({super.key});

  @override
  State<MealCreateScreen> createState() => _MealCreateScreenState();
}

class _MealCreateScreenState extends State<MealCreateScreen> {
  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<VoiceLogViewModel>();

    return Scaffold(
      backgroundColor: FreshColors.screen,
      floatingActionButton: _MealCreateVoiceActionButton(viewModel: viewModel),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
              if (viewModel.hasVoiceTranscript) ...[
                _VoiceTranscriptCard(transcript: viewModel.transcript),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (_shouldShowManualFoodSearch(viewModel)) ...[
                _ManualFoodSearchPanel(viewModel: viewModel),
                const SizedBox(height: FreshSpacing.md),
              ],
              if (viewModel.showProposalChangeSuccess) ...[
                const _ProposalChangeSuccessToast(),
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
              if (viewModel.state == VoiceLogState.clarificationRequired &&
                  (viewModel.clarificationOptions?.isNotEmpty ?? false)) ...[
                _ResolverClarificationCard(
                  groups: viewModel.clarificationOptions!,
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
              const SizedBox(height: 104),
            ],
          ),
        ),
      ),
    );
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
}

const _candidatePreviewCount = 3;
const _candidateDisplayLimit = 10;
const _foodSearchResultLimit = 10;

bool _shouldShowManualFoodSearch(VoiceLogViewModel viewModel) {
  final hasPrimaryResult = viewModel.proposal != null ||
      viewModel.autoCommittedMeal != null ||
      viewModel.summary != null ||
      viewModel.remaining != null ||
      viewModel.meals != null ||
      viewModel.items != null ||
      viewModel.templates != null ||
      viewModel.template != null;
  if (hasPrimaryResult || viewModel.transcript.trim().isNotEmpty) {
    return false;
  }
  return viewModel.state == VoiceLogState.idle ||
      viewModel.state == VoiceLogState.ready ||
      viewModel.state == VoiceLogState.error;
}

class _VoiceTranscriptCard extends StatelessWidget {
  const _VoiceTranscriptCard({required this.transcript});

  final String transcript;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FreshCard(
      key: const ValueKey('voice_transcript_card'),
      padding: const EdgeInsets.symmetric(
        horizontal: FreshSpacing.md,
        vertical: FreshSpacing.sm,
      ),
      radius: FreshRadii.md,
      color: FreshColors.surfaceSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.voiceTranscriptHeardLabel,
            style: textTheme.labelLarge?.copyWith(
              color: FreshColors.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: FreshSpacing.sm),
          Expanded(
            child: Text(
              transcript,
              style: textTheme.bodySmall?.copyWith(
                color: FreshColors.inkSoft,
                height: 1.25,
                letterSpacing: 0,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualFoodSearchPanel extends StatefulWidget {
  const _ManualFoodSearchPanel({required this.viewModel});

  final VoiceLogViewModel viewModel;

  @override
  State<_ManualFoodSearchPanel> createState() => _ManualFoodSearchPanelState();
}

class _ManualFoodSearchPanelState extends State<_ManualFoodSearchPanel> {
  final List<_EditableMealItem> _items = [];

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      key: const ValueKey('manual_food_search_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const FreshIconChip(
                icon: Icons.search_rounded,
                color: FreshColors.limeDeep,
                backgroundColor: FreshColors.limeWash,
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Text(
                  context.l10n.foodSearchTitle,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.md),
          _FoodSearchBox(
            keyPrefix: 'manual_food_search',
            actionLabel: context.l10n.foodSearchAddAction,
            actionIcon: Icons.add_rounded,
            hintText: context.l10n.foodSearchHint,
            onSelected: (candidate) {
              setState(() {
                _items.add(_EditableMealItem(candidate));
              });
            },
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: FreshSpacing.lg),
            Text(
              context.l10n.foodSearchSelectedFoods,
              style: textTheme.labelLarge?.copyWith(
                color: FreshColors.inkMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: FreshSpacing.sm),
            for (var index = 0; index < _items.length; index++) ...[
              _ManualDraftIngredientRow(
                key: ValueKey('manual_food_draft_item_$index'),
                item: _items[index],
                index: index,
                onNutritionEdit: () => _editNutrition(index),
                onDelete: () {
                  setState(() {
                    _items.removeAt(index).dispose();
                  });
                },
              ),
              if (index != _items.length - 1)
                const Divider(height: FreshSpacing.lg),
            ],
            const SizedBox(height: FreshSpacing.md),
            FilledButton.icon(
              key: const ValueKey('manual_food_review_meal_button'),
              onPressed: widget.viewModel.isLoading ? null : _reviewMeal,
              icon: const Icon(Icons.restaurant_menu_rounded),
              label: Text(context.l10n.foodSearchReviewMeal),
            ),
          ],
        ],
      ),
    );
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

  Future<void> _reviewMeal() async {
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
    await widget.viewModel.createProposalFromManualItems(edited);
    if (!mounted) return;
    if (widget.viewModel.proposal != null) {
      setState(() {
        for (final item in _items) {
          item.dispose();
        }
        _items.clear();
      });
    }
  }
}

class _ManualDraftIngredientRow extends StatelessWidget {
  const _ManualDraftIngredientRow({
    super.key,
    required this.item,
    required this.index,
    required this.onNutritionEdit,
    required this.onDelete,
  });

  final _EditableMealItem item;
  final int index;
  final VoidCallback onNutritionEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nutrition = item.currentNutrition();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: ValueKey('manual_food_item_name_$index'),
          controller: item.nameController,
          decoration: InputDecoration(labelText: context.l10n.foodSearchName),
        ),
        const SizedBox(height: FreshSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('manual_food_item_quantity_$index'),
                controller: item.quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.l10n.foodSearchQuantity,
                ),
              ),
            ),
            const SizedBox(width: FreshSpacing.sm),
            SizedBox(
              width: 82,
              child: TextField(
                key: ValueKey('manual_food_item_unit_$index'),
                controller: item.unitController,
                decoration: InputDecoration(
                  labelText: context.l10n.foodSearchUnit,
                ),
              ),
            ),
            const SizedBox(width: FreshSpacing.sm),
            IconButton(
              key: ValueKey('manual_food_item_delete_$index'),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: context.l10n.foodSearchRemoveDraft,
            ),
          ],
        ),
        const SizedBox(height: FreshSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                _nutritionLabel(nutrition),
                style: textTheme.labelMedium?.copyWith(
                  color: FreshColors.inkMuted,
                  letterSpacing: 0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              key: ValueKey('manual_food_item_nutrition_$index'),
              onPressed: onNutritionEdit,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(context.l10n.foodSearchNutrition),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProposalChangeSuccessToast extends StatelessWidget {
  const _ProposalChangeSuccessToast();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      key: const ValueKey('proposal_change_success_toast'),
      color: FreshColors.limeWash,
      radius: FreshRadii.lg,
      padding: const EdgeInsets.symmetric(
        horizontal: FreshSpacing.lg,
        vertical: FreshSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_rounded,
            color: FreshColors.limeDeep,
            size: 20,
          ),
          const SizedBox(width: FreshSpacing.sm),
          Flexible(
            child: Text(
              context.l10n.voiceChangesApplied,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: FreshColors.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

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
  final Set<String> _searchExpandedGroups = <String>{};

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      key: const ValueKey('resolver_clarification_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FreshSectionTitle(title: context.l10n.voiceFoodMatches),
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
                context.l10n.voiceNoDatabaseMatch,
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
            const SizedBox(height: FreshSpacing.sm),
            _ClarificationFoodSearch(
              group: group,
              expanded: group.candidates.isEmpty ||
                  _searchExpandedGroups.contains(_groupKey(group)),
              onToggleExpanded: () => _toggleSearchExpanded(group),
              onSelected: (candidate) async {
                await widget.onCandidateSelected(
                  group,
                  _candidateWithMentionQuantity(candidate, group.mention),
                );
              },
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

  void _toggleSearchExpanded(FoodCandidateGroup group) {
    final key = _groupKey(group);
    setState(() {
      if (!_searchExpandedGroups.add(key)) {
        _searchExpandedGroups.remove(key);
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

class _ClarificationFoodSearch extends StatelessWidget {
  const _ClarificationFoodSearch({
    required this.group,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onSelected,
  });

  final FoodCandidateGroup group;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Future<void> Function(MealItem candidate) onSelected;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey(
            'food_candidate_search_toggle_${group.mention.canonicalName}',
          ),
          onPressed: onToggleExpanded,
          icon: const Icon(Icons.search_rounded, size: 18),
          label: Text(context.l10n.foodSearchSearchInstead),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FoodSearchBox(
          keyPrefix: 'clarification_food_search_${group.mention.canonicalName}',
          actionLabel: context.l10n.foodSearchUseAction,
          actionIcon: Icons.check_rounded,
          hintText: context.l10n.foodSearchHint,
          initialQuery: group.mention.canonicalName,
          onSelected: onSelected,
        ),
        if (group.candidates.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey(
                'food_candidate_search_collapse_${group.mention.canonicalName}',
              ),
              onPressed: onToggleExpanded,
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              label: Text(context.l10n.foodSearchHideSearch),
            ),
          ),
      ],
    );
  }
}

class _FoodSearchBox extends StatefulWidget {
  const _FoodSearchBox({
    required this.keyPrefix,
    required this.actionLabel,
    required this.actionIcon,
    required this.hintText,
    required this.onSelected,
    this.initialQuery,
  });

  final String keyPrefix;
  final String actionLabel;
  final IconData actionIcon;
  final String hintText;
  final FutureOr<void> Function(MealItem candidate) onSelected;
  final String? initialQuery;

  @override
  State<_FoodSearchBox> createState() => _FoodSearchBoxState();
}

class _FoodSearchBoxState extends State<_FoodSearchBox> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<MealItem> _results = const [];
  bool _loading = false;
  String? _error;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    if (_controller.text.trim().length >= 2) {
      _queueSearchAfterBuild();
    }
  }

  @override
  void didUpdateWidget(covariant _FoodSearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery &&
        widget.initialQuery != null &&
        widget.initialQuery != _controller.text) {
      _controller.text = widget.initialQuery!;
      _queueSearchAfterBuild();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: ValueKey('${widget.keyPrefix}_field'),
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _scheduleSearch(),
          onSubmitted: (_) => _scheduleSearch(immediate: true),
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _controller.text.trim().isEmpty
                ? null
                : IconButton(
                    key: ValueKey('${widget.keyPrefix}_clear'),
                    tooltip: context.l10n.foodSearchClear,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _clear,
                  ),
          ),
        ),
        if (_loading) ...[
          const SizedBox(height: FreshSpacing.sm),
          LinearProgressIndicator(
            key: ValueKey('${widget.keyPrefix}_loading'),
            minHeight: 3,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: FreshSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(
                    color: FreshColors.coral,
                    letterSpacing: 0,
                  ),
                ),
              ),
              TextButton(
                key: ValueKey('${widget.keyPrefix}_retry'),
                onPressed: () => _scheduleSearch(immediate: true),
                child: Text(context.l10n.foodSearchRetry),
              ),
            ],
          ),
        ],
        if (!_loading &&
            _error == null &&
            _controller.text.trim().length >= 2 &&
            _results.isEmpty) ...[
          const SizedBox(height: FreshSpacing.sm),
          Text(
            context.l10n.foodSearchEmpty,
            key: ValueKey('${widget.keyPrefix}_empty'),
            style: textTheme.bodySmall?.copyWith(
              color: FreshColors.inkMuted,
              letterSpacing: 0,
            ),
          ),
        ],
        if (_results.isNotEmpty) ...[
          const SizedBox(height: FreshSpacing.sm),
          for (var index = 0; index < _results.length; index++) ...[
            _FoodSearchResultLine(
              key: ValueKey('${widget.keyPrefix}_result_$index'),
              buttonKey: ValueKey('${widget.keyPrefix}_result_button_$index'),
              item: _results[index],
              actionLabel: widget.actionLabel,
              actionIcon: widget.actionIcon,
              onSelected: () => widget.onSelected(_results[index]),
            ),
            if (index != _results.length - 1)
              const Divider(height: FreshSpacing.md),
          ],
        ],
      ],
    );
  }

  void _clear() {
    _debounce?.cancel();
    setState(() {
      _controller.clear();
      _results = const [];
      _loading = false;
      _error = null;
    });
  }

  void _queueSearchAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleSearch(immediate: true);
    });
  }

  void _scheduleSearch({bool immediate = false}) {
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }

    if (immediate) {
      unawaited(_search(query));
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_search(query));
    });
  }

  Future<void> _search(String query) async {
    final serial = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<VoiceLogViewModel>().searchFoods(
            query,
            limit: _foodSearchResultLimit,
          );
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _results = result.items.take(_foodSearchResultLimit).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _results = const [];
        _loading = false;
        _error = context.l10n.foodSearchError;
      });
    }
  }
}

class _FoodSearchResultLine extends StatelessWidget {
  const _FoodSearchResultLine({
    super.key,
    required this.buttonKey,
    required this.item,
    required this.actionLabel,
    required this.actionIcon,
    required this.onSelected,
  });

  final Key buttonKey;
  final MealItem item;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _foodSearchItemSubtitle(item),
                style: textTheme.labelMedium?.copyWith(
                  color: FreshColors.inkMuted,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: FreshSpacing.sm),
        TextButton.icon(
          key: buttonKey,
          onPressed: () {
            FocusScope.of(context).unfocus();
            onSelected();
          },
          icon: Icon(actionIcon, size: 18),
          label: Text(actionLabel),
        ),
      ],
    );
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
    return _FoodCandidateStrip(
      candidates: group.candidates,
      expanded: expanded,
      itemKeyPrefix: 'food_candidate_${group.mention.canonicalName}',
      toggleKey: ValueKey(
        'food_candidate_toggle_${group.mention.canonicalName}',
      ),
      isSelected: (candidate) => isCandidateSelected(group, candidate),
      onSelected: (candidate) => onCandidateSelected(group, candidate),
      onToggleExpanded: onToggleExpanded,
    );
  }
}

class _FoodCandidateStrip extends StatelessWidget {
  const _FoodCandidateStrip({
    required this.candidates,
    required this.expanded,
    required this.itemKeyPrefix,
    required this.toggleKey,
    required this.isSelected,
    required this.onSelected,
    required this.onToggleExpanded,
    this.label,
  });

  final List<MealItem> candidates;
  final bool expanded;
  final String itemKeyPrefix;
  final Key toggleKey;
  final bool Function(MealItem candidate) isSelected;
  final ValueChanged<MealItem> onSelected;
  final VoidCallback onToggleExpanded;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final visibleCandidates = candidates.take(_candidateDisplayLimit).toList();
    final visibleIndexes = _visibleCandidateIndexes(visibleCandidates);
    final hiddenCount = visibleCandidates.length - visibleIndexes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: textTheme.labelMedium?.copyWith(
              color: FreshColors.inkMuted,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
        ],
        for (final index in visibleIndexes)
          _CandidateMealLine(
            key: ValueKey('${itemKeyPrefix}_$index'),
            candidate: visibleCandidates[index],
            selected: isSelected(visibleCandidates[index]),
            onSelected: () => onSelected(visibleCandidates[index]),
          ),
        if (visibleCandidates.length > _candidatePreviewCount) ...[
          const SizedBox(height: FreshSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: toggleKey,
              onPressed: onToggleExpanded,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
              label: Text(
                expanded
                    ? 'Show fewer'
                    : 'Show ${hiddenCount.clamp(0, visibleCandidates.length)} more',
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<int> _visibleCandidateIndexes(List<MealItem> visibleCandidates) {
    if (expanded) {
      return [
        for (var index = 0; index < visibleCandidates.length; index++) index,
      ];
    }

    final indexes = <int>{};
    for (var index = 0;
        index < visibleCandidates.length && index < _candidatePreviewCount;
        index++) {
      indexes.add(index);
    }

    for (var index = 0; index < visibleCandidates.length; index++) {
      if (isSelected(visibleCandidates[index])) {
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

class _MealCreateVoiceActionButton extends StatelessWidget {
  const _MealCreateVoiceActionButton({required this.viewModel});

  final VoiceLogViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final isRecording = viewModel.state == VoiceLogState.recording;
    final isDisabled = viewModel.state == VoiceLogState.stopping ||
        viewModel.state == VoiceLogState.transcribing ||
        viewModel.state == VoiceLogState.agentRunning;
    final isCorrection = viewModel.proposal != null;
    final hasError = viewModel.state == VoiceLogState.error;
    final tooltip = isRecording
        ? 'Stop and submit voice'
        : isDisabled
            ? 'Processing voice'
            : isCorrection
                ? 'Record correction'
                : 'Record meal';
    final backgroundColor = isRecording
        ? FreshColors.coral
        : hasError
            ? FreshColors.yellow
            : isDisabled
                ? palette.surfaceMuted
                : palette.lime;
    final icon = isRecording
        ? Icons.stop_rounded
        : isDisabled
            ? Icons.graphic_eq_rounded
            : hasError
                ? Icons.error_outline_rounded
                : Icons.mic_rounded;

    return SafeArea(
      child: Semantics(
        key: const ValueKey('meal_create_voice_action_button'),
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: VoiceActionButtonChrome(
            dimension: 72,
            backgroundColor: backgroundColor,
            isRecording: isRecording,
            child: IconButton(
              key: const ValueKey('mic_button'),
              tooltip: tooltip,
              onPressed: isDisabled ? null : () => _handleTap(viewModel),
              icon: Icon(icon),
              color: palette.ink,
              disabledColor: palette.inkMuted,
              iconSize: 32,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shape: const CircleBorder(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(VoiceLogViewModel viewModel) async {
    if (viewModel.canStartRecording) {
      await viewModel.startRecording();
      if (viewModel.state == VoiceLogState.recording) {
        VoiceActionHaptics.recordingStarted();
      }
      return;
    }
    if (viewModel.canStopRecording) {
      VoiceActionHaptics.recordingStopped();
      await viewModel.stopRecording(submitAfterTranscription: true);
    }
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
                  onSearchReplacementSelected: (candidate) {
                    setState(() {
                      _items[index].replaceWith(
                        _replacementCandidateFor(_items[index], candidate),
                      );
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
    if (_mealItemListsMateriallyEqual(widget.proposal.items, edited)) {
      Navigator.of(context).pop();
      return;
    }
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

  MealItem _replacementCandidateFor(
    _EditableMealItem item,
    MealItem candidate,
  ) {
    final quantity = double.tryParse(item.quantityController.text.trim());
    final unit = item.unitController.text.trim();
    if (quantity == null || quantity <= 0 || unit.isEmpty) return candidate;
    return _candidateWithQuantity(candidate, quantity: quantity, unit: unit);
  }
}

class _EditableIngredientRow extends StatelessWidget {
  const _EditableIngredientRow({
    super.key,
    required this.item,
    required this.index,
    required this.candidates,
    required this.onCandidateSelected,
    required this.onSearchReplacementSelected,
    required this.onNutritionEdit,
    required this.onDelete,
  });

  final _EditableMealItem item;
  final int index;
  final List<MealItem> candidates;
  final ValueChanged<MealItem> onCandidateSelected;
  final ValueChanged<MealItem> onSearchReplacementSelected;
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
          _InlineReplacementFoodSearch(
            index: index,
            item: item,
            onSelected: onSearchReplacementSelected,
          ),
          const SizedBox(height: FreshSpacing.sm),
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
    return _FoodCandidateStrip(
      label: 'Food match',
      candidates: widget.candidates,
      expanded: _expanded,
      itemKeyPrefix: 'proposal_item_${widget.index}_candidate',
      toggleKey: ValueKey('proposal_item_${widget.index}_candidate_toggle'),
      isSelected: (candidate) => _sameMealItem(candidate, widget.selectedItem),
      onSelected: widget.onSelected,
      onToggleExpanded: () => setState(() => _expanded = !_expanded),
    );
  }
}

class _InlineReplacementFoodSearch extends StatefulWidget {
  const _InlineReplacementFoodSearch({
    required this.index,
    required this.item,
    required this.onSelected,
  });

  final int index;
  final _EditableMealItem item;
  final ValueChanged<MealItem> onSelected;

  @override
  State<_InlineReplacementFoodSearch> createState() =>
      _InlineReplacementFoodSearchState();
}

class _InlineReplacementFoodSearchState
    extends State<_InlineReplacementFoodSearch> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey('proposal_item_${widget.index}_search_toggle'),
          onPressed: () => setState(() => _expanded = true),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: Text(context.l10n.foodSearchReplaceSearch),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FoodSearchBox(
          keyPrefix: 'proposal_item_${widget.index}_search',
          actionLabel: context.l10n.foodSearchReplaceAction,
          actionIcon: Icons.swap_horiz_rounded,
          hintText: context.l10n.foodSearchHint,
          initialQuery: widget.item.nameController.text,
          onSelected: (candidate) {
            widget.onSelected(candidate);
            setState(() => _expanded = false);
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('proposal_item_${widget.index}_search_collapse'),
            onPressed: () => setState(() => _expanded = false),
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
            label: Text(context.l10n.foodSearchHideSearch),
          ),
        ),
      ],
    );
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

MealItem _candidateWithMentionQuantity(
  MealItem candidate,
  FoodMention mention,
) {
  return _candidateWithQuantity(
    candidate,
    quantity: mention.quantity,
    unit: mention.unit,
  );
}

MealItem _candidateWithQuantity(
  MealItem candidate, {
  required double quantity,
  required String unit,
}) {
  if (_normalizedText(candidate.unit) != _normalizedText(unit) ||
      candidate.quantity <= 0 ||
      quantity <= 0) {
    return candidate;
  }
  final factor = quantity / candidate.quantity;
  return candidate.copyWith(
    quantity: quantity,
    unit: unit,
    calories: (candidate.calories * factor).round(),
    proteinGrams: _roundMacro(candidate.proteinGrams * factor),
    carbsGrams: _roundMacro(candidate.carbsGrams * factor),
    fatGrams: _roundMacro(candidate.fatGrams * factor),
  );
}

String _foodSearchItemSubtitle(MealItem item) {
  return '${_formatQuantity(item.quantity)} ${item.unit} · '
      '${_nutritionLabel(_NutritionEdit(
    calories: item.calories,
    proteinGrams: item.proteinGrams,
    carbsGrams: item.carbsGrams,
    fatGrams: item.fatGrams,
  ))}';
}

String _nutritionLabel(_NutritionEdit nutrition) {
  return '${nutrition.calories} Kcal · '
      '${_formatMacro(nutrition.proteinGrams)}P · '
      '${_formatMacro(nutrition.carbsGrams)}C · '
      '${_formatMacro(nutrition.fatGrams)}F';
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
      (a.externalId != b.externalId || a.externalSource != b.externalSource)) {
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
