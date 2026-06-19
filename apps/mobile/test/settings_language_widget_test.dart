import 'package:cal_tracker_mobile/app/locale_view_model.dart';
import 'package:cal_tracker_mobile/app/performance_overlay_view_model.dart';
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
import 'package:cal_tracker_mobile/ui/features/auth/view_models/auth_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/meal_history/view_models/meal_history_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/settings/view_models/settings_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/settings/views/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Menu language row changes from Language to Idioma', (
    tester,
  ) async {
    final preferencesRepository = _FakePreferencesRepository();
    final localeViewModel = LocaleViewModel(
      preferencesRepository: preferencesRepository,
    );
    final nutritionRepository = _FakeNutritionRepository();
    await _pumpSettings(
      tester,
      nutritionRepository: nutritionRepository,
      localeViewModel: localeViewModel,
    );

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Macro distribution'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    expect(find.text('Data sources'), findsOneWidget);
    expect(find.textContaining('Open Food Facts'), findsOneWidget);
    expect(find.textContaining('USDA FoodData Central'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('language_settings_row')));
    await tester.pumpAndSettle();
    final languageOptionFinder = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('language_option_');
    });
    expect(
      languageOptionFinder,
      findsNWidgets(AppLocalizations.supportedLocales.length),
    );
    for (final locale in AppLocalizations.supportedLocales) {
      expect(
        find.byKey(ValueKey('language_option_${locale.toLanguageTag()}')),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey('language_option_es')));
    await tester.pumpAndSettle();

    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Distribución de macros'), findsOneWidget);
    expect(find.text('Fuentes de datos'), findsOneWidget);
    expect(preferencesRepository.savedLocaleCode, 'es');
  });

  testWidgets('Menu theme row defaults to dark and persists choices', (
    tester,
  ) async {
    final preferencesRepository = _FakePreferencesRepository();
    final themeModeViewModel = ThemeModeViewModel(
      preferencesRepository: preferencesRepository,
    );
    await _pumpSettings(
      tester,
      preferencesRepository: preferencesRepository,
      themeModeViewModel: themeModeViewModel,
    );

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theme_settings_row')));
    await tester.pumpAndSettle();

    expect(find.text('Choose appearance'), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_option_system')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_option_light')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme_option_dark')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('theme_option_dark')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('theme_option_light')));
    await tester.pumpAndSettle();

    expect(themeModeViewModel.themeMode, ThemeMode.light);
    expect(preferencesRepository.savedModes, [ThemeMode.light]);
    expect(find.text('Light'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theme_settings_row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme_option_dark')));
    await tester.pumpAndSettle();

    expect(themeModeViewModel.themeMode, ThemeMode.dark);
    expect(preferencesRepository.savedModes, [ThemeMode.light, ThemeMode.dark]);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('Developer menu toggles the performance overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final performanceOverlayViewModel = PerformanceOverlayViewModel();
    await _pumpSettings(
      tester,
      performanceOverlayViewModel: performanceOverlayViewModel,
    );

    expect(find.text('Developer tools'), findsOneWidget);
    expect(find.text('Performance overlay'), findsOneWidget);
    expect(performanceOverlayViewModel.visible, isFalse);

    final switchFinder = find.byKey(
      const ValueKey('settings_performance_overlay_switch'),
    );
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder.hitTestable());
    await tester.pumpAndSettle();

    expect(performanceOverlayViewModel.visible, isTrue);
    expect(find.textContaining('Overlay on'), findsOneWidget);
  });

  testWidgets('Menu hydration sheet uses localized copy and saves liters', (
    tester,
  ) async {
    final nutritionRepository = _FakeNutritionRepository();
    await _pumpSettings(tester, nutritionRepository: nutritionRepository);

    expect(find.text('2.5 L per day'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hydration_goal_row')));
    await tester.pumpAndSettle();

    expect(find.text('Set your daily water goal'), findsOneWidget);
    expect(
      find.text('Choose how much water you want to drink each day.'),
      findsOneWidget,
    );
    expect(find.text('Liters (L)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hydration_goal_cancel_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('save_goal_button')).hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('hydration_unit_ounces')));
    await tester.pumpAndSettle();
    expect(find.text('84.5'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('hydration_goal_increase_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save_goal_button')));
    await tester.pumpAndSettle();

    expect(nutritionRepository.updatedHydrationGoalLiters, 2.75);
    expect(find.text('2.75 L per day'), findsOneWidget);

    final preferencesRepository = _FakePreferencesRepository();
    final localeViewModel = LocaleViewModel(
      preferencesRepository: preferencesRepository,
    );
    await localeViewModel.setLocaleTag('es');
    await _pumpSettings(
      tester,
      nutritionRepository: _FakeNutritionRepository(),
      localeViewModel: localeViewModel,
    );

    await tester.tap(find.byKey(const ValueKey('hydration_goal_row')));
    await tester.pumpAndSettle();

    expect(find.text('Define tu objetivo diario de agua'), findsOneWidget);
    expect(
      find.text('Elige cuánta agua quieres beber cada día.'),
      findsOneWidget,
    );

    await tester.drag(find.byType(BottomSheet), const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(find.text('Define tu objetivo diario de agua'), findsNothing);
  });

  testWidgets('Menu calorie target row opens shared calorie sheet and saves', (
    tester,
  ) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithoutConfiguredCalories,
    );
    await _pumpSettings(tester, nutritionRepository: nutritionRepository);

    await tester.tap(find.byKey(const ValueKey('calorie_target_row')));
    await tester.pumpAndSettle();

    expect(find.text('Set your daily calories'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard_calorie_target_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calorie_target_decrement')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calorie_target_increment')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calorie_target_field')), findsNothing);

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

    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('1900 Kcal daily target'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('Menu hides default calorie and macro previews before setup', (
    tester,
  ) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithoutConfiguredCaloriesWithDefaultMacro,
    );
    await _pumpSettings(tester, nutritionRepository: nutritionRepository);

    expect(find.text('Not set'), findsNWidgets(2));
    expect(find.text('2200 Kcal daily target'), findsNothing);
    expect(find.textContaining('Balanced:'), findsNothing);
  });

  testWidgets('Menu macro row requires calories before opening macros', (
    tester,
  ) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithoutConfiguredCalories,
    );
    await _pumpSettings(tester, nutritionRepository: nutritionRepository);

    await tester.tap(find.byKey(const ValueKey('macro_distribution_row')));
    await tester.pumpAndSettle();

    expect(find.text('Set calories first'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('macro_distribution_save_button')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('macro_requires_calories_set_now')),
    );
    await tester.pumpAndSettle();

    expect(nutritionRepository.updateCalls, 0);
    expect(find.text('Set your daily calories'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard_calorie_target_field')),
      findsOneWidget,
    );
  });

  testWidgets('Menu macro gate skip does not update goals', (tester) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithoutConfiguredCalories,
    );
    await _pumpSettings(tester, nutritionRepository: nutritionRepository);

    await tester.tap(find.byKey(const ValueKey('macro_distribution_row')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('macro_requires_calories_skip')),
    );
    await tester.pumpAndSettle();

    expect(nutritionRepository.updateCalls, 0);
    expect(find.text('Set calories first'), findsNothing);
    expect(find.text('Menu'), findsOneWidget);
  });

  testWidgets(
    'Menu macro row opens macro sheet after calories are configured',
    (tester) async {
      await _pumpSettings(tester);

      await tester.tap(find.byKey(const ValueKey('macro_distribution_row')));
      await tester.pumpAndSettle();

      expect(find.text('Set your macros'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('macro_distribution_save_button')),
        findsOneWidget,
      );
      expect(find.text('Set calories first'), findsNothing);
    },
  );

  testWidgets('Menu macro row uses a flat surface border in dark mode', (
    tester,
  ) async {
    final preferencesRepository = _FakePreferencesRepository();
    final themeModeViewModel = ThemeModeViewModel(
      preferencesRepository: preferencesRepository,
    );
    await themeModeViewModel.setThemeMode(ThemeMode.dark);

    await _pumpSettings(
      tester,
      themeModeViewModel: themeModeViewModel,
    );

    final decoration = _freshCardDecoration(tester, 'macro_distribution_row');

    expect(decoration.boxShadow, isNull);
    expect(decoration.border, isNotNull);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  _FakePreferencesRepository? preferencesRepository,
  _FakeNutritionRepository? nutritionRepository,
  LocaleViewModel? localeViewModel,
  ThemeModeViewModel? themeModeViewModel,
  PerformanceOverlayViewModel? performanceOverlayViewModel,
}) async {
  final effectivePreferencesRepository =
      preferencesRepository ?? _FakePreferencesRepository();
  final effectiveLocaleViewModel = localeViewModel ??
      LocaleViewModel(preferencesRepository: effectivePreferencesRepository);
  final effectiveThemeModeViewModel = themeModeViewModel ??
      ThemeModeViewModel(preferencesRepository: effectivePreferencesRepository);
  final effectiveNutritionRepository =
      nutritionRepository ?? _FakeNutritionRepository();
  final effectivePerformanceOverlayViewModel =
      performanceOverlayViewModel ?? PerformanceOverlayViewModel();
  final authRepository = _FakeAuthRepository();
  final authViewModel = AuthViewModel(authRepository: authRepository)
    ..setUser(_testUser);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
        ChangeNotifierProvider<LocaleViewModel>.value(
          value: effectiveLocaleViewModel,
        ),
        ChangeNotifierProvider<ThemeModeViewModel>.value(
          value: effectiveThemeModeViewModel,
        ),
        ChangeNotifierProvider<PerformanceOverlayViewModel>.value(
          value: effectivePerformanceOverlayViewModel,
        ),
        ChangeNotifierProvider(
          create: (_) => DashboardViewModel(
            nutritionRepository: effectiveNutritionRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => MealHistoryViewModel(
            nutritionRepository: effectiveNutritionRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel(
            authRepository: authRepository,
            nutritionRepository: effectiveNutritionRepository,
          ),
        ),
      ],
      child: const _SettingsTestApp(),
    ),
  );
  await tester.pumpAndSettle();
}

class _SettingsTestApp extends StatelessWidget {
  const _SettingsTestApp();

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleViewModel>().locale;
    final themeMode = context.watch<ThemeModeViewModel>().themeMode;
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      home: const Scaffold(body: SettingsScreen()),
    );
  }
}

BoxDecoration _freshCardDecoration(WidgetTester tester, String cardKey) {
  final decoratedBox = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byKey(ValueKey(cardKey)),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return decoratedBox.decoration as BoxDecoration;
}

class _FakePreferencesRepository implements AppPreferencesRepository {
  ThemeMode savedThemeMode = ThemeMode.system;
  String? savedLocaleCode;
  final List<ThemeMode> savedModes = [];

  @override
  Future<String?> loadLocaleCode() async => savedLocaleCode;

  @override
  Future<void> saveLocaleCode(String code) async {
    savedLocaleCode = code;
  }

  @override
  Future<ThemeMode> loadThemeMode() async => savedThemeMode;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    savedThemeMode = mode;
    savedModes.add(mode);
  }

  @override
  Future<int> nextAuthHeroIndex({int count = 5}) async => 0;
}

class _FakeNutritionRepository extends NutritionRepository {
  _FakeNutritionRepository({DailySummary? dailySummary})
      : _dailySummary = dailySummary ?? _summary,
        super(apiClient: _unusedApiClient());

  DailySummary _dailySummary;
  int updateCalls = 0;
  int? updatedCalories;
  double? updatedHydrationGoalLiters;
  String? updateSource;

  @override
  Future<DailySummary> getDailySummary({String? date}) async {
    return _dailySummary;
  }

  @override
  Future<List<Meal>> getMealHistory() async => _dailySummary.meals;

  @override
  Future<DailyGoals> updateDailyGoals({
    String? date,
    int? calories,
    double? hydrationGoalLiters,
    String? calorieTargetSource,
    MacroDistributionConfig? macroConfig,
    int? macroCalorieTarget,
  }) async {
    updateCalls += 1;
    updatedCalories = calories;
    updatedHydrationGoalLiters = hydrationGoalLiters;
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
      macroMode: _dailySummary.macroMode,
      macroSource: _dailySummary.macroSource,
      macroPreset: _dailySummary.macroPreset,
      proteinPct: _dailySummary.proteinPct,
      carbsPct: _dailySummary.carbsPct,
      fatPct: _dailySummary.fatPct,
      macroCalories: _dailySummary.macroCalories,
      calorieDeltaKcal: _dailySummary.calorieDeltaKcal,
      meals: _dailySummary.meals,
    );
    return DailyGoals(
      date: _dailySummary.date,
      target: _dailySummary.target,
      hydrationGoalLiters: _dailySummary.hydrationGoalLiters,
      calorieTargetConfigured: _dailySummary.calorieTargetConfigured,
      calorieTargetSource: _dailySummary.calorieTargetSource,
      macroMode: _dailySummary.macroMode,
      macroSource: _dailySummary.macroSource,
      macroPreset: _dailySummary.macroPreset,
      proteinPct: _dailySummary.proteinPct,
      carbsPct: _dailySummary.carbsPct,
      fatPct: _dailySummary.fatPct,
      macroCalories: _dailySummary.macroCalories,
      calorieDeltaKcal: _dailySummary.calorieDeltaKcal,
    );
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
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
      : super(
            apiClient: _unusedApiClient(), tokenStorage: _MemoryTokenStorage());
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

const _testUser = AuthUser(
  id: 'user-1',
  email: 'test@example.com',
  displayName: 'Test User',
  trustedModeEnabled: false,
);

const _summary = DailySummary(
  date: '2026-05-10',
  consumed: NutritionSnapshot(
    calories: 0,
    proteinGrams: 0,
    carbsGrams: 0,
    fatGrams: 0,
  ),
  target: NutritionSnapshot(
    calories: 2200,
    proteinGrams: 160,
    carbsGrams: 240,
    fatGrams: 70,
  ),
  remaining: NutritionSnapshot(
    calories: 2200,
    proteinGrams: 160,
    carbsGrams: 240,
    fatGrams: 70,
  ),
  hydrationGoalLiters: 2.5,
  waterConsumedLiters: 0,
  calorieTargetConfigured: true,
  calorieTargetSource: 'manual',
  meals: [],
);

const _summaryWithoutConfiguredCalories = DailySummary(
  date: '2026-05-10',
  consumed: NutritionSnapshot(
    calories: 0,
    proteinGrams: 0,
    carbsGrams: 0,
    fatGrams: 0,
  ),
  target: NutritionSnapshot(
    calories: 2200,
    proteinGrams: 160,
    carbsGrams: 240,
    fatGrams: 70,
  ),
  remaining: NutritionSnapshot(
    calories: 2200,
    proteinGrams: 160,
    carbsGrams: 240,
    fatGrams: 70,
  ),
  hydrationGoalLiters: 0,
  waterConsumedLiters: 0,
  calorieTargetConfigured: false,
  calorieTargetSource: 'default',
  meals: [],
);

const _summaryWithoutConfiguredCaloriesWithDefaultMacro = DailySummary(
  date: '2026-05-10',
  consumed: NutritionSnapshot(
    calories: 0,
    proteinGrams: 0,
    carbsGrams: 0,
    fatGrams: 0,
  ),
  target: NutritionSnapshot(
    calories: 2200,
    proteinGrams: 160,
    carbsGrams: 240,
    fatGrams: 70,
  ),
  remaining: NutritionSnapshot(
    calories: 2200,
    proteinGrams: 160,
    carbsGrams: 240,
    fatGrams: 70,
  ),
  hydrationGoalLiters: 0,
  waterConsumedLiters: 0,
  calorieTargetConfigured: false,
  calorieTargetSource: 'default',
  macroMode: MacroMode.percentage,
  macroSource: MacroSource.preset,
  macroPreset: MacroPreset.balanced,
  proteinPct: 30,
  carbsPct: 40,
  fatPct: 30,
  macroCalories: 2200,
  calorieDeltaKcal: 0,
  meals: [],
);
