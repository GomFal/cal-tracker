import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../domain/models/nutrition_edit.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../../../core/motion.dart';
import '../../../shared/food_search_panel.dart';
import '../view_models/meal_templates_view_model.dart';

class MealTemplateEditorScreen extends StatefulWidget {
  const MealTemplateEditorScreen({
    super.key,
    this.templateId,
    this.initialDraft,
  });

  static const newRoute = '/templates/meals/new';

  static String editRoute(String templateId) =>
      '/templates/meals/$templateId/edit';

  final String? templateId;
  final UsualMealDraft? initialDraft;

  @override
  State<MealTemplateEditorScreen> createState() =>
      _MealTemplateEditorScreenState();
}

class _MealTemplateEditorScreenState extends State<MealTemplateEditorScreen> {
  final _titleController = TextEditingController();
  final _aliasesController = TextEditingController();
  final _items = <_TemplateMealItemController>[];
  List<FoodCandidateGroup> _candidateGroups = const [];
  bool _hydrated = false;
  bool _loadRequested = false;
  String? _validationError;

  bool get _isEditing => widget.templateId != null;

  @override
  void initState() {
    super.initState();
    if (!_isEditing) {
      _items.add(_TemplateMealItemController.empty());
      _hydrated = true;
    }
    final initialDraft = widget.initialDraft;
    if (initialDraft != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _applyDraft(initialDraft));
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _aliasesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MealTemplatesViewModel>();
    _requestLoad(viewModel);
    final template = widget.templateId == null
        ? null
        : viewModel.templateById(widget.templateId!);
    if (template != null && !_hydrated) {
      _hydrate(template);
    }

    final l10n = context.l10n;
    final isMissingTemplate =
        _isEditing && viewModel.hasLoaded && template == null;
    final palette = context.freshPalette;
    return ContentFrame(
      title: _isEditing
          ? l10n.mealTemplateEditorEditTitle
          : l10n.mealTemplateEditorCreateTitle,
      actions: [
        FreshIconButton(
          onPressed: () => _closeEditor(context),
          icon: Icons.close_rounded,
          tooltip: l10n.commonClose,
        ),
      ],
      child: isMissingTemplate
          ? FreshStatusBanner(
              icon: Icons.error_outline_rounded,
              title: l10n.mealTemplateEditorMissingTemplateTitle,
              message: l10n.mealTemplateEditorMissingTemplateMessage,
              color: palette.coral,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (viewModel.isLoading && !_hydrated) ...[
                  const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: FreshSpacing.md),
                ],
                _MealTemplateBasicsSection(
                  titleController: _titleController,
                  aliasesController: _aliasesController,
                ),
                if (_candidateGroups.isNotEmpty) ...[
                  const SizedBox(height: FreshSpacing.md),
                  _CandidateGroupsSection(
                    groups: _candidateGroups,
                    onSelected: _applyCandidate,
                  ),
                ],
                const SizedBox(height: FreshSpacing.md),
                _TemplateItemsSection(
                  items: _items,
                  onAddBlank: () {
                    setState(() {
                      _items.add(_TemplateMealItemController.empty());
                    });
                  },
                  onAddFood: (item) {
                    setState(() {
                      _items.add(
                        _TemplateMealItemController.fromMealItem(item),
                      );
                    });
                  },
                  onDelete: (index) {
                    setState(() {
                      _items.removeAt(index).dispose();
                      if (_items.isEmpty) {
                        _items.add(_TemplateMealItemController.empty());
                      }
                    });
                  },
                  onItemChanged: () => setState(() {}),
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: FreshSpacing.md),
                  FreshStatusBanner(
                    icon: Icons.error_outline_rounded,
                    title: _validationError!,
                    message: null,
                    color: palette.coral,
                  ),
                ],
                if (viewModel.error != null) ...[
                  const SizedBox(height: FreshSpacing.md),
                  FreshStatusBanner(
                    icon: Icons.error_outline_rounded,
                    title: context.l10n.mealTemplateEditorSaveFailedTitle,
                    message: viewModel.error,
                    color: palette.coral,
                  ),
                ],
                const SizedBox(height: FreshSpacing.lg),
                _SaveBar(
                  isSaving: viewModel.isSaving,
                  nutrition: _totalNutrition(),
                  onSave: template == null && _isEditing
                      ? null
                      : () => _save(viewModel, template),
                ),
              ],
            ),
    );
  }

  void _requestLoad(MealTemplatesViewModel viewModel) {
    if (_loadRequested) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      viewModel.load();
    });
  }

  void _hydrate(MealTemplate template) {
    _titleController.text = template.title;
    _aliasesController.text = template.aliases.join(', ');
    for (final item in _items) {
      item.dispose();
    }
    _items
      ..clear()
      ..addAll(template.items.map(_TemplateMealItemController.fromMealItem));
    if (_items.isEmpty) {
      _items.add(_TemplateMealItemController.empty());
    }
    _hydrated = true;
  }

  void _applyDraft(UsualMealDraft draft) {
    _validationError = null;
    if (draft.title != null && draft.title!.trim().isNotEmpty) {
      _titleController.text = draft.title!.trim();
    }
    if (draft.aliases.isNotEmpty) {
      _aliasesController.text = draft.aliases.join(', ');
    }
    if (draft.items.isNotEmpty) {
      for (final item in _items) {
        item.dispose();
      }
      _items
        ..clear()
        ..addAll(draft.items.map(_TemplateMealItemController.fromMealItem));
    }
    _candidateGroups = draft.candidateGroups;
    // Draft was applied (status is no longer shown in UI)
    // Candidate groups are handled by the calling method via _candidateGroups
  }

  void _applyCandidate(FoodCandidateGroup group, MealItem candidate) {
    final adjusted = _candidateWithMentionQuantity(candidate, group.mention);
    setState(() {
      final index = _items.indexWhere((item) => item.matchesGroup(group));
      if (index == -1) {
        _items.add(_TemplateMealItemController.fromMealItem(adjusted));
        return;
      }
      _items[index].replaceWith(adjusted);
    });
  }

  Future<void> _save(
    MealTemplatesViewModel viewModel,
    MealTemplate? template,
  ) async {
    setState(() => _validationError = null);
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(
        () => _validationError = context.l10n.mealTemplateEditorTitleRequired,
      );
      return;
    }
    final items = _validItems();
    if (items == null || items.isEmpty) {
      setState(
        () => _validationError = items == null
            ? context.l10n.commonIngredientDetailsError
            : context.l10n.commonAddAtLeastOneIngredient,
      );
      return;
    }
    final aliases = _aliasesController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    try {
      final saved = template == null
          ? await viewModel.createTemplate(
              title: title,
              items: items,
              aliases: aliases,
            )
          : await viewModel.updateTemplate(
              template,
              title: title,
              items: items,
              aliases: aliases,
            );
      if (!mounted) return;
      _closeEditor(context, saved);
    } catch (error) {
      // Error is surfaced through the viewModel and displayed in build()
    }
  }

  List<MealItem>? _validItems() {
    final items = <MealItem>[];
    for (final item in _items) {
      final parsed = item.toMealItemOrNull();
      if (parsed == null) {
        final hasAnyValue = item.hasAnyValue;
        if (hasAnyValue) return null;
        continue;
      }
      items.add(parsed);
    }
    return items;
  }

  NutritionSnapshot _totalNutrition() {
    var calories = 0;
    var protein = 0.0;
    var carbs = 0.0;
    var fat = 0.0;
    for (final item in _validItems() ?? const <MealItem>[]) {
      calories += item.calories;
      protein += item.proteinGrams;
      carbs += item.carbsGrams;
      fat += item.fatGrams;
    }
    return NutritionSnapshot(
      calories: calories,
      proteinGrams: roundMacroToTenth(protein),
      carbsGrams: roundMacroToTenth(carbs),
      fatGrams: roundMacroToTenth(fat),
    );
  }
}

void _closeEditor(BuildContext context, [Object? result]) {
  if (context.canPop()) {
    context.pop(result);
    return;
  }
  Navigator.of(context).maybePop(result);
}

class _MealTemplateBasicsSection extends StatelessWidget {
  const _MealTemplateBasicsSection({
    required this.titleController,
    required this.aliasesController,
  });

  final TextEditingController titleController;
  final TextEditingController aliasesController;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.mealTemplateEditorDetailsSection,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: FreshSpacing.md),
        FreshUnderlineTextField(
          fieldKey: const ValueKey('meal_template_title_field'),
          controller: titleController,
          label: l10n.mealTemplateEditorTitleLabel,
          placeholder: l10n.mealTemplateEditorTitleHint,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: FreshSpacing.md),
        FreshUnderlineTextField(
          fieldKey: const ValueKey('meal_template_aliases_field'),
          controller: aliasesController,
          label: l10n.mealTemplateEditorAliasesLabel,
          placeholder: l10n.mealTemplateEditorAliasesHint,
        ),
        Divider(height: 24, color: palette.rule),
      ],
    );
  }
}

class _CandidateGroupsSection extends StatelessWidget {
  const _CandidateGroupsSection({
    required this.groups,
    required this.onSelected,
  });

  final List<FoodCandidateGroup> groups;
  final void Function(FoodCandidateGroup group, MealItem candidate) onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 24, color: palette.rule),
        Text(
          l10n.mealTemplateEditorCandidatesSection,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: FreshSpacing.xs),
        Text(
          l10n.mealTemplateEditorCandidatesHelper,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
        ),
        const SizedBox(height: FreshSpacing.md),
        for (final group in groups) ...[
          Text(
            group.mention.originalText,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: FreshSpacing.sm),
          if (group.candidates.isEmpty)
            Text(
              l10n.mealTemplateEditorNoCandidates,
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Wrap(
              spacing: FreshSpacing.sm,
              runSpacing: FreshSpacing.sm,
              children: [
                for (final candidate in group.candidates.take(10))
                  ActionChip(
                    key: ValueKey(
                      'meal_template_candidate_${group.mention.originalText}_${candidate.name}',
                    ),
                    avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: Text(candidate.name),
                    onPressed: () => onSelected(group, candidate),
                  ),
              ],
            ),
          const SizedBox(height: FreshSpacing.md),
        ],
      ],
    );
  }
}

class _TemplateItemsSection extends StatefulWidget {
  const _TemplateItemsSection({
    required this.items,
    required this.onAddBlank,
    required this.onAddFood,
    required this.onDelete,
    this.onItemChanged,
  });

  final List<_TemplateMealItemController> items;
  final VoidCallback onAddBlank;
  final ValueChanged<MealItem> onAddFood;
  final ValueChanged<int> onDelete;
  final VoidCallback? onItemChanged;

  @override
  State<_TemplateItemsSection> createState() => _TemplateItemsSectionState();
}

class _TemplateItemsSectionState extends State<_TemplateItemsSection> {
  bool _searchExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FreshSectionTitle(title: l10n.mealEditorIngredientsSection),
        const SizedBox(height: FreshSpacing.sm),
        FreshAnimatedSwitcher(
          duration: FreshMotion.fast,
          child: _searchExpanded
              ? FoodSearchPanel(
                  key: const ValueKey('meal_template_food_search_panel'),
                  keyPrefix: 'meal_template_food_search',
                  searchFoods: context
                      .read<MealTemplatesViewModel>()
                      .searchFoods,
                  onSelected: (item) {
                    widget.onAddFood(item);
                    setState(() => _searchExpanded = false);
                  },
                  onClose: () => setState(() => _searchExpanded = false),
                )
              : KeyedSubtree(
                  key: const ValueKey('meal_template_food_search_collapsed'),
                  child: FreshSearchActionRow(
                    key: const ValueKey('meal_template_add_from_search_button'),
                    icon: Icons.search_rounded,
                    label: l10n.mealTemplateEditorAddFromSearch,
                    onTap: () => setState(() => _searchExpanded = true),
                  ),
                ),
        ),
        const SizedBox(height: FreshSpacing.md),
        for (var index = 0; index < widget.items.length; index++) ...[
          _TemplateItemCard(
            key: ValueKey('meal_template_item_card_$index'),
            item: widget.items[index],
            index: index,
            onDelete: () => widget.onDelete(index),
            onItemChanged: widget.onItemChanged,
          ),
          const SizedBox(height: FreshSpacing.md),
        ],
        OutlinedButton.icon(
          key: const ValueKey('meal_template_add_blank_item_button'),
          onPressed: widget.onAddBlank,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.commonAddIngredient),
        ),
      ],
    );
  }
}

class _TemplateItemCard extends StatefulWidget {
  const _TemplateItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.onDelete,
    this.onItemChanged,
  });

  final _TemplateMealItemController item;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback? onItemChanged;

  @override
  State<_TemplateItemCard> createState() => _TemplateItemCardState();
}

class _TemplateItemCardState extends State<_TemplateItemCard> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final nutrition = widget.item.previewNutrition;
    return Padding(
      padding: const EdgeInsets.only(top: FreshSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.commonIngredient} ${widget.index + 1}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('meal_template_delete_item_${widget.index}'),
                onPressed: widget.onDelete,
                tooltip: l10n.commonDeleteIngredient,
                icon: const Icon(Icons.delete_outline_rounded),
                color: palette.inkMuted,
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.sm),
          FreshUnderlineTextField(
            fieldKey: ValueKey('meal_template_item_name_${widget.index}'),
            controller: widget.item.nameController,
            label: l10n.foodSearchName,
            onChanged: (_) => _notifyChanged(),
          ),
          const SizedBox(height: FreshSpacing.sm),
          Text(
            l10n.commonAmount,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          FreshInlineAmountStepper(
            amountFieldKey: ValueKey(
              'meal_template_item_quantity_${widget.index}',
            ),
            unitFieldKey: ValueKey('meal_template_item_unit_${widget.index}'),
            amountController: widget.item.quantityController,
            unitController: widget.item.unitController,
            decrementLabel: widget.item.isGramUnit ? '−10g' : '−1',
            incrementLabel: widget.item.isGramUnit ? '+10g' : '+1',
            decrementKey: ValueKey(
              'meal_template_item_decrease_10_${widget.index}',
            ),
            incrementKey: ValueKey(
              'meal_template_item_increase_10_${widget.index}',
            ),
            onAmountChanged: (_) => _notifyChanged(),
            onUnitChanged: (_) => _notifyChanged(),
            onDecrement: () {
              widget.item.adjustQuantity(widget.item.isGramUnit ? -10 : -1);
              _notifyChanged();
            },
            onIncrement: () {
              widget.item.adjustQuantity(widget.item.isGramUnit ? 10 : 1);
              _notifyChanged();
            },
          ),
          const SizedBox(height: FreshSpacing.sm),
          FreshNumberUnitField(
            fieldKey: ValueKey('meal_template_item_calories_${widget.index}'),
            label: l10n.commonCalories,
            controller: widget.item.caloriesController,
            unit: l10n.commonKcal,
            keyboardType: TextInputType.number,
            onChanged: (_) => _notifyChanged(),
          ),
          const SizedBox(height: FreshSpacing.sm),
          FreshMacroFields(
            fields: [
              FreshMacroFieldData(
                key: ValueKey('meal_template_item_protein_${widget.index}'),
                label: l10n.commonProtein,
                controller: widget.item.proteinController,
                color: palette.coral,
                onChanged: (_) => _notifyChanged(),
              ),
              FreshMacroFieldData(
                key: ValueKey('meal_template_item_carbs_${widget.index}'),
                label: l10n.commonCarbs,
                controller: widget.item.carbsController,
                color: palette.orange,
                onChanged: (_) => _notifyChanged(),
              ),
              FreshMacroFieldData(
                key: ValueKey('meal_template_item_fat_${widget.index}'),
                label: l10n.commonFat,
                controller: widget.item.fatController,
                color: palette.yellow,
                onChanged: (_) => _notifyChanged(),
              ),
            ],
          ),
          if (nutrition != null) ...[
            const SizedBox(height: FreshSpacing.sm),
            Text(
              _nutritionLabel(context, nutrition),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.inkMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _notifyChanged() {
    setState(() {});
    widget.onItemChanged?.call();
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.isSaving,
    required this.nutrition,
    required this.onSave,
  });

  final bool isSaving;
  final NutritionSnapshot nutrition;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return DecoratedBox(
      key: const ValueKey('meal_template_save_bar'),
      decoration: BoxDecoration(color: palette.screen),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, FreshSpacing.lg, 0, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            final total = _TotalNutrition(nutrition: nutrition);
            final button = FilledButton.icon(
              key: const ValueKey('meal_template_save_button'),
              onPressed: isSaving ? null : onSave,
              style: FilledButton.styleFrom(
                backgroundColor: palette.lime,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                disabledBackgroundColor: palette.surfaceMuted,
                disabledForegroundColor: palette.inkMuted,
              ),
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(context.l10n.mealTemplateEditorSaveButton),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  total,
                  const SizedBox(height: FreshSpacing.md),
                  button,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: total),
                const SizedBox(width: FreshSpacing.md),
                button,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TotalNutrition extends StatelessWidget {
  const _TotalNutrition({required this.nutrition});

  final NutritionSnapshot nutrition;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    return Column(
      key: const ValueKey('meal_template_total_nutrition_summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.mealEditorMealTotal,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: palette.inkMuted),
        ),
        const SizedBox(height: FreshSpacing.xs),
        Text(
          _nutritionLabel(context, nutrition),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: palette.ink),
        ),
      ],
    );
  }
}

class _TemplateMealItemController {
  _TemplateMealItemController({
    required String name,
    required String quantity,
    required String unit,
    required String calories,
    required String protein,
    required String carbs,
    required String fat,
    this.originalText,
    this.canonicalName,
    this.language,
    this.source = 'manual',
    this.externalSource,
    this.externalId,
    this.sourceUrl,
    this.license,
    this.confidence,
    this.needsReview,
    this.resolvedGrams,
    this.portionDescription,
  }) : nameController = TextEditingController(text: name),
       quantityController = TextEditingController(text: quantity),
       unitController = TextEditingController(text: unit),
       caloriesController = TextEditingController(text: calories),
       proteinController = TextEditingController(text: protein),
       carbsController = TextEditingController(text: carbs),
       fatController = TextEditingController(text: fat);

  factory _TemplateMealItemController.empty() {
    return _TemplateMealItemController(
      name: '',
      quantity: '',
      unit: 'g',
      calories: '',
      protein: '',
      carbs: '',
      fat: '',
    );
  }

  factory _TemplateMealItemController.fromMealItem(MealItem item) {
    return _TemplateMealItemController(
      name: item.name,
      quantity: _formatQuantity(item.quantity),
      unit: item.unit,
      calories: item.calories.toString(),
      protein: _formatQuantity(item.proteinGrams),
      carbs: _formatQuantity(item.carbsGrams),
      fat: _formatQuantity(item.fatGrams),
      originalText: item.originalText,
      canonicalName: item.canonicalName,
      language: item.language,
      source: item.source,
      externalSource: item.externalSource,
      externalId: item.externalId,
      sourceUrl: item.sourceUrl,
      license: item.license,
      confidence: item.confidence,
      needsReview: item.needsReview,
      resolvedGrams: item.resolvedGrams,
      portionDescription: item.portionDescription,
    );
  }

  final TextEditingController nameController;
  final TextEditingController quantityController;
  final TextEditingController unitController;
  final TextEditingController caloriesController;
  final TextEditingController proteinController;
  final TextEditingController carbsController;
  final TextEditingController fatController;
  String? originalText;
  String? canonicalName;
  String? language;
  String source;
  String? externalSource;
  String? externalId;
  String? sourceUrl;
  String? license;
  double? confidence;
  bool? needsReview;
  double? resolvedGrams;
  String? portionDescription;

  bool get hasAnyValue {
    final unit = unitController.text.trim();
    return nameController.text.trim().isNotEmpty ||
        quantityController.text.trim().isNotEmpty ||
        (unit.isNotEmpty && unit != 'g') ||
        caloriesController.text.trim().isNotEmpty ||
        proteinController.text.trim().isNotEmpty ||
        carbsController.text.trim().isNotEmpty ||
        fatController.text.trim().isNotEmpty;
  }

  NutritionSnapshot? get previewNutrition {
    final calories = int.tryParse(caloriesController.text.trim());
    final protein = _parseDouble(proteinController.text);
    final carbs = _parseDouble(carbsController.text);
    final fat = _parseDouble(fatController.text);
    if (calories == null || protein == null || carbs == null || fat == null) {
      return null;
    }
    return NutritionSnapshot(
      calories: calories,
      proteinGrams: roundMacroToTenth(protein),
      carbsGrams: roundMacroToTenth(carbs),
      fatGrams: roundMacroToTenth(fat),
    );
  }

  bool get isGramUnit => unitController.text.trim().toLowerCase() == 'g';

  void adjustQuantity(double delta) {
    final current = _parseDouble(quantityController.text) ?? 0;
    final next = current + delta;
    quantityController.text = _formatQuantity(next < 0.1 ? 0.1 : next);
  }

  void replaceWith(MealItem item) {
    nameController.text = item.name;
    quantityController.text = _formatQuantity(item.quantity);
    unitController.text = item.unit;
    caloriesController.text = item.calories.toString();
    proteinController.text = _formatQuantity(item.proteinGrams);
    carbsController.text = _formatQuantity(item.carbsGrams);
    fatController.text = _formatQuantity(item.fatGrams);
    originalText = item.originalText;
    canonicalName = item.canonicalName;
    language = item.language;
    source = item.source;
    externalSource = item.externalSource;
    externalId = item.externalId;
    sourceUrl = item.sourceUrl;
    license = item.license;
    confidence = item.confidence;
    needsReview = item.needsReview;
    resolvedGrams = item.resolvedGrams;
    portionDescription = item.portionDescription;
  }

  bool matchesGroup(FoodCandidateGroup group) {
    final names = _normalizedValues([
      nameController.text,
      canonicalName,
      originalText,
    ]);
    final mentionNames = _normalizedValues([
      group.mention.originalText,
      group.mention.canonicalName,
      group.mention.canonicalEnglishName,
    ]);
    return names.intersection(mentionNames).isNotEmpty;
  }

  MealItem? toMealItemOrNull() {
    final name = nameController.text.trim();
    final quantity = _parseDouble(quantityController.text);
    final unit = unitController.text.trim();
    final calories = int.tryParse(caloriesController.text.trim());
    final protein = _parseDouble(proteinController.text);
    final carbs = _parseDouble(carbsController.text);
    final fat = _parseDouble(fatController.text);
    if (name.isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        unit.isEmpty ||
        calories == null ||
        calories < 0 ||
        protein == null ||
        protein < 0 ||
        carbs == null ||
        carbs < 0 ||
        fat == null ||
        fat < 0) {
      return null;
    }
    return MealItem(
      name: name,
      quantity: quantity,
      unit: unit,
      calories: calories,
      proteinGrams: roundMacroToTenth(protein),
      carbsGrams: roundMacroToTenth(carbs),
      fatGrams: roundMacroToTenth(fat),
      source: source,
      originalText: originalText,
      canonicalName: canonicalName,
      language: language,
      externalSource: externalSource,
      externalId: externalId,
      sourceUrl: sourceUrl,
      license: license,
      confidence: confidence,
      needsReview: needsReview,
      resolvedGrams: resolvedGrams,
      portionDescription: portionDescription,
    );
  }

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    unitController.dispose();
    caloriesController.dispose();
    proteinController.dispose();
    carbsController.dispose();
    fatController.dispose();
  }
}

MealItem _candidateWithMentionQuantity(
  MealItem candidate,
  FoodMention mention,
) {
  if (candidate.unit.trim().toLowerCase() !=
          mention.unit.trim().toLowerCase() ||
      candidate.quantity <= 0 ||
      mention.quantity <= 0) {
    return candidate;
  }
  final factor = mention.quantity / candidate.quantity;
  return candidate.copyWith(
    quantity: mention.quantity,
    unit: mention.unit,
    calories: (candidate.calories * factor).round(),
    proteinGrams: roundMacroToTenth(candidate.proteinGrams * factor),
    carbsGrams: roundMacroToTenth(candidate.carbsGrams * factor),
    fatGrams: roundMacroToTenth(candidate.fatGrams * factor),
  );
}

String _nutritionLabel(BuildContext context, NutritionSnapshot nutrition) {
  final l10n = context.l10n;
  return '${nutrition.calories} ${l10n.commonKcal} · '
      '${_formatQuantity(nutrition.proteinGrams)}g ${l10n.commonProtein} · '
      '${_formatQuantity(nutrition.carbsGrams)}g ${l10n.commonCarbs} · '
      '${_formatQuantity(nutrition.fatGrams)}g ${l10n.commonFat}';
}

double? _parseDouble(String? value) {
  final normalized = (value ?? '').trim().replaceAll(',', '.');
  return double.tryParse(normalized);
}

Set<String> _normalizedValues(List<String?> values) {
  return values
      .map((value) => value?.trim().toLowerCase())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet();
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
