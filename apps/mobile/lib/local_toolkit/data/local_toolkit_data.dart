import 'local_fakes.dart';
import 'local_fixture_store.dart';

export 'local_fakes.dart';
export 'local_fixture_store.dart';

class LocalToolkitDependencies {
  const LocalToolkitDependencies({
    required this.store,
    required this.tokenStorage,
    required this.authRepository,
    required this.nutritionRepository,
    required this.preferencesRepository,
    required this.mobileUpdateService,
    required this.audioRecorderService,
  });

  final LocalFixtureStore store;
  final LocalTokenStorage tokenStorage;
  final LocalAuthRepository authRepository;
  final LocalNutritionRepository nutritionRepository;
  final LocalPreferencesRepository preferencesRepository;
  final LocalMobileUpdateService mobileUpdateService;
  final LocalAudioRecorderService audioRecorderService;
}

LocalFixtureStore createLocalFixtureStore({DateTime Function()? now}) {
  return LocalFixtureStore.seeded(now: now);
}

LocalToolkitDependencies createLocalToolkitDependencies({
  LocalFixtureStore? store,
}) {
  final fixtureStore = store ?? createLocalFixtureStore();
  final tokenStorage = LocalTokenStorage();
  return LocalToolkitDependencies(
    store: fixtureStore,
    tokenStorage: tokenStorage,
    authRepository: LocalAuthRepository(
      fixtureStore,
      tokenStorage: tokenStorage,
    ),
    nutritionRepository: LocalNutritionRepository(fixtureStore),
    preferencesRepository: LocalPreferencesRepository(),
    mobileUpdateService: LocalMobileUpdateService(),
    audioRecorderService: LocalAudioRecorderService(fixtureStore),
  );
}
