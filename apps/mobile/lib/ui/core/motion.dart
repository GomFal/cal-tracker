import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FreshMotion {
  const FreshMotion._();

  static const press = Duration(milliseconds: 110);
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 320);

  static const easeOutQuart = Cubic(0.25, 1, 0.5, 1);
  static const easeOutQuint = Cubic(0.22, 1, 0.36, 1);
  static const easeInCubic = Cubic(0.32, 0, 0.67, 0);

  static bool disableAnimations(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  static Duration duration(BuildContext context, Duration duration) {
    return disableAnimations(context) ? Duration.zero : duration;
  }
}

class FreshFadeSlide extends StatelessWidget {
  const FreshFadeSlide({
    super.key,
    required this.child,
    this.offset = const Offset(0, 8),
    this.duration = FreshMotion.normal,
    this.curve = FreshMotion.easeOutQuart,
  });

  final Widget child;
  final Offset offset;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (FreshMotion.disableAnimations(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        final remaining = 1 - value;
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: offset * remaining, child: child),
        );
      },
      child: child,
    );
  }
}

class FreshAnimatedSwitcher extends StatelessWidget {
  const FreshAnimatedSwitcher({
    super.key,
    required this.child,
    this.duration = FreshMotion.normal,
    this.offset = const Offset(0, 6),
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final Offset offset;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (FreshMotion.disableAnimations(context)) return child;
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration * 0.75,
      switchInCurve: FreshMotion.easeOutQuart,
      switchOutCurve: FreshMotion.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final offsetAnimation = animation.drive(
          Tween<Offset>(
            begin: Offset(offset.dx / 100, offset.dy / 100),
            end: Offset.zero,
          ).chain(CurveTween(curve: FreshMotion.easeOutQuart)),
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: child,
    );
  }
}

class FreshPressable extends StatefulWidget {
  const FreshPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.onTap,
    this.borderRadius,
    this.scale = 0.985,
  });

  final Widget child;
  final bool enabled;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double scale;

  @override
  State<FreshPressable> createState() => _FreshPressableState();
}

class _FreshPressableState extends State<FreshPressable> {
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant FreshPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveScale = _pressed && widget.enabled ? widget.scale : 1.0;
    final duration = FreshMotion.duration(context, FreshMotion.press);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: widget.borderRadius,
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: effectiveScale,
          duration: duration,
          curve: FreshMotion.easeOutQuint,
          child: widget.child,
        ),
      ),
    );
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }
}

Page<T> freshTransitionPage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: FreshMotion.duration(context, FreshMotion.medium),
    reverseTransitionDuration: FreshMotion.duration(context, FreshMotion.fast),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (FreshMotion.disableAnimations(context)) return child;
      final curved = animation.drive(
        CurveTween(curve: FreshMotion.easeOutQuart),
      );
      final offset = animation.drive(
        Tween<Offset>(
          begin: const Offset(0.035, 0.015),
          end: Offset.zero,
        ).chain(CurveTween(curve: FreshMotion.easeOutQuart)),
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: offset, child: child),
      );
    },
  );
}
