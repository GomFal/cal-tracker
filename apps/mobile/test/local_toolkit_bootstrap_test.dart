import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/local_toolkit/data/local_toolkit_data.dart';
import 'package:cal_tracker_mobile/local_toolkit/ui/local_toolkit_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('local bootstrap starts with toolkit overlay and no backend',
      (tester) async {
    final dependencies = createLocalToolkitDependencies(
      store: createLocalFixtureStore(
        now: () => DateTime(2026, 5, 28, 12),
      ),
    );

    await tester.pumpWidget(
      CalTrackerBootstrap(
        tokenStorage: dependencies.tokenStorage,
        authRepository: dependencies.authRepository,
        nutritionRepository: dependencies.nutritionRepository,
        preferencesRepository: dependencies.preferencesRepository,
        mobileUpdateService: dependencies.mobileUpdateService,
        audioRecorderService: dependencies.audioRecorderService,
        checkForUpdates: false,
        appWrapperBuilder: (context, child, router) {
          return LocalToolkitOverlay(
            labels: _labels,
            activeScenario: LocalToolkitScenario.normalDay,
            trustedModeEnabled: dependencies.store.user.trustedModeEnabled,
            onRouteJump: (route) => router.go('/dashboard'),
            child: child,
          );
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(LocalToolkitOverlay.floatingButtonKey), findsOneWidget);

    await tester.tap(find.byKey(LocalToolkitOverlay.floatingButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(LocalToolkitOverlay.panelKey), findsOneWidget);
    expect(find.text('Local toolkit'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
  });
}

const _labels = LocalToolkitOverlayLabels(
  toolButtonTooltip: 'Open local toolkit',
  panelTitle: 'Local toolkit',
  panelSubtitle: 'Jump routes, apply scenarios, and mutate local state.',
  routeSectionTitle: 'Routes',
  scenarioSectionTitle: 'Scenarios',
  quickMutatorsSectionTitle: 'Quick mutators',
  routeAuth: 'Auth',
  routeDashboard: 'Dashboard',
  routeLogMeal: 'Log Meal',
  routeHistory: 'History',
  routeTemplates: 'Templates',
  routeSettings: 'Settings',
  scenarioUnauthenticated: 'Unauthenticated',
  scenarioEmptyDay: 'Empty day',
  scenarioNormalDay: 'Normal day',
  scenarioOverTarget: 'Over target',
  scenarioGoalsNotConfigured: 'Goals not configured',
  scenarioProposalReady: 'Proposal ready',
  scenarioClarificationRequired: 'Clarification required',
  scenarioAutoCommittedMeal: 'Auto-committed meal',
  scenarioTemplateHeavyAccount: 'Template-heavy account',
  quickResetScenario: 'Reset scenario',
  quickAddSampleMeal: 'Add sample meal',
  quickClearMeals: 'Clear meals',
  quickToggleTrustedMode: 'Toggle trusted mode',
  quickSwitchLocale: 'Switch locale',
  quickSwitchTheme: 'Switch light/dark theme',
  trustedModeOn: 'Trusted on',
  trustedModeOff: 'Trusted off',
  closeTooltip: 'Close toolkit',
);
