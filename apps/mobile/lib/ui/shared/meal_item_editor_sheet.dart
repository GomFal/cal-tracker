import 'package:flutter/material.dart';

import '../../domain/models/nutrition_edit.dart';
import '../../domain/models/nutrition_models.dart';
import '../../l10n/app_localizations_context.dart';
import '../core/design_system.dart';
import 'editable_meal_item_controller.dart';
import 'food_search_panel.dart';
import 'nutrition_edit_components.dart';
import 'nutrition_edit_sheet.dart';

typedef MealItemHeaderBuilder = Widget? Function(
  BuildContext context,
  EditableMealItemController item,
  int index,
  ValueChanged<MealItem> onReplace,
);

class MealItemEditorSheet extends StatefulWidget {
  const MealItemEditorSheet({
    super.key,
    required this.meal,
    this.keyPrefix = 'meal',
    this.searchFoods,
    this.onDeleteMeal,
    this.itemHeaderBuilder,
    this.initiallyExpandFirst = false,
    this.ensureInitialItem = true,
  });

  final Meal meal;
  final String keyPrefix;
  final FoodSearchCallback? searchFoods;
  final Future<bool> Function()? onDeleteMeal;
  final MealItemHeaderBuilder? itemHeaderBuilder;
  final bool initiallyExpandFirst;
  final bool ensureInitialItem;

  @override
  State<MealItemEditorSheet> createState() => _MealItemEditorSheetState();
}

class _MealItemEditorSheetState extends State<MealItemEditorSheet> {
  late final List<EditableMealItemController> _items;
  bool _addSearchExpanded = false;
  int? _expandedIndex;
  int? _replacementSearchIndex;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final item in widget.meal.items) EditableMealItemController(item),
    ];
    if (_items.isEmpty && widget.ensureInitialItem) {
      _items.add(EditableMealItemController.empty());
      _expandedIndex = 0;
    } else if (widget.initiallyExpandFirst) {
      _expandedIndex = 0;
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
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.surface),
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
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
              const SizedBox(height: FreshSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.commonEditIngredients,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.meal.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FreshSpacing.sm),
                  FilledButton(
                    key: ValueKey(
                      widget.keyPrefix == 'proposal'
                          ? 'save_proposal_edits_button'
                          : 'save_${widget.keyPrefix}_item_edits_button',
                    ),
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                    ),
                    child: Text(l10n.commonSave),
                  ),
                ],
              ),
              const SizedBox(height: FreshSpacing.sm),
              _MealTotalSummary(items: _items),
              if (widget.onDeleteMeal != null) ...[
                const SizedBox(height: FreshSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: ValueKey(
                      '${widget.keyPrefix}_delete_meal_${widget.meal.id}',
                    ),
                    onPressed: _deleteMeal,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(l10n.dashboardDeleteMealTooltip),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.coral,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 4,
                      ),
                    ),
                  ),
                ),
              ],
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
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.mealEditorIngredientsSection,
                        style: textTheme.labelLarge?.copyWith(
                          color: palette.inkMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: FreshSpacing.xs),
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
                                      final newIndex = _items.length;
                                      _items.add(
                                        EditableMealItemController(item),
                                      );
                                      _expandedIndex = newIndex;
                                      _replacementSearchIndex = null;
                                      _addSearchExpanded = false;
                                      _error = null;
                                    });
                                  },
                                  onClose: () {
                                    setState(() => _addSearchExpanded = false);
                                  },
                                )
                              : KeyedSubtree(
                                  key: ValueKey(
                                    '${widget.keyPrefix}_food_search_collapsed',
                                  ),
                                  child: _CompactSearchAddBar(
                                    key: ValueKey(
                                      '${widget.keyPrefix}_add_from_search_button',
                                    ),
                                    label: l10n.mealEditorSearchOrAddIngredient,
                                    onTap: () {
                                      setState(() {
                                        _addSearchExpanded = true;
                                        _replacementSearchIndex = null;
                                      });
                                    },
                                  ),
                                ),
                        ),
                        const SizedBox(height: FreshSpacing.sm),
                      ],
                      for (var index = 0; index < _items.length; index++) ...[
                        _IngredientEditorCard(
                          key: ValueKey('${widget.keyPrefix}_item_card_$index'),
                          item: _items[index],
                          index: index,
                          keyPrefix: widget.keyPrefix,
                          searchFoods: widget.searchFoods,
                          isExpanded: _expandedIndex == index,
                          isReplacementSearchActive:
                              _replacementSearchIndex == index,
                          header: widget.itemHeaderBuilder?.call(
                            context,
                            _items[index],
                            index,
                            (replacement) {
                              setState(() {
                                _items[index].replaceWith(replacement);
                                _expandedIndex = index;
                                _error = null;
                              });
                            },
                          ),
                          onExpand: () {
                            setState(() {
                              _expandedIndex = index;
                              _replacementSearchIndex = null;
                            });
                          },
                          onReplacementSearchRequested:
                              widget.searchFoods == null
                                  ? null
                                  : () {
                                      setState(() {
                                        _expandedIndex = index;
                                        _replacementSearchIndex = index;
                                        _addSearchExpanded = false;
                                      });
                                    },
                          onReplacementSearchClosed: () {
                            setState(() => _replacementSearchIndex = null);
                          },
                          onChanged: () {
                            if (_error != null) {
                              _error = null;
                            }
                            setState(() {});
                          },
                          onReplace: (replacement) {
                            setState(() {
                              final scaledReplacement =
                                  _replacementWithCurrentQuantity(
                                _items[index],
                                replacement,
                              );
                              _items[index].dispose();
                              _items[index] = EditableMealItemController(
                                scaledReplacement,
                              );
                              _expandedIndex = index;
                              _replacementSearchIndex = null;
                              _error = null;
                            });
                          },
                          onDelete: _items.length == 1
                              ? null
                              : () {
                                  setState(() {
                                    _items.removeAt(index).dispose();
                                    if (_expandedIndex == index) {
                                      _expandedIndex = null;
                                    } else if (_expandedIndex != null &&
                                        _expandedIndex! > index) {
                                      _expandedIndex = _expandedIndex! - 1;
                                    }
                                    if (_replacementSearchIndex == index) {
                                      _replacementSearchIndex = null;
                                    } else if (_replacementSearchIndex !=
                                            null &&
                                        _replacementSearchIndex! > index) {
                                      _replacementSearchIndex =
                                          _replacementSearchIndex! - 1;
                                    }
                                  });
                                },
                        ),
                        const SizedBox(height: FreshSpacing.sm),
                      ],
                      OutlinedButton.icon(
                        key: ValueKey('add_${widget.keyPrefix}_item_button'),
                        onPressed: () {
                          setState(() {
                            final newIndex = _items.length;
                            _items.add(EditableMealItemController.empty());
                            _expandedIndex = newIndex;
                            _replacementSearchIndex = null;
                            _error = null;
                          });
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l10n.commonAddIngredient),
                      ),
                    ],
                  ),
                ),
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

  Future<void> _deleteMeal() async {
    final deleteMeal = widget.onDeleteMeal;
    if (deleteMeal == null) return;
    final deleted = await deleteMeal();
    if (!mounted || !deleted) return;
    Navigator.of(context).pop();
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
    return KeyedSubtree(
      key: const ValueKey('meal_editor_total_card'),
      child: Text(
        '${context.l10n.caloriesValue(total.calories)}   '
        '${_compactMacroSummary(context, total)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium?.copyWith(
          color: palette.ink,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _CompactSearchAddBar extends StatelessWidget {
  const _CompactSearchAddBar({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: palette.inkMuted, size: 18),
              const SizedBox(width: FreshSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.inkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              Icon(Icons.add_rounded, color: palette.lime, size: 20),
            ],
          ),
        ),
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
    required this.isExpanded,
    required this.isReplacementSearchActive,
    required this.header,
    required this.onExpand,
    required this.onReplacementSearchRequested,
    required this.onReplacementSearchClosed,
    required this.onChanged,
    required this.onReplace,
    required this.onDelete,
  });

  final EditableMealItemController item;
  final int index;
  final String keyPrefix;
  final FoodSearchCallback? searchFoods;
  final bool isExpanded;
  final bool isReplacementSearchActive;
  final Widget? header;
  final VoidCallback onExpand;
  final VoidCallback? onReplacementSearchRequested;
  final VoidCallback onReplacementSearchClosed;
  final VoidCallback onChanged;
  final ValueChanged<MealItem> onReplace;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final nutrition = item.currentNutrition();
    final macroCalories = nutrition.macroCalories;
    final hasWarning = nutrition.hasCalorieMismatch;
    Widget content;
    if (!isExpanded) {
      content = _CompactIngredientRow(
        item: item,
        index: index,
        keyPrefix: keyPrefix,
        nutrition: nutrition,
        onTap: onExpand,
      );
    } else {
      final nameField = FreshUnderlineTextField(
        fieldKey: ValueKey('${keyPrefix}_item_name_$index'),
        controller: item.nameController,
        placeholder: l10n.commonIngredient,
        onChanged: (_) => onChanged(),
      );
      content = DecoratedBox(
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) ...[
                header!,
                const SizedBox(height: FreshSpacing.sm),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nameField),
                  const SizedBox(width: FreshSpacing.sm),
                  _IngredientOverflowMenu(
                    index: index,
                    keyPrefix: keyPrefix,
                    canReplace: searchFoods != null,
                    canDelete: onDelete != null,
                    onReplaceFood: onReplacementSearchRequested,
                    onEditDetails: () => _showNutritionDetails(context),
                    onDelete: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: FreshSpacing.sm),
              _CompactAmountStepper(
                amountFieldKey: ValueKey(
                  '${keyPrefix}_item_quantity_field_$index',
                ),
                unitFieldKey: ValueKey('${keyPrefix}_item_unit_$index'),
                amountController: item.quantityController,
                unitController: item.unitController,
                decrementKey: ValueKey('${keyPrefix}_item_decrease_10_$index'),
                incrementKey: ValueKey('${keyPrefix}_item_increase_10_$index'),
                onAmountChanged: (_) => onChanged(),
                onUnitChanged: (_) => onChanged(),
                onDecrement: () {
                  item.adjustQuantity(item.isGramUnit ? -10 : -1);
                  onChanged();
                },
                onIncrement: () {
                  item.adjustQuantity(item.isGramUnit ? 10 : 1);
                  onChanged();
                },
              ),
              if (item.isGramUnit) ...[
                const SizedBox(height: FreshSpacing.sm),
                Wrap(
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
                        label: Text('${preset.toInt()}'),
                        visualDensity: VisualDensity.compact,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          item.setQuantity(preset);
                          onChanged();
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: FreshSpacing.sm),
              _ExpandedNutritionSummary(
                nutrition: nutrition,
                macroCalories: macroCalories,
                hasWarning: hasWarning,
              ),
              if (hasWarning) ...[
                const SizedBox(height: FreshSpacing.sm),
                NutritionMacroWarningBanner(
                  key: ValueKey('${keyPrefix}_item_macro_warning_$index'),
                  title: l10n.mealEditorCaloriesMismatchTitle,
                  message:
                      l10n.mealEditorCaloriesMismatchMessage(macroCalories),
                ),
              ],
              if (isReplacementSearchActive && searchFoods != null) ...[
                const SizedBox(height: FreshSpacing.sm),
                FoodSearchPanel(
                  key: ValueKey('${keyPrefix}_item_search_$index'),
                  keyPrefix: '${keyPrefix}_item_${index}_search',
                  searchFoods: searchFoods!,
                  onSelected: onReplace,
                  onClose: onReplacementSearchClosed,
                  actionLabel: context.l10n.foodSearchReplaceAction,
                  actionIcon: Icons.swap_horiz_rounded,
                  initialQuery: item.nameController.text,
                  closeKeySuffix: 'collapse',
                ),
              ],
            ],
          ),
        ),
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: content,
    );
  }

  Future<void> _showNutritionDetails(BuildContext context) async {
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
  }
}

class _CompactIngredientRow extends StatelessWidget {
  const _CompactIngredientRow({
    required this.item,
    required this.index,
    required this.keyPrefix,
    required this.nutrition,
    required this.onTap,
  });

  final EditableMealItemController item;
  final int index;
  final String keyPrefix;
  final NutritionEdit nutrition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final name = item.nameController.text.trim();
    final title = name.isEmpty ? context.l10n.commonIngredient : name;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('${keyPrefix}_item_compact_$index'),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: FreshSpacing.sm),
                  SizedBox(
                    width: 72,
                    child: Text(
                      '${item.quantityController.text.trim()} '
                      '${item.unitController.text.trim()}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.inkMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: FreshSpacing.sm),
                  SizedBox(
                    width: 88,
                    child: Text(
                      context.l10n.caloriesValue(nutrition.calories),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _compactMacroSummary(context, nutrition),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: palette.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedNutritionSummary extends StatelessWidget {
  const _ExpandedNutritionSummary({
    required this.nutrition,
    required this.macroCalories,
    required this.hasWarning,
  });

  final NutritionEdit nutrition;
  final int macroCalories;
  final bool hasWarning;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: NutritionMacroSummaryText(
            nutrition: nutrition,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: FreshSpacing.sm),
        Text(
          context.l10n.caloriesValue(nutrition.calories),
          textAlign: TextAlign.right,
          style: textTheme.bodyMedium?.copyWith(
            color: hasWarning ? palette.coral : palette.ink,
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (hasWarning) ...[
          const SizedBox(width: FreshSpacing.xs),
          Text(
            context.l10n.mealEditorMacroCaloriesShort(macroCalories),
            textAlign: TextAlign.right,
            style: textTheme.labelSmall?.copyWith(
              color: palette.coral,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

enum _IngredientOverflowAction { replace, editDetails, delete }

class _IngredientOverflowMenu extends StatelessWidget {
  const _IngredientOverflowMenu({
    required this.index,
    required this.keyPrefix,
    required this.canReplace,
    required this.canDelete,
    required this.onReplaceFood,
    required this.onEditDetails,
    required this.onDelete,
  });

  final int index;
  final String keyPrefix;
  final bool canReplace;
  final bool canDelete;
  final VoidCallback? onReplaceFood;
  final VoidCallback onEditDetails;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<_IngredientOverflowAction>(
      key: ValueKey('${keyPrefix}_item_actions_$index'),
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      padding: EdgeInsets.zero,
      onSelected: (action) {
        switch (action) {
          case _IngredientOverflowAction.replace:
            onReplaceFood?.call();
            break;
          case _IngredientOverflowAction.editDetails:
            onEditDetails();
            break;
          case _IngredientOverflowAction.delete:
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (canReplace)
          PopupMenuItem(
            key: ValueKey('${keyPrefix}_item_${index}_search_toggle'),
            value: _IngredientOverflowAction.replace,
            child: _OverflowMenuRow(
              icon: Icons.swap_horiz_rounded,
              label: l10n.mealEditorReplaceFood,
            ),
          ),
        PopupMenuItem(
          key: ValueKey('${keyPrefix}_item_edit_details_$index'),
          value: _IngredientOverflowAction.editDetails,
          child: _OverflowMenuRow(
            icon: Icons.tune_rounded,
            label: l10n.mealEditorEditDetails,
          ),
        ),
        PopupMenuItem(
          key: ValueKey('delete_${keyPrefix}_item_$index'),
          value: _IngredientOverflowAction.delete,
          enabled: canDelete,
          child: _OverflowMenuRow(
            icon: Icons.delete_outline_rounded,
            label: l10n.commonDeleteIngredient,
          ),
        ),
      ],
    );
  }
}

class _OverflowMenuRow extends StatelessWidget {
  const _OverflowMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: FreshSpacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CompactAmountStepper extends StatelessWidget {
  const _CompactAmountStepper({
    required this.amountFieldKey,
    required this.unitFieldKey,
    required this.amountController,
    required this.unitController,
    required this.decrementKey,
    required this.incrementKey,
    required this.onDecrement,
    required this.onIncrement,
    required this.onAmountChanged,
    required this.onUnitChanged,
  });

  final Key amountFieldKey;
  final Key unitFieldKey;
  final TextEditingController amountController;
  final TextEditingController unitController;
  final Key decrementKey;
  final Key incrementKey;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    return FreshInlineAmountStepper(
      amountFieldKey: amountFieldKey,
      unitFieldKey: unitFieldKey,
      amountController: amountController,
      unitController: unitController,
      decrementKey: decrementKey,
      incrementKey: incrementKey,
      decrementLabel: '−',
      incrementLabel: '+',
      onDecrement: onDecrement,
      onIncrement: onIncrement,
      onAmountChanged: onAmountChanged,
      onUnitChanged: onUnitChanged,
    );
  }
}

String _compactMacroSummary(BuildContext context, NutritionEdit nutrition) {
  final l10n = context.l10n;
  return '${l10n.commonProtein} ${formatMacro(nutrition.proteinGrams)}g · '
      '${l10n.commonCarbs} ${formatMacro(nutrition.carbsGrams)}g · '
      '${l10n.commonFat} ${formatMacro(nutrition.fatGrams)}g';
}

MealItem _replacementWithCurrentQuantity(
  EditableMealItemController current,
  MealItem replacement,
) {
  final quantity = double.tryParse(current.quantityController.text.trim());
  final unit = current.unitController.text.trim();
  if (quantity == null || quantity <= 0 || unit.isEmpty) return replacement;
  final sameUnit = replacement.unit.trim().toLowerCase() == unit.toLowerCase();
  if (!sameUnit || replacement.quantity <= 0) return replacement;
  final factor = quantity / replacement.quantity;
  return replacement.copyWith(
    quantity: quantity,
    unit: unit,
    calories: (replacement.calories * factor).round(),
    proteinGrams: roundMacroToTenth(replacement.proteinGrams * factor),
    carbsGrams: roundMacroToTenth(replacement.carbsGrams * factor),
    fatGrams: roundMacroToTenth(replacement.fatGrams * factor),
  );
}
