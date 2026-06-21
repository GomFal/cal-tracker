import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/local_toolkit/data/local_toolkit_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved ingredients My foods benchmark', (tester) async {
    final dependencies = createLocalToolkitDependencies();
    _seedBenchmarkUsualFoods(dependencies.store);

    await tester.pumpWidget(
      CalTrackerBootstrap(
        tokenStorage: dependencies.tokenStorage,
        authRepository: dependencies.authRepository,
        nutritionRepository: dependencies.nutritionRepository,
        preferencesRepository: dependencies.preferencesRepository,
        mobileUpdateService: dependencies.mobileUpdateService,
        audioRecorderService: dependencies.audioRecorderService,
        checkForUpdates: false,
      ),
    );
    await _pumpUntilHitTestable(
      tester,
      find.byKey(const ValueKey('main_nav_usual')),
    );

    await binding.traceAction(() async {
      await tester.tap(
        find.byKey(const ValueKey('main_nav_usual')).hitTestable(),
      );
      await _pumpUntilHitTestable(
        tester,
        find.byKey(const ValueKey('usuals_tab_ingredients')),
      );

      await tester.tap(
        find.byKey(const ValueKey('usuals_tab_ingredients')).hitTestable(),
      );
      await _pumpUntilHitTestable(
        tester,
        find.byKey(
          const ValueKey('usual_food_edit_local-usual-food-1'),
        ),
      );
    }, reportKey: 'usual_foods_list_open_timeline');

    await binding.traceAction(() async {
      await tester.tap(
        find
            .byKey(
              const ValueKey('usual_food_edit_local-usual-food-1'),
            )
            .hitTestable(),
      );
      await _pumpUntilFound(tester, find.text('Edit saved ingredient'));
      await _pumpUntilFound(tester, find.text('Greek yogurt'));
    }, reportKey: 'usual_food_editor_open_timeline');
  });
}

void _seedBenchmarkUsualFoods(LocalFixtureStore store) {
  for (var index = 0; index < 12; index++) {
    store.createUsualFood(
      UsualFoodInput(
        name: index == 0 ? 'Greek yogurt' : 'Benchmark ingredient ${index + 1}',
        servingGrams: 100 + index * 10,
        nutrition: NutritionSnapshot(
          calories: 120 + index * 8,
          proteinGrams: 8 + index * 0.7,
          carbsGrams: 10 + index * 1.1,
          fatGrams: 3 + index * 0.3,
        ),
      ),
    );
  }
}

Future<void> _pumpUntilHitTestable(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  await _pumpUntilFound(tester, finder.hitTestable(), timeout: timeout);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 16));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}
