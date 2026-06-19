import 'dart:math' as math;

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/core/design_system.dart';
import 'package:cal_tracker_mobile/ui/features/meal_history/view_models/meal_history_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_history/views/meal_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('edits history meals with explicit ingredients', (tester) async {
    final repository = _FakeNutritionRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MealHistoryViewModel(nutritionRepository: repository),
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chicken and rice'));
    await tester.pumpAndSettle();

    expect(find.text('Correct'), findsNothing);
    expect(find.byKey(const ValueKey('meal_correction_field')), findsNothing);

    await tester.tap(find.text('Edit ingredients'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('history_item_compact_0')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('history_item_quantity_field_0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('history_item_compact_0')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('history_item_quantity_field_0')),
      '200',
    );
    final actionsFinder = find.byKey(const ValueKey('history_item_actions_0'));
    await tester.ensureVisible(actionsFinder);
    await tester.pumpAndSettle();
    await tester.tap(actionsFinder.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('history_item_edit_details_0')).hitTestable(),
    );
    await tester.pumpAndSettle();

    _expectMacroFieldColor(
      tester,
      key: const ValueKey('history_item_protein_0'),
      color: FreshPalette.light.coral,
    );
    _expectMacroFieldColor(
      tester,
      key: const ValueKey('history_item_carbs_0'),
      color: FreshPalette.light.orange,
    );
    _expectMacroFieldColor(
      tester,
      key: const ValueKey('history_item_fat_0'),
      color: FreshPalette.light.yellow,
    );

    await tester.enterText(
      find.byKey(const ValueKey('history_item_protein_0')),
      '100',
    );
    await tester.enterText(
      find.byKey(const ValueKey('history_item_carbs_0')),
      '0',
    );
    await tester.enterText(
      find.byKey(const ValueKey('history_item_fat_0')),
      '0',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('history_item_apply_suggestion_0')),
    );
    await tester.pumpAndSettle();
    final caloriesField = tester.widget<TextField>(
      find.byKey(const ValueKey('history_item_calories_0')),
    );
    expect(caloriesField.controller!.text, '400');
    await tester.tap(find.byKey(const ValueKey('history_item_save_details_0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('save_history_item_edits_button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('save_history_item_edits_button')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.lastCorrectedItems, isNotNull);
    final chicken = repository.lastCorrectedItems!.first;
    expect(chicken.name, 'Chicken breast');
    expect(chicken.quantity, 200);
    expect(chicken.calories, 400);
    expect(find.text('530 Kcal'), findsOneWidget);
  });

  testWidgets('measurement controls adjust quantities and wrap presets', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _FakeNutritionRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MealHistoryViewModel(nutritionRepository: repository),
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chicken and rice'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit ingredients'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('history_item_compact_0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history_item_compact_0')));
    await tester.pumpAndSettle();

    await tester.binding.setSurfaceSize(const Size(300, 720));
    await tester.pumpAndSettle();

    final quantityFinder = find.byKey(
      const ValueKey('history_item_quantity_field_0'),
    );
    final unitFinder = find.byKey(const ValueKey('history_item_unit_0'));
    final decreaseFinder = find.byKey(
      const ValueKey('history_item_decrease_10_0'),
    );
    final increaseFinder = find.byKey(
      const ValueKey('history_item_increase_10_0'),
    );

    expect(_textFieldValue(tester, quantityFinder), '100');
    expect(_textFieldValue(tester, unitFinder), 'g');
    expect(
      find.descendant(of: decreaseFinder, matching: find.byType(TextButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: decreaseFinder,
        matching: find.byType(OutlinedButton),
      ),
      findsNothing,
    );

    await tester.tap(increaseFinder.hitTestable());
    await tester.pumpAndSettle();
    expect(_textFieldValue(tester, quantityFinder), '110');

    await tester.tap(decreaseFinder.hitTestable());
    await tester.pumpAndSettle();
    expect(_textFieldValue(tester, quantityFinder), '100');

    final preset150Finder = find.byKey(
      const ValueKey('history_item_quantity_preset_150_0'),
    );
    await tester.ensureVisible(preset150Finder);
    await tester.pumpAndSettle();
    await tester.tap(preset150Finder.hitTestable());
    await tester.pumpAndSettle();
    expect(_textFieldValue(tester, quantityFinder), '150');

    final presetWrapFinder = find.byKey(
      const ValueKey('history_item_quantity_presets_0'),
    );
    final presetRects = [
      for (final value in const [50, 100, 150, 200])
        tester.getRect(
          find.byKey(ValueKey('history_item_quantity_preset_${value}_0')),
        ),
    ];
    final rows = _rectRows(presetRects);
    final wrapRect = tester.getRect(presetWrapFinder);

    expect(rows.length, greaterThanOrEqualTo(1));
    for (final row in rows) {
      final left = row.map((rect) => rect.left).reduce(math.min);
      final right = row.map((rect) => rect.right).reduce(math.max);
      final rowCenter = (left + right) / 2;
      expect((rowCenter - wrapRect.center.dx).abs(), lessThanOrEqualTo(1.0));
      expect(left, greaterThanOrEqualTo(wrapRect.left - 0.1));
      expect(right, lessThanOrEqualTo(wrapRect.right + 0.1));
    }

    expect(tester.takeException(), isNull);
  });
}

String _textFieldValue(WidgetTester tester, Finder finder) {
  return tester.widget<TextField>(finder).controller!.text;
}

List<List<Rect>> _rectRows(List<Rect> rects) {
  final sorted = [...rects]..sort((a, b) => a.top.compareTo(b.top));
  final rows = <List<Rect>>[];
  for (final rect in sorted) {
    List<Rect>? matchingRow;
    for (final row in rows) {
      if ((row.first.center.dy - rect.center.dy).abs() < 1.0) {
        matchingRow = row;
        break;
      }
    }
    if (matchingRow == null) {
      rows.add([rect]);
    } else {
      matchingRow.add(rect);
    }
  }
  return rows;
}

void _expectMacroFieldColor(
  WidgetTester tester, {
  required ValueKey<String> key,
  required Color color,
}) {
  final field = tester.widget<TextField>(find.byKey(key));
  expect(field.style?.color, color);
  expect(field.decoration?.labelStyle?.color, color);
  expect(field.decoration?.floatingLabelStyle?.color, color);
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
      home: const Scaffold(body: MealHistoryScreen()),
    );
  }
}

class _FakeNutritionRepository extends NutritionRepository {
  _FakeNutritionRepository()
      : _meal = Meal(
          id: 'meal-1',
          title: 'Chicken and rice',
          occurredAt: DateTime.now(),
          nutrition: const NutritionSnapshot(
            calories: 295,
            proteinGrams: 33.7,
            carbsGrams: 28,
            fatGrams: 3.9,
          ),
          items: const [
            MealItem(
              name: 'Chicken breast',
              quantity: 100,
              unit: 'g',
              calories: 165,
              proteinGrams: 31,
              carbsGrams: 0,
              fatGrams: 3.6,
              source: 'test_fixture',
            ),
            MealItem(
              name: 'Cooked rice',
              quantity: 100,
              unit: 'g',
              calories: 130,
              proteinGrams: 2.7,
              carbsGrams: 28,
              fatGrams: 0.3,
              source: 'test_fixture',
            ),
          ],
        ),
        super(apiClient: _unusedApiClient());

  List<MealItem>? lastCorrectedItems;
  Meal _meal;

  @override
  Future<List<Meal>> getMealHistory() async => [_meal];

  @override
  Future<DailySummary> getDailySummary({String? date}) async {
    final requestedDate = date ?? _formatDateOnly(DateTime.now());
    final meals =
        requestedDate == _formatDateOnly(_meal.occurredAt) ? [_meal] : <Meal>[];
    final consumed = _sumMealNutrition(meals);
    return DailySummary(
      date: requestedDate,
      consumed: consumed,
      target: _targetNutrition,
      remaining: NutritionSnapshot(
        calories: _targetNutrition.calories - consumed.calories,
        proteinGrams: _targetNutrition.proteinGrams - consumed.proteinGrams,
        carbsGrams: _targetNutrition.carbsGrams - consumed.carbsGrams,
        fatGrams: _targetNutrition.fatGrams - consumed.fatGrams,
      ),
      hydrationGoalLiters: 2.5,
      waterConsumedLiters: 0,
      calorieTargetConfigured: true,
      calorieTargetSource: 'manual',
      meals: meals,
    );
  }

  @override
  Future<Meal> correctMealItems(String mealId, List<MealItem> items) async {
    lastCorrectedItems = items;
    _meal = Meal(
      id: mealId,
      title: _meal.title,
      occurredAt: _meal.occurredAt,
      nutrition: NutritionSnapshot(
        calories: items.fold<int>(0, (sum, item) => sum + item.calories),
        proteinGrams: items.fold<double>(
          0,
          (sum, item) => sum + item.proteinGrams,
        ),
        carbsGrams: items.fold<double>(0, (sum, item) => sum + item.carbsGrams),
        fatGrams: items.fold<double>(0, (sum, item) => sum + item.fatGrams),
      ),
      items: items,
    );
    return _meal;
  }
}

const _targetNutrition = NutritionSnapshot(
  calories: 2200,
  proteinGrams: 160,
  carbsGrams: 240,
  fatGrams: 70,
);

NutritionSnapshot _sumMealNutrition(List<Meal> meals) {
  return NutritionSnapshot(
    calories: meals.fold<int>(0, (sum, meal) => sum + meal.nutrition.calories),
    proteinGrams: meals.fold<double>(
      0,
      (sum, meal) => sum + meal.nutrition.proteinGrams,
    ),
    carbsGrams: meals.fold<double>(
      0,
      (sum, meal) => sum + meal.nutrition.carbsGrams,
    ),
    fatGrams: meals.fold<double>(
      0,
      (sum, meal) => sum + meal.nutrition.fatGrams,
    ),
  );
}

String _formatDateOnly(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class _MemoryTokenStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}
}

CalTrackerApiClient _unusedApiClient() {
  return CalTrackerApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    tokenStorage: _MemoryTokenStorage(),
  );
}
