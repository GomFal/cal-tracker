import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/nutrition_edit.dart';
import '../../domain/models/nutrition_models.dart';
import '../../l10n/app_localizations_context.dart';
import '../core/design_system.dart';
import 'food_search_panel.dart';
import 'nutrition_edit_components.dart';

class MealItemEditorSheet extends StatefulWidget {
  const MealItemEditorSheet({
    super.key,
    required this.meal,
    this.keyPrefix = 'meal',
    this.searchFoods,
  });

  final Meal meal;
  final String keyPrefix;
  final FoodSearchCallback? searchFoods;

  @override
  State<MealItemEditorSheet> createState() => _MealItemEditorSheetState();
}

class _MealItemEditorSheetState extends State<MealItemEditorSheet> {
  late final List<_EditableMealItem> _items;
  bool _addSearchExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = [for (final item in widget.meal.items) _EditableMealItem(item)];
    if (_items.isEmpty) {
      _items.add(_EditableMealItem.empty());
    }
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
    final l10n = context.l10n;
    final palette = context.freshPalette;
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.surfaceSoft),
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
                    color: context.freshPalette.rule,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: FreshSpacing.lg),
              Text(l10n.commonEditIngredients, style: textTheme.titleLarge),
              const SizedBox(height: FreshSpacing.xs),
              Text(
                widget.meal.title,
                style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: FreshSpacing.md),
              _MealTotalSummary(items: _items),
              const SizedBox(height: FreshSpacing.md),
              if (_error != null) ...[
                FreshStatusBanner(
                  icon: Icons.error_outline_rounded,
                  title: l10n.commonCheckIngredientDetails,
                  message: _error!,
                  color: palette.coral,
                ),
                const SizedBox(height: FreshSpacing.md),
              ],
              Text(
                l10n.mealEditorIngredientsSection,
                style: textTheme.labelLarge?.copyWith(
                  color: palette.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: FreshSpacing.sm),
              if (widget.searchFoods != null) ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _addSearchExpanded
                      ? FoodSearchPanel(
                          key: ValueKey(
                            '${widget.keyPrefix}_food_search_panel',
                          ),
                          keyPrefix: '${widget.keyPrefix}_food_search',
                          searchFoods: widget.searchFoods!,
                          onSelected: (item) {
                            setState(() {
                              _items.add(_EditableMealItem(item));
                              _addSearchExpanded = false;
                              _error = null;
                            });
                          },
                          onClose: () {
                            setState(() => _addSearchExpanded = false);
                          },
                        )
                      : Align(
                          key: ValueKey(
                            '${widget.keyPrefix}_food_search_collapsed',
                          ),
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: ValueKey(
                              '${widget.keyPrefix}_add_from_search_button',
                            ),
                            onPressed: () {
                              setState(() => _addSearchExpanded = true);
                            },
                            icon: const Icon(Icons.search_rounded),
                            label: Text(l10n.mealTemplateEditorAddFromSearch),
                          ),
                        ),
                ),
                const SizedBox(height: FreshSpacing.md),
              ],
              for (var index = 0; index < _items.length; index++) ...[
                _IngredientEditorCard(
                  key: ValueKey('${widget.keyPrefix}_item_card_$index'),
                  item: _items[index],
                  index: index,
                  keyPrefix: widget.keyPrefix,
                  searchFoods: widget.searchFoods,
                  onChanged: () {
                    if (_error != null) {
                      _error = null;
                    }
                    setState(() {});
                  },
                  onReplace: (replacement) {
                    setState(() {
                      _items[index].dispose();
                      _items[index] = _EditableMealItem(replacement);
                      _error = null;
                    });
                  },
                  onDelete: _items.length == 1
                      ? null
                      : () {
                          setState(() {
                            _items.removeAt(index).dispose();
                          });
                        },
                ),
                const SizedBox(height: FreshSpacing.lg),
              ],
              OutlinedButton.icon(
                key: ValueKey('add_${widget.keyPrefix}_item_button'),
                onPressed: () {
                  setState(() {
                    _items.add(_EditableMealItem.empty());
                    _error = null;
                  });
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.commonAddIngredient),
              ),
              const SizedBox(height: FreshSpacing.md),
              FilledButton.icon(
                key: ValueKey('save_${widget.keyPrefix}_item_edits_button'),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.commonSaveEdits),
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
      final mealItem = item.toMealItem();
      if (mealItem == null) {
        setState(() {
          _error = context.l10n.commonIngredientDetailsError;
        });
        return;
      }
      edited.add(mealItem);
    }
    if (edited.isEmpty) {
      setState(() {
        _error = context.l10n.commonAddAtLeastOneIngredient;
      });
      return;
    }
    Navigator.of(context).pop(edited);
  }
}

class _MealTotalSummary extends StatelessWidget {
  const _MealTotalSummary({required this.items});

  final List<_EditableMealItem> items;

  @override
  Widget build(BuildContext context) {
    final total = NutritionEdit.sum([
      for (final item in items) item.currentNutrition(),
    ]);
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final caloriesText = Text(
      context.l10n.caloriesValue(total.calories),
      style: textTheme.headlineMedium?.copyWith(
        color: palette.ink,
        fontWeight: FontWeight.w800,
      ),
    );
    final macrosText = Text(
      _macroSummary(context, total),
      textAlign: TextAlign.end,
      style: textTheme.bodySmall?.copyWith(
        color: palette.inkSoft,
        height: 1.25,
      ),
    );
    return FreshCard(
      key: const ValueKey('meal_editor_total_card'),
      padding: const EdgeInsets.all(16),
      shadow: false,
      color: palette.limeWash,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.mealEditorMealTotal,
            style: textTheme.labelLarge?.copyWith(
              color: palette.limeDeep,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 260) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    caloriesText,
                    const SizedBox(height: FreshSpacing.xs),
                    macrosText,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  caloriesText,
                  const Spacer(),
                  Flexible(child: macrosText),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IngredientEditorCard extends StatelessWidget {
  const _IngredientEditorCard({
    super.key,
    required this.item,
    required this.index,
    required this.keyPrefix,
    required this.searchFoods,
    required this.onChanged,
    required this.onReplace,
    required this.onDelete,
  });

  final _EditableMealItem item;
  final int index;
  final String keyPrefix;
  final FoodSearchCallback? searchFoods;
  final VoidCallback onChanged;
  final ValueChanged<MealItem> onReplace;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final nutrition = item.currentNutrition();
    final macroCalories = nutrition.macroCalories;
    final hasWarning = nutrition.hasCalorieMismatch;
    final nameField = TextField(
      key: ValueKey('${keyPrefix}_item_name_$index'),
      controller: item.nameController,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: l10n.commonIngredient,
        isDense: true,
      ),
    );
    final caloriesPill = DecoratedBox(
      decoration: BoxDecoration(
        color: hasWarning
            ? palette.coral.withValues(alpha: 0.08)
            : palette.limeWash,
        borderRadius: BorderRadius.circular(FreshRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              context.l10n.caloriesValue(nutrition.calories),
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (hasWarning)
              Text(
                l10n.mealEditorMacroCaloriesShort(macroCalories),
                style: textTheme.labelSmall?.copyWith(
                  color: palette.coral,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
    return FreshCard(
      padding: const EdgeInsets.all(16),
      shadow: true,
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 260) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    nameField,
                    const SizedBox(height: FreshSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: caloriesPill,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nameField),
                  const SizedBox(width: FreshSpacing.sm),
                  caloriesPill,
                ],
              );
            },
          ),
          const SizedBox(height: FreshSpacing.md),
          Text(
            l10n.commonAmount,
            style: textTheme.labelMedium?.copyWith(
              color: palette.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: FreshSpacing.xs),
          Row(
            children: [
              _QuantityStepButton(
                key: ValueKey('${keyPrefix}_item_decrease_10_$index'),
                label: item.isGramUnit ? '-10g' : '-1',
                onPressed: () {
                  item.adjustQuantity(item.isGramUnit ? -10 : -1);
                  onChanged();
                },
              ),
              const SizedBox(width: FreshSpacing.sm),
              Expanded(
                child: TextField(
                  key: ValueKey('${keyPrefix}_item_quantity_field_$index'),
                  controller: item.quantityController,
                  onChanged: (_) => onChanged(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              SizedBox(
                width: 64,
                child: TextField(
                  key: ValueKey('${keyPrefix}_item_unit_$index'),
                  controller: item.unitController,
                  onChanged: (_) => onChanged(),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              _QuantityStepButton(
                key: ValueKey('${keyPrefix}_item_increase_10_$index'),
                label: item.isGramUnit ? '+10g' : '+1',
                onPressed: () {
                  item.adjustQuantity(item.isGramUnit ? 10 : 1);
                  onChanged();
                },
              ),
            ],
          ),
          if (item.isGramUnit) ...[
            const SizedBox(height: FreshSpacing.sm),
            Center(
              child: Wrap(
                key: ValueKey('${keyPrefix}_item_quantity_presets_$index'),
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: FreshSpacing.xs,
                runSpacing: FreshSpacing.xs,
                children: [
                  for (final preset in const [50.0, 100.0, 150.0, 200.0])
                    ActionChip(
                      key: ValueKey(
                        '${keyPrefix}_item_quantity_preset_${preset.toInt()}_$index',
                      ),
                      label: Text('${preset.toInt()}g'),
                      onPressed: () {
                        item.setQuantity(preset);
                        onChanged();
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: FreshSpacing.md),
          NutritionMacroSummaryText(nutrition: nutrition),
          if (hasWarning) ...[
            const SizedBox(height: FreshSpacing.sm),
            NutritionMacroWarningBanner(
              key: ValueKey('${keyPrefix}_item_macro_warning_$index'),
              title: l10n.mealEditorCaloriesMismatchTitle,
              message: l10n.mealEditorCaloriesMismatchMessage(macroCalories),
            ),
          ],
          if (searchFoods != null) ...[
            const SizedBox(height: FreshSpacing.sm),
            _InlineReplacementFoodSearch(
              key: ValueKey('${keyPrefix}_item_search_$index'),
              index: index,
              item: item,
              keyPrefix: keyPrefix,
              searchFoods: searchFoods!,
              onSelected: onReplace,
            ),
          ],
          const SizedBox(height: FreshSpacing.sm),
          Row(
            children: [
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: ValueKey('${keyPrefix}_item_edit_details_$index'),
                    onPressed: () async {
                      final edited = await showModalBottomSheet<NutritionEdit>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (context) => _NutritionDetailsSheet(
                          item: item,
                          keyPrefix: keyPrefix,
                          index: index,
                        ),
                      );
                      if (edited == null) return;
                      item.setNutritionOverride(edited);
                      onChanged();
                    },
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(
                      l10n.mealEditorEditDetails,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('delete_${keyPrefix}_item_$index'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: l10n.commonDeleteIngredient,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineReplacementFoodSearch extends StatefulWidget {
  const _InlineReplacementFoodSearch({
    super.key,
    required this.index,
    required this.item,
    required this.keyPrefix,
    required this.searchFoods,
    required this.onSelected,
  });

  final int index;
  final _EditableMealItem item;
  final String keyPrefix;
  final FoodSearchCallback searchFoods;
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
    final searchKeyPrefix = '${widget.keyPrefix}_item_${widget.index}_search';
    if (!_expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey('${searchKeyPrefix}_toggle'),
          onPressed: () => setState(() => _expanded = true),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: Text(context.l10n.foodSearchReplaceSearch),
        ),
      );
    }

    return FoodSearchPanel(
      keyPrefix: searchKeyPrefix,
      searchFoods: widget.searchFoods,
      onSelected: (item) {
        widget.onSelected(item);
        setState(() => _expanded = false);
      },
      onClose: () => setState(() => _expanded = false),
      actionLabel: context.l10n.foodSearchReplaceAction,
      actionIcon: Icons.swap_horiz_rounded,
      initialQuery: widget.item.nameController.text,
      closeKeySuffix: 'collapse',
    );
  }
}

class _QuantityStepButton extends StatelessWidget {
  const _QuantityStepButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return SizedBox(
      width: 52,
      height: 48,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: palette.limeDeep,
          overlayColor: palette.lime.withValues(alpha: 0.12),
          padding: EdgeInsets.zero,
          minimumSize: const Size(52, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          shape: const StadiumBorder(),
        ),
        child: Text(label),
      ),
    );
  }
}

class _NutritionDetailsSheet extends StatefulWidget {
  const _NutritionDetailsSheet({
    required this.item,
    required this.keyPrefix,
    required this.index,
  });

  final _EditableMealItem item;
  final String keyPrefix;
  final int index;

  @override
  State<_NutritionDetailsSheet> createState() => _NutritionDetailsSheetState();
}

class _NutritionDetailsSheetState extends State<_NutritionDetailsSheet> {
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final nutrition = widget.item.currentNutrition();
    _caloriesController = TextEditingController(
      text: nutrition.calories.toString(),
    );
    _proteinController = TextEditingController(
      text: formatMacro(nutrition.proteinGrams),
    );
    _carbsController = TextEditingController(
      text: formatMacro(nutrition.carbsGrams),
    );
    _fatController = TextEditingController(
      text: formatMacro(nutrition.fatGrams),
    );
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
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final preview = _previewNutrition();
    final macroCalories = preview?.macroCalories ?? 0;
    final showSuggestion = preview?.hasCalorieMismatch ?? false;
    return Padding(
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
                  color: context.freshPalette.rule,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: FreshSpacing.lg),
            Text(l10n.mealEditorNutritionDetails, style: textTheme.titleLarge),
            const SizedBox(height: FreshSpacing.xs),
            Text(
              widget.item.nameController.text.trim().isEmpty
                  ? l10n.commonIngredient
                  : widget.item.nameController.text.trim(),
              style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
            ),
            const SizedBox(height: FreshSpacing.md),
            if (_error != null) ...[
              FreshStatusBanner(
                icon: Icons.error_outline_rounded,
                title: l10n.commonCheckIngredientDetails,
                message: _error!,
                color: palette.coral,
              ),
              const SizedBox(height: FreshSpacing.md),
            ],
            TextField(
              key: ValueKey(
                '${widget.keyPrefix}_item_calories_${widget.index}',
              ),
              controller: _caloriesController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.commonCalories,
                suffixIcon: showSuggestion
                    ? NutritionCalorieSuggestionSuffix(
                        key: ValueKey(
                          '${widget.keyPrefix}_item_apply_suggestion_${widget.index}',
                        ),
                        calories: macroCalories,
                        onApply: () => _applyMacroCalories(macroCalories),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
              ),
            ),
            const SizedBox(height: FreshSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey(
                      '${widget.keyPrefix}_item_protein_${widget.index}',
                    ),
                    controller: _proteinController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    style: macroFieldStyle(Theme.of(context).textTheme, defaultNutritionMacroColors(context)[NutritionMacroKind.protein]!),
                    decoration: macroInputDecoration(
                      label: l10n.commonProtein,
                      color: defaultNutritionMacroColors(context)[NutritionMacroKind.protein]!,
                    ),
                  ),
                ),
                const SizedBox(width: FreshSpacing.sm),
                Expanded(
                  child: TextField(
                    key: ValueKey(
                      '${widget.keyPrefix}_item_carbs_${widget.index}',
                    ),
                    controller: _carbsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    style: macroFieldStyle(Theme.of(context).textTheme, defaultNutritionMacroColors(context)[NutritionMacroKind.carbs]!),
                    decoration: macroInputDecoration(
                      label: l10n.commonCarbs,
                      color: defaultNutritionMacroColors(context)[NutritionMacroKind.carbs]!,
                    ),
                  ),
                ),
                const SizedBox(width: FreshSpacing.sm),
                Expanded(
                  child: TextField(
                    key: ValueKey(
                      '${widget.keyPrefix}_item_fat_${widget.index}',
                    ),
                    controller: _fatController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    style: macroFieldStyle(Theme.of(context).textTheme, defaultNutritionMacroColors(context)[NutritionMacroKind.fat]!),
                    decoration: macroInputDecoration(
                      label: l10n.commonFat,
                      color: defaultNutritionMacroColors(context)[NutritionMacroKind.fat]!,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FreshSpacing.sm),
            if (!showSuggestion) ...[
              const SizedBox(height: FreshSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surfaceSoft,
                  borderRadius: BorderRadius.circular(FreshRadii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l10n.mealEditorCalculatedFromMacros(macroCalories),
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.inkMuted,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: FreshSpacing.md),
            FilledButton.icon(
              key: ValueKey(
                '${widget.keyPrefix}_item_save_details_${widget.index}',
              ),
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  NutritionEdit? _previewNutrition() {
    final calories = int.tryParse(_caloriesController.text.trim());
    final protein = double.tryParse(_proteinController.text.trim());
    final carbs = double.tryParse(_carbsController.text.trim());
    final fat = double.tryParse(_fatController.text.trim());
    if (calories == null || protein == null || carbs == null || fat == null) {
      return null;
    }
    return NutritionEdit(
      calories: calories,
      proteinGrams: roundMacroToTenth(protein),
      carbsGrams: roundMacroToTenth(carbs),
      fatGrams: roundMacroToTenth(fat),
    );
  }

  void _applyMacroCalories(int calories) {
    _caloriesController.text = calories.toString();
    _caloriesController.selection = TextSelection.collapsed(
      offset: _caloriesController.text.length,
    );
    setState(() {});
  }

  void _save() {
    final nutrition = _previewNutrition();
    if (nutrition == null ||
        nutrition.calories < 0 ||
        nutrition.proteinGrams < 0 ||
        nutrition.carbsGrams < 0 ||
        nutrition.fatGrams < 0) {
      setState(() {
        _error = context.l10n.commonIngredientDetailsError;
      });
      return;
    }
    Navigator.of(context).pop(nutrition);
  }
}

class _EditableMealItem {
  _EditableMealItem(MealItem item)
      : original = item,
        isNew = false {
    nameController = TextEditingController(text: item.name);
    quantityController = TextEditingController(
      text: formatQuantity(item.quantity),
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
        ),
        isNew = true {
    nameController = TextEditingController();
    quantityController = TextEditingController(text: '100');
    unitController = TextEditingController(text: 'g');
  }

  final MealItem original;
  final bool isNew;
  NutritionEdit? _nutritionOverride;
  double? _nutritionOverrideQuantity;
  late final TextEditingController nameController;
  late final TextEditingController quantityController;
  late final TextEditingController unitController;

  bool get isGramUnit => normalizedText(unitController.text) == 'g';

  void adjustQuantity(double delta) {
    final current = double.tryParse(quantityController.text.trim());
    final next = math.max(0.1, (current ?? original.quantity) + delta);
    setQuantity(next);
  }

  void setQuantity(double value) {
    quantityController.text = formatQuantity(value);
  }

  void setNutritionOverride(NutritionEdit value) {
    _nutritionOverride = value;
    _nutritionOverrideQuantity = double.tryParse(
      quantityController.text.trim(),
    );
  }

  NutritionEdit currentNutrition() {
    final quantity = double.tryParse(quantityController.text.trim());
    final override = _nutritionOverride;
    if (override != null) {
      final baseQuantity = _nutritionOverrideQuantity;
      final factor = baseQuantity != null &&
              baseQuantity > 0 &&
              quantity != null &&
              quantity > 0
          ? quantity / baseQuantity
          : 1.0;
      return override.scaled(factor);
    }
    final factor = original.quantity > 0 && quantity != null && quantity > 0
        ? quantity / original.quantity
        : 1.0;
    return NutritionEdit(
      calories: (original.calories * factor).round(),
      proteinGrams: roundMacroToTenth(original.proteinGrams * factor),
      carbsGrams: roundMacroToTenth(original.carbsGrams * factor),
      fatGrams: roundMacroToTenth(original.fatGrams * factor),
    );
  }

  MealItem? toMealItem() {
    final name = nameController.text.trim();
    final quantity = double.tryParse(quantityController.text.trim());
    final unit = unitController.text.trim();
    if (name.isEmpty || quantity == null || quantity <= 0 || unit.isEmpty) {
      return null;
    }
    final nutrition = currentNutrition();
    if (nutrition.calories < 0 ||
        nutrition.proteinGrams < 0 ||
        nutrition.carbsGrams < 0 ||
        nutrition.fatGrams < 0) {
      return null;
    }
    final source = original.source.contains('manual_edit')
        ? original.source
        : '${original.source}:manual_edit';
    return original.copyWith(
      name: name,
      quantity: quantity,
      unit: unit,
      calories: nutrition.calories,
      proteinGrams: nutrition.proteinGrams,
      carbsGrams: nutrition.carbsGrams,
      fatGrams: nutrition.fatGrams,
      source: isNew ? 'manual_edit' : source,
    );
  }

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    unitController.dispose();
  }
}



String _macroSummary(BuildContext context, NutritionEdit nutrition) {
  final l10n = context.l10n;
  return '${l10n.commonProtein} ${formatMacro(nutrition.proteinGrams)}g · '
      '${l10n.commonCarbs} ${formatMacro(nutrition.carbsGrams)}g · '
      '${l10n.commonFat} ${formatMacro(nutrition.fatGrams)}g';
}




