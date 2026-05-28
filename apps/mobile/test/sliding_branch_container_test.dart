import 'package:cal_tracker_mobile/ui/core/app_shell.dart';
import 'package:cal_tracker_mobile/ui/core/shell_modal_lock.dart';
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

  testWidgets('user swipe does not change branches when disabled', (
    tester,
  ) async {
    final changes = <int>[];

    await tester.pumpWidget(
      _StatefulBranchHarness(
        initialIndex: 0,
        userScrollEnabled: false,
        onPageChanged: changes.add,
      ),
    );

    expect(_hitTestableBranch(0), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(_hitTestableBranch(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('programmatic branch changes still work when swipe is disabled', (
    tester,
  ) async {
    final changes = <int>[];

    await tester.pumpWidget(
      _BranchHarness(
        currentIndex: 0,
        userScrollEnabled: false,
        onPageChanged: changes.add,
      ),
    );

    await tester.pumpWidget(
      _BranchHarness(
        currentIndex: 2,
        userScrollEnabled: false,
        onPageChanged: changes.add,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(_hitTestableBranch(2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('modal lock observer locks until all popup routes close', () {
    final controller = ShellModalLockController();
    final observer = ShellModalLockObserver(controller);
    final firstPopup = _TestPopupRoute();
    final secondPopup = _TestPopupRoute();

    observer.didPush(firstPopup, null);
    expect(controller.isLocked, isTrue);

    observer.didPush(secondPopup, firstPopup);
    expect(controller.isLocked, isTrue);

    observer.didPop(secondPopup, firstPopup);
    expect(controller.isLocked, isTrue);

    observer.didRemove(firstPopup, null);
    expect(controller.isLocked, isFalse);
  });

  test('modal lock controller tracks popup routes across observers', () {
    final controller = ShellModalLockController();
    final rootObserver = ShellModalLockObserver(controller);
    final branchObserver = ShellModalLockObserver(controller);
    final rootPopup = _TestPopupRoute();
    final branchPopup = _TestPopupRoute();

    rootObserver.didPush(rootPopup, null);
    branchObserver.didPush(branchPopup, null);
    expect(controller.isLocked, isTrue);

    branchObserver.didPop(branchPopup, null);
    expect(controller.isLocked, isTrue);

    rootObserver.didPop(rootPopup, null);
    expect(controller.isLocked, isFalse);
  });

  test('modal lock observer syncs replacements', () {
    final controller = ShellModalLockController();
    final observer = ShellModalLockObserver(controller);
    final popup = _TestPopupRoute();
    final page = MaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    observer.didPush(popup, null);
    expect(controller.isLocked, isTrue);

    observer.didReplace(newRoute: page, oldRoute: popup);
    expect(controller.isLocked, isFalse);
  });
}

Finder _hitTestableBranch(int index) {
  return find.byKey(ValueKey('branch_$index')).hitTestable();
}

class _StatefulBranchHarness extends StatefulWidget {
  const _StatefulBranchHarness({
    required this.initialIndex,
    required this.onPageChanged,
    this.userScrollEnabled = true,
  });

  final int initialIndex;
  final ValueChanged<int> onPageChanged;
  final bool userScrollEnabled;

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
      userScrollEnabled: widget.userScrollEnabled,
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
    this.userScrollEnabled = true,
  });

  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final bool userScrollEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox.expand(
        child: SlidingBranchContainer(
          currentIndex: currentIndex,
          userScrollEnabled: userScrollEnabled,
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

class _TestPopupRoute extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const SizedBox.shrink();
  }
}
