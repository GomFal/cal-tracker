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

GoRouter buildRouter(
  AuthViewModel authViewModel, {
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/dashboard',
    refreshListenable: authViewModel,
    redirect: (context, state) {
      final isAuthRoute = state.matchedLocation == '/auth';
      if (authViewModel.isRestoring) {
        return isAuthRoute ? '/dashboard' : null;
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
        path: '/meal/create',
        builder: (context, state) => _AuthRestoreGate(
          authViewModel: authViewModel,
          child: const MealCreateScreen(),
        ),
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) => _AuthRestoreGate(
          authViewModel: authViewModel,
          child: AppShell(navigationShell: navigationShell),
        ),
        navigatorContainerBuilder: (context, navigationShell, children) {
          return SlidingBranchContainer(
            currentIndex: navigationShell.currentIndex,
            children: children,
            onPageChanged: (index) {
              if (index == navigationShell.currentIndex) return;
              navigationShell.goBranch(index);
            },
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  _AuthRestoreGate(
                    authViewModel: authViewModel,
                    child: const DashboardScreen(),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  _AuthRestoreGate(
                    authViewModel: authViewModel,
                    child: const MealHistoryScreen(),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/templates',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  _AuthRestoreGate(
                    authViewModel: authViewModel,
                    child: const MealTemplatesScreen(),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  _AuthRestoreGate(
                    authViewModel: authViewModel,
                    child: const SettingsScreen(),
                  ),
                ),
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

class _AuthRestoreGate extends StatelessWidget {
  const _AuthRestoreGate({
    required this.authViewModel,
    required this.child,
  });

  final AuthViewModel authViewModel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: authViewModel,
      builder: (context, _) {
        if (authViewModel.hasSession) return child;
        if (!authViewModel.isRestoring) {
          return const Scaffold(
            body: SizedBox.shrink(key: ValueKey('auth_blocked_gate')),
          );
        }
        return const Scaffold(
          body: Center(
            child: SizedBox.square(
              key: ValueKey('auth_restore_gate'),
              dimension: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        );
      },
    );
  }
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
