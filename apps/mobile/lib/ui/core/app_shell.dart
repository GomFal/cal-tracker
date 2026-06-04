import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/nutrition_repository.dart';
import '../../l10n/app_localizations_context.dart';
import '../features/voice_log/view_models/voice_log_view_model.dart';
import 'design_system.dart';
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
    this.duration = const Duration(milliseconds: 260),
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

    unawaited(
      _controller
          .animateToPage(
        index,
        duration: widget.duration,
        curve: Curves.easeOutQuart,
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
        color: palette.screen,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
        child: FreshCard(
          padding: const EdgeInsets.symmetric(vertical: 16),
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
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: selected ? palette.ink : palette.inkSoft,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
    final icon = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: selected ? palette.limeWash : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        item.icon,
        color: selected ? palette.limeDeep : palette.ink,
        size: 22,
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(FreshRadii.lg),
      onTap: onTap,
      child: SizedBox(
        width: vertical ? 78 : 56,
        height: vertical ? 64 : 58,
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
    );
  }
}

class _CenterVoiceButton extends StatefulWidget {
  const _CenterVoiceButton();

  @override
  State<_CenterVoiceButton> createState() => _CenterVoiceButtonState();
}

class _CenterVoiceButtonState extends State<_CenterVoiceButton> {
  bool _longPressRecording = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final viewModel = context.watch<VoiceLogViewModel>();
    final isRecording = viewModel.state == VoiceLogState.recording;
    final isBusy = viewModel.state == VoiceLogState.requestingPermission ||
        viewModel.state == VoiceLogState.stopping ||
        viewModel.state == VoiceLogState.transcribing ||
        viewModel.state == VoiceLogState.agentRunning;
    final hasError = viewModel.state == VoiceLogState.error;
    final backgroundColor = isRecording
        ? palette.coral
        : hasError
            ? palette.yellow
            : isBusy
                ? palette.surfaceMuted
                : palette.lime;
    final icon = isRecording
        ? Icons.stop_rounded
        : isBusy
            ? Icons.graphic_eq_rounded
            : hasError
                ? Icons.error_outline_rounded
                : Icons.mic_rounded;
    final tooltip = isRecording
        ? 'Stop recording'
        : isBusy
            ? 'Processing voice'
            : 'Record meal';

    return Semantics(
      key: const ValueKey('bottom_voice_action_button'),
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isBusy ? null : () => unawaited(_handleTap()),
          onLongPressStart: isBusy
              ? null
              : (details) => unawaited(_handleLongPressStart(details)),
          onLongPressEnd: isBusy
              ? null
              : (details) => unawaited(_handleLongPressEnd(details)),
          onLongPressCancel:
              isBusy ? null : () => unawaited(_handleLongPressCancel()),
          child: VoiceActionButtonChrome(
            dimension: 62,
            backgroundColor: backgroundColor,
            isRecording: isRecording,
            child: Icon(icon, color: palette.ink, size: 28),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap() async {
    final viewModel = context.read<VoiceLogViewModel>();
    if (viewModel.canStartRecording) {
      await viewModel.startRecording();
      if (viewModel.state == VoiceLogState.recording) {
        VoiceActionHaptics.recordingStarted();
      }
      return;
    }
    if (viewModel.canStopRecording) {
      VoiceActionHaptics.recordingStopped();
      await _stopAndOpen(viewModel);
    }
  }

  Future<void> _handleLongPressStart(LongPressStartDetails details) async {
    final viewModel = context.read<VoiceLogViewModel>();
    if (!viewModel.canStartRecording) return;
    _longPressRecording = true;
    await viewModel.startRecording();
    if (viewModel.state == VoiceLogState.recording) {
      VoiceActionHaptics.recordingStarted();
    }
  }

  Future<void> _handleLongPressEnd(LongPressEndDetails details) async {
    await _stopLongPressRecording();
  }

  Future<void> _handleLongPressCancel() async {
    await _stopLongPressRecording();
  }

  Future<void> _stopLongPressRecording() async {
    if (!_longPressRecording) return;
    _longPressRecording = false;
    final viewModel = context.read<VoiceLogViewModel>();
    if (viewModel.canStopRecording) {
      VoiceActionHaptics.recordingStopped();
      await _stopAndOpen(viewModel);
    }
  }

  Future<void> _stopAndOpen(VoiceLogViewModel viewModel) async {
    final result = await viewModel.stopRecording(
      submitAfterTranscription: true,
    );
    if (!mounted) return;
    final destination = globalVoiceRoutingDestinationFor(result);
    if (destination != null) {
      context.go(destination.location, extra: destination.extra);
    }
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Container(
      width: compact ? 46 : 52,
      height: compact ? 46 : 52,
      decoration: BoxDecoration(
        color: palette.limeWash,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.local_fire_department, color: palette.limeDeep),
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
