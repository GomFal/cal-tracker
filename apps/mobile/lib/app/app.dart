import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/nutrition_repository.dart';
import '../data/services/app_preferences_repository.dart';
import '../data/services/app_preferences_storage.dart';
import '../data/services/agent_chat_cache_store.dart';
import '../data/services/agent_chat_session_store.dart';
import '../data/services/api_config.dart';
import '../data/services/audio_recorder_service.dart';
import '../data/services/client_metadata_provider.dart';
import '../data/services/client_telemetry_service.dart';
import '../data/services/mobile_update_service.dart';
import '../data/services/nutrition_cache_store.dart';
import '../data/services/private_cache_storage.dart';
import '../data/services/secure_token_storage.dart';
import '../generated/api/cal_tracker_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../ui/core/mobile_update_dialog_host.dart';
import '../ui/core/performance_overlay_strip.dart';
import '../ui/features/agent_chat/view_models/agent_chat_view_model.dart';
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
  late _CalTrackerComposition _composition;
  int _providerEpoch = 0;

  @override
  void initState() {
    super.initState();
    _composition = _CalTrackerComposition.create(widget);
  }

  @override
  void didUpdateWidget(covariant CalTrackerBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_compositionInputsChanged(oldWidget, widget)) {
      unawaited(_composition.dispose());
      _composition = _CalTrackerComposition.create(widget);
      _providerEpoch += 1;
    }
  }

  @override
  void dispose() {
    unawaited(_composition.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final composition = _composition;

    return MultiProvider(
      key: ValueKey<int>(_providerEpoch),
      providers: [
        Provider<ClientTelemetryService>.value(
          value: composition.telemetryService,
        ),
        Provider<ClientMetadataProvider>.value(
          value: composition.metadataProvider,
        ),
        Provider<AuthRepository>.value(value: composition.authRepository),
        Provider<NutritionRepository>.value(
          value: composition.nutritionRepository,
        ),
        Provider<AgentChatSessionStore>.value(
          value: composition.agentChatSessionStore,
        ),
        Provider<AgentChatCacheStore>.value(
          value: composition.agentChatCacheStore,
        ),
        Provider<AudioRecorderService>.value(
          value: composition.audioRecorderService,
        ),
        Provider<AppPreferencesRepository>.value(
          value: composition.preferencesRepository,
        ),
        ChangeNotifierProvider(
          create: (_) {
            final viewModel = MobileUpdateViewModel(
              updateService: composition.mobileUpdateService,
            );
            if (widget.checkForUpdates) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                viewModel.checkForUpdate();
              });
            }
            return viewModel;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeModeViewModel(
            preferencesRepository: composition.preferencesRepository,
          )..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocaleViewModel(
            preferencesRepository: composition.preferencesRepository,
          )..load(),
        ),
        ChangeNotifierProvider(create: (_) => PerformanceOverlayViewModel()),
        ChangeNotifierProvider(
          create: (_) =>
              AuthViewModel(authRepository: composition.authRepository)
                ..restoreSession(),
        ),
        ChangeNotifierProvider(
          create: (_) => VoiceLogViewModel(
            nutritionRepository: composition.nutritionRepository,
            audioRecorderService: composition.audioRecorderService,
            ownsAudioRecorderService: composition.ownsAudioRecorderService,
            telemetryService: composition.telemetryService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AgentChatViewModel(
            nutritionRepository: composition.nutritionRepository,
            audioRecorderService: composition.audioRecorderService,
            sessionStore: composition.agentChatSessionStore,
            cacheStore: composition.agentChatCacheStore,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => DashboardViewModel(
            nutritionRepository: composition.nutritionRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => MealHistoryViewModel(
            nutritionRepository: composition.nutritionRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => MealTemplatesViewModel(
            nutritionRepository: composition.nutritionRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel(
            authRepository: composition.authRepository,
            nutritionRepository: composition.nutritionRepository,
          ),
        ),
      ],
      child: _CalTrackerApp(appWrapperBuilder: widget.appWrapperBuilder),
    );
  }
}

bool _compositionInputsChanged(
  CalTrackerBootstrap oldWidget,
  CalTrackerBootstrap widget,
) {
  return oldWidget.apiConfig.baseUrl != widget.apiConfig.baseUrl ||
      oldWidget.preferencesRepository != widget.preferencesRepository ||
      oldWidget.authRepository != widget.authRepository ||
      oldWidget.nutritionRepository != widget.nutritionRepository ||
      oldWidget.tokenStorage != widget.tokenStorage ||
      oldWidget.mobileUpdateService != widget.mobileUpdateService ||
      oldWidget.audioRecorderService != widget.audioRecorderService ||
      oldWidget.clientTelemetryService != widget.clientTelemetryService ||
      oldWidget.clientMetadataProvider != widget.clientMetadataProvider;
}

class _CalTrackerComposition {
  _CalTrackerComposition({
    required this.preferencesRepository,
    required this.authRepository,
    required this.nutritionRepository,
    required bool ownsNutritionRepository,
    required this.agentChatSessionStore,
    required this.agentChatCacheStore,
    required this.mobileUpdateService,
    required bool ownsMobileUpdateService,
    required this.audioRecorderService,
    required this.ownsAudioRecorderService,
    required this.telemetryService,
    required this.metadataProvider,
    required bool ownsTelemetryService,
  })  : _ownsNutritionRepository = ownsNutritionRepository,
        _ownsMobileUpdateService = ownsMobileUpdateService,
        _ownsTelemetryService = ownsTelemetryService;

  factory _CalTrackerComposition.create(CalTrackerBootstrap widget) {
    final tokenStorage = widget.tokenStorage ?? const SecureTokenStorage();
    final preferencesRepository = widget.preferencesRepository ??
        AppPreferencesRepository(storage: AppPreferencesStorage());
    final metadataProvider =
        widget.clientMetadataProvider ?? ClientMetadataProvider();
    final ownsTelemetryService = widget.clientTelemetryService == null;
    final telemetryService = widget.clientTelemetryService ??
        ClientTelemetryService(
          apiConfig: widget.apiConfig,
          tokenStorage: tokenStorage,
          metadataProvider: metadataProvider,
        );
    if (ownsTelemetryService) {
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
    final privateCacheStorage = PrivateCacheStorage(
      legacyStorage: AppPreferencesStorage(),
    );
    final ownsNutritionRepository = widget.nutritionRepository == null;
    final nutritionRepository = widget.nutritionRepository ??
        NutritionRepository(
          apiClient: apiClient,
          cacheStore: NutritionCacheStore(storage: privateCacheStorage),
          telemetryService: telemetryService,
        );
    final agentChatSessionStore = AgentChatSessionStore(
      storage: privateCacheStorage,
    );
    final agentChatCacheStore = AgentChatCacheStore(
      storage: privateCacheStorage,
    );
    final ownsAudioRecorderService = widget.audioRecorderService == null;
    final ownsMobileUpdateService = widget.mobileUpdateService == null;

    return _CalTrackerComposition(
      preferencesRepository: preferencesRepository,
      authRepository: authRepository,
      nutritionRepository: nutritionRepository,
      ownsNutritionRepository: ownsNutritionRepository,
      agentChatSessionStore: agentChatSessionStore,
      agentChatCacheStore: agentChatCacheStore,
      mobileUpdateService: widget.mobileUpdateService ??
          MobileUpdateService(apiConfig: widget.apiConfig),
      ownsMobileUpdateService: ownsMobileUpdateService,
      audioRecorderService:
          widget.audioRecorderService ?? AudioRecorderService(),
      ownsAudioRecorderService: ownsAudioRecorderService,
      telemetryService: telemetryService,
      metadataProvider: metadataProvider,
      ownsTelemetryService: ownsTelemetryService,
    );
  }

  final AppPreferencesRepository preferencesRepository;
  final AuthRepository authRepository;
  final NutritionRepository nutritionRepository;
  final bool _ownsNutritionRepository;
  final AgentChatSessionStore agentChatSessionStore;
  final AgentChatCacheStore agentChatCacheStore;
  final MobileUpdateService mobileUpdateService;
  final bool _ownsMobileUpdateService;
  final AudioRecorderService audioRecorderService;
  final bool ownsAudioRecorderService;
  final ClientTelemetryService telemetryService;
  final ClientMetadataProvider metadataProvider;
  final bool _ownsTelemetryService;

  Future<void> dispose() async {
    if (_ownsMobileUpdateService) {
      mobileUpdateService.dispose();
    }
    if (_ownsNutritionRepository) {
      await nutritionRepository.dispose();
    }
    if (_ownsTelemetryService) {
      await telemetryService.dispose();
    }
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
  StreamSubscription<Uri>? _linkSubscription;
  bool _linkListenerStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authViewModel = context.read<AuthViewModel>();
    if (_authViewModel == authViewModel) return;
    _router?.dispose();
    _authViewModel = authViewModel;
    _router = buildRouter(authViewModel, navigatorKey: _navigatorKey);
    _startAuthLinkListener();
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeModeViewModel>().themeMode;
    final locale = context.watch<LocaleViewModel>().locale;
    return MaterialApp.router(
      scrollBehavior: const CalTrackerScrollBehavior(),
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
        final wrappedApp =
            widget.appWrapperBuilder?.call(context, preloadedApp, _router!) ??
                preloadedApp;
        return PerformanceOverlayHost(child: wrappedApp);
      },
    );
  }

  void _startAuthLinkListener() {
    if (_linkListenerStarted) return;
    _linkListenerStarted = true;
    try {
      final appLinks = AppLinks();
      unawaited(_handleInitialAuthLink(appLinks));
      _linkSubscription = appLinks.uriLinkStream.listen(
        (uri) => unawaited(_handleAuthLink(uri)),
        onError: (_) {},
      );
    } on Object {
      // Deep links are opportunistic during tests and unsupported platforms.
    }
  }

  Future<void> _handleInitialAuthLink(AppLinks appLinks) async {
    try {
      final uri = await appLinks.getInitialLink();
      if (uri != null) await _handleAuthLink(uri);
    } on Object {
      // Missing platform plugins in widget tests should not block startup.
    }
  }

  Future<void> _handleAuthLink(Uri uri) async {
    if (uri.path != '/auth/email/confirm') return;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;
    final authViewModel = _authViewModel;
    final router = _router;
    if (authViewModel == null || router == null) return;
    await authViewModel.confirmEmail(token);
    if (!mounted) return;
    router.go(authViewModel.hasSession ? '/dashboard' : '/auth');
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
      context.read<AgentChatSessionStore>().activateUser(userId);
      context.read<AgentChatCacheStore>().activateUser(userId);
      _schedulePreload();
      return;
    }

    if (authViewModel.isRestoring || _activeUserId == null) return;
    _activeUserId = null;
    context.read<DashboardViewModel>().reset();
    context.read<MealHistoryViewModel>().reset();
    context.read<MealTemplatesViewModel>().reset();
    context.read<SettingsViewModel>().reset();
    context.read<AgentChatViewModel>().reset();
    context.read<VoiceLogViewModel>().resetForLogout();

    final sessionStore = context.read<AgentChatSessionStore>();
    final chatCacheStore = context.read<AgentChatCacheStore>();
    final cacheCleanup = Future.wait([
      _ignoreLogoutCleanupError(repository.clearActiveUserCache()),
      _ignoreLogoutCleanupError(sessionStore.clearActiveUserData()),
      _ignoreLogoutCleanupError(chatCacheStore.clearActiveUserData()),
    ]);

    // Each store captures its active user key when cleanup starts. Deactivate
    // immediately afterwards so stale in-flight work cannot write more data
    // under the signed-out user while deletion completes in the background.
    repository.deactivateCache();
    sessionStore.deactivateUser();
    chatCacheStore.deactivateUser();
    unawaited(cacheCleanup);
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
    // Keep startup responsive on real dev/prod backends. The dashboard is the
    // first visible authenticated screen, so warm it first, then reuse its
    // cached daily summary for settings. Avoid preloading the full history week
    // here: that can fan out into seven summary requests and large JSON/cache
    // work on the UI isolate. History still loads cache-first when opened.
    await _ignorePreloadError(() => context.read<DashboardViewModel>().load());
    if (!mounted) return;
    await Future.wait([
      _ignorePreloadError(() => context.read<SettingsViewModel>().load()),
      _ignorePreloadError(() => context.read<MealTemplatesViewModel>().load()),
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

Future<void> _ignoreLogoutCleanupError(Future<void> operation) async {
  try {
    await operation;
  } on Object {
    // Independent cleanup failures must not restore or delay the signed-out UI.
  }
}
