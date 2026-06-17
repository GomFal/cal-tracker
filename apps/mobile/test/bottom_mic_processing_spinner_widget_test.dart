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
import 'package:cal_tracker_mobile/ui/features/agent_chat/view_models/agent_chat_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';

class _MockNutritionRepository extends Mock implements NutritionRepository {}

class _MockAudioRecorderService extends Mock implements AudioRecorderService {}

class _FakeAgentChatViewModel extends AgentChatViewModel {
  _FakeAgentChatViewModel()
      : super(
          nutritionRepository: _MockNutritionRepository(),
          audioRecorderService: _MockAudioRecorderService(),
        );

  int startCount = 0;
  int stopCount = 0;

  @override
  Future<void> startRecording() async {
    startCount++;
    isRecording = true;
    notifyListeners();
  }

  @override
  Future<void> stopRecording() async {
    stopCount++;
    isRecording = false;
    notifyListeners();
  }
}

({
  Widget app,
  VoiceLogViewModel voiceViewModel,
  AgentChatViewModel agentViewModel,
}) _buildTestApp({AgentChatViewModel? agentViewModel}) {
  final nutritionRepository = _MockNutritionRepository();
  final audioRecorderService = _MockAudioRecorderService();
  when(() => audioRecorderService.stateStream)
      .thenAnswer((_) => const Stream.empty());
  when(() => audioRecorderService.dispose()).thenAnswer((_) async {});

  final voiceViewModel = VoiceLogViewModel(
    nutritionRepository: nutritionRepository,
    audioRecorderService: audioRecorderService,
  );
  final resolvedAgentViewModel = agentViewModel ??
      AgentChatViewModel(
        nutritionRepository: nutritionRepository,
        audioRecorderService: audioRecorderService,
      );

  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/agent',
        builder: (context, state) => Scaffold(
          key: const ValueKey('agent_route_placeholder'),
          body: TextButton(
            key: const ValueKey('agent_route_back_button'),
            onPressed: () => context.pop(),
            child: const Text('Back'),
          ),
        ),
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        navigatorContainerBuilder: (context, navigationShell, children) =>
            IndexedStack(
          index: navigationShell.currentIndex,
          children: children,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const SizedBox(
                  key: ValueKey('dashboard_route_placeholder'),
                ),
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
      ChangeNotifierProvider<VoiceLogViewModel>.value(value: voiceViewModel),
      ChangeNotifierProvider<AgentChatViewModel>.value(
        value: resolvedAgentViewModel,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
    ),
  );

  return (
    app: app,
    voiceViewModel: voiceViewModel,
    agentViewModel: resolvedAgentViewModel,
  );
}

void _setPhoneViewport(WidgetTester tester) {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 2.0;
}

void main() {
  group('Bottom agent button', () {
    for (final phase in [
      VoiceLogState.idle,
      VoiceLogState.stopping,
      VoiceLogState.transcribing,
      VoiceLogState.agentRunning,
      VoiceLogState.recording,
      VoiceLogState.proposalReady,
      VoiceLogState.error,
    ]) {
      testWidgets('does not mirror legacy voice state $phase', (tester) async {
        _setPhoneViewport(tester);
        final harness = _buildTestApp();
        await tester.pumpWidget(harness.app);
        await tester.pump();
        await tester.pump();

        harness.voiceViewModel.setPhaseForTest(phase);
        await tester.pump();

        expect(
          find.byKey(const ValueKey('bottom_voice_action_button')),
          findsOneWidget,
        );
        expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
        expect(find.byKey(voiceActionProcessingStaticRingKey), findsNothing);
        expect(find.byKey(voiceActionRecordingPulseKey), findsNothing);
      });
    }

    testWidgets('uses an agent icon, opens chat on tap, and returns back', (
      tester,
    ) async {
      _setPhoneViewport(tester);
      final harness = _buildTestApp();
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.support_agent_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('bottom_voice_action_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('agent_route_placeholder')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('agent_route_back_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dashboard_route_placeholder')),
          findsOneWidget);
    });

    testWidgets('records directly on long press and opens chat on release', (
      tester,
    ) async {
      _setPhoneViewport(tester);
      final agentViewModel = _FakeAgentChatViewModel();
      final harness = _buildTestApp(agentViewModel: agentViewModel);
      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('bottom_voice_action_button')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump();

      expect(agentViewModel.startCount, 1);
      expect(harness.agentViewModel.isRecording, isTrue);
      expect(find.byKey(voiceActionRecordingPulseKey), findsOneWidget);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.byKey(const ValueKey('agent_route_placeholder')),
          findsOneWidget);
      expect(harness.agentViewModel.isRecording, isFalse);
      expect(agentViewModel.stopCount, 1);
    });
  });
}
