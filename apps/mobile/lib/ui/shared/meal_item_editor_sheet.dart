import 'package:flutter/material.dart';

import '../../domain/models/nutrition_edit.dart';
import '../../domain/models/nutrition_models.dart';
import '../../l10n/app_localizations_context.dart';
import '../core/design_system.dart';
import 'editable_meal_item_controller.dart';
import 'food_search_panel.dart';
import 'nutrition_edit_components.dart';
import 'nutrition_edit_sheet.dart';

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
  late final List<EditableMealItemController> _items;
  bool _addSearchExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final item in widget.meal.items) EditableMealItemController(item),
    ];
    if (_items.isEmpty) {
      _items.add(EditableMealItemController.empty());
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
      decoration: BoxDecoration(color: palette.surface),
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
                              _items.add(EditableMealItemController(item));
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
                      _items[index] = EditableMealItemController(replacement);
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
                    _items.add(EditableMealItemController.empty());
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
      final mealItem = item.toValidatedMealItem();
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

  final List<EditableMealItemController> items;

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
    return Container(
      key: const ValueKey('meal_editor_total_card'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(FreshRadii.md),
        border: Border.all(color: palette.rule),
      ),
      padding: const EdgeInsets.all(16),
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

  final EditableMealItemController item;
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
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(FreshRadii.md),
      ),
      padding: const EdgeInsets.all(16),
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
                        builder: (sheetContext) => NutritionEditSheet(
                          initialNutrition: item.currentNutrition(),
                          ingredientName: item.nameController.text.trim(),
                          title: sheetContext.l10n.mealEditorNutritionDetails,
                          subtitleFallback: sheetContext.l10n.commonIngredient,
                          keyPrefix: keyPrefix,
                          index: index,
                          fieldKeySuffix: 'item',
                          saveButtonKeySuffix: 'item_save_details',
                          useMacroFieldStyle: true,
                          useSafeArea: false,
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
  final EditableMealItemController item;
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

String _macroSummary(BuildContext context, NutritionEdit nutrition) {
  final l10n = context.l10n;
  return '${l10n.commonProtein} ${formatMacro(nutrition.proteinGrams)}g · '
      '${l10n.commonCarbs} ${formatMacro(nutrition.carbsGrams)}g · '
      '${l10n.commonFat} ${formatMacro(nutrition.fatGrams)}g';
}
