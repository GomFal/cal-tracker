import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/auth_repository.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/app_preferences_repository.dart';
import 'package:cal_tracker_mobile/data/services/client_metadata_provider.dart';
import 'package:cal_tracker_mobile/data/services/client_telemetry_service.dart';
import 'package:cal_tracker_mobile/data/services/secure_token_storage.dart';
import 'package:cal_tracker_mobile/generated/api/cal_tracker_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('CalTrackerBootstrap keeps composition root stable on rebuild', (
    tester,
  ) async {
    final tokenStorage = _MemoryTokenStorage();
    final preferencesRepository = _FakePreferencesRepository();
    final nutritionRepository = _FakeNutritionRepository();
    final telemetryServices = <ClientTelemetryService>[];
    final metadataProviders = <ClientMetadataProvider>[];
    final authRepositories = <AuthRepository>[];
    final nutritionRepositories = <NutritionRepository>[];
    late StateSetter rebuild;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return CalTrackerBootstrap(
            apiConfig: const ApiConfig(baseUrl: 'http://localhost'),
            tokenStorage: tokenStorage,
            preferencesRepository: preferencesRepository,
            nutritionRepository: nutritionRepository,
            checkForUpdates: false,
            appWrapperBuilder: (context, child, router) {
              telemetryServices.add(context.read<ClientTelemetryService>());
              metadataProviders.add(context.read<ClientMetadataProvider>());
              authRepositories.add(context.read<AuthRepository>());
              nutritionRepositories.add(context.read<NutritionRepository>());
              return child;
            },
          );
        },
      ),
    );
    await tester.pump();

    rebuild(() {});
    await tester.pump();

    expect(telemetryServices, hasLength(greaterThanOrEqualTo(2)));
    expect(identical(telemetryServices.first, telemetryServices.last), isTrue);
    expect(identical(metadataProviders.first, metadataProviders.last), isTrue);
    expect(identical(authRepositories.first, authRepositories.last), isTrue);
    expect(
      identical(nutritionRepositories.first, nutritionRepositories.last),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
  });

  testWidgets('CalTrackerBootstrap clamps scroll boundaries globally', (
    tester,
  ) async {
    await tester.pumpWidget(
      CalTrackerBootstrap(
        apiConfig: const ApiConfig(baseUrl: 'http://localhost'),
        tokenStorage: _MemoryTokenStorage(),
        preferencesRepository: _FakePreferencesRepository(),
        nutritionRepository: _FakeNutritionRepository(),
        checkForUpdates: false,
      ),
    );
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final behavior = materialApp.scrollBehavior;

    expect(behavior, isA<CalTrackerScrollBehavior>());
    expect(
      behavior!.getScrollPhysics(tester.element(find.byType(MaterialApp))),
      isA<ClampingScrollPhysics>(),
    );

    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
  });
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
  @override
  Future<ThemeMode> loadThemeMode() async => ThemeMode.system;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async {}

  @override
  Future<String?> loadLocaleCode() async => null;

  @override
  Future<void> saveLocaleCode(String code) async {}

  @override
  Future<int> nextAuthHeroIndex({int count = 5}) async => 0;
}

class _FakeNutritionRepository extends NutritionRepository {
  _FakeNutritionRepository()
      : super(
          apiClient: CalTrackerApiClient(
            config: const ApiConfig(baseUrl: 'http://localhost'),
            tokenStorage: _MemoryTokenStorage(),
          ),
        );
}
