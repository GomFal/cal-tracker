import 'package:cal_tracker_mobile/app/app.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/client_metadata_provider.dart';
import 'package:cal_tracker_mobile/data/services/client_telemetry_service.dart';
import 'package:cal_tracker_mobile/local_toolkit/data/local_toolkit_data.dart';
import 'package:cal_tracker_mobile/local_toolkit/ui/local_toolkit_overlay.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('local bootstrap starts with toolkit overlay and no backend',
      (tester) async {
    final dependencies = createLocalToolkitDependencies(
      store: createLocalFixtureStore(
        now: () => DateTime(2026, 5, 28, 12),
      ),
    );
    // Use a long flush interval so the periodic timer in ClientTelemetryService
    // does not fire during the test. The local toolkit does not exercise
    // telemetry, so suppressing the periodic flush is safe.
    final telemetryService = ClientTelemetryService(
      apiConfig: const ApiConfig(baseUrl: 'http://localhost'),
      tokenStorage: dependencies.tokenStorage,
      metadataProvider: ClientMetadataProvider(),
      flushInterval: const Duration(days: 1),
    );
    addTearDown(telemetryService.dispose);

    await tester.pumpWidget(
      CalTrackerBootstrap(
        tokenStorage: dependencies.tokenStorage,
        authRepository: dependencies.authRepository,
        nutritionRepository: dependencies.nutritionRepository,
        preferencesRepository: dependencies.preferencesRepository,
        mobileUpdateService: dependencies.mobileUpdateService,
        audioRecorderService: dependencies.audioRecorderService,
        clientTelemetryService: telemetryService,
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

    final toolkitButton = find.byKey(LocalToolkitOverlay.floatingButtonKey);
    expect(toolkitButton, findsOneWidget);

    final initialButtonCenter = tester.getCenter(toolkitButton);
    await tester.drag(toolkitButton, const Offset(-120, -180));
    await tester.pumpAndSettle();

    final draggedButtonCenter = tester.getCenter(toolkitButton);
    expect(draggedButtonCenter.dx, lessThan(initialButtonCenter.dx));
    expect(draggedButtonCenter.dy, lessThan(initialButtonCenter.dy));

    await tester.tap(toolkitButton);
    await tester.pumpAndSettle();

    expect(find.byKey(LocalToolkitOverlay.panelKey), findsOneWidget);
    expect(find.text('Local toolkit'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);

    // Tear down the widget tree and the telemetry service so the test
    // framework does not see a pending periodic flush timer.
    await tester.pumpWidget(const SizedBox.expand());
    await telemetryService.dispose();
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
  routeNewUsualMeal: 'New usual meal',
  routeEditFirstUsualMeal: 'Edit first usual meal',
  routeNewUsualFood: 'New usual food',
  routeEditFirstUsualFood: 'Edit first usual food',
  routeScanUsualFood: 'Scan usual food',
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
  quickTogglePerformanceOverlay: 'Toggle perf overlay',
  performanceOverlayOn: 'Overlay on',
  performanceOverlayOff: 'Overlay off',
  trustedModeOn: 'Trusted on',
  trustedModeOff: 'Trusted off',
  closeTooltip: 'Close toolkit',
);
