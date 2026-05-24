import 'dart:async';

import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_history/view_models/meal_history_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNutritionRepository extends Mock implements NutritionRepository {}

void main() {
  group('DashboardViewModel cache', () {
    late MockNutritionRepository repository;
    late DateTime now;
    late DashboardViewModel viewModel;

    setUp(() {
      repository = MockNutritionRepository();
      now = DateTime(2026, 5, 10, 10);
      viewModel = DashboardViewModel(
        nutritionRepository: repository,
        now: () => now,
      );
    });

    test('loads once while cache is fresh', () async {
      when(() => repository.getDailySummary())
          .thenAnswer((_) async => _summary('2026-05-10'));

      await viewModel.load();
      await viewModel.load();

      verify(() => repository.getDailySummary()).called(1);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.summary?.date, '2026-05-10');
    });

    test('force refresh bypasses cache and shows loading', () async {
      when(() => repository.getDailySummary())
          .thenAnswer((_) async => _summary('2026-05-10'));
      await viewModel.load();

      final completer = Completer<DailySummary>();
      when(() => repository.getDailySummary()).thenAnswer(
        (_) => completer.future,
      );

      final refresh = viewModel.load(forceRefresh: true);
      expect(viewModel.isLoading, isTrue);

      completer.complete(_summary('2026-05-11'));
      await refresh;

      verify(() => repository.getDailySummary()).called(2);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.summary?.date, '2026-05-11');
    });

    test('expired cache refreshes silently', () async {
      when(() => repository.getDailySummary())
          .thenAnswer((_) async => _summary('2026-05-10'));
      await viewModel.load();
      now = now.add(const Duration(seconds: 61));

      final completer = Completer<DailySummary>();
      when(() => repository.getDailySummary()).thenAnswer(
        (_) => completer.future,
      );

      final refresh = viewModel.load();
      expect(viewModel.isLoading, isFalse);

      completer.complete(_summary('2026-05-11'));
      await refresh;

      verify(() => repository.getDailySummary()).called(2);
      expect(viewModel.summary?.date, '2026-05-11');
    });
  });

  group('DashboardViewModel hydration updates', () {
    late MockNutritionRepository repository;
    late DateTime now;
    late DashboardViewModel viewModel;

    setUp(() {
      repository = MockNutritionRepository();
      now = DateTime(2026, 5, 10, 10);
      viewModel = DashboardViewModel(
        nutritionRepository: repository,
        now: () => now,
      );
    });

    test('updates daily water optimistically without loading state', () async {
      when(() => repository.getDailySummary()).thenAnswer(
        (_) async => _summary(
          '2026-05-10',
          hydrationGoalLiters: 2.5,
        ),
      );
      await viewModel.load();

      final save = Completer<DailySummary>();
      when(
        () => repository.updateDailyHydration(waterConsumedLiters: 0.25),
      ).thenAnswer((_) => save.future);

      final update = viewModel.updateDailyWater(0.25);

      expect(viewModel.summary?.waterConsumedLiters, 0.25);
      expect(viewModel.isLoading, isFalse);

      save.complete(
        _summary(
          '2026-05-10',
          hydrationGoalLiters: 2.5,
          waterConsumedLiters: 0.25,
        ),
      );

      expect(await update, isTrue);
      expect(viewModel.summary?.waterConsumedLiters, 0.25);
      expect(viewModel.error, isNull);
      verify(
        () => repository.updateDailyHydration(waterConsumedLiters: 0.25),
      ).called(1);
    });

    test('queues rapid daily water updates and saves the latest value',
        () async {
      when(() => repository.getDailySummary()).thenAnswer(
        (_) async => _summary(
          '2026-05-10',
          hydrationGoalLiters: 2.5,
        ),
      );
      await viewModel.load();

      final firstSave = Completer<DailySummary>();
      final secondSave = Completer<DailySummary>();
      when(
        () => repository.updateDailyHydration(waterConsumedLiters: 0.25),
      ).thenAnswer((_) => firstSave.future);
      when(
        () => repository.updateDailyHydration(waterConsumedLiters: 0.5),
      ).thenAnswer((_) => secondSave.future);

      final firstUpdate = viewModel.updateDailyWater(0.25);
      final secondUpdate = viewModel.updateDailyWater(0.5);

      expect(viewModel.summary?.waterConsumedLiters, 0.5);
      expect(viewModel.isLoading, isFalse);
      verify(
        () => repository.updateDailyHydration(waterConsumedLiters: 0.25),
      ).called(1);
      verifyNever(
        () => repository.updateDailyHydration(waterConsumedLiters: 0.5),
      );

      firstSave.complete(
        _summary(
          '2026-05-10',
          hydrationGoalLiters: 2.5,
          waterConsumedLiters: 0.25,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      verify(
        () => repository.updateDailyHydration(waterConsumedLiters: 0.5),
      ).called(1);
      expect(viewModel.summary?.waterConsumedLiters, 0.5);

      secondSave.complete(
        _summary(
          '2026-05-10',
          hydrationGoalLiters: 2.5,
          waterConsumedLiters: 0.5,
        ),
      );

      expect(await firstUpdate, isTrue);
      expect(await secondUpdate, isTrue);
      expect(viewModel.summary?.waterConsumedLiters, 0.5);
      expect(viewModel.error, isNull);
    });

    test('rolls back optimistic water when save fails', () async {
      when(() => repository.getDailySummary()).thenAnswer(
        (_) async => _summary(
          '2026-05-10',
          hydrationGoalLiters: 2.5,
        ),
      );
      await viewModel.load();

      final save = Completer<DailySummary>();
      when(
        () => repository.updateDailyHydration(waterConsumedLiters: 0.25),
      ).thenAnswer((_) => save.future);

      final update = viewModel.updateDailyWater(0.25);

      expect(viewModel.summary?.waterConsumedLiters, 0.25);
      expect(viewModel.isLoading, isFalse);
      save.completeError(Exception('database unavailable'));

      expect(await update, isFalse);
      expect(viewModel.summary?.waterConsumedLiters, 0);
      expect(viewModel.error, 'We could not save that change. Try again.');
    });
  });

  group('MealHistoryViewModel cache', () {
    late MockNutritionRepository repository;
    late DateTime now;
    late MealHistoryViewModel viewModel;

    setUp(() {
      repository = MockNutritionRepository();
      now = DateTime(2026, 5, 10, 10);
      viewModel = MealHistoryViewModel(
        nutritionRepository: repository,
        now: () => now,
      );
    });

    test('loads once while cache is fresh', () async {
      _stubWeekSummaries(repository, selectedMealId: 'meal-1');

      await viewModel.load();
      await viewModel.load();

      verify(() => repository.getDailySummary(date: any(named: 'date')))
          .called(7);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.meals, hasLength(1));
    });

    test('force refresh bypasses cache and shows loading', () async {
      _stubWeekSummaries(repository, selectedMealId: 'meal-1');
      await viewModel.load();

      final completer = Completer<DailySummary>();
      when(() => repository.getDailySummary(date: any(named: 'date')))
          .thenAnswer(
        (_) => completer.future,
      );

      final refresh = viewModel.load(forceRefresh: true);
      expect(viewModel.isLoading, isTrue);

      completer.complete(_summary('2026-05-10', meals: [_meal('meal-2')]));
      await refresh;

      verify(() => repository.getDailySummary(date: any(named: 'date')))
          .called(14);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.meals.single.id, 'meal-2');
    });

    test('expired cache refreshes silently', () async {
      _stubWeekSummaries(repository, selectedMealId: 'meal-1');
      await viewModel.load();
      now = now.add(const Duration(seconds: 61));

      final completer = Completer<DailySummary>();
      when(() => repository.getDailySummary(date: any(named: 'date')))
          .thenAnswer(
        (_) => completer.future,
      );

      final refresh = viewModel.load();
      expect(viewModel.isLoading, isFalse);

      completer.complete(_summary('2026-05-10', meals: [_meal('meal-2')]));
      await refresh;

      verify(() => repository.getDailySummary(date: any(named: 'date')))
          .called(14);
      expect(viewModel.meals.single.id, 'meal-2');
    });
  });

  group('MealTemplatesViewModel cache', () {
    late MockNutritionRepository repository;
    late DateTime now;
    late MealTemplatesViewModel viewModel;

    setUp(() {
      repository = MockNutritionRepository();
      now = DateTime(2026, 5, 10, 10);
      viewModel = MealTemplatesViewModel(
        nutritionRepository: repository,
        now: () => now,
      );
    });

    test('loads once while cache is fresh', () async {
      when(() => repository.getTemplates())
          .thenAnswer((_) async => [_template('template-1')]);

      await viewModel.load();
      await viewModel.load();

      verify(() => repository.getTemplates()).called(1);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.templates, hasLength(1));
    });

    test('force refresh bypasses cache and shows loading', () async {
      when(() => repository.getTemplates())
          .thenAnswer((_) async => [_template('template-1')]);
      await viewModel.load();

      final completer = Completer<List<MealTemplate>>();
      when(() => repository.getTemplates()).thenAnswer(
        (_) => completer.future,
      );

      final refresh = viewModel.load(forceRefresh: true);
      expect(viewModel.isLoading, isTrue);

      completer.complete([_template('template-2')]);
      await refresh;

      verify(() => repository.getTemplates()).called(2);
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.templates.single.id, 'template-2');
    });

    test('expired cache refreshes silently', () async {
      when(() => repository.getTemplates())
          .thenAnswer((_) async => [_template('template-1')]);
      await viewModel.load();
      now = now.add(const Duration(seconds: 61));

      final completer = Completer<List<MealTemplate>>();
      when(() => repository.getTemplates()).thenAnswer(
        (_) => completer.future,
      );

      final refresh = viewModel.load();
      expect(viewModel.isLoading, isFalse);

      completer.complete([_template('template-2')]);
      await refresh;

      verify(() => repository.getTemplates()).called(2);
      expect(viewModel.templates.single.id, 'template-2');
    });
  });
}

const _nutrition = NutritionSnapshot(
  calories: 400,
  proteinGrams: 30,
  carbsGrams: 45,
  fatGrams: 12,
);

void _stubWeekSummaries(
  MockNutritionRepository repository, {
  required String selectedMealId,
}) {
  when(() => repository.getDailySummary(date: any(named: 'date'))).thenAnswer(
    (invocation) async {
      final date = invocation.namedArguments[#date] as String;
      return _summary(
        date,
        meals: date == '2026-05-10' ? [_meal(selectedMealId)] : const [],
      );
    },
  );
}

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
