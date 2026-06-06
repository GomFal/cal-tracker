import 'package:cal_tracker_mobile/domain/models/nutrition_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionEdit.hasCalorieMismatch', () {
    test('delta 49 returns false', () {
      // 100 P = 400 kcal, 50 C = 200 kcal, 50 F = 450 kcal
      // macroCalories = 1050
      // calories = 1001 => delta = 49
      const edit = NutritionEdit(
        calories: 1001,
        proteinGrams: 100,
        carbsGrams: 50,
        fatGrams: 50,
      );
      expect(edit.hasCalorieMismatch, false);
      expect((edit.calories - edit.macroCalories).abs(), 49);
    });

    test('delta 50 returns false (boundary, inclusive tolerance)', () {
      // 100 P = 400, 50 C = 200, 50 F = 450 => 1050
      // calories = 1000 => delta = 50
      const edit = NutritionEdit(
        calories: 1000,
        proteinGrams: 100,
        carbsGrams: 50,
        fatGrams: 50,
      );
      expect(edit.hasCalorieMismatch, false);
      expect((edit.calories - edit.macroCalories).abs(), 50);
    });

    test('delta 51 returns true (exceeds tolerance)', () {
      // 100 P = 400, 50 C = 200, 50 F = 450 => 1050
      // calories = 999 => delta = 51
      const edit = NutritionEdit(
        calories: 999,
        proteinGrams: 100,
        carbsGrams: 50,
        fatGrams: 50,
      );
      expect(edit.hasCalorieMismatch, true);
      expect((edit.calories - edit.macroCalories).abs(), 51);
    });

    test('delta -50 returns false (negative, within tolerance)', () {
      // 100 P = 400, 50 C = 200, 50 F = 450 => 1050
      // calories = 1100 => delta = -50
      const edit = NutritionEdit(
        calories: 1100,
        proteinGrams: 100,
        carbsGrams: 50,
        fatGrams: 50,
      );
      expect(edit.hasCalorieMismatch, false);
      expect((edit.calories - edit.macroCalories).abs(), 50);
    });

    test('delta -51 returns true (negative, exceeds tolerance)', () {
      // 100 P = 400, 50 C = 200, 50 F = 450 => 1050
      // calories = 1101 => delta = -51
      const edit = NutritionEdit(
        calories: 1101,
        proteinGrams: 100,
        carbsGrams: 50,
        fatGrams: 50,
      );
      expect(edit.hasCalorieMismatch, true);
      expect((edit.calories - edit.macroCalories).abs(), 51);
    });
  });

  group('NutritionEdit.scaled', () {
    test('scales values by factor and rounds macros to tenth', () {
      const edit = NutritionEdit(
        calories: 200,
        proteinGrams: 12.5,
        carbsGrams: 25.5,
        fatGrams: 5.3,
      );
      final scaled = edit.scaled(2.0);
      expect(scaled.calories, 400);
      expect(scaled.proteinGrams, 25.0);
      expect(scaled.carbsGrams, 51.0);
      expect(scaled.fatGrams, 10.6);
    });

    test('scale by 0.5 rounds correctly', () {
      const edit = NutritionEdit(
        calories: 400,
        proteinGrams: 30.4,
        carbsGrams: 50.6,
        fatGrams: 20.2,
      );
      final scaled = edit.scaled(0.5);
      expect(scaled.calories, 200);
      expect(scaled.proteinGrams, 15.2);
      expect(scaled.carbsGrams, 25.3);
      expect(scaled.fatGrams, 10.1);
    });
  });

  group('NutritionEdit.sum', () {
    test('sums multiple edits and rounds macros to tenth', () {
      const edit1 = NutritionEdit(
        calories: 200,
        proteinGrams: 12.3,
        carbsGrams: 25.7,
        fatGrams: 5.2,
      );
      const edit2 = NutritionEdit(
        calories: 300,
        proteinGrams: 18.7,
        carbsGrams: 40.3,
        fatGrams: 10.8,
      );
      final total = NutritionEdit.sum([edit1, edit2]);
      expect(total.calories, 500);
      expect(total.proteinGrams, 31.0); // 12.3 + 18.7 = 31.0
      expect(total.carbsGrams, 66.0); // 25.7 + 40.3 = 66.0
      expect(total.fatGrams, 16.0); // 5.2 + 10.8 = 16.0
    });

    test('sum with empty iterable returns zero edit', () {
      final total = NutritionEdit.sum([]);
      expect(total.calories, 0);
      expect(total.proteinGrams, 0.0);
      expect(total.carbsGrams, 0.0);
      expect(total.fatGrams, 0.0);
    });
  });
}
