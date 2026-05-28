import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/locale_view_model.dart';
import 'app/theme_mode_view_model.dart';
import 'l10n/generated/app_localizations.dart';
import 'local_toolkit/data/local_toolkit_data.dart';
import 'local_toolkit/ui/local_toolkit_overlay.dart';
import 'ui/features/auth/view_models/auth_view_model.dart';
import 'ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'ui/features/meal_history/view_models/meal_history_view_model.dart';
import 'ui/features/meal_templates/view_models/meal_templates_view_model.dart';
import 'ui/features/settings/view_models/settings_view_model.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  final dependencies = createLocalToolkitDependencies();
  runApp(_LocalToolkitApp(dependencies: dependencies));
}

class _LocalToolkitApp extends StatelessWidget {
  const _LocalToolkitApp({required this.dependencies});

  final LocalToolkitDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return CalTrackerBootstrap(
      tokenStorage: dependencies.tokenStorage,
      authRepository: dependencies.authRepository,
      nutritionRepository: dependencies.nutritionRepository,
      preferencesRepository: dependencies.preferencesRepository,
      mobileUpdateService: dependencies.mobileUpdateService,
      audioRecorderService: dependencies.audioRecorderService,
      checkForUpdates: false,
      appWrapperBuilder: (context, child, router) {
        return _LocalToolkitHost(
          dependencies: dependencies,
          router: router,
          child: child,
        );
      },
    );
  }
}

class _LocalToolkitHost extends StatefulWidget {
  const _LocalToolkitHost({
    required this.dependencies,
    required this.router,
    required this.child,
  });

  final LocalToolkitDependencies dependencies;
  final GoRouter router;
  final Widget child;

  @override
  State<_LocalToolkitHost> createState() => _LocalToolkitHostState();
}

class _LocalToolkitHostState extends State<_LocalToolkitHost> {
  LocalToolkitScenario _activeScenario = LocalToolkitScenario.normalDay;

  LocalFixtureStore get _store => widget.dependencies.store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, child) {
        final l10n = AppLocalizations.of(context);
        final localeCode = context.watch<LocaleViewModel>().localeCode;
        final themeMode = context.watch<ThemeModeViewModel>().themeMode;
        return LocalToolkitOverlay(
          labels: _labels(l10n),
          activeScenario: _activeScenario,
          trustedModeEnabled: _store.user.trustedModeEnabled,
          currentLocaleLabel: localeCode.toUpperCase(),
          currentThemeLabel: themeMode == ThemeMode.dark ? 'Dark' : 'Light',
          onRouteJump: _handleRouteJump,
          onScenarioSelected: _handleScenarioSelected,
          onResetScenario: _resetScenario,
          onAddSampleMeal: _addSampleMeal,
          onClearMeals: _clearMeals,
          onToggleTrustedMode: _toggleTrustedMode,
          onSwitchLocale: _switchLocale,
          onSwitchTheme: _switchTheme,
          child: child ?? widget.child,
        );
      },
      child: widget.child,
    );
  }

  LocalToolkitOverlayLabels _labels(AppLocalizations l10n) {
    return LocalToolkitOverlayLabels(
      toolButtonTooltip: l10n.localToolkitToolButtonTooltip,
      panelTitle: l10n.localToolkitPanelTitle,
      panelSubtitle: l10n.localToolkitPanelSubtitle,
      routeSectionTitle: l10n.localToolkitRouteSectionTitle,
      scenarioSectionTitle: l10n.localToolkitScenarioSectionTitle,
      quickMutatorsSectionTitle: l10n.localToolkitQuickMutatorsSectionTitle,
      routeAuth: l10n.localToolkitRouteAuth,
      routeDashboard: l10n.localToolkitRouteDashboard,
      routeLogMeal: l10n.localToolkitRouteLogMeal,
      routeHistory: l10n.localToolkitRouteHistory,
      routeTemplates: l10n.localToolkitRouteTemplates,
      routeSettings: l10n.localToolkitRouteSettings,
      scenarioUnauthenticated: l10n.localToolkitScenarioUnauthenticated,
      scenarioEmptyDay: l10n.localToolkitScenarioEmptyDay,
      scenarioNormalDay: l10n.localToolkitScenarioNormalDay,
      scenarioOverTarget: l10n.localToolkitScenarioOverTarget,
      scenarioGoalsNotConfigured: l10n.localToolkitScenarioGoalsNotConfigured,
      scenarioProposalReady: l10n.localToolkitScenarioProposalReady,
      scenarioClarificationRequired:
          l10n.localToolkitScenarioClarificationRequired,
      scenarioAutoCommittedMeal: l10n.localToolkitScenarioAutoCommittedMeal,
      scenarioTemplateHeavyAccount:
          l10n.localToolkitScenarioTemplateHeavyAccount,
      quickResetScenario: l10n.localToolkitQuickResetScenario,
      quickAddSampleMeal: l10n.localToolkitQuickAddSampleMeal,
      quickClearMeals: l10n.localToolkitQuickClearMeals,
      quickToggleTrustedMode: l10n.localToolkitQuickToggleTrustedMode,
      quickSwitchLocale: l10n.localToolkitQuickSwitchLocale,
      quickSwitchTheme: l10n.localToolkitQuickSwitchTheme,
      trustedModeOn: l10n.localToolkitTrustedModeOn,
      trustedModeOff: l10n.localToolkitTrustedModeOff,
      closeTooltip: l10n.localToolkitCloseTooltip,
    );
  }

  void _handleRouteJump(LocalToolkitRoute route) {
    if (route == LocalToolkitRoute.auth) {
      _store.setSessionActive(false);
      unawaited(context.read<AuthViewModel>().logout());
      widget.router.go('/auth');
      return;
    }
    _ensureAuthenticated();
    widget.router.go(switch (route) {
      LocalToolkitRoute.auth => '/auth',
      LocalToolkitRoute.dashboard => '/dashboard',
      LocalToolkitRoute.logMeal => '/meal/create',
      LocalToolkitRoute.history => '/history',
      LocalToolkitRoute.templates => '/templates',
      LocalToolkitRoute.settings => '/settings',
    });
    _refreshVisibleData();
  }

  void _handleScenarioSelected(LocalToolkitScenario scenario) {
    setState(() => _activeScenario = scenario);
    switch (scenario) {
      case LocalToolkitScenario.unauthenticated:
        _store.setSessionActive(false);
        unawaited(context.read<AuthViewModel>().logout());
        widget.router.go('/auth');
        return;
      case LocalToolkitScenario.emptyDay:
        _ensureAuthenticated();
        _store.applyEmptyDayPreset();
        widget.router.go('/dashboard');
        break;
      case LocalToolkitScenario.normalDay:
        _ensureAuthenticated();
        _store.applyNormalDayPreset();
        widget.router.go('/dashboard');
        break;
      case LocalToolkitScenario.overTarget:
        _ensureAuthenticated();
        _store.applyOverTargetPreset();
        widget.router.go('/dashboard');
        break;
      case LocalToolkitScenario.goalsNotConfigured:
        _ensureAuthenticated();
        _store.applyGoalsNotConfiguredPreset();
        widget.router.go('/dashboard');
        break;
      case LocalToolkitScenario.proposalReady:
        _ensureAuthenticated();
        _store.selectScenario('proposal');
        widget.router.go('/meal/create');
        break;
      case LocalToolkitScenario.clarificationRequired:
        _ensureAuthenticated();
        _store.selectScenario('clarification');
        widget.router.go('/meal/create');
        break;
      case LocalToolkitScenario.autoCommittedMeal:
        _ensureAuthenticated();
        _store.selectScenario('auto_committed');
        widget.router.go('/meal/create');
        break;
      case LocalToolkitScenario.templateHeavyAccount:
        _ensureAuthenticated();
        _store.applyTemplateHeavyPreset();
        widget.router.go('/templates');
        break;
    }
    _refreshVisibleData();
  }

  void _resetScenario() {
    setState(() => _activeScenario = LocalToolkitScenario.normalDay);
    _store.reset();
    _ensureAuthenticated();
    _refreshVisibleData();
  }

  void _addSampleMeal() {
    _ensureAuthenticated();
    _store.addSampleMeal();
    _refreshVisibleData();
  }

  void _clearMeals() {
    _ensureAuthenticated();
    _store.clearTodayMeals();
    _refreshVisibleData();
  }

  void _toggleTrustedMode() {
    _ensureAuthenticated();
    final enabled = !_store.user.trustedModeEnabled;
    _store.setTrustedMode(enabled);
    context.read<AuthViewModel>().setUser(_store.user);
    unawaited(context.read<SettingsViewModel>().load());
  }

  void _switchLocale() {
    final localeViewModel = context.read<LocaleViewModel>();
    final nextCode = localeViewModel.localeCode == 'en' ? 'es' : 'en';
    unawaited(localeViewModel.setLocaleCode(nextCode));
  }

  void _switchTheme() {
    final themeViewModel = context.read<ThemeModeViewModel>();
    unawaited(themeViewModel.setDarkMode(!themeViewModel.isDarkMode));
  }

  void _ensureAuthenticated() {
    _store.setSessionActive(true);
    context.read<AuthViewModel>().setUser(_store.user);
  }

  void _refreshVisibleData() {
    unawaited(context.read<DashboardViewModel>().load(forceRefresh: true));
    unawaited(context.read<MealHistoryViewModel>().load(forceRefresh: true));
    unawaited(context.read<MealTemplatesViewModel>().load(forceRefresh: true));
    unawaited(context.read<SettingsViewModel>().load());
  }
}
