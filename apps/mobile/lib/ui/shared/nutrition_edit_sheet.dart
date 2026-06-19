import 'package:flutter/material.dart';

import '../../domain/models/nutrition_edit.dart';
import '../../l10n/app_localizations_context.dart';
import '../core/design_system.dart';
import 'nutrition_edit_components.dart';

/// Shared bottom-sheet content for editing nutrition details (calories and
/// macros). Used by [MealItemEditorSheet] and voice-log screens, preserving
/// their existing key patterns and visual differences.
///
/// Callers open this via e.g. `showModalBottomSheet<NutritionEdit>` and must
/// pass the resolved [initialNutrition] and [ingredientName] snapshot (not a
/// mutable item reference).
class NutritionEditSheet extends StatefulWidget {
  const NutritionEditSheet({
    super.key,
    required this.initialNutrition,
    required this.ingredientName,
    required this.title,
    this.subtitleFallback,
    this.keyPrefix = '',
    this.index = 0,
    this.fieldKeySuffix = 'item',
    this.saveButtonKeySuffix = 'item_save_details',
    this.macroColors,
    this.useMacroFieldStyle = true,
    this.errorTitle,
    this.errorMessage,
    this.useSafeArea = false,
  });

  /// The nutrition values to pre-fill.
  final NutritionEdit initialNutrition;

  /// The current ingredient name (may be empty).
  final String ingredientName;

  /// Sheet title (e.g. `l10n.mealEditorNutritionDetails` or `'Edit nutrition'`).
  final String title;

  /// Fallback text when [ingredientName] is empty.
  final String? subtitleFallback;

  /// Prefix for all ValueKey strings.
  final String keyPrefix;

  /// Index within the parent item list.
  final int index;

  /// Segment used in field keys, e.g. `'item'` or `'nutrition'`.
  ///
  /// Produces keys like `${keyPrefix}_${fieldKeySuffix}_calories_${index}`.
  final String fieldKeySuffix;

  /// Segment used in the save button key, e.g. `'item_save_details'` or
  /// `'save_nutrition_button'`.
  ///
  /// Produces the key `${keyPrefix}_${saveButtonKeySuffix}_${index}`.
  final String saveButtonKeySuffix;

  /// Per-macro display colors. Defaults to [defaultNutritionMacroColors].
  final Map<NutritionMacroKind, Color>? macroColors;

  /// Whether to apply [macroFieldStyle] (colored text style) to macro fields.
  /// When `false`, only the decoration label gets the macro color.
  final bool useMacroFieldStyle;

  /// Override for the error banner title. Defaults to
  /// `l10n.commonCheckIngredientDetails`.
  final String? errorTitle;

  /// Override for the error banner message. Defaults to
  /// `l10n.commonIngredientDetailsError`.
  final String? errorMessage;

  /// Wrap the content in [SafeArea].
  final bool useSafeArea;

  @override
  State<NutritionEditSheet> createState() => _NutritionEditSheetState();
}

class _NutritionEditSheetState extends State<NutritionEditSheet> {
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _caloriesController = TextEditingController(
      text: widget.initialNutrition.calories.toString(),
    );
    _proteinController = TextEditingController(
      text: formatMacro(widget.initialNutrition.proteinGrams),
    );
    _carbsController = TextEditingController(
      text: formatMacro(widget.initialNutrition.carbsGrams),
    );
    _fatController = TextEditingController(
      text: formatMacro(widget.initialNutrition.fatGrams),
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
    final colors = widget.macroColors ?? defaultNutritionMacroColors(context);

    final content = Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.rule,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: FreshSpacing.lg),
            Text(widget.title, style: textTheme.titleLarge),
            const SizedBox(height: FreshSpacing.xs),
            Text(
              widget.ingredientName.isNotEmpty
                  ? widget.ingredientName
                  : (widget.subtitleFallback ?? widget.ingredientName),
              style: textTheme.bodyMedium?.copyWith(
                color: palette.inkMuted,
              ),
            ),
            const SizedBox(height: FreshSpacing.md),
            if (_error != null) ...[
              FreshStatusBanner(
                icon: Icons.error_outline_rounded,
                title: widget.errorTitle ?? l10n.commonCheckIngredientDetails,
                message: _error!,
                color: palette.coral,
              ),
              const SizedBox(height: FreshSpacing.md),
            ],
            // Calorie field
            FreshNumberUnitField(
              fieldKey: ValueKey(
                '${widget.keyPrefix}_${widget.fieldKeySuffix}_calories_${widget.index}',
              ),
              label: l10n.commonCalories,
              controller: _caloriesController,
              unit: l10n.commonKcal,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              suffix: showSuggestion
                  ? NutritionCalorieSuggestionSuffix(
                      key: ValueKey(
                        '${widget.keyPrefix}_${widget.fieldKeySuffix}_apply_suggestion_${widget.index}',
                      ),
                      calories: macroCalories,
                      onApply: () => _applyMacroCalories(macroCalories),
                    )
                  : null,
            ),
            const SizedBox(height: FreshSpacing.lg),
            // Macro fields row
            FreshMacroFields(
              useMacroTextColor: widget.useMacroFieldStyle,
              fields: [
                FreshMacroFieldData(
                  key: ValueKey(
                    '${widget.keyPrefix}_${widget.fieldKeySuffix}_protein_${widget.index}',
                  ),
                  label: l10n.commonProtein,
                  controller: _proteinController,
                  color: colors[NutritionMacroKind.protein]!,
                  onChanged: (_) => setState(() {}),
                ),
                FreshMacroFieldData(
                  key: ValueKey(
                    '${widget.keyPrefix}_${widget.fieldKeySuffix}_carbs_${widget.index}',
                  ),
                  label: l10n.commonCarbs,
                  controller: _carbsController,
                  color: colors[NutritionMacroKind.carbs]!,
                  onChanged: (_) => setState(() {}),
                ),
                FreshMacroFieldData(
                  key: ValueKey(
                    '${widget.keyPrefix}_${widget.fieldKeySuffix}_fat_${widget.index}',
                  ),
                  label: l10n.commonFat,
                  controller: _fatController,
                  color: colors[NutritionMacroKind.fat]!,
                  onChanged: (_) => setState(() {}),
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
            // Save button
            FilledButton.icon(
              key: ValueKey(
                '${widget.keyPrefix}_${widget.saveButtonKeySuffix}_${widget.index}',
              ),
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );

    if (widget.useSafeArea) {
      return SafeArea(child: content);
    }
    return content;
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
        _error =
            widget.errorMessage ?? context.l10n.commonIngredientDetailsError;
      });
      return;
    }
    Navigator.of(context).pop(nutrition);
  }
}
