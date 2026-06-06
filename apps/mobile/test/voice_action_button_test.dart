import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/ui/core/design_system.dart';
import 'package:cal_tracker_mobile/ui/core/voice_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scales recording state without moving neighboring widgets',
      (tester) async {
    await tester.pumpWidget(_buildHarness(isRecording: false));

    final rightIdle = tester.getTopLeft(find.byKey(_rightKey));
    final buttonSizeIdle = tester.getSize(find.byKey(_buttonKey));
    var scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(_buttonKey),
        matching: find.byType(AnimatedScale),
      ),
    );

    expect(scale.scale, 1);
    expect(find.byKey(voiceActionRecordingPulseKey), findsNothing);

    await tester.pumpWidget(_buildHarness(isRecording: true));
    await tester.pump(const Duration(milliseconds: 220));

    final rightRecording = tester.getTopLeft(find.byKey(_rightKey));
    final buttonSizeRecording = tester.getSize(find.byKey(_buttonKey));
    scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(_buttonKey),
        matching: find.byType(AnimatedScale),
      ),
    );

    expect(scale.scale, 1.1);
    expect(rightRecording, rightIdle);
    expect(buttonSizeRecording, buttonSizeIdle);
    expect(find.byKey(voiceActionRecordingPulseKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('uses a static recording ring when animations are disabled',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(isRecording: true, disableAnimations: true),
    );

    final scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(_buttonKey),
        matching: find.byType(AnimatedScale),
      ),
    );

    expect(scale.duration, Duration.zero);
    expect(find.byKey(voiceActionRecordingPulseKey), findsNothing);
    expect(find.byKey(voiceActionRecordingStaticRingKey), findsOneWidget);
  });

  testWidgets('shows processing spinner when isProcessing is true',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(isProcessing: true, isRecording: false),
    );

    expect(find.byKey(voiceActionProcessingSpinnerKey), findsOneWidget);
    expect(find.byKey(voiceActionProcessingStaticRingKey), findsNothing);
  });

  testWidgets('hides processing spinner when isProcessing is false',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(isProcessing: false, isRecording: false),
    );

    expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
    expect(find.byKey(voiceActionProcessingStaticRingKey), findsNothing);
  });

  testWidgets(
      'shows static processing ring when animations are disabled',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        isProcessing: true,
        isRecording: false,
        disableAnimations: true,
      ),
    );

    expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
    expect(find.byKey(voiceActionProcessingStaticRingKey), findsOneWidget);
  });

  testWidgets(
      'processing spinner is hidden when recording (recording has priority)',
      (tester) async {
    await tester.pumpWidget(
      _buildHarness(isProcessing: true, isRecording: true),
    );

    // Recording pulse is shown
    expect(find.byKey(voiceActionRecordingPulseKey), findsOneWidget);
    // Processing spinner is hidden (recording has priority)
    expect(find.byKey(voiceActionProcessingSpinnerKey), findsNothing);
    expect(find.byKey(voiceActionProcessingStaticRingKey), findsNothing);
  });
}

const _buttonKey = ValueKey('voice_action_test_button');
const _rightKey = ValueKey('voice_action_test_right');

Widget _buildHarness({
  required bool isRecording,
  bool isProcessing = false,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: buildTheme(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(dimension: 40),
              VoiceActionButtonChrome(
                key: _buttonKey,
                dimension: 62,
                backgroundColor:
                    isRecording ? FreshColors.coral : FreshColors.lime,
                isProcessing: isProcessing,
                isRecording: isRecording,
                child: const Icon(Icons.mic_rounded),
              ),
              const SizedBox.square(key: _rightKey, dimension: 40),
            ],
          ),
        ),
      ),
    ),
  );
}
