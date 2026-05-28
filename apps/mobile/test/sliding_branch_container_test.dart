import 'package:cal_tracker_mobile/ui/core/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('swiping left advances to the next branch', (tester) async {
    final changes = <int>[];

    await tester.pumpWidget(
      _StatefulBranchHarness(initialIndex: 0, onPageChanged: changes.add),
    );

    expect(_hitTestableBranch(0), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(changes, [1]);
    expect(_hitTestableBranch(1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping right returns to the previous branch', (tester) async {
    final changes = <int>[];

    await tester.pumpWidget(
      _StatefulBranchHarness(initialIndex: 1, onPageChanged: changes.add),
    );

    expect(_hitTestableBranch(1), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(changes, [0]);
    expect(_hitTestableBranch(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not wrap backward from the first branch', (tester) async {
    final changes = <int>[];

    await tester.pumpWidget(
      _StatefulBranchHarness(initialIndex: 0, onPageChanged: changes.add),
    );

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(_hitTestableBranch(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not wrap forward from the final branch', (tester) async {
    final changes = <int>[];

    await tester.pumpWidget(
      _StatefulBranchHarness(initialIndex: 3, onPageChanged: changes.add),
    );

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(_hitTestableBranch(3), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('programmatic branch changes animate without callbacks', (
    tester,
  ) async {
    final changes = <int>[];

    await tester.pumpWidget(
      _BranchHarness(currentIndex: 0, onPageChanged: changes.add),
    );

    expect(_hitTestableBranch(0), findsOneWidget);

    await tester.pumpWidget(
      _BranchHarness(currentIndex: 2, onPageChanged: changes.add),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(_hitTestableBranch(2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _hitTestableBranch(int index) {
  return find.byKey(ValueKey('branch_$index')).hitTestable();
}

class _StatefulBranchHarness extends StatefulWidget {
  const _StatefulBranchHarness({
    required this.initialIndex,
    required this.onPageChanged,
  });

  final int initialIndex;
  final ValueChanged<int> onPageChanged;

  @override
  State<_StatefulBranchHarness> createState() => _StatefulBranchHarnessState();
}

class _StatefulBranchHarnessState extends State<_StatefulBranchHarness> {
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return _BranchHarness(
      currentIndex: currentIndex,
      onPageChanged: (index) {
        setState(() => currentIndex = index);
        widget.onPageChanged(index);
      },
    );
  }
}

class _BranchHarness extends StatelessWidget {
  const _BranchHarness({
    required this.currentIndex,
    required this.onPageChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox.expand(
        child: SlidingBranchContainer(
          currentIndex: currentIndex,
          onPageChanged: onPageChanged,
          children: [
            for (var index = 0; index < 4; index++)
              GestureDetector(
                key: ValueKey('branch_$index'),
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Center(child: Text('Branch $index')),
              ),
          ],
        ),
      ),
    );
  }
}
