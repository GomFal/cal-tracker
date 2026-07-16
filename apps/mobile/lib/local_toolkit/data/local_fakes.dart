import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../data/services/api_config.dart';
import '../../data/services/app_preferences_repository.dart';
import '../../data/services/audio_recorder_service.dart';
import '../../data/services/mobile_update_service.dart';
import '../../data/services/secure_token_storage.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/models/macro_distribution.dart';
import '../../domain/models/mobile_update_models.dart';
import '../../domain/models/nutrition_models.dart';
import '../../generated/api/cal_tracker_api.dart';
import 'local_fixture_store.dart';

class LocalTokenStorage implements TokenStorage {
  StoredTokens? _tokens;

  @override
  Future<StoredTokens?> read() async => _tokens;

  @override
  Future<void> write(StoredTokens tokens) async {
    _tokens = tokens;
  }

  @override
  Future<void> clear() async {
    _tokens = null;
  }
}
class LocalAuthRepository extends AuthRepository {
  factory LocalAuthRepository(
    LocalFixtureStore store, {
    LocalTokenStorage? tokenStorage,
  }) {
    final storage = tokenStorage ?? LocalTokenStorage();
    return LocalAuthRepository._(store, storage);
  }

  LocalAuthRepository._(this.store, this._tokenStorage)
      : super(
          apiClient: createLocalApiClient(tokenStorage: _tokenStorage),
          tokenStorage: _tokenStorage,
        );

  final LocalFixtureStore store;
  final LocalTokenStorage _tokenStorage;

  @override
  Future<AuthUser?> restoreSession() async {
    if (!store.sessionActive) return null;
    final tokens = await _tokenStorage.read();
    if (tokens == null) {
      await _tokenStorage.write(
        const StoredTokens(
          accessToken: 'local-access-token',
          refreshToken: 'local-refresh-token',
        ),
      );
    }
    return store.user;
  }

  @override
  Future<AuthSession> login({required String email, required String password}) {
    return _authenticate(email: email, displayName: store.user.displayName);
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    store.setSessionActive(false);
  }

  @override
  Future<AuthSession> confirmEmail(String token) {
    return _authenticate(
      email: store.user.email,
      displayName: store.user.displayName,
    );
  }

  @override
  Future<AuthSession?> loginWithGoogle() {
    return _authenticate(
      email: 'google-local@bettercalories.test',
      displayName: 'Google Local User',
    );
  }

  @override
  Future<void> logout() async {
    await _tokenStorage.clear();
    store.setSessionActive(false);
  }

  @override
  Future<AuthUser> updateTrustedMode(bool enabled) async {
    store.setTrustedMode(enabled);
    return store.user;
  }

  Future<AuthSession> _authenticate({
    required String email,
    required String displayName,
  }) async {
    final user = AuthUser(
      id: store.user.id,
      email: email,
      displayName: displayName,
      trustedModeEnabled: store.user.trustedModeEnabled,
    );
    final session = AuthSession(
      accessToken: 'local-access-token',
      refreshToken: 'local-refresh-token',
      user: user,
    );
    await _tokenStorage.write(
      StoredTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      ),
    );
    store.setUser(user);
    return session;
  }
}

class LocalNutritionRepository extends NutritionRepository {
  LocalNutritionRepository(this.store)
      : super(apiClient: createLocalApiClient());

  @override
  bool get isBackendLikelyHealthy => true;

  @override
  Future<bool> checkBackendHealth() async => true;

  final LocalFixtureStore store;

  @override
  Future<AgentRunResult> logText(
    String text, {
    String? activeProposalId,
  }) async {
    return store.scenarioForInput(text.trim()).resolve(store);
  }

  @override
  Future<VoiceMealRunResult> logAudio(
    File audioFile, {
    String? activeProposalId,
  }) async {
    final scenario = store.scenarioForInput(store.selectedScenarioKey);
    return VoiceMealRunResult(
      transcript: scenario.transcript,
      provider: 'local',
      model: 'local-fixture',
      traceId: 'local-trace',
      result: scenario.resolve(store),
    );
  }

  @override
  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 10,
    String? barcode,
  }) async {
    return FoodSearchResult(
      items: store.searchFoods(query: query, barcode: barcode, limit: limit),
      candidateGroups: store.candidateGroups,
    );
  }

  @override
  Future<Meal> commitProposal(String proposalId, {MealLabel? mealLabel}) async {
    return store.commitProposal(proposalId, mealLabel: mealLabel);
  }

  @override
  Future<Meal> correctMealItems(String mealId, List<MealItem> items) async {
    return store.correctMealItems(mealId, items);
  }

  @override
  Future<MealProposal> updateProposalItems(
    String proposalId,
    List<MealItem> items,
  ) async {
    return store.updateProposalItems(proposalId, items);
  }

  @override
  Future<MealProposal> createProposalFromItems({
    required String phrase,
    required List<MealItem> items,
    String? title,
  }) async {
    return store.createProposalFromItems(
      phrase: phrase,
      items: items,
      title: title,
    );
  }

  @override
  Future<bool> deleteMeal(String mealId, {bool confirmed = false}) async {
    return store.deleteMeal(mealId);
  }

  @override
  Future<DailySummary> getDailySummary({String? date}) async {
    return store.getDailySummary(date: date);
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
    if (macroConfig != null) {
      final targetCalories = macroCalorieTarget ??
          calories ??
          store.getDailySummary().target.calories;
      if (!isValidMacroConfig(macroConfig, calories: targetCalories)) {
        throw ArgumentError('Invalid macro configuration');
      }
    }
    return store.updateDailyGoals(
      date: date,
      calories: calories,
      hydrationGoalLiters: hydrationGoalLiters,
      calorieTargetSource: calorieTargetSource,
      macroConfig: macroConfig,
      macroCalorieTarget: macroCalorieTarget,
    );
  }

  @override
  Future<DailySummary> updateDailyHydration({
    String? date,
    required double waterConsumedLiters,
  }) async {
    return store.updateHydration(
      date: date,
      waterConsumedLiters: waterConsumedLiters,
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
    final target = localCalorieEstimate(
      age: age,
      sex: sex,
      heightCm: heightCm,
      weightKg: weightKg,
      activityLevel: activityLevel,
      goal: goal,
    );
    final maintenance = localCalorieEstimate(
      age: age,
      sex: sex,
      heightCm: heightCm,
      weightKg: weightKg,
      activityLevel: activityLevel,
      goal: 'maintain',
    );
    return CalorieEstimate(
      bmr: (maintenance / 1.45).round(),
      maintenanceCalories: maintenance,
      targetCalories: target,
      recommendedRangeMin: target - 150,
      recommendedRangeMax: target + 150,
      activityFactor: 1.45,
      adjustmentCalories: target - maintenance,
      warnings: const [],
      explanation: 'Local estimate for toolkit development.',
    );
  }

  @override
  Future<List<Meal>> getMealHistory() async {
    return store.getMealHistory();
  }

  @override
  Future<List<MealTemplate>> getTemplates() async {
    return store.templates;
  }

  @override
  Future<List<UsualFood>> getUsualFoods() async {
    return store.usualFoods;
  }

  @override
  Future<MealTemplate> setTemplateTrustedMode(
    MealTemplate template,
    bool enabled,
  ) async {
    return store.setTemplateTrustedMode(template, enabled);
  }

  @override
  Future<MealTemplate> createTemplate({
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
    bool trustedAutoCommitEnabled = false,
  }) async {
    return store.createTemplate(
      title: title,
      items: items,
      aliases: aliases,
      trustedAutoCommitEnabled: trustedAutoCommitEnabled,
    );
  }

  @override
  Future<MealTemplate> updateTemplate({
    required String templateId,
    required String title,
    required List<MealItem> items,
    required List<String> aliases,
    bool trustedAutoCommitEnabled = false,
  }) async {
    return store.updateTemplate(
      templateId: templateId,
      title: title,
      items: items,
      aliases: aliases,
      trustedAutoCommitEnabled: trustedAutoCommitEnabled,
    );
  }

  @override
  Future<UsualMealDraft> draftUsualMeal(String text) async {
    return store.draftUsualMeal(text);
  }

  @override
  Future<UsualFood> createUsualFood(UsualFoodInput input) async {
    return store.createUsualFood(input);
  }

  @override
  Future<UsualFood> updateUsualFood(String foodId, UsualFoodInput input) async {
    return store.updateUsualFood(foodId, input);
  }

  @override
  Future<bool> deleteTemplate(String templateId) async {
    return store.deleteTemplate(templateId);
  }

  @override
  Future<bool> deleteUsualFood(String foodId) async {
    return store.deleteUsualFood(foodId);
  }

  @override
  Future<UsualFoodDraft> draftUsualFood(String text) async {
    final lines = text.split(RegExp(r'[\r\n]+'));
    final name = lines.isNotEmpty && lines.first.trim().isNotEmpty
        ? lines.first.trim()
        : 'Scanned local food';
    final servingMatch = RegExp(r'(\d+)\s*(g|gr|gram|grams)').firstMatch(text);
    final caloriesMatch = RegExp(r'(\d+)\s*kcal').firstMatch(text);
    final proteinMatch = RegExp(r'protein[^\d]*(\d+)\s*g').firstMatch(text);
    final carbsMatch = RegExp(r'carbs?[^\d]*(\d+)\s*g').firstMatch(text);
    final fatMatch = RegExp(r'fat[^\d]*(\d+)\s*g').firstMatch(text);

    final servingGrams =
        servingMatch != null ? double.parse(servingMatch.group(1)!) : 100.0;
    final calories =
        caloriesMatch != null ? int.parse(caloriesMatch.group(1)!) : 150;
    final proteinGrams =
        proteinMatch != null ? double.parse(proteinMatch.group(1)!) : 0.0;
    final carbsGrams =
        carbsMatch != null ? double.parse(carbsMatch.group(1)!) : 0.0;
    final fatGrams = fatMatch != null ? double.parse(fatMatch.group(1)!) : 0.0;

    final missing = <String>[
      if (servingMatch == null) 'servingGrams',
      if (caloriesMatch == null) 'calories',
      if (proteinMatch == null) 'proteinGrams',
      if (carbsMatch == null) 'carbsGrams',
      if (fatMatch == null) 'fatGrams',
    ];

    return UsualFoodDraft(
      name: name,
      servingGrams: servingGrams,
      calories: calories,
      proteinGrams: proteinGrams,
      carbsGrams: carbsGrams,
      fatGrams: fatGrams,
      missingRequiredFields: missing,
    );
  }

  @override
  Future<String> transcribeAudio(File audioFile) async {
    return store.scenarioForInput(store.selectedScenarioKey).transcript;
  }
}

class LocalPreferencesRepository implements AppPreferencesRepository {
  LocalPreferencesRepository({
    ThemeMode initialThemeMode = ThemeMode.dark,
    String? initialLocaleCode,
  })  : _themeMode = initialThemeMode,
        _localeCode = initialLocaleCode;

  ThemeMode _themeMode;
  String? _localeCode;
  int _authHeroIndex = -1;

  @override
  Future<ThemeMode> loadThemeMode() async => _themeMode;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {
    _themeMode = mode;
  }

  @override
  Future<String?> loadLocaleCode() async => _localeCode;

  @override
  Future<void> saveLocaleCode(String code) async {
    _localeCode = code;
  }

  @override
  Future<int> nextAuthHeroIndex({int count = 5}) async {
    _authHeroIndex = (_authHeroIndex + 1) % count;
    return _authHeroIndex;
  }
}

class LocalMobileUpdateService extends MobileUpdateService {
  LocalMobileUpdateService()
      : super(apiConfig: const ApiConfig(baseUrl: 'http://localhost'));

  @override
  Future<MobileUpdateCheck> checkForUpdate() async {
    return const MobileUpdateCheck(
      installedVersionName: 'local',
      installedVersionCode: 1,
      manifest: MobileUpdateManifest(
        channel: 'local',
        packageName: 'app.bettercalories.dev.local',
        versionName: 'local',
        versionCode: 1,
        apkUrl: 'http://localhost/local.apk',
        publishedAt: '1970-01-01T00:00:00.000Z',
      ),
    );
  }

  @override
  Future<void> openDownload(MobileUpdateManifest manifest) async {}
}

class LocalAudioRecorderService extends AudioRecorderService {
  LocalAudioRecorderService(this.store)
      : super(recorder: _NoopAudioRecorder(), minimumBytes: 0);

  final LocalFixtureStore store;
  final StreamController<RecorderState> _stateController =
      StreamController<RecorderState>.broadcast();
  String? _currentPath;

  @override
  Stream<RecorderState> get stateStream => _stateController.stream;

  @override
  String? get currentPath => _currentPath;

  @override
  Future<bool> hasPermission() async => store.audioPermissionGranted;

  @override
  Future<void> start() async {
    if (!await hasPermission()) {
      throw const RecorderException(
        'permission_denied',
        AudioRecorderService.microphonePermissionDeniedMessage,
      );
    }
    _currentPath =
        '${Directory.systemTemp.path}/bettercalories_local_audio.wav';
    _stateController.add(RecorderState.recording);
  }

  @override
  Future<RecordedAudio?> stop() async {
    final path = _currentPath;
    _currentPath = null;
    _stateController.add(RecorderState.stopping);
    if (path == null) return null;
    return RecordedAudio(path: path, mimeType: 'audio/wav', sizeBytes: 1024);
  }

  @override
  Future<void> cancel() async {
    _currentPath = null;
    _stateController.add(RecorderState.idle);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }
}

class _NoopAudioRecorder implements AudioRecorder {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CalTrackerApiClient createLocalApiClient({TokenStorage? tokenStorage}) {
  return CalTrackerApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    tokenStorage: tokenStorage ?? LocalTokenStorage(),
  );
}
