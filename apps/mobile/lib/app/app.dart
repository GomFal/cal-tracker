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

typedef CalTrackerAppWrapperBuilder = Widget Function(
  BuildContext context,
  Widget child,
  GoRouter router,
);

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
    final apiClient = CalTrackerApiClient(
      config: apiConfig,
      tokenStorage: tokenStorage,
    );
    final authRepository = this.authRepository ??
        AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);
    final nutritionRepository =
        this.nutritionRepository ?? NutritionRepository(apiClient: apiClient);
    final preferencesRepository = this.preferencesRepository ??
        AppPreferencesRepository(
          storage: AppPreferencesStorage(),
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
        Provider<AppPreferencesRepository>.value(
          value: preferencesRepository,
        ),
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
          create: (_) => ThemeModeViewModel(
            preferencesRepository: preferencesRepository,
          )..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocaleViewModel(
            preferencesRepository: preferencesRepository,
          )..load(),
        ),
        ChangeNotifierProvider(
            create: (_) => AuthViewModel(authRepository: authRepository)
              ..restoreSession()),
        ChangeNotifierProvider(
            create: (_) => VoiceLogViewModel(
                  nutritionRepository: nutritionRepository,
                  audioRecorderService: audioRecorderService,
                )),
        ChangeNotifierProvider(
            create: (_) =>
                DashboardViewModel(nutritionRepository: nutritionRepository)),
        ChangeNotifierProvider(
            create: (_) =>
                MealHistoryViewModel(nutritionRepository: nutritionRepository)),
        ChangeNotifierProvider(
            create: (_) => MealTemplatesViewModel(
                nutritionRepository: nutritionRepository)),
        ChangeNotifierProvider(
            create: (_) => SettingsViewModel(
                  authRepository: authRepository,
                  nutritionRepository: nutritionRepository,
                )),
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
      supportedLocales: LocaleViewModel.supportedLocales,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: _router!,
      builder: (context, child) {
        final app = MobileUpdateDialogHost(
          navigatorKey: _navigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
        return widget.appWrapperBuilder?.call(context, app, _router!) ?? app;
      },
    );
  }
}
