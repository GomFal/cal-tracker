import 'package:cal_tracker_mobile/app/locale_view_model.dart';
import 'package:cal_tracker_mobile/app/theme.dart';
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
  testWidgets('Menu language row changes from Language to Idioma',
      (tester) async {
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

    await tester.tap(find.byKey(const ValueKey('language_settings_row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language_option_es')));
    await tester.pumpAndSettle();

    expect(find.text('Idioma'), findsOneWidget);
    expect(preferencesRepository.savedLocaleCode, 'es');
  });

  testWidgets('Menu calorie target row opens shared calorie sheet and saves',
      (tester) async {
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
        find.byKey(const ValueKey('calorie_target_decrement')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('calorie_target_increment')), findsOneWidget);
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
  });

  testWidgets('Menu hides default calorie and macro previews before setup',
      (tester) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithoutConfiguredCaloriesWithDefaultMacro,
    );
    await _pumpSettings(tester, nutritionRepository: nutritionRepository);

    expect(find.text('Not set'), findsNWidgets(2));
    expect(find.text('2200 Kcal daily target'), findsNothing);
    expect(find.textContaining('Balanced:'), findsNothing);
  });

  testWidgets('Menu macro row requires calories before opening macros',
      (tester) async {
    final nutritionRepository = _FakeNutritionRepository(
      dailySummary: _summaryWithoutConfiguredCalories,
    );
    await _pumpSettings(tester, nutritionRepository: nutritionRepository);

    await tester.tap(find.byKey(const ValueKey('macro_distribution_row')));
    await tester.pumpAndSettle();

    expect(find.text('Set calories first'), findsOneWidget);
    expect(find.byKey(const ValueKey('macro_distribution_save_button')),
        findsNothing);

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
    await tester
        .tap(find.byKey(const ValueKey('macro_requires_calories_skip')));
    await tester.pumpAndSettle();

    expect(nutritionRepository.updateCalls, 0);
    expect(find.text('Set calories first'), findsNothing);
    expect(find.text('Menu'), findsOneWidget);
  });

  testWidgets('Menu macro row opens macro sheet after calories are configured',
      (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('macro_distribution_row')));
    await tester.pumpAndSettle();

    expect(find.text('Set your macros'), findsOneWidget);
    expect(find.byKey(const ValueKey('macro_distribution_save_button')),
        findsOneWidget);
    expect(find.text('Set calories first'), findsNothing);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  _FakeNutritionRepository? nutritionRepository,
  LocaleViewModel? localeViewModel,
}) async {
  final preferencesRepository = _FakePreferencesRepository();
  final effectiveLocaleViewModel = localeViewModel ??
      LocaleViewModel(
        preferencesRepository: preferencesRepository,
      );
  final effectiveNutritionRepository =
      nutritionRepository ?? _FakeNutritionRepository();
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
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
      home: const Scaffold(body: SettingsScreen()),
    );
  }
}

class _FakePreferencesRepository implements AppPreferencesRepository {
  String? savedLocaleCode;

  @override
  Future<String?> loadLocaleCode() async => savedLocaleCode;

  @override
  Future<void> saveLocaleCode(String code) async {
    savedLocaleCode = code;
  }

  @override
  Future<ThemeMode> loadThemeMode() async => ThemeMode.light;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {}

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
    int? hydrationGoalGlasses,
    String? calorieTargetSource,
    MacroDistributionConfig? macroConfig,
    int? macroCalorieTarget,
  }) async {
    updateCalls += 1;
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
      hydrationGoalGlasses:
          hydrationGoalGlasses ?? _dailySummary.hydrationGoalGlasses,
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
      hydrationGoalGlasses: _dailySummary.hydrationGoalGlasses,
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
          apiClient: _unusedApiClient(),
          tokenStorage: _MemoryTokenStorage(),
        );
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
  hydrationGoalGlasses: 12,
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
  hydrationGoalGlasses: 12,
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
  hydrationGoalGlasses: 12,
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
