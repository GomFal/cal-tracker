import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/data/repositories/nutrition_repository.dart';
import 'package:cal_tracker_mobile/data/services/audio_recorder_service.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/core/app_shell.dart';
import 'package:cal_tracker_mobile/ui/features/agent_chat/view_models/agent_chat_view_model.dart';
import 'package:cal_tracker_mobile/ui/features/voice_log/view_models/voice_log_view_model.dart';

class _MockNutritionRepository extends Mock implements NutritionRepository {}

class _MockAudioRecorderService extends Mock implements AudioRecorderService {}

/// Builds a test app that wraps the mic bubble in a GoRouter route context.
Widget _buildTestApp(String initialLocation) {
  final nutritionRepository = _MockNutritionRepository();
  final audioRecorderService = _MockAudioRecorderService();
  when(
    () => audioRecorderService.stateStream,
  ).thenAnswer((_) => const Stream.empty());
  when(() => audioRecorderService.dispose()).thenAnswer((_) async {});

  final voiceViewModel = VoiceLogViewModel(
    nutritionRepository: nutritionRepository,
    audioRecorderService: audioRecorderService,
  );
  final agentViewModel = AgentChatViewModel(
    nutritionRepository: nutritionRepository,
    audioRecorderService: audioRecorderService,
  );

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/agent',
        builder: (context, state) =>
            const SizedBox(key: ValueKey('agent_route_placeholder')),
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
                routes: [
                  GoRoute(
                    path: 'meals/new',
                    builder: (context, state) => const SizedBox(),
                  ),
                  GoRoute(
                    path: 'meals/:id/edit',
                    builder: (context, state) => const SizedBox(),
                  ),
                  GoRoute(
                    path: 'ingredients/new',
                    builder: (context, state) => const SizedBox(),
                  ),
                  GoRoute(
                    path: 'ingredients/:id/edit',
                    builder: (context, state) => const SizedBox(),
                  ),
                ],
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

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VoiceLogViewModel>.value(value: voiceViewModel),
      ChangeNotifierProvider<AgentChatViewModel>.value(value: agentViewModel),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
    ),
  );
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
  const bubbleText = 'Hold the agent button to speak directly';

  group('Bottom agent bubble tooltip', () {
    testWidgets('appears on /templates/meals/new', (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_buildTestApp('/templates/meals/new'));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('bottom_voice_action_button')),
        findsOneWidget,
      );
      expect(find.text(bubbleText), findsOneWidget);
    });

    testWidgets('appears on /templates/ingredients/new', (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_buildTestApp('/templates/ingredients/new'));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('bottom_voice_action_button')),
        findsOneWidget,
      );
      expect(find.text(bubbleText), findsOneWidget);
    });

    testWidgets('does NOT appear on /templates/meals/:id/edit', (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_buildTestApp('/templates/meals/abc123/edit'));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('bottom_voice_action_button')),
        findsOneWidget,
      );
      expect(find.text(bubbleText), findsNothing);
    });

    testWidgets('does NOT appear on /templates/ingredients/:id/edit', (
      tester,
    ) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(
        _buildTestApp('/templates/ingredients/abc123/edit'),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('bottom_voice_action_button')),
        findsOneWidget,
      );
      expect(find.text(bubbleText), findsNothing);
    });

    testWidgets('does NOT appear on /dashboard', (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_buildTestApp('/dashboard'));
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('bottom_voice_action_button')),
        findsOneWidget,
      );
      expect(find.text(bubbleText), findsNothing);
    });

    testWidgets('navigation and agent controls expose semantics', (
      tester,
    ) async {
      _setPhoneViewport(tester);
      final semanticsHandle = tester.ensureSemantics();

      await tester.pumpWidget(_buildTestApp('/dashboard'));
      await tester.pump();
      await tester.pump();

      final homeData =
          tester.getSemantics(find.bySemanticsLabel('Home')).getSemanticsData();
      expect(homeData.flagsCollection.isButton, isTrue);
      expect(homeData.flagsCollection.isSelected, Tristate.isTrue);
      expect(homeData.hasAction(SemanticsAction.tap), isTrue);

      final statsData = tester
          .getSemantics(find.bySemanticsLabel('Stats'))
          .getSemanticsData();
      expect(statsData.flagsCollection.isButton, isTrue);
      expect(statsData.flagsCollection.isSelected, Tristate.isFalse);
      expect(statsData.hasAction(SemanticsAction.tap), isTrue);

      final agentData = tester
          .getSemantics(
              find.byKey(const ValueKey('bottom_voice_action_button')))
          .getSemanticsData();
      expect(agentData.label, 'Open agent chat. Hold to speak');
      expect(agentData.flagsCollection.isButton, isTrue);
      expect(agentData.hasAction(SemanticsAction.tap), isTrue);
      semanticsHandle.dispose();
    });

    testWidgets('dismisses when mic button is tapped', (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_buildTestApp('/templates/meals/new'));
      await tester.pump();
      await tester.pump();

      expect(find.text(bubbleText), findsOneWidget);

      // Tap the semantically-labeled mic button using the semantics finder
      await tester.tap(
        find.byKey(const ValueKey('bottom_voice_action_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(bubbleText), findsNothing);
    });

    testWidgets('auto-dismisses after 6 seconds', (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_buildTestApp('/templates/meals/new'));
      await tester.pump();
      await tester.pump();

      expect(find.text(bubbleText), findsOneWidget);

      // Advance past the 6-second auto-dismiss timer
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(bubbleText), findsNothing);
    });
  });
}
