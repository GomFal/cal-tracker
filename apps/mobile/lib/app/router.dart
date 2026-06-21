import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/models/nutrition_models.dart';
import '../l10n/app_localizations_context.dart';
import '../ui/core/app_shell.dart';
import '../ui/core/motion.dart';
import '../ui/core/shell_modal_lock.dart';
import '../ui/features/agent_chat/views/agent_chat_screen.dart';
import '../ui/features/auth/view_models/auth_view_model.dart';
import '../ui/features/auth/views/auth_screen.dart';
import '../ui/features/dashboard/views/dashboard_screen.dart';
import '../ui/features/meal_history/views/meal_history_screen.dart';
import '../ui/features/meal_templates/views/meal_template_editor_screen.dart';
import '../ui/features/meal_templates/views/meal_templates_screen.dart';
import '../ui/features/meal_templates/views/usual_food_editor_screen.dart';
import '../ui/features/meal_templates/views/usual_food_scan_screen.dart';
import '../ui/features/settings/views/settings_screen.dart';
import '../ui/features/voice_log/views/voice_log_screen.dart';

GoRouter buildRouter(
  AuthViewModel authViewModel, {
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final modalLockController = ShellModalLockController();
  List<NavigatorObserver> modalLockObservers() => [
    ShellModalLockObserver(modalLockController),
  ];
  return GoRouter(
    navigatorKey: navigatorKey,
    observers: modalLockObservers(),
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
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/agent',
        pageBuilder: (context, state) => freshTransitionPage<void>(
          context: context,
          state: state,
          child: _AuthRestoreGate(
            authViewModel: authViewModel,
            child: const AgentChatScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/meal/create',
        pageBuilder: (context, state) {
          final extra = state.extra;
          return freshTransitionPage<void>(
            context: context,
            state: state,
            child: _AuthRestoreGate(
              authViewModel: authViewModel,
              child: MealCreateScreen(
                initialItems: extra is MealCreateInitialItems
                    ? extra.items
                    : const [],
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/templates/ingredients/scan',
        pageBuilder: (context, state) => freshTransitionPage<void>(
          context: context,
          state: state,
          child: _AuthRestoreGate(
            authViewModel: authViewModel,
            child: const UsualFoodScanScreen(),
          ),
        ),
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) => _AuthRestoreGate(
          authViewModel: authViewModel,
          child: AppShell(navigationShell: navigationShell),
        ),
        navigatorContainerBuilder: (context, navigationShell, children) {
          return ListenableBuilder(
            listenable: modalLockController,
            builder: (context, _) {
              return SlidingBranchContainer(
                currentIndex: navigationShell.currentIndex,
                userScrollEnabled: !modalLockController.isLocked,
                onPageChanged: (index) {
                  if (index == navigationShell.currentIndex) return;
                  navigationShell.goBranch(index);
                },
                children: children,
              );
            },
          );
        },
        branches: [
          StatefulShellBranch(
            observers: modalLockObservers(),
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
            observers: modalLockObservers(),
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
            observers: modalLockObservers(),
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
                routes: [
                  GoRoute(
                    path: 'ingredients/new',
                    pageBuilder: (context, state) => freshTransitionPage<void>(
                      context: context,
                      state: state,
                      child: _AuthRestoreGate(
                        authViewModel: authViewModel,
                        child: UsualFoodEditorScreen(
                          initialDraft: state.extra is UsualFoodDraft
                              ? state.extra as UsualFoodDraft
                              : null,
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'ingredients/:id/edit',
                    pageBuilder: (context, state) => freshTransitionPage<void>(
                      context: context,
                      state: state,
                      child: _AuthRestoreGate(
                        authViewModel: authViewModel,
                        child: UsualFoodEditorScreen(
                          foodId: state.pathParameters['id'],
                          initialFood: state.extra is UsualFood
                              ? state.extra as UsualFood
                              : null,
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'meals/new',
                    pageBuilder: (context, state) => freshTransitionPage<void>(
                      context: context,
                      state: state,
                      child: _AuthRestoreGate(
                        authViewModel: authViewModel,
                        child: MealTemplateEditorScreen(
                          initialDraft: state.extra is UsualMealDraft
                              ? state.extra as UsualMealDraft
                              : null,
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'meals/:id/edit',
                    pageBuilder: (context, state) => freshTransitionPage<void>(
                      context: context,
                      state: state,
                      child: _AuthRestoreGate(
                        authViewModel: authViewModel,
                        child: MealTemplateEditorScreen(
                          templateId: state.pathParameters['id'],
                          initialTemplate: state.extra is MealTemplate
                              ? state.extra as MealTemplate
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            observers: modalLockObservers(),
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
        child: Text(state.error?.message ?? context.l10n.routeNotFound),
      ),
    ),
  );
}

class _AuthRestoreGate extends StatelessWidget {
  const _AuthRestoreGate({required this.authViewModel, required this.child});

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
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}
