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
import '../data/services/client_metadata_provider.dart';
import '../data/services/client_telemetry_service.dart';
import '../data/services/mobile_update_service.dart';
import '../data/services/nutrition_cache_store.dart';
import '../data/services/secure_token_storage.dart';
import '../generated/api/cal_tracker_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../ui/core/mobile_update_dialog_host.dart';
import '../ui/core/performance_overlay_strip.dart';
import '../ui/features/auth/view_models/auth_view_model.dart';
import '../ui/features/dashboard/view_models/dashboard_view_model.dart';
import '../ui/features/meal_history/view_models/meal_history_view_model.dart';
import '../ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import '../ui/features/settings/view_models/settings_view_model.dart';
import '../ui/features/voice_log/view_models/voice_log_view_model.dart';
import 'locale_view_model.dart';
import 'mobile_update_view_model.dart';
import 'performance_overlay_view_model.dart';
import 'router.dart';
import 'theme.dart';
import 'theme_mode_view_model.dart';

typedef CalTrackerAppWrapperBuilder = Widget Function(
    BuildContext context, Widget child, GoRouter router);

class CalTrackerBootstrap extends StatefulWidget {
  const CalTrackerBootstrap({
    super.key,
    this.apiConfig = const ApiConfig.fromEnvironment(),
    this.preferencesRepository,
    this.authRepository,
    this.nutritionRepository,
    this.tokenStorage,
    this.mobileUpdateService,
    this.audioRecorderService,
    this.clientTelemetryService,
    this.clientMetadataProvider,
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
  final ClientTelemetryService? clientTelemetryService;
  final ClientMetadataProvider? clientMetadataProvider;
  final bool checkForUpdates;
  final CalTrackerAppWrapperBuilder? appWrapperBuilder;

  @override
  State<CalTrackerBootstrap> createState() => _CalTrackerBootstrapState();
}

class _CalTrackerBootstrapState extends State<CalTrackerBootstrap> {
  ClientTelemetryService? _ownedTelemetryService;

  @override
  void dispose() {
    // If we created the telemetry service we own its lifecycle and must
    // cancel its periodic flush timer. External services (e.g. tests that
    // inject their own instance) are left to the caller.
    _ownedTelemetryService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokenStorage = widget.tokenStorage ?? const SecureTokenStorage();
    final preferencesRepository = widget.preferencesRepository ??
        AppPreferencesRepository(storage: AppPreferencesStorage());
    final metadataProvider =
        widget.clientMetadataProvider ?? ClientMetadataProvider();
    final telemetryService = widget.clientTelemetryService ??
        (_ownedTelemetryService = ClientTelemetryService(
          apiConfig: widget.apiConfig,
          tokenStorage: tokenStorage,
          metadataProvider: metadataProvider,
        ));
    // Only start the periodic flush when this widget owns the service so
    // tests that inject their own ClientTelemetryService stay in control of
    // its lifecycle.
    if (widget.clientTelemetryService == null) {
      telemetryService.start();
    }
    final apiClient = CalTrackerApiClient(
      config: widget.apiConfig,
      tokenStorage: tokenStorage,
      localeTagProvider: () async {
        final savedTag = await preferencesRepository.loadLocaleCode();
        return LocaleViewModel.normalizeLocaleTag(savedTag).toLanguageTag();
      },
      metadataProvider: metadataProvider,
      telemetryService: telemetryService,
    );
    final authRepository = widget.authRepository ??
        AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);
    final nutritionRepository = widget.nutritionRepository ??
        NutritionRepository(
          apiClient: apiClient,
          cacheStore: NutritionCacheStore(storage: AppPreferencesStorage()),
          telemetryService: telemetryService,
        );
    final mobileUpdateService = widget.mobileUpdateService ??
        MobileUpdateService(apiConfig: widget.apiConfig);
    final audioRecorderService =
        widget.audioRecorderService ?? AudioRecorderService();

    return MultiProvider(
      providers: [
        Provider<ClientTelemetryService>.value(value: telemetryService),
        Provider<ClientMetadataProvider>.value(value: metadataProvider),
        Provider<AuthRepository>.value(value: authRepository),
        Provider<NutritionRepository>.value(value: nutritionRepository),
        Provider<AudioRecorderService>.value(value: audioRecorderService),
        Provider<AppPreferencesRepository>.value(value: preferencesRepository),
        ChangeNotifierProvider(
          create: (_) {
            final viewModel = MobileUpdateViewModel(
              updateService: mobileUpdateService,
            );
            if (widget.checkForUpdates) {
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
          create: (_) => PerformanceOverlayViewModel(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              AuthViewModel(authRepository: authRepository)..restoreSession(),
        ),
        ChangeNotifierProvider(
          create: (_) => VoiceLogViewModel(
            nutritionRepository: nutritionRepository,
            audioRecorderService: audioRecorderService,
            telemetryService: telemetryService,
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
      child: _CalTrackerApp(appWrapperBuilder: widget.appWrapperBuilder),
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
        final wrappedApp = widget.appWrapperBuilder?.call(
              context,
              preloadedApp,
              _router!,
            ) ??
            preloadedApp;
        return PerformanceOverlayHost(child: wrappedApp);
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
