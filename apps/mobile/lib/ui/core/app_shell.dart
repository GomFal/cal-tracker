import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations_context.dart';
import '../features/voice_log/view_models/voice_log_view_model.dart';
import 'design_system.dart';
import 'voice_action_button.dart';

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
  });

  final int currentIndex;
  final List<Widget> children;
  final Duration duration;

  @override
  State<SlidingBranchContainer> createState() => _SlidingBranchContainerState();
}

class _SlidingBranchContainerState extends State<SlidingBranchContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _currentIndex;
  int? _previousIndex;
  int _direction = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    )..addStatusListener(_handleAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant SlidingBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.currentIndex == _currentIndex) {
      return;
    }

    _previousIndex = _currentIndex;
    _direction = widget.currentIndex > _currentIndex ? 1 : -1;
    _currentIndex = widget.currentIndex;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _previousIndex == null) {
      return;
    }
    setState(() => _previousIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = Curves.easeOutQuart.transform(_controller.value);
          final isAnimating = _previousIndex != null && _controller.value < 1;

          return Stack(
            fit: StackFit.expand,
            children: [
              for (final index in _paintOrder())
                _BranchSlot(
                  active: index == _currentIndex,
                  visible: index == _currentIndex ||
                      (isAnimating && index == _previousIndex),
                  ignoring: isAnimating || index != _currentIndex,
                  translation: _translationFor(index, progress),
                  child: widget.children[index],
                ),
            ],
          );
        },
      ),
    );
  }

  Iterable<int> _paintOrder() sync* {
    for (var index = 0; index < widget.children.length; index++) {
      if (index != _previousIndex && index != _currentIndex) {
        yield index;
      }
    }
    if (_previousIndex != null &&
        _previousIndex! >= 0 &&
        _previousIndex! < widget.children.length) {
      yield _previousIndex!;
    }
    if (_currentIndex >= 0 && _currentIndex < widget.children.length) {
      yield _currentIndex;
    }
  }

  Offset _translationFor(int index, double progress) {
    if (index == _currentIndex) {
      return Offset.lerp(
        Offset(_direction.toDouble(), 0),
        Offset.zero,
        progress,
      )!;
    }
    if (index == _previousIndex) {
      return Offset.lerp(
        Offset.zero,
        Offset(-_direction.toDouble(), 0),
        progress,
      )!;
    }
    return Offset.zero;
  }
}

class _BranchSlot extends StatelessWidget {
  const _BranchSlot({
    required this.active,
    required this.visible,
    required this.ignoring,
    required this.translation,
    required this.child,
  });

  final bool active;
  final bool visible;
  final bool ignoring;
  final Offset translation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: ignoring,
          child: FractionalTranslation(
            translation: translation,
            transformHitTests: false,
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }
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
  const _FreshSideNav({
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
            Text(item.label,
                style: labelStyle, overflow: TextOverflow.ellipsis),
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
    final isBusy = viewModel.state == VoiceLogState.stopping ||
        viewModel.state == VoiceLogState.transcribing ||
        viewModel.state == VoiceLogState.agentRunning;
    final hasError = viewModel.state == VoiceLogState.error;
    final backgroundColor = isRecording
        ? FreshColors.coral
        : hasError
            ? FreshColors.yellow
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
    final stopFuture = viewModel.stopRecording(submitAfterTranscription: true);
    if (mounted) {
      context.go('/meal/create');
    }
    await stopFuture;
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
