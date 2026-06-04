import 'macro_distribution.dart';

const int kCalorieMismatchToleranceKcal = 50;

class NutritionEdit {
  const NutritionEdit({
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final int calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;

  int get macroCalories => macroCaloriesFromGrams(
        MacroGrams(
          proteinGrams: proteinGrams,
          carbsGrams: carbsGrams,
          fatGrams: fatGrams,
        ),
      );

  /// La tolerancia es inclusiva.
  /// Diferencias <= 50 kcal NO avisan; diferencias > 50 sí avisan.
  bool get hasCalorieMismatch =>
      (calories - macroCalories).abs() > kCalorieMismatchToleranceKcal;

  NutritionEdit scaled(double factor) {
    return NutritionEdit(
      calories: (calories * factor).round(),
      proteinGrams: roundMacroToTenth(proteinGrams * factor),
      carbsGrams: roundMacroToTenth(carbsGrams * factor),
      fatGrams: roundMacroToTenth(fatGrams * factor),
    );
  }

  static NutritionEdit sum(Iterable<NutritionEdit> values) {
    var totalCalories = 0;
    var totalProtein = 0.0;
    var totalCarbs = 0.0;
    var totalFat = 0.0;
    for (final value in values) {
      totalCalories += value.calories;
      totalProtein += value.proteinGrams;
      totalCarbs += value.carbsGrams;
      totalFat += value.fatGrams;
    }
    return NutritionEdit(
      calories: totalCalories,
      proteinGrams: roundMacroToTenth(totalProtein),
      carbsGrams: roundMacroToTenth(totalCarbs),
      fatGrams: roundMacroToTenth(totalFat),
    );
  }
}

double roundMacroToTenth(double value) => (value * 10).round() / 10;
