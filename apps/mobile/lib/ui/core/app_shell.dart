import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/nutrition_repository.dart';
import '../../l10n/app_localizations_context.dart';
import '../features/agent_chat/view_models/agent_chat_view_model.dart';
import 'design_system.dart';
import 'motion.dart';
import 'voice_action_button.dart';

class GlobalVoiceRoutingDestination {
  const GlobalVoiceRoutingDestination(this.location, {this.extra});

  final String location;
  final Object? extra;
}

GlobalVoiceRoutingDestination? globalVoiceRoutingDestinationFor(
  AgentRunResult? result,
) {
  if (result == null) return null;
  if (result.kind == 'usual_food_draft' && result.usualFoodDraft != null) {
    return GlobalVoiceRoutingDestination(
      '/templates/ingredients/new',
      extra: result.usualFoodDraft,
    );
  }
  if (result.kind == 'usual_meal_draft' && result.usualMealDraft != null) {
    return GlobalVoiceRoutingDestination(
      '/templates/meals/new',
      extra: result.usualMealDraft,
    );
  }
  return const GlobalVoiceRoutingDestination('/meal/create');
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedIndex = navigationShell.currentIndex;
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Scaffold(
            backgroundColor: palette.screen,
            body: Row(
              children: [
                _FreshSideNav(
                  selectedIndex: selectedIndex,
                  onSelected: (index) => _go(context, index),
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: palette.screen,
          body: navigationShell,
          bottomNavigationBar: _FreshBottomNav(
            selectedIndex: selectedIndex,
            onSelected: (index) => _go(context, index),
          ),
        );
      },
    );
  }

  void _go(BuildContext context, int index) {
    if (navigationShell.currentIndex == index) return;
    navigationShell.goBranch(index);
  }
}

class SlidingBranchContainer extends StatefulWidget {
  const SlidingBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
    this.duration = FreshMotion.medium,
    this.userScrollEnabled = true,
    this.onPageChanged,
  });

  final int currentIndex;
  final List<Widget> children;
  final Duration duration;
  final bool userScrollEnabled;
  final ValueChanged<int>? onPageChanged;

  @override
  State<SlidingBranchContainer> createState() => _SlidingBranchContainerState();
}

class _SlidingBranchContainerState extends State<SlidingBranchContainer> {
  late final PageController _controller;
  late int _pageIndex;
  int? _programmaticTargetIndex;

  @override
  void initState() {
    super.initState();
    _pageIndex = _clampedIndex(widget.currentIndex);
    _controller = PageController(initialPage: _pageIndex, keepPage: false);
  }

  @override
  void didUpdateWidget(covariant SlidingBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetIndex = _clampedIndex(widget.currentIndex);
    if (widget.children.isEmpty ||
        targetIndex == _pageIndex ||
        targetIndex == _programmaticTargetIndex) {
      return;
    }

    _animateToPage(targetIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _clampedIndex(int index) {
    final maxIndex = widget.children.length - 1;
    if (maxIndex < 0) return 0;
    return index.clamp(0, maxIndex).toInt();
  }

  void _animateToPage(int index) {
    _programmaticTargetIndex = index;
    _pageIndex = index;
    if (!_controller.hasClients) {
      return;
    }

    if (FreshMotion.disableAnimations(context)) {
      _controller.jumpToPage(index);
      _programmaticTargetIndex = null;
      return;
    }

    unawaited(
      _controller
          .animateToPage(
            index,
            duration: FreshMotion.duration(context, widget.duration),
            curve: FreshMotion.easeOutQuart,
          )
          .whenComplete(() {
            if (!mounted || _programmaticTargetIndex != index) {
              return;
            }
            _programmaticTargetIndex = null;
          }),
    );
  }

  void _handlePageChanged(int index) {
    _pageIndex = index;
    if (_programmaticTargetIndex != null) {
      if (_programmaticTargetIndex == index) {
        _programmaticTargetIndex = null;
      }
      return;
    }
    if (index == widget.currentIndex) return;
    widget.onPageChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    return PageView(
      controller: _controller,
      physics: widget.userScrollEnabled
          ? null
          : const NeverScrollableScrollPhysics(),
      onPageChanged: _handlePageChanged,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          _BranchSlot(
            active: index == widget.currentIndex,
            child: widget.children[index],
          ),
      ],
    );
  }
}

class _BranchSlot extends StatefulWidget {
  const _BranchSlot({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_BranchSlot> createState() => _BranchSlotState();
}

class _BranchSlotState extends State<_BranchSlot>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(
      enabled: widget.active,
      child: RepaintBoundary(child: widget.child),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _FreshBottomNav extends StatelessWidget {
  const _FreshBottomNav({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final items = _items(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.screen,
          border: Border(top: BorderSide(color: palette.rule, width: 1)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavButton(
              key: _navButtonKey(items, 0),
              item: items[0],
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            _NavButton(
              key: _navButtonKey(items, 1),
              item: items[1],
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
            const _CenterVoiceButton(),
            _NavButton(
              key: _navButtonKey(items, 2),
              item: items[2],
              selected: selectedIndex == 2,
              onTap: () => onSelected(2),
            ),
            _NavButton(
              key: _navButtonKey(items, 3),
              item: items[3],
              selected: selectedIndex == 3,
              onTap: () => onSelected(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _FreshSideNav extends StatelessWidget {
  const _FreshSideNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final items = _items(context);
    return SafeArea(
      child: Container(
        width: 112,
        padding: const EdgeInsets.all(16),
        color: palette.screen,
        child: Column(
          children: [
            const _BrandMark(compact: true),
            const SizedBox(height: FreshSpacing.xl),
            for (var index = 0; index < items.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _NavButton(
                  key: _navButtonKey(items, index),
                  item: items[index],
                  selected: selectedIndex == index,
                  vertical: true,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    this.vertical = false,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: selected ? palette.lime : palette.inkMuted,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
    final icon = Icon(
      item.icon,
      color: selected ? palette.lime : palette.inkMuted,
      size: vertical ? 26 : 24,
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: true,
      label: item.label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(FreshRadii.lg),
          onTap: onTap,
          child: SizedBox(
            width: vertical ? 78 : 64,
            height: vertical ? 64 : 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(height: 4),
                Text(
                  item.label,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterVoiceButton extends StatefulWidget {
  const _CenterVoiceButton();

  @override
  State<_CenterVoiceButton> createState() => _CenterVoiceButtonState();
}

class _CenterVoiceButtonState extends State<_CenterVoiceButton> {
  Timer? _bubbleTimer;
  bool _showBubble = false;
  bool _bubbleUserDismissed = false;
  bool _directVoicePressActive = false;
  bool _directVoiceReleasePending = false;
  bool _directVoiceOpenOnRelease = true;

  static const _bubbleCreateRoutes = <String>{
    '/templates/meals/new',
    '/templates/ingredients/new',
  };

  @override
  void initState() {
    super.initState();
    _initBubbleTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initBubbleTimer();
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    super.dispose();
  }

  void _initBubbleTimer() {
    final location = _currentLocation();
    final shouldShow =
        _bubbleCreateRoutes.contains(location) && !_bubbleUserDismissed;
    if (shouldShow == _showBubble) return;
    _bubbleTimer?.cancel();
    if (shouldShow) {
      setState(() => _showBubble = true);
      _bubbleTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _showBubble = false);
      });
    } else {
      setState(() => _showBubble = false);
    }
  }

  String _currentLocation() {
    try {
      return GoRouterState.of(context).uri.toString();
    } catch (_) {
      return '';
    }
  }

  void _dismissBubble() {
    if (!_showBubble) return;
    _bubbleTimer?.cancel();
    _bubbleUserDismissed = true;
    setState(() => _showBubble = false);
  }

  void _startDirectVoicePress(BuildContext context) {
    final viewModel = context.read<AgentChatViewModel>();
    if (viewModel.isBusy || viewModel.isRecording || _directVoicePressActive) {
      return;
    }
    _dismissBubble();
    _directVoicePressActive = true;
    _directVoiceReleasePending = false;
    _directVoiceOpenOnRelease = true;
    VoiceActionHaptics.recordingStarted();
    unawaited(_startDirectVoiceRecording(viewModel));
  }

  Future<void> _startDirectVoiceRecording(AgentChatViewModel viewModel) async {
    await viewModel.startRecording();
    if (!mounted) return;

    if (!viewModel.isRecording) {
      final shouldOpenChat =
          _directVoiceReleasePending && _directVoiceOpenOnRelease;
      _resetDirectVoicePress();
      if (shouldOpenChat) _openAgentChat(context);
      return;
    }

    if (_directVoiceReleasePending) {
      _completeDirectVoicePress(
        context,
        viewModel,
        openChat: _directVoiceOpenOnRelease,
      );
    }
  }

  void _requestFinishDirectVoicePress(
    BuildContext context, {
    required bool openChat,
  }) {
    if (!_directVoicePressActive) return;
    _directVoiceReleasePending = true;
    _directVoiceOpenOnRelease = openChat;
    final viewModel = context.read<AgentChatViewModel>();
    if (!viewModel.isRecording) return;
    _completeDirectVoicePress(context, viewModel, openChat: openChat);
  }

  void _completeDirectVoicePress(
    BuildContext context,
    AgentChatViewModel viewModel, {
    required bool openChat,
  }) {
    _resetDirectVoicePress();
    VoiceActionHaptics.recordingStopped();
    if (openChat) _openAgentChat(context);
    unawaited(viewModel.stopRecording());
  }

  void _resetDirectVoicePress() {
    _directVoicePressActive = false;
    _directVoiceReleasePending = false;
    _directVoiceOpenOnRelease = true;
  }

  void _openAgentChat(BuildContext context) {
    if (_currentLocation() == '/agent') return;
    context.push('/agent');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final viewModel = context.watch<AgentChatViewModel>();
    final isRecording = viewModel.isRecording;
    final tooltip = context.l10n.agentChatOpenAction;

    final addButton = Semantics(
      key: const ValueKey('bottom_voice_action_button'),
      container: true,
      button: true,
      enabled: true,
      label: tooltip,
      value: isRecording ? context.l10n.voiceRecordingTitle : null,
      onTap: () {
        _dismissBubble();
        _openAgentChat(context);
      },
      child: ExcludeSemantics(
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _dismissBubble();
              _openAgentChat(context);
            },
            onLongPressStart: (_) => _startDirectVoicePress(context),
            onLongPressEnd: (_) =>
                _requestFinishDirectVoicePress(context, openChat: true),
            onLongPressCancel: () =>
                _requestFinishDirectVoicePress(context, openChat: false),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isRecording ? palette.coral : palette.lime,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  isRecording
                      ? Icons.stop_rounded
                      : Icons.support_agent_rounded,
                  color: isRecording ? palette.coral : palette.lime,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final agentButton = FreshAnimatedSwitcher(
      alignment: Alignment.bottomCenter,
      duration: FreshMotion.fast,
      child: _showBubble
          ? SizedBox(
              key: const ValueKey('bottom_voice_action_bubble_visible'),
              width: 48,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  addButton,
                  Positioned(
                    bottom: 56,
                    left: 0,
                    right: 0,
                    child: OverflowBox(
                      fit: OverflowBoxFit.deferToChild,
                      maxWidth: 300,
                      maxHeight: 120,
                      alignment: Alignment.topCenter,
                      child: _BubbleTip(
                        message: context.l10n.bottomMicFillEditorHint,
                        onDismiss: _dismissBubble,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : KeyedSubtree(
              key: const ValueKey('bottom_voice_action_bubble_hidden'),
              child: addButton,
            ),
    );

    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: palette.inkMuted,
      fontWeight: FontWeight.w500,
    );

    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          agentButton,
          const SizedBox(height: 4),
          Text(
            context.l10n.navAgent,
            style: labelStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BubbleTip extends StatelessWidget {
  const _BubbleTip({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onDismiss,
      child: Semantics(
        label: message,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: CustomPaint(
            painter: _BubblePainter(
              bubbleColor: isDark ? palette.surfaceMuted : palette.ink,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? palette.surfaceMuted : palette.ink,
                borderRadius: BorderRadius.circular(FreshRadii.sm),
              ),
              child: Text(
                message,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark ? palette.ink : palette.surfaceSoft,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.bubbleColor});

  final Color bubbleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bubbleColor
      ..style = PaintingStyle.fill;

    final bubbleRect = Rect.fromLTWH(0, 0, size.width, size.height - 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect, const Radius.circular(8)),
      paint,
    );

    // Draw the pointing-down arrow/triangle
    final path = Path()
      ..moveTo(size.width / 2 - 6, size.height - 8)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 6, size.height - 8)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) {
    return oldDelegate.bubbleColor != bubbleColor;
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Container(
      width: compact ? 40 : 48,
      height: compact ? 40 : 48,
      decoration: BoxDecoration(
        color: palette.surfaceSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.local_fire_department,
        color: palette.lime,
        size: compact ? 22 : 26,
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label, this.keyName);

  final IconData icon;
  final String label;
  final String keyName;
}

List<_NavItem> _items(BuildContext context) {
  final l10n = context.l10n;
  return [
    _NavItem(Icons.home_outlined, l10n.navHome, 'home'),
    _NavItem(Icons.bar_chart_rounded, l10n.navStats, 'stats'),
    _NavItem(Icons.star_border_rounded, l10n.navUsual, 'usual'),
    _NavItem(Icons.grid_view_rounded, l10n.navMenu, 'menu'),
  ];
}

ValueKey<String> _navButtonKey(List<_NavItem> items, int index) {
  return ValueKey<String>('main_nav_${items[index].keyName}');
}
