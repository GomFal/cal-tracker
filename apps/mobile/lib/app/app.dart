import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/nutrition_repository.dart';
import '../data/services/app_preferences_repository.dart';
import '../data/services/app_preferences_storage.dart';
import '../data/services/api_config.dart';
import '../data/services/audio_recorder_service.dart';
import '../data/services/mobile_update_service.dart';
import '../data/services/nutrition_cache_store.dart';
import '../data/services/secure_token_storage.dart';
import '../generated/api/cal_tracker_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../ui/core/mobile_update_dialog_host.dart';
import '../ui/features/auth/view_models/auth_view_model.dart';
import '../ui/features/dashboard/view_models/dashboard_view_model.dart';
import '../ui/features/meal_history/view_models/meal_history_view_model.dart';
import '../ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import '../ui/features/settings/view_models/settings_view_model.dart';
import '../ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'locale_view_model.dart';
import 'mobile_update_view_model.dart';
import 'router.dart';
import 'theme.dart';
import 'theme_mode_view_model.dart';

typedef CalTrackerAppWrapperBuilder =
    Widget Function(BuildContext context, Widget child, GoRouter router);

class CalTrackerBootstrap extends StatelessWidget {
  const CalTrackerBootstrap({
    super.key,
    this.apiConfig = const ApiConfig.fromEnvironment(),
    this.preferencesRepository,
    this.authRepository,
    this.nutritionRepository,
    this.tokenStorage,
    this.mobileUpdateService,
    this.audioRecorderService,
    this.checkForUpdates = true,
    this.appWrapperBuilder,
  });

  final ApiConfig apiConfig;
  final AppPreferencesRepository? preferencesRepository;
  final AuthRepository? authRepository;
  final NutritionRepository? nutritionRepository;
  final TokenStorage? tokenStorage;
  final MobileUpdateService? mobileUpdateService;
  final AudioRecorderService? audioRecorderService;
  final bool checkForUpdates;
  final CalTrackerAppWrapperBuilder? appWrapperBuilder;

  @override
  Widget build(BuildContext context) {
    final tokenStorage = this.tokenStorage ?? const SecureTokenStorage();
    final preferencesRepository =
        this.preferencesRepository ??
        AppPreferencesRepository(storage: AppPreferencesStorage());
    final apiClient = CalTrackerApiClient(
      config: apiConfig,
      tokenStorage: tokenStorage,
      localeTagProvider: () async {
        final savedTag = await preferencesRepository.loadLocaleCode();
        return LocaleViewModel.normalizeLocaleTag(savedTag).toLanguageTag();
      },
    );
    final authRepository =
        this.authRepository ??
        AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);
    final nutritionRepository =
        this.nutritionRepository ??
        NutritionRepository(
          apiClient: apiClient,
          cacheStore: NutritionCacheStore(storage: AppPreferencesStorage()),
        );
    final mobileUpdateService =
        this.mobileUpdateService ?? MobileUpdateService(apiConfig: apiConfig);
    final audioRecorderService =
        this.audioRecorderService ?? AudioRecorderService();

    return MultiProvider(
      providers: [
        Provider<AuthRepository>.value(value: authRepository),
        Provider<NutritionRepository>.value(value: nutritionRepository),
        Provider<AudioRecorderService>.value(value: audioRecorderService),
        Provider<AppPreferencesRepository>.value(value: preferencesRepository),
        ChangeNotifierProvider(
          create: (_) {
            final viewModel = MobileUpdateViewModel(
              updateService: mobileUpdateService,
            );
            if (checkForUpdates) {
              viewModel.checkForUpdate();
            }
            return viewModel;
          },
        ),
        ChangeNotifierProvider(
          create: (_) =>
              ThemeModeViewModel(preferencesRepository: preferencesRepository)
                ..load(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              LocaleViewModel(preferencesRepository: preferencesRepository)
                ..load(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AuthViewModel(authRepository: authRepository)..restoreSession(),
        ),
        ChangeNotifierProvider(
          create: (_) => VoiceLogViewModel(
            nutritionRepository: nutritionRepository,
            audioRecorderService: audioRecorderService,
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
          create: (_) =>
              MealTemplatesViewModel(nutritionRepository: nutritionRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel(
            authRepository: authRepository,
            nutritionRepository: nutritionRepository,
          ),
        ),
      ],
      child: _CalTrackerApp(appWrapperBuilder: appWrapperBuilder),
    );
  }
}

class _CalTrackerApp extends StatefulWidget {
  const _CalTrackerApp({this.appWrapperBuilder});

  final CalTrackerAppWrapperBuilder? appWrapperBuilder;

  @override
  State<_CalTrackerApp> createState() => _CalTrackerAppState();
}

class _CalTrackerAppState extends State<_CalTrackerApp> {
  AuthViewModel? _authViewModel;
  GoRouter? _router;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authViewModel = context.read<AuthViewModel>();
    if (_authViewModel == authViewModel) return;
    _router?.dispose();
    _authViewModel = authViewModel;
    _router = buildRouter(authViewModel, navigatorKey: _navigatorKey);
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeModeViewModel>().themeMode;
    final locale = context.watch<LocaleViewModel>().locale;
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: _router!,
      builder: (context, child) {
        final app = MobileUpdateDialogHost(
          navigatorKey: _navigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
        final preloadedApp = _AuthenticatedDataPreloader(child: app);
        return widget.appWrapperBuilder?.call(
              context,
              preloadedApp,
              _router!,
            ) ??
            preloadedApp;
      },
    );
  }
}

class _AuthenticatedDataPreloader extends StatefulWidget {
  const _AuthenticatedDataPreloader({required this.child});

  final Widget child;

  @override
  State<_AuthenticatedDataPreloader> createState() =>
      _AuthenticatedDataPreloaderState();
}

class _AuthenticatedDataPreloaderState
    extends State<_AuthenticatedDataPreloader> {
  AuthViewModel? _authViewModel;
  String? _activeUserId;
  bool _preloadScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authViewModel = context.read<AuthViewModel>();
    if (_authViewModel == authViewModel) return;
    _authViewModel?.removeListener(_handleAuthChanged);
    _authViewModel = authViewModel;
    _authViewModel?.addListener(_handleAuthChanged);
    _handleAuthChanged();
  }

  @override
  void dispose() {
    _authViewModel?.removeListener(_handleAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _handleAuthChanged() {
    final authViewModel = _authViewModel;
    if (authViewModel == null || !mounted) return;
    final repository = context.read<NutritionRepository>();
    if (authViewModel.hasSession) {
      final userId = authViewModel.user!.id;
      if (_activeUserId == userId) return;
      _activeUserId = userId;
      repository.activateCacheForUser(userId);
      _schedulePreload();
      return;
    }

    if (authViewModel.isRestoring || _activeUserId == null) return;
    _activeUserId = null;
    context.read<DashboardViewModel>().reset();
    context.read<MealHistoryViewModel>().reset();
    context.read<MealTemplatesViewModel>().reset();
    context.read<SettingsViewModel>().reset();
    unawaited(repository.clearActiveUserCache());
  }

  void _schedulePreload() {
    if (_preloadScheduled) return;
    _preloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _preloadScheduled = false;
      unawaited(_preloadAuthenticatedData());
    });
  }

  Future<void> _preloadAuthenticatedData() async {
    await Future.wait([
      _ignorePreloadError(() => context.read<DashboardViewModel>().load()),
      _ignorePreloadError(() => context.read<MealHistoryViewModel>().load()),
      _ignorePreloadError(() => context.read<MealTemplatesViewModel>().load()),
      _ignorePreloadError(() => context.read<SettingsViewModel>().load()),
      _ignorePreloadError(() async {
        await context.read<NutritionRepository>().checkBackendHealth();
      }),
    ]);
  }

  Future<void> _ignorePreloadError(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      // Preloading is opportunistic; screens still handle their own load state.
    }
  }
}
