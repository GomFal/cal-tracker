import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/performance_overlay_view_model.dart';

class PerformanceOverlayHost extends StatelessWidget {
  const PerformanceOverlayHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visible = context.select<PerformanceOverlayViewModel, bool>(
      (viewModel) => viewModel.visible,
    );
    return Stack(
      children: [
        child,
        if (visible) const RepaintBoundary(child: _PerformanceOverlayStrip()),
      ],
    );
  }
}

class _PerformanceOverlayStrip extends StatelessWidget {
  const _PerformanceOverlayStrip();

  static const _height = 104.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: _height,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.76),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
              ),
              child: ClipRect(
                child: PerformanceOverlay.allEnabled(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
