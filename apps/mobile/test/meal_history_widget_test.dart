import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
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

    await tester.enterText(
      find.byKey(const ValueKey('history_item_quantity_field_0')),
      '200',
    );
    final detailsFinder = find.byKey(
      const ValueKey('history_item_edit_details_0'),
    );
    await tester.ensureVisible(detailsFinder);
    await tester.pumpAndSettle();
    await tester.tap(detailsFinder.hitTestable());
    await tester.pumpAndSettle();

    _expectMacroFieldColor(
      tester,
      key: const ValueKey('history_item_protein_0'),
      color: const Color(0xffc95a5a),
    );
    _expectMacroFieldColor(
      tester,
      key: const ValueKey('history_item_carbs_0'),
      color: const Color(0xffb88758),
    );
    _expectMacroFieldColor(
      tester,
      key: const ValueKey('history_item_fat_0'),
      color: const Color(0xffe0b93b),
    );

    await tester.enterText(
      find.byKey(const ValueKey('history_item_protein_0')),
      '90',
    );
    await tester.enterText(
        find.byKey(const ValueKey('history_item_carbs_0')), '0');
    await tester.enterText(
        find.byKey(const ValueKey('history_item_fat_0')), '0');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('history_item_apply_suggestion_0')),
    );
    await tester.pumpAndSettle();
    final caloriesField = tester.widget<TextField>(
      find.byKey(const ValueKey('history_item_calories_0')),
    );
    expect(caloriesField.controller!.text, '360');
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
    expect(chicken.calories, 360);
    expect(find.text('490 Kcal'), findsOneWidget);
  });
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
