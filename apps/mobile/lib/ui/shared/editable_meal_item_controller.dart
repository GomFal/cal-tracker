import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/nutrition_edit.dart';
import '../../domain/models/nutrition_models.dart';
import 'nutrition_edit_components.dart';

/// Shared controller for editing a [MealItem] in UI.
///
/// Manages three [TextEditingController]s (name, quantity, unit),
/// a nutrition override with scaling, and produces a [MealItem]
/// through one of two output methods:
///
/// - [toValidatedMealItem]: validates fields and returns `null` on invalid
///   input (for the meal editor sheet).
/// - [toMealItemWith]: assumes valid inputs are passed explicitly
///   (for the voice log screen).
class EditableMealItemController {
  EditableMealItemController(MealItem item)
      : original = item,
        isNew = false {
    nameController = TextEditingController(text: item.name);
    quantityController = TextEditingController(
      text: formatQuantity(item.quantity),
    );
    unitController = TextEditingController(text: item.unit);
  }

  EditableMealItemController.empty()
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

  /// The original [MealItem] this controller was initialised with.
  ///
  /// Mutable so that [replaceWith] can update it without creating
  /// a new controller instance.
  MealItem original;

  /// Whether this item was created through the [EditableMealItemController.empty]
  /// factory (i.e. the user added a new blank ingredient).
  final bool isNew;

  NutritionEdit? _nutritionOverride;
  double? _nutritionOverrideQuantity;

  late final TextEditingController nameController;
  late final TextEditingController quantityController;
  late final TextEditingController unitController;

  /// Whether the current unit text (normalised) is `'g'`.
  bool get isGramUnit => normalizedText(unitController.text) == 'g';

  /// Adjust the quantity by [delta] (minimum 0.1).
  void adjustQuantity(double delta) {
    final current = double.tryParse(quantityController.text.trim());
    final next = math.max(0.1, (current ?? original.quantity) + delta);
    setQuantity(next);
  }

  /// Set the quantity field to [value] (formatted for display).
  void setQuantity(double value) {
    quantityController.text = formatQuantity(value);
  }

  /// Replace the underlying [original] and reset all controllers
  /// and overrides to match [item] (used by voice log proposal editor).
  void replaceWith(MealItem item) {
    original = item;
    _nutritionOverride = null;
    _nutritionOverrideQuantity = null;
    nameController.text = item.name;
    quantityController.text = formatQuantity(item.quantity);
    unitController.text = item.unit;
  }

  /// Set a nutrition override. The override is scaled along with
  /// the quantity when [currentNutrition] is called later.
  void setNutritionOverride(NutritionEdit value) {
    _nutritionOverride = value;
    _nutritionOverrideQuantity = double.tryParse(
      quantityController.text.trim(),
    );
  }

  /// Compute the effective [NutritionEdit] by scaling the override
  /// (or the original item) to the current quantity.
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

  /// Validated output for the meal editor sheet.
  ///
  /// Returns `null` when:
  /// - name is empty
  /// - quantity is missing, zero, or negative
  /// - unit is empty
  /// - any nutrition component is negative
  ///
  /// The `source` field uses `isNew` and `original.source.contains('manual_edit')`
  /// to produce the correct provenance string.
  MealItem? toValidatedMealItem() {
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

  /// Non-validating output for the voice log screen.
  ///
  /// Assumes the caller has already validated [name], [quantity], [unit].
  /// Uses the simpler source logic (`original.source == 'manual_edit'`)
  /// consistent with the voice log call site.
  MealItem toMealItemWith({
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

  /// Dispose all text editing controllers.
  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    unitController.dispose();
  }
}
