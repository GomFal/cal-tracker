import 'dart:async';

import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/nutrition_cache_store.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_data_change.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_summary_updates.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_history/view_models/meal_history_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/settings/view_models/settings_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _UnusedApiClient extends Mock implements CalTrackerApiClient {}

void main() {
  group('DashboardViewModel stale-while-revalidate', () {
    late _FakeNutritionRepository repository;
    late DashboardViewModel viewModel;

    setUp(() {
      repository = _FakeNutritionRepository();
      viewModel = DashboardViewModel(
        nutritionRepository: repository,
        now: () => DateTime(2026, 5, 10, 10),
      );
    });

    test('hydrates cached summary before background refresh completes',
        () async {
      repository.cacheDaily(_summary('2026-05-10', waterConsumedLiters: 0.25));
      final refresh = Completer<DailySummary>();
      repository.nextDailyRefresh = refresh;

      final load = viewModel.load();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.isRefreshing, isTrue);
      expect(viewModel.summary?.waterConsumedLiters, 0.25);

      refresh.complete(_summary('2026-05-10', waterConsumedLiters: 0.5));
      await load;

      expect(viewModel.isRefreshing, isFalse);
      expect(viewModel.summary?.waterConsumedLiters, 0.5);
    });

    test('uses blocking loading only when no cached summary exists', () async {
      final refresh = Completer<DailySummary>();
      repository.nextDailyRefresh = refresh;

      final load = viewModel.load();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.isLoading, isTrue);
      expect(viewModel.summary, isNull);

      refresh.complete(_summary('2026-05-10'));
      await load;

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.summary?.date, '2026-05-10');
    });

    test('rolls back optimistic water when save fails', () async {
      repository.backendDaily['2026-05-10'] = _summary(
        '2026-05-10',
        hydrationGoalLiters: 2.5,
      );
      await viewModel.load();

      final save = Completer<DailySummary>();
      repository.nextHydrationSave = save;

      final update = viewModel.updateDailyWater(0.25);

      expect(viewModel.summary?.waterConsumedLiters, 0.25);
      expect(viewModel.isLoading, isFalse);

      save.completeError(Exception('database unavailable'));

      expect(await update, isFalse);
      expect(viewModel.summary?.waterConsumedLiters, 0);
      expect(viewModel.error, 'We could not save that change. Try again.');
    });

    test('applies a confirmed chat summary without a global reload', () async {
      repository.backendDaily['2026-05-10'] = _summary('2026-05-10');
      repository.activateCacheForUser('user-a');
      await viewModel.load();

      await repository.reconcileConfirmedMutation(
        ConfirmedNutritionMutation(
          version: 1,
          mutationId: 'chat-summary-1',
          committedAt: DateTime.utc(2026, 5, 10, 12),
          effects: [
            NutritionDataEffect(
              domain: NutritionDataDomain.dailySummary,
              operation: NutritionDataOperation.replace,
              date: '2026-05-10',
              snapshot: _summary(
                '2026-05-10',
                meals: [_meal('chat-meal')],
              ).toJson(),
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.summary?.meals.single.id, 'chat-meal');
      expect(repository.dailyRefreshCalls, 1);
    });

    test('rolls back optimistic delete when backend fails', () async {
      final meal = _meal('meal-1');
      repository.backendDaily['2026-05-10'] =
          _summary('2026-05-10', meals: [meal]);
      await viewModel.load();

      repository.deleteMealError = Exception('database unavailable');
      final deleted = viewModel.deleteMeal(meal);

      expect(viewModel.summary?.meals, isEmpty);

      expect(await deleted, isFalse);
      expect(viewModel.summary?.meals.single.id, 'meal-1');
      expect(viewModel.error, 'We could not save that change. Try again.');
    });
  });

  group('MealHistoryViewModel cache', () {
    test('renders cached week while refreshing in the background', () async {
      final repository = _FakeNutritionRepository();
      repository.cacheDaily(
        _summary('2026-05-10', meals: [_meal('cached-meal')]),
      );
      final viewModel = MealHistoryViewModel(
        nutritionRepository: repository,
        now: () => DateTime(2026, 5, 10, 10),
      );

      final refresh = Completer<DailySummary>();
      repository.nextDailyRefresh = refresh;

      final load = viewModel.load();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.meals.single.id, 'cached-meal');
      expect(repository.dailyRefreshCalls, 7);

      refresh.complete(_summary('2026-05-10'));
      await load;
    });

    test('updates cached week optimistically when a meal is edited', () async {
      final repository = _FakeNutritionRepository();
      final meal = _meal('meal-1');
      repository.backendDaily['2026-05-10'] =
          _summary('2026-05-10', meals: [meal]);
      final viewModel = MealHistoryViewModel(
        nutritionRepository: repository,
        now: () => DateTime(2026, 5, 10, 10),
      );
      await viewModel.load();

      final editedItems = [
        _item('Rice', calories: 150),
        _item('Chicken', calories: 200),
      ];

      await viewModel.correctMealItems(meal, editedItems);

      expect(viewModel.meals.single.nutrition.calories, 350);
      expect(repository.cachedDaily['2026-05-10']?.meals.single.items,
          editedItems);
    });
  });

  group('MealTemplatesViewModel cache', () {
    test('hydrates cached meals and usual foods before refresh completes',
        () async {
      final repository = _FakeNutritionRepository()
        ..cachedTemplatesValue = [_template('template-cached')]
        ..cachedUsualFoodsValue = [_usualFood('food-cached')];
      repository.nextTemplatesRefresh = Completer<List<MealTemplate>>();
      repository.nextUsualFoodsRefresh = Completer<List<UsualFood>>();
      final viewModel = MealTemplatesViewModel(
        nutritionRepository: repository,
        now: () => DateTime(2026, 5, 10, 10),
      );

      final load = viewModel.load();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.isRefreshing, isTrue);
      expect(viewModel.templates.single.id, 'template-cached');
      expect(viewModel.usualFoods.single.id, 'food-cached');

      repository.nextTemplatesRefresh!.complete([_template('template-fresh')]);
      repository.nextUsualFoodsRefresh!.complete([_usualFood('food-fresh')]);
      await load;

      expect(viewModel.isRefreshing, isFalse);
      expect(viewModel.templates.single.id, 'template-fresh');
      expect(viewModel.usualFoods.single.id, 'food-fresh');
    });

    test('applies template and usual-food upserts from the repository bus',
        () async {
      final repository = _FakeNutritionRepository()
        ..backendTemplates = [_template('template-1')]
        ..backendUsualFoods = [_usualFood('food-1')];
      repository.activateCacheForUser('user-a');
      final viewModel = MealTemplatesViewModel(
        nutritionRepository: repository,
        now: () => DateTime(2026, 5, 10, 10),
      );
      await viewModel.load();

      await repository.reconcileConfirmedMutation(
        ConfirmedNutritionMutation(
          version: 1,
          mutationId: 'chat-template-1',
          committedAt: DateTime.utc(2026, 5, 10, 12),
          effects: [
            NutritionDataEffect(
              domain: NutritionDataDomain.mealTemplates,
              operation: NutritionDataOperation.upsert,
              entityId: 'template-chat',
              snapshot: _template('template-chat').toJson(),
            ),
            NutritionDataEffect(
              domain: NutritionDataDomain.usualFoods,
              operation: NutritionDataOperation.upsert,
              entityId: 'food-chat',
              snapshot: _usualFood('food-chat').toJson(),
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.templates.map((item) => item.id),
          contains('template-chat'));
      expect(
          viewModel.usualFoods.map((item) => item.id), contains('food-chat'));
    });

    test('rolls back optimistic template delete when backend fails', () async {
      final repository = _FakeNutritionRepository()
        ..backendTemplates = [_template('template-1')];
      final viewModel = MealTemplatesViewModel(
        nutritionRepository: repository,
        now: () => DateTime(2026, 5, 10, 10),
      );
      await viewModel.load();

      repository.deleteTemplateError = Exception('database unavailable');
      await viewModel.deleteTemplate(viewModel.templates.single);

      expect(viewModel.templates.single.id, 'template-1');
      expect(
          viewModel.error, 'We could not update that usual meal. Try again.');
    });
  });

  group('SettingsViewModel cache', () {
    test('hydrates goals from cached daily summary before refresh completes',
        () async {
      final repository = _FakeNutritionRepository();
      repository.cacheDaily(_summary('2026-05-10', hydrationGoalLiters: 2.5));
      final refresh = Completer<DailySummary>();
      repository.nextDailyRefresh = refresh;
      final viewModel = SettingsViewModel(
        authRepository: _FakeAuthRepository(),
        nutritionRepository: repository,
        now: () => DateTime(2026, 5, 10, 10),
      );

      final load = viewModel.load();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.isLoading, isFalse);
      expect(viewModel.isRefreshing, isTrue);
      expect(viewModel.goals?.hydrationGoalLiters, 2.5);

      refresh.complete(_summary('2026-05-10', hydrationGoalLiters: 3));
      await load;

      expect(viewModel.goals?.hydrationGoalLiters, 3);
    });
  });
}

class _FakeAuthRepository extends Mock implements AuthRepository {}

class _FakeNutritionRepository extends NutritionRepository {
  _FakeNutritionRepository() : super(apiClient: _UnusedApiClient());

  final cachedDaily = <String, DailySummary>{};
  final backendDaily = <String, DailySummary>{};
  List<MealTemplate>? cachedTemplatesValue;
  List<MealTemplate> backendTemplates = const [];
  List<UsualFood>? cachedUsualFoodsValue;
  List<UsualFood> backendUsualFoods = const [];
  Completer<DailySummary>? nextDailyRefresh;
  Completer<DailySummary>? nextHydrationSave;
  Completer<List<MealTemplate>>? nextTemplatesRefresh;
  Completer<List<UsualFood>>? nextUsualFoodsRefresh;
  Object? deleteMealError;
  Object? deleteTemplateError;
  int dailyRefreshCalls = 0;

  void cacheDaily(DailySummary summary) {
    cachedDaily[summary.date] = summary;
  }

  @override
  Future<CachedNutritionValue<DailySummary>?> cachedDailySummary({
    String? date,
  }) async {
    final summary = cachedDaily[date ?? '2026-05-10'];
    if (summary == null) return null;
    return CachedNutritionValue(
      value: summary,
      cachedAt: DateTime(2026, 5, 10, 9),
    );
  }

  @override
  Future<void> putCachedDailySummary(DailySummary summary) async {
    cachedDaily[summary.date] = summary;
  }

  @override
  Future<DailySummary> refreshDailySummary({
    String? date,
    bool force = false,
  }) async {
    dailyRefreshCalls += 1;
    final requestedDate = date ?? '2026-05-10';
    final completer = nextDailyRefresh;
    if (completer != null) {
      final summary = await completer.future;
      cachedDaily[summary.date] = summary;
      nextDailyRefresh = null;
      return summary;
    }
    final summary = backendDaily[requestedDate] ?? _summary(requestedDate);
    cachedDaily[requestedDate] = summary;
    return summary;
  }

  @override
  Future<DailySummary> updateDailyHydration({
    String? date,
    required double waterConsumedLiters,
  }) async {
    final completer = nextHydrationSave;
    if (completer != null) {
      nextHydrationSave = null;
      final summary = await completer.future;
      cachedDaily[summary.date] = summary;
      return summary;
    }
    final requestedDate = date ?? '2026-05-10';
    final current = cachedDaily[requestedDate] ??
        backendDaily[requestedDate] ??
        _summary(requestedDate);
    final summary = dailySummaryWithWater(current, waterConsumedLiters);
    cachedDaily[requestedDate] = summary;
    return summary;
  }

  @override
  Future<Meal> correctMealItems(String mealId, List<MealItem> items) async {
    for (final entry in cachedDaily.entries) {
      final match = entry.value.meals.where((meal) => meal.id == mealId);
      if (match.isEmpty) continue;
      final meal = mealWithItems(match.single, items);
      cachedDaily[entry.key] = replaceMealInSummary(entry.value, meal);
      return meal;
    }
    return mealWithItems(_meal(mealId), items);
  }

  @override
  Future<bool> deleteMeal(String mealId, {bool confirmed = false}) async {
    final error = deleteMealError;
    if (error != null) throw error;
    for (final entry in cachedDaily.entries) {
      cachedDaily[entry.key] = removeMealFromSummary(entry.value, mealId);
    }
    return true;
  }

  @override
  Future<CachedNutritionValue<List<MealTemplate>>?> cachedTemplates() async {
    final templates = cachedTemplatesValue;
    if (templates == null) return null;
    return CachedNutritionValue(
      value: templates,
      cachedAt: DateTime(2026, 5, 10, 9),
    );
  }

  @override
  Future<void> putCachedTemplates(List<MealTemplate> templates) async {
    cachedTemplatesValue = templates;
  }

  @override
  Future<List<MealTemplate>> refreshTemplates({bool force = false}) async {
    final completer = nextTemplatesRefresh;
    if (completer != null) {
      final templates = await completer.future;
      cachedTemplatesValue = templates;
      nextTemplatesRefresh = null;
      return templates;
    }
    cachedTemplatesValue = backendTemplates;
    return backendTemplates;
  }

  @override
  Future<CachedNutritionValue<List<UsualFood>>?> cachedUsualFoods() async {
    final foods = cachedUsualFoodsValue;
    if (foods == null) return null;
    return CachedNutritionValue(
      value: foods,
      cachedAt: DateTime(2026, 5, 10, 9),
    );
  }

  @override
  Future<void> putCachedUsualFoods(List<UsualFood> foods) async {
    cachedUsualFoodsValue = foods;
  }

  @override
  Future<List<UsualFood>> refreshUsualFoods({bool force = false}) async {
    final completer = nextUsualFoodsRefresh;
    if (completer != null) {
      final foods = await completer.future;
      cachedUsualFoodsValue = foods;
      nextUsualFoodsRefresh = null;
      return foods;
    }
    cachedUsualFoodsValue = backendUsualFoods;
    return backendUsualFoods;
  }

  @override
  Future<bool> deleteTemplate(String templateId) async {
    final error = deleteTemplateError;
    if (error != null) throw error;
    backendTemplates = backendTemplates
        .where((template) => template.id != templateId)
        .toList();
    return true;
  }
}

const _nutrition = NutritionSnapshot(
  calories: 400,
  proteinGrams: 30,
  carbsGrams: 45,
  fatGrams: 12,
);

DailySummary _summary(
  String date, {
  List<Meal> meals = const [],
  double hydrationGoalLiters = 0,
  double waterConsumedLiters = 0,
}) {
  return DailySummary(
    date: date,
    consumed: _nutrition,
    target: _nutrition,
    remaining: _nutrition,
    hydrationGoalLiters: hydrationGoalLiters,
    waterConsumedLiters: waterConsumedLiters,
    calorieTargetConfigured: false,
    calorieTargetSource: 'default',
    meals: meals,
  );
}

Meal _meal(String id) {
  return Meal(
    id: id,
    title: 'Chicken and rice',
    occurredAt: DateTime(2026, 5, 10, 12),
    nutrition: _nutrition,
    items: const [],
  );
}

MealItem _item(String name, {required int calories}) {
  return MealItem(
    name: name,
    quantity: 100,
    unit: 'g',
    calories: calories,
    proteinGrams: 10,
    carbsGrams: 10,
    fatGrams: 5,
    source: 'test_fixture',
  );
}

MealTemplate _template(String id) {
  return MealTemplate(
    id: id,
    title: 'Usual lunch',
    trustedAutoCommitEnabled: false,
    nutrition: _nutrition,
    items: const [],
    aliases: const [],
  );
}

UsualFood _usualFood(String id) {
  return UsualFood(
    id: id,
    name: 'Rice',
    servingGrams: 100,
    nutrition: _nutrition,
  );
}
