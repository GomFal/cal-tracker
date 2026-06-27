import 'package:cal_tracker_mobile/app/theme.dart';
import 'package:cal_tracker_mobile/ui/core/design_system.dart';
import 'package:cal_tracker_mobile/ui/core/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('motion durations collapse when animations are disabled', (
    tester,
  ) async {
    late Duration enabled;
    late Duration disabled;

    await tester.pumpWidget(
      _motionHarness(
        child: Builder(
          builder: (context) {
            enabled = FreshMotion.duration(context, FreshMotion.normal);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      _motionHarness(
        disableAnimations: true,
        child: Builder(
          builder: (context) {
            disabled = FreshMotion.duration(context, FreshMotion.normal);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(enabled, FreshMotion.normal);
    expect(disabled, Duration.zero);
  });

  testWidgets('fade slide renders final state when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _motionHarness(
        disableAnimations: true,
        child: const FreshFadeSlide(child: Text('ready')),
      ),
    );

    expect(find.text('ready'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    expect(
      find.byWidgetPredicate(
          (widget) => widget is TweenAnimationBuilder<double>),
      findsNothing,
    );
  });

  testWidgets(
    'animated switcher uses direct child when animations are disabled',
    (tester) async {
      await tester.pumpWidget(
        _motionHarness(
          disableAnimations: true,
          child: const FreshAnimatedSwitcher(child: Text('static')),
        ),
      );

      expect(find.text('static'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsNothing);
    },
  );

  testWidgets('pressable scales without moving neighboring widgets', (
    tester,
  ) async {
    await tester.pumpWidget(_motionHarness(child: const _PressableHarness()));

    final rightIdle = tester.getTopLeft(find.byKey(_rightKey));
    var scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(_pressableKey),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.scale, 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_pressableKey)),
    );
    await tester.pump();

    final rightPressed = tester.getTopLeft(find.byKey(_rightKey));
    scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(_pressableKey),
        matching: find.byType(AnimatedScale),
      ),
    );

    expect(scale.scale, lessThan(1));
    expect(rightPressed, rightIdle);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('progress ring skips tweening when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _motionHarness(
        disableAnimations: true,
        child: const FreshProgressRing(progress: 0.75, center: Text('75')),
      ),
    );

    expect(find.text('75'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is TweenAnimationBuilder<double>,
      ),
      findsNothing,
    );
  });
}

const _pressableKey = ValueKey('pressable');
const _rightKey = ValueKey('pressable_right');

Widget _motionHarness({required Widget child, bool disableAnimations = false}) {
  return MaterialApp(
    theme: buildTheme(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

class _PressableHarness extends StatelessWidget {
  const _PressableHarness();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(dimension: 40),
        FreshPressable(
          key: _pressableKey,
          onTap: () {},
          child: const SizedBox.square(dimension: 72),
        ),
        const SizedBox.square(key: _rightKey, dimension: 40),
      ],
    );
  }
}
