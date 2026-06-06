import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/core/app_shell.dart';
import 'package:cal_tracker_mobile/ui/core/voice_action_button.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';

class _MockNutritionRepository extends Mock implements NutritionRepository {}

class _MockAudioRecorderService extends Mock implements AudioRecorderService {}

/// Builds a test app that wraps the mic button in a GoRouter route context.
/// Returns the [VoiceLogViewModel] so tests can manipulate state directly.
({Widget app, VoiceLogViewModel viewModel}) _buildTestApp() {
  final audioRecorderService = _MockAudioRecorderService();
  when(() => audioRecorderService.stateStream)
      .thenAnswer((_) => const Stream.empty());
  when(() => audioRecorderService.dispose()).thenAnswer((_) async {});

  final viewModel = VoiceLogViewModel(
    nutritionRepository: _MockNutritionRepository(),
    audioRecorderService: audioRecorderService,
  );

  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        navigatorContainerBuilder:
            (context, navigationShell, children) => IndexedStack(
              index: navigationShell.currentIndex,
              children: children,
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const SizedBox(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const SizedBox(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/templates',
                builder: (context, state) => const SizedBox(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SizedBox(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  final app = MultiProvider(
    providers: [
      ChangeNotifierProvider<VoiceLogViewModel>.value(value: viewModel),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
    ),
  );

  return (app: app, viewModel: viewModel);
}

/// Sets a phone-sized viewport so the bottom nav (with mic button) is rendered.
void _setPhoneViewport(WidgetTester tester) {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 2.0;
}

void main() {
  group('Bottom mic processing spinner', () {
    testWidgets('spinner is hidden when idle', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('bottom_voice_action_button')),
        findsOneWidget,
      );
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
      expect(find.byKey(voiceActionProcessingStaticRingKey), findsNothing);
    });

    testWidgets('spinner appears when stopping', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      harness.viewModel.setPhaseForTest(VoiceLogState.stopping);
      await tester.pump();

      expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);
    });

    testWidgets('spinner appears when transcribing', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      harness.viewModel.setPhaseForTest(VoiceLogState.transcribing);
      await tester.pump();

      expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);
    });

    testWidgets('spinner appears when agentRunning', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      harness.viewModel.setPhaseForTest(VoiceLogState.agentRunning);
      await tester.pump();

      expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);
    });

    testWidgets('spinner hides when state transitions to idle', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      harness.viewModel.setPhaseForTest(VoiceLogState.transcribing);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);

      harness.viewModel.setPhaseForTest(VoiceLogState.idle);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
    });

    testWidgets('spinner hides on proposalReady', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      harness.viewModel.setPhaseForTest(VoiceLogState.agentRunning);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);

      harness.viewModel.setPhaseForTest(VoiceLogState.proposalReady);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
    });

    testWidgets('spinner hides on autoCommitted', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      harness.viewModel.setPhaseForTest(VoiceLogState.transcribing);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);

      harness.viewModel.setPhaseForTest(VoiceLogState.autoCommitted);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
    });

    testWidgets('spinner hides on error', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      harness.viewModel.setPhaseForTest(VoiceLogState.agentRunning);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);

      harness.viewModel.setPhaseForTest(VoiceLogState.error);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
    });

    testWidgets('spinner hides on resultReady', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      harness.viewModel.setPhaseForTest(VoiceLogState.stopping);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);

      harness.viewModel.setPhaseForTest(VoiceLogState.resultReady);
      await tester.pump();
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
    });

    testWidgets('recording pulse hides processing spinner', (tester) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      // When recording, the recording pulse takes priority over processing spinner
      // Even if isProcessing is somehow true, VoiceActionButtonChrome hides the spinner
      harness.viewModel.setPhaseForTest(VoiceLogState.recording);
      await tester.pump();

      expect(find.byKey(voiceActionRecordingPulseKey), findsOneWidget);
      expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
      expect(find.byKey(voiceActionProcessingStaticRingKey), findsNothing);
    });
  });
}
