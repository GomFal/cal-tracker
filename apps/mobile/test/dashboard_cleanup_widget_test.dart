import 'dart:async';

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/app/theme_mode_view_model.dart';
import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_repository.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/auth_models.dart';
import 'package:cal_tracker_mobile/domain/models/macro_distribution.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/core/design_system.dart';
import 'package:cal_tracker_mobile/ui/features/auth/view_models/auth_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/views/dashboard_screen.dart';
import 'package:cal_tracker_mobile/ui/features/meal_history/view_models/meal_history_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_history/views/meal_history_screen.dart';
import 'package:cal_tracker_mobile/ui/features/settings/view_models/settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'dashboard keeps cleaned up Home surface without theme toggle',
    (tester) async {
      final preferencesRepository = _FakePreferencesRepository();
      final themeModeViewModel = ThemeModeViewModel(
        preferencesRepository: preferencesRepository,
      );
      final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
        ..setUser(_testUser);
      final nutritionRepository = _FakeNutritionRepository(
        dailySummary: _summaryWithNoMeals,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
            ChangeNotifierProvider<ThemeModeViewModel>.value(
              value: themeModeViewModel,
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  DashboardViewModel(nutritionRepository: nutritionRepository),
            ),
          ],
          child: _testApp(const DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dark_mode_toggle')), findsNothing);
      expect(
        find.byKey(const ValueKey('dashboard_progress_card')),
        findsOneWidget,
      );
      expect(find.text('MACROS'), findsOneWidget);
      expect(find.text('0 / 0 L'), findsOneWidget);
      expect(find.byKey(const ValueKey('dashboard_goal_line')), findsNothing);
      expect(find.text('Calendar'), findsNothing);
      expect(find.text('Notifications'), findsNothing);
      expect(find.byIcon(Icons.calendar_today_rounded), findsNothing);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
      expect(find.byIcon(Icons.bolt_rounded), findsNothing);

      expect(themeModeViewModel.themeMode, ThemeMode.dark);
      expect(preferencesRepository.savedModes, isEmpty);
    },
  );

  testWidgets('dashboard water widget steps between zero and the goal', (
    tester,
  ) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithWaterGoal,
    );
    final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
      ..setUser(_testUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
          ChangeNotifierProvider(
            create: (_) => ThemeModeViewModel(
              preferencesRepository: _FakePreferencesRepository(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                DashboardViewModel(nutritionRepository: nutritionRepository),
          ),
        ],
        child: _testApp(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WATER INTAKE'), findsOneWidget);
    expect(find.text('0 / 2.5 L'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('dashboard_water_increase_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.25 / 2.5 L'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('dashboard_water_decrease_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 / 2.5 L'), findsOneWidget);
  });

  testWidgets('dashboard water section has no blue card container', (
    tester,
  ) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithWaterGoal,
    );
    final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
      ..setUser(_testUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
          ChangeNotifierProvider(
            create: (_) => ThemeModeViewModel(
              preferencesRepository: _FakePreferencesRepository(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                DashboardViewModel(nutritionRepository: nutritionRepository),
          ),
        ],
        child: _testApp(
          const DashboardScreen(),
          themeMode: ThemeMode.dark,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('dashboard_water_intake_card')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('dashboard_water_progress')),
      findsOneWidget,
    );
  });

  testWidgets(
    'dashboard empty meals section shows CTA without card',
    (tester) async {
      final nutritionRepository = _FakeNutritionRepository(
        dailySummary: _summaryWithNoMeals,
      );
      final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
        ..setUser(_testUser);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
            ChangeNotifierProvider(
              create: (_) => ThemeModeViewModel(
                preferencesRepository: _FakePreferencesRepository(),
              ),
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  DashboardViewModel(nutritionRepository: nutritionRepository),
            ),
          ],
          child: _testApp(
            const DashboardScreen(),
            themeMode: ThemeMode.dark,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dashboard_empty_meals_card')),
        findsNothing,
      );
      expect(
        find.text('No meals logged today'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'dashboard calorie setup hero shows setup prompt without card shadows',
    (tester) async {
      final nutritionRepository = _FakeNutritionRepository(
        dailySummary: _summaryWithoutConfiguredCalories,
      );
      final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
        ..setUser(_testUser);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
            ChangeNotifierProvider(
              create: (_) => ThemeModeViewModel(
                preferencesRepository: _FakePreferencesRepository(),
              ),
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  DashboardViewModel(nutritionRepository: nutritionRepository),
            ),
          ],
          child: _testApp(
            const DashboardScreen(),
            themeMode: ThemeMode.dark,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dashboard_progress_card')),
        findsOneWidget,
      );
      expect(
        find.text('Set up your'),
        findsOneWidget,
      );
      expect(
        find.text('daily calories'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'dashboard water widget updates optimistically without page refresh',
    (tester) async {
      final firstSave = Completer<DailySummary>();
      final secondSave = Completer<DailySummary>();
      final nutritionRepository = _FakeNutritionRepository(
        dailySummary: _summaryWithWaterGoal,
        hydrationUpdateCompleters: [firstSave, secondSave],
      );
      final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
        ..setUser(_testUser);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
            ChangeNotifierProvider(
              create: (_) => ThemeModeViewModel(
                preferencesRepository: _FakePreferencesRepository(),
              ),
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  DashboardViewModel(nutritionRepository: nutritionRepository),
            ),
          ],
          child: _testApp(const DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 / 2.5 L'), findsOneWidget);
      // Hero section now has a LinearProgressIndicator thin bar

      await tester.tap(
        find.byKey(const ValueKey('dashboard_water_increase_button')),
      );
      await tester.pump();

      expect(find.text('0.25 / 2.5 L'), findsOneWidget);
      // Hero section now has a LinearProgressIndicator thin bar

      await tester.tap(
        find.byKey(const ValueKey('dashboard_water_increase_button')),
      );
      await tester.pump();

      expect(find.text('0.5 / 2.5 L'), findsOneWidget);
      // Hero section now has a LinearProgressIndicator thin bar
      expect(nutritionRepository.hydrationUpdateRequests, [0.25]);

      firstSave.complete(_summaryWithWater(_summaryWithWaterGoal, 0.25));
      await tester.pump();

      expect(nutritionRepository.hydrationUpdateRequests, [0.25, 0.5]);
      expect(find.text('0.5 / 2.5 L'), findsOneWidget);
      // Hero section now has a LinearProgressIndicator thin bar

      secondSave.complete(_summaryWithWater(_summaryWithWaterGoal, 0.5));
      await tester.pumpAndSettle();

      expect(find.text('0.5 / 2.5 L'), findsOneWidget);
      // Hero section now has a LinearProgressIndicator thin bar
    },
  );

  testWidgets('dashboard meal cards edit explicit ingredients', (tester) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithMeal,
    );
    final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
      ..setUser(_testUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
          ChangeNotifierProvider(
            create: (_) => ThemeModeViewModel(
              preferencesRepository: _FakePreferencesRepository(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                DashboardViewModel(nutritionRepository: nutritionRepository),
          ),
        ],
        child: _testApp(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FreshFoodStack), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboard_water_increase_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('dashboard_meal_row_meal-1')));
    await tester.pumpAndSettle();

    expect(find.text('Edit ingredients'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard_item_compact_0')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('dashboard_item_name_0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dashboard_item_compact_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboard_item_name_0')), findsOneWidget);

    final actionsFinder =
        find.byKey(const ValueKey('dashboard_item_actions_0'));
    await tester.ensureVisible(actionsFinder);
    await tester.pumpAndSettle();
    await tester.tap(actionsFinder.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('dashboard_item_edit_details_0')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('dashboard_item_protein_0')),
      '50',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('dashboard_item_apply_suggestion_0')),
    );
    await tester.pumpAndSettle();
    final caloriesField = tester.widget<TextField>(
      find.byKey(const ValueKey('dashboard_item_calories_0')),
    );
    expect(caloriesField.controller!.text, '488');
    await tester.tap(
      find.byKey(const ValueKey('dashboard_item_save_details_0')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('save_dashboard_item_edits_button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('save_dashboard_item_edits_button')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(nutritionRepository.lastCorrectedItems, isNotNull);
    expect(nutritionRepository.lastCorrectedItems!.single.calories, 488);
    expect(find.text('488 Kcal'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);
  });

  testWidgets('dashboard meal editor adds an ingredient from food search', (
    tester,
  ) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithMeal,
      searchItems: [_publicRice],
    );
    final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
      ..setUser(_testUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
          ChangeNotifierProvider(
            create: (_) => ThemeModeViewModel(
              preferencesRepository: _FakePreferencesRepository(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                DashboardViewModel(nutritionRepository: nutritionRepository),
          ),
        ],
        child: _testApp(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dashboard_meal_row_meal-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(const ValueKey('dashboard_add_from_search_button'))
          .hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('dashboard_food_search_field')),
      'rice',
    );
    await tester.tap(
      find.byKey(const ValueKey('dashboard_food_search_submit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(const ValueKey('dashboard_food_search_result_0'))
          .hitTestable(),
    );
    await tester.pumpAndSettle();

    final addedNameField = tester.widget<TextField>(
      find.byKey(const ValueKey('dashboard_item_name_1')),
    );
    expect(addedNameField.controller!.text, 'Public rice');
    expect(nutritionRepository.searchQueries, ['rice']);
    expect(nutritionRepository.lastCorrectedItems, isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('save_dashboard_item_edits_button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('save_dashboard_item_edits_button')),
    );
    await tester.pumpAndSettle();

    expect(nutritionRepository.lastCorrectedItems, hasLength(2));
    expect(nutritionRepository.lastCorrectedItems!.last.name, 'Public rice');
    expect(nutritionRepository.lastCorrectedItems!.last.externalId, 'rice');
  });

  testWidgets('dashboard meal editor replaces an ingredient from food search', (
    tester,
  ) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithMeal,
      searchItems: [_publicBread],
    );
    final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
      ..setUser(_testUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
          ChangeNotifierProvider(
            create: (_) => ThemeModeViewModel(
              preferencesRepository: _FakePreferencesRepository(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                DashboardViewModel(nutritionRepository: nutritionRepository),
          ),
        ],
        child: _testApp(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dashboard_meal_row_meal-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dashboard_item_compact_0')));
    await tester.pumpAndSettle();
    final searchToggle = find.byKey(
      const ValueKey('dashboard_item_0_search_toggle'),
    );
    final actionsFinder =
        find.byKey(const ValueKey('dashboard_item_actions_0'));
    await tester.ensureVisible(actionsFinder);
    await tester.pumpAndSettle();
    await tester.tap(actionsFinder.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(searchToggle.hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('dashboard_item_0_search_field')),
      'bread',
    );
    await tester.tap(
      find.byKey(const ValueKey('dashboard_item_0_search_submit')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('dashboard_item_0_search_result_0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byKey(const ValueKey('dashboard_item_0_search_result_0'))
          .hitTestable(),
    );
    await tester.pumpAndSettle();

    final replacedNameField = tester.widget<TextField>(
      find.byKey(const ValueKey('dashboard_item_name_0')),
    );
    expect(replacedNameField.controller!.text, 'Bread');
    expect(nutritionRepository.lastCorrectedItems, isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('save_dashboard_item_edits_button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('save_dashboard_item_edits_button')),
    );
    await tester.pumpAndSettle();

    expect(nutritionRepository.lastCorrectedItems, hasLength(1));
    expect(nutritionRepository.lastCorrectedItems!.single.name, 'Bread');
    expect(nutritionRepository.lastCorrectedItems!.single.calories, 265);
    expect(nutritionRepository.lastCorrectedItems!.single.externalId, 'bread');
  });

  testWidgets('dashboard meal editor deletes after confirmation',
      (tester) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithMeal,
    );
    final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
      ..setUser(_testUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
          ChangeNotifierProvider(
            create: (_) => ThemeModeViewModel(
              preferencesRepository: _FakePreferencesRepository(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                DashboardViewModel(nutritionRepository: nutritionRepository),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                MealHistoryViewModel(nutritionRepository: nutritionRepository),
          ),
        ],
        child: _testApp(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Oats bowl'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard_meal_row_meal-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dashboard_edit_meal_meal-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('dashboard_delete_meal_meal-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('dashboard_meal_row_meal-1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit ingredients'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('dashboard_delete_meal_meal-1')));
    await tester.pumpAndSettle();

    expect(find.text('Delete meal?'), findsOneWidget);
    expect(find.text('Oats bowl'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(nutritionRepository.deletedMealIds, isEmpty);
    expect(find.text('Oats bowl'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('dashboard_delete_meal_meal-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(nutritionRepository.deletedMealIds, ['meal-1']);
    expect(find.text('Oats bowl'), findsNothing);
    expect(find.text('No meals logged today'), findsOneWidget);
  });

  testWidgets('dashboard first-run calorie setup saves and refreshes Home', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository();
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithoutConfiguredCalories,
    );
    final authViewModel = AuthViewModel(authRepository: authRepository)
      ..setUser(_testUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
          ChangeNotifierProvider(
            create: (_) => ThemeModeViewModel(
              preferencesRepository: _FakePreferencesRepository(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                DashboardViewModel(nutritionRepository: nutritionRepository),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                MealHistoryViewModel(nutritionRepository: nutritionRepository),
          ),
          ChangeNotifierProvider(
            create: (_) => SettingsViewModel(
              authRepository: authRepository,
              nutritionRepository: nutritionRepository,
            ),
          ),
        ],
        child: _testApp(const DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up your'), findsOneWidget);
    expect(find.text('daily calories'), findsOneWidget);
    expect(find.text('Here.'), findsOneWidget);
    expect(find.text('Choose a target to track today.'), findsNothing);
    expect(find.text('Tap to set your calorie target'), findsNothing);
    expect(find.text('??'), findsNothing);

    final progressCard = find.byKey(const ValueKey('dashboard_progress_card'));
    await tester.ensureVisible(progressCard);
    await tester.pumpAndSettle();
    await tester.tap(progressCard);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('dashboard_calorie_target_field')),
      '1900',
    );
    await tester.tap(
      find.byKey(const ValueKey('dashboard_save_calorie_target_button')),
    );
    await tester.pumpAndSettle();

    expect(nutritionRepository.updatedCalories, 1900);
    expect(nutritionRepository.updateSource, 'manual');
    expect(find.text('Calories saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('macro_prompt_not_now')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('macro_prompt_not_now')));
    await tester.pumpAndSettle();
    expect(find.text('Set up your'), findsNothing);
    expect(find.text('daily calories'), findsNothing);
    expect(find.text('Here.'), findsNothing);
    expect(
      find.byKey(const ValueKey('dashboard_remaining_calories')),
      findsOneWidget,
    );
    expect(find.text('1900'), findsOneWidget);
    expect(find.text('0/120'), findsNothing);
    expect(find.text('0/220'), findsNothing);
    expect(find.text('0/70'), findsNothing);
    expect(find.byKey(const ValueKey('dashboard_goal_line')), findsNothing);
  });

  testWidgets('history shows empty logged meals without fake metric cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => MealHistoryViewModel(
              nutritionRepository: _FakeNutritionRepository(
                dailySummary: _summaryWithNoMeals,
              ),
            ),
          ),
        ],
        child: _testApp(const MealHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('history_calorie_chart')), findsOneWidget);
    expect(find.text('Logged meals'), findsOneWidget);
    expect(find.text('No meals logged'), findsOneWidget);
    expect(find.text('Exercise'), findsNothing);
    expect(find.text('BPM'), findsNothing);
    expect(find.text('Weight'), findsNothing);
    expect(find.text('Water'), findsNothing);
  });

  testWidgets('history shows logged meals without fake metric cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => MealHistoryViewModel(
              nutritionRepository: _FakeNutritionRepository(
                dailySummary: _summaryWithMeal,
              ),
            ),
          ),
        ],
        child: _testApp(const MealHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('history_calorie_chart')), findsOneWidget);
    expect(find.text('Logged meals'), findsOneWidget);
    expect(find.text('Oats bowl'), findsOneWidget);
    expect(find.text('Exercise'), findsNothing);
    expect(find.text('BPM'), findsNothing);
    expect(find.text('Weight'), findsNothing);
    expect(find.text('Water'), findsNothing);
  });
}

Widget _testApp(Widget child, {ThemeMode themeMode = ThemeMode.light}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildLightTheme(),
    darkTheme: buildDarkTheme(),
    themeMode: themeMode,
    home: Scaffold(body: child),
  );
}

class _FakeNutritionRepository extends NutritionRepository {
  _FakeNutritionRepository({
    DailySummary? dailySummary,
    List<Meal>? mealHistory,
    List<Completer<DailySummary>>? hydrationUpdateCompleters,
    List<MealItem> searchItems = const [],
    Object? searchError,
  })  : _dailySummary = dailySummary ?? _summaryWithNoMeals,
        _mealHistory = mealHistory ?? const [],
        _hydrationUpdateCompleters =
            hydrationUpdateCompleters ?? <Completer<DailySummary>>[],
        _searchItems = searchItems,
        _searchError = searchError,
        super(apiClient: _unusedApiClient());

  DailySummary _dailySummary;
  final List<Meal> _mealHistory;
  final List<Completer<DailySummary>> _hydrationUpdateCompleters;
  final List<MealItem> _searchItems;
  final Object? _searchError;
  List<MealItem>? lastCorrectedItems;
  final List<String> deletedMealIds = [];
  final List<double> hydrationUpdateRequests = [];
  final List<String> searchQueries = [];
  int? updatedCalories;
  String? updateSource;

  @override
  Future<DailySummary> getDailySummary({String? date}) async => _dailySummary;

  @override
  Future<List<Meal>> getMealHistory() async => _mealHistory;

  @override
  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 10,
    String? barcode,
  }) async {
    searchQueries.add(query);
    final error = _searchError;
    if (error != null) {
      throw error;
    }
    return FoodSearchResult(items: _searchItems.take(limit).toList());
  }

  @override
  Future<DailyGoals> updateDailyGoals({
    String? date,
    int? calories,
    double? hydrationGoalLiters,
    String? calorieTargetSource,
    MacroDistributionConfig? macroConfig,
    int? macroCalorieTarget,
  }) async {
    updatedCalories = calories;
    updateSource = calorieTargetSource;
    final target = calories == null
        ? _dailySummary.target
        : NutritionSnapshot(
            calories: calories,
            proteinGrams: _dailySummary.target.proteinGrams,
            carbsGrams: _dailySummary.target.carbsGrams,
            fatGrams: _dailySummary.target.fatGrams,
          );
    _dailySummary = DailySummary(
      date: _dailySummary.date,
      consumed: _dailySummary.consumed,
      target: target,
      remaining: NutritionSnapshot(
        calories: target.calories - _dailySummary.consumed.calories,
        proteinGrams: target.proteinGrams - _dailySummary.consumed.proteinGrams,
        carbsGrams: target.carbsGrams - _dailySummary.consumed.carbsGrams,
        fatGrams: target.fatGrams - _dailySummary.consumed.fatGrams,
      ),
      hydrationGoalLiters:
          hydrationGoalLiters ?? _dailySummary.hydrationGoalLiters,
      waterConsumedLiters: _dailySummary.waterConsumedLiters,
      calorieTargetConfigured:
          calories == null ? _dailySummary.calorieTargetConfigured : true,
      calorieTargetSource:
          calorieTargetSource ?? _dailySummary.calorieTargetSource,
      meals: _dailySummary.meals,
    );
    return DailyGoals(
      date: _dailySummary.date,
      target: _dailySummary.target,
      hydrationGoalLiters: _dailySummary.hydrationGoalLiters,
      calorieTargetConfigured: _dailySummary.calorieTargetConfigured,
      calorieTargetSource: _dailySummary.calorieTargetSource,
    );
  }

  @override
  Future<DailySummary> updateDailyHydration({
    String? date,
    required double waterConsumedLiters,
  }) async {
    hydrationUpdateRequests.add(waterConsumedLiters);
    final clamped = waterConsumedLiters
        .clamp(0, _dailySummary.hydrationGoalLiters)
        .toDouble();
    if (_hydrationUpdateCompleters.isNotEmpty) {
      _dailySummary = await _hydrationUpdateCompleters.removeAt(0).future;
      return _dailySummary;
    }
    _dailySummary = _summaryWithWater(_dailySummary, clamped);
    return _dailySummary;
  }

  @override
  Future<CalorieEstimate> estimateCalories({
    required int age,
    required String sex,
    required double heightCm,
    required double weightKg,
    required String activityLevel,
    required String goal,
    String? pace,
  }) async {
    return const CalorieEstimate(
      bmr: 1395,
      maintenanceCalories: 1920,
      targetCalories: 1620,
      recommendedRangeMin: 1520,
      recommendedRangeMax: 1720,
      activityFactor: 1.375,
      adjustmentCalories: 300,
      warnings: [],
      explanation: 'Test estimate',
    );
  }

  @override
  Future<Meal> correctMealItems(String mealId, List<MealItem> items) async {
    lastCorrectedItems = items;
    final meal = _dailySummary.meals.firstWhere((meal) => meal.id == mealId);
    final nutrition = _sumNutrition(items);
    final corrected = Meal(
      id: meal.id,
      title: meal.title,
      occurredAt: meal.occurredAt,
      mealLabel: meal.mealLabel,
      nutrition: nutrition,
      items: items,
    );
    final meals = [
      for (final item in _dailySummary.meals)
        if (item.id == mealId) corrected else item,
    ];
    final consumed = _sumMealNutrition(meals);
    _dailySummary = DailySummary(
      date: _dailySummary.date,
      consumed: consumed,
      target: _dailySummary.target,
      remaining: NutritionSnapshot(
        calories: _dailySummary.target.calories - consumed.calories,
        proteinGrams: _dailySummary.target.proteinGrams - consumed.proteinGrams,
        carbsGrams: _dailySummary.target.carbsGrams - consumed.carbsGrams,
        fatGrams: _dailySummary.target.fatGrams - consumed.fatGrams,
      ),
      hydrationGoalLiters: _dailySummary.hydrationGoalLiters,
      waterConsumedLiters: _dailySummary.waterConsumedLiters,
      calorieTargetConfigured: _dailySummary.calorieTargetConfigured,
      calorieTargetSource: _dailySummary.calorieTargetSource,
      meals: meals,
    );
    return corrected;
  }

  @override
  Future<bool> deleteMeal(String mealId, {bool confirmed = false}) async {
    if (!confirmed) return false;
    final mealExists = _dailySummary.meals.any((meal) => meal.id == mealId);
    if (!mealExists) return false;
    deletedMealIds.add(mealId);
    final meals = [
      for (final meal in _dailySummary.meals)
        if (meal.id != mealId) meal,
    ];
    final consumed = _sumMealNutrition(meals);
    _dailySummary = DailySummary(
      date: _dailySummary.date,
      consumed: consumed,
      target: _dailySummary.target,
      remaining: NutritionSnapshot(
        calories: _dailySummary.target.calories - consumed.calories,
        proteinGrams: _dailySummary.target.proteinGrams - consumed.proteinGrams,
        carbsGrams: _dailySummary.target.carbsGrams - consumed.carbsGrams,
        fatGrams: _dailySummary.target.fatGrams - consumed.fatGrams,
      ),
      hydrationGoalLiters: _dailySummary.hydrationGoalLiters,
      waterConsumedLiters: _dailySummary.waterConsumedLiters,
      calorieTargetConfigured: _dailySummary.calorieTargetConfigured,
      calorieTargetSource: _dailySummary.calorieTargetSource,
      meals: meals,
    );
    return true;
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
      : super(
            apiClient: _unusedApiClient(), tokenStorage: _MemoryTokenStorage());
}

class _MemoryTokenStorage implements TokenStorage {
  StoredTokens? _tokens;

  @override
  Future<void> clear() async {
    _tokens = null;
  }

  @override
  Future<StoredTokens?> read() async => _tokens;

  @override
  Future<void> write(StoredTokens tokens) async {
    _tokens = tokens;
  }
}

class _FakePreferencesRepository implements AppPreferencesRepository {
  ThemeMode savedThemeMode = ThemeMode.system;
  String? savedLocaleCode;
  final List<ThemeMode> savedModes = [];
  int nextHeroIndex = 0;

  @override
  Future<ThemeMode> loadThemeMode() async => savedThemeMode;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    savedThemeMode = mode;
    savedModes.add(mode);
  }

  @override
  Future<String?> loadLocaleCode() async => savedLocaleCode;

  @override
  Future<void> saveLocaleCode(String code) async {
    savedLocaleCode = code;
  }

  @override
  Future<int> nextAuthHeroIndex({int count = 5}) async {
    final value = nextHeroIndex % count;
    nextHeroIndex++;
    return value;
  }
}

CalTrackerApiClient _unusedApiClient() {
  return CalTrackerApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    tokenStorage: _MemoryTokenStorage(),
  );
}

DailySummary _summaryWithWater(
  DailySummary summary,
  double waterConsumedLiters,
) {
  return DailySummary(
    date: summary.date,
    consumed: summary.consumed,
    target: summary.target,
    remaining: summary.remaining,
    hydrationGoalLiters: summary.hydrationGoalLiters,
    waterConsumedLiters: waterConsumedLiters,
    calorieTargetConfigured: summary.calorieTargetConfigured,
    calorieTargetSource: summary.calorieTargetSource,
    macroMode: summary.macroMode,
    macroSource: summary.macroSource,
    macroPreset: summary.macroPreset,
    proteinPct: summary.proteinPct,
    carbsPct: summary.carbsPct,
    fatPct: summary.fatPct,
    macroCalories: summary.macroCalories,
    calorieDeltaKcal: summary.calorieDeltaKcal,
    meals: summary.meals,
  );
}

const _testUser = AuthUser(
  id: 'user-1',
  email: 'test@example.com',
  displayName: 'Test User',
  trustedModeEnabled: false,
);

const _emptyNutrition = NutritionSnapshot(
  calories: 0,
  proteinGrams: 0,
  carbsGrams: 0,
  fatGrams: 0,
);

const _targetNutrition = NutritionSnapshot(
  calories: 1920,
  proteinGrams: 120,
  carbsGrams: 220,
  fatGrams: 70,
);

const _summaryWithNoMeals = DailySummary(
  date: '2026-05-09',
  consumed: _emptyNutrition,
  target: _targetNutrition,
  remaining: _targetNutrition,
  hydrationGoalLiters: 0,
  waterConsumedLiters: 0,
  calorieTargetConfigured: true,
  calorieTargetSource: 'manual',
  meals: [],
);

const _summaryWithWaterGoal = DailySummary(
  date: '2026-05-09',
  consumed: _emptyNutrition,
  target: _targetNutrition,
  remaining: _targetNutrition,
  hydrationGoalLiters: 2.5,
  waterConsumedLiters: 0,
  calorieTargetConfigured: true,
  calorieTargetSource: 'manual',
  meals: [],
);

const _summaryWithoutConfiguredCalories = DailySummary(
  date: '2026-05-09',
  consumed: _emptyNutrition,
  target: _targetNutrition,
  remaining: _targetNutrition,
  hydrationGoalLiters: 0,
  waterConsumedLiters: 0,
  calorieTargetConfigured: false,
  calorieTargetSource: 'default',
  meals: [],
);

final _testMeal = Meal(
  id: 'meal-1',
  title: 'Oats bowl',
  occurredAt: DateTime(2026, 5, 9, 8),
  mealLabel: MealLabel.breakfast,
  nutrition: const NutritionSnapshot(
    calories: 420,
    proteinGrams: 20,
    carbsGrams: 45,
    fatGrams: 12,
  ),
  items: const [
    MealItem(
      name: 'Oats',
      quantity: 100,
      unit: 'g',
      calories: 420,
      proteinGrams: 20,
      carbsGrams: 45,
      fatGrams: 12,
      source: 'test_fixture',
    ),
  ],
);

final _summaryWithMeal = DailySummary(
  date: '2026-05-09',
  consumed: _testMeal.nutrition,
  target: _targetNutrition,
  remaining: const NutritionSnapshot(
    calories: 1500,
    proteinGrams: 100,
    carbsGrams: 175,
    fatGrams: 58,
  ),
  hydrationGoalLiters: 2.5,
  waterConsumedLiters: 0,
  calorieTargetConfigured: true,
  calorieTargetSource: 'manual',
  meals: [_testMeal],
);

const _publicRice = MealItem(
  name: 'Public rice',
  quantity: 100,
  unit: 'g',
  calories: 130,
  proteinGrams: 2.7,
  carbsGrams: 28,
  fatGrams: 0.3,
  source: 'public_food_search',
  externalSource: 'test_food_db',
  externalId: 'rice',
);

const _publicBread = MealItem(
  name: 'Bread',
  quantity: 100,
  unit: 'g',
  calories: 265,
  proteinGrams: 9,
  carbsGrams: 49,
  fatGrams: 3.2,
  source: 'public_food_search',
  externalSource: 'test_food_db',
  externalId: 'bread',
);

NutritionSnapshot _sumNutrition(List<MealItem> items) {
  return NutritionSnapshot(
    calories: items.fold<int>(0, (sum, item) => sum + item.calories),
    proteinGrams: items.fold<double>(0, (sum, item) => sum + item.proteinGrams),
    carbsGrams: items.fold<double>(0, (sum, item) => sum + item.carbsGrams),
    fatGrams: items.fold<double>(0, (sum, item) => sum + item.fatGrams),
  );
}

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
