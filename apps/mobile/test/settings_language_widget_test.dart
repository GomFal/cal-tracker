import 'package:cal_tracker_mobile/app/locale_view_model.dart';
import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_repository.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/domain/models/auth_models.dart';
import 'package:cal_tracker_mobile/domain/models/nutrition_models.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/features/auth/view_models/auth_view_model.dart';
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
    final authViewModel = AuthViewModel(authRepository: _FakeAuthRepository())
      ..setUser(_testUser);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authViewModel),
          ChangeNotifierProvider<LocaleViewModel>.value(
            value: localeViewModel,
          ),
          ChangeNotifierProvider(
            create: (_) => SettingsViewModel(
              authRepository: _FakeAuthRepository(),
              nutritionRepository: nutritionRepository,
            ),
          ),
        ],
        child: const _SettingsTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Data sources'), findsOneWidget);
    expect(find.textContaining('Open Food Facts'), findsOneWidget);
    expect(find.textContaining('USDA FoodData Central'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('language_settings_row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language_option_es')));
    await tester.pumpAndSettle();

    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Fuentes de datos'), findsOneWidget);
    expect(preferencesRepository.savedLocaleCode, 'es');
  });
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
  _FakeNutritionRepository() : super(apiClient: _unusedApiClient());

  @override
  Future<DailySummary> getDailySummary({String? date}) async {
    return _summary;
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
