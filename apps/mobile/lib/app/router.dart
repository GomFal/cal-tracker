import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations_context.dart';
import '../ui/core/design_system.dart';
import '../ui/core/app_shell.dart';
import '../ui/features/auth/view_models/auth_view_model.dart';
import '../ui/features/auth/views/auth_screen.dart';
import '../ui/features/dashboard/views/dashboard_screen.dart';
import '../ui/features/meal_history/views/meal_history_screen.dart';
import '../ui/features/meal_templates/views/meal_templates_screen.dart';
import '../ui/features/settings/views/settings_screen.dart';
import '../ui/features/voice_log/views/voice_log_screen.dart';
import 'theme.dart';

GoRouter buildRouter(AuthViewModel authViewModel) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: authViewModel,
    redirect: (context, state) {
      final isAuthRoute = state.matchedLocation == '/auth';
      final isSessionLoadingRoute = state.matchedLocation == '/session-loading';
      if (authViewModel.isRestoringSession) {
        return isSessionLoadingRoute ? null : '/session-loading';
      }
      if (isSessionLoadingRoute) {
        return authViewModel.hasSession ? '/dashboard' : '/auth';
      }
      if (!authViewModel.hasSession && !isAuthRoute) {
        return '/auth';
      }
      if (authViewModel.hasSession && isAuthRoute) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const _LightOnlyAuthRoute(),
      ),
      GoRoute(
        path: '/session-loading',
        builder: (context, state) => const _SessionLoadingRoute(),
      ),
      GoRoute(
        path: '/meal/create',
        builder: (context, state) => const MealCreateScreen(),
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        navigatorContainerBuilder: (context, navigationShell, children) {
          return SlidingBranchContainer(
            currentIndex: navigationShell.currentIndex,
            children: children,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                pageBuilder: (context, state) =>
                    _tabPage(state, const DashboardScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                pageBuilder: (context, state) =>
                    _tabPage(state, const MealHistoryScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/templates',
                pageBuilder: (context, state) =>
                    _tabPage(state, const MealTemplatesScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) =>
                    _tabPage(state, const SettingsScreen()),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
          child: Text(state.error?.message ?? context.l10n.routeNotFound)),
    ),
  );
}

Page<void> _tabPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}

class _LightOnlyAuthRoute extends StatelessWidget {
  const _LightOnlyAuthRoute();

  static const _overlayStyle = SystemUiOverlayStyle(
    statusBarColor: FreshColors.screen,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: FreshColors.screen,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle,
      child: Theme(
        data: buildLightTheme(),
        child: const AuthScreen(),
      ),
    );
  }
}

class _SessionLoadingRoute extends StatelessWidget {
  const _SessionLoadingRoute();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
