import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';

part 'fresh_inputs.dart';

class FreshColors {
  const FreshColors._();

  // AMOLED minimal palette — derived from the dashboard redesign reference.
  static const appBg = Color(0xff000000);
  static const screen = Color(0xff000000);
  static const surface = Color(0xff0a0a0a);
  static const surfaceSoft = Color(0xff111111);
  static const surfaceMuted = Color(0xff1a1a1a);
  static const ink = Color(0xffffffff);
  static const inkSoft = Color(0xffb8b8b8);
  static const inkMuted = Color(0xff6e6e6e);
  static const rule = Color(0xff1f1f1f);
  static const ruleSoft = Color(0xff161616);
  static const lime = Color(0xffc8e14c);
  static const limeDeep = Color(0xffb8d142);
  static const limeSoft = Color(0xff1f2410);
  static const limeWash = Color(0xff13160a);
  static const leaf = Color(0xffc8e14c);
  static const water = Color(0xffc8e14c);
  static const orange = Color(0xffc8e14c);
  static const mint = Color(0xffc8e14c);
  static const coral = Color(0xffff6f80);
  static const yellow = Color(0xffc8e14c);
}

class FreshPalette extends ThemeExtension<FreshPalette> {
  const FreshPalette({
    required this.appBg,
    required this.screen,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceMuted,
    required this.ink,
    required this.inkSoft,
    required this.inkMuted,
    required this.rule,
    required this.ruleSoft,
    required this.lime,
    required this.limeDeep,
    required this.limeSoft,
    required this.limeWash,
    required this.leaf,
    required this.water,
    required this.orange,
    required this.mint,
    required this.coral,
    required this.yellow,
  });

  static const light = FreshPalette(
    appBg: Color(0xfff7f8f2),
    screen: Color(0xffffffff),
    surface: Color(0xffffffff),
    surfaceSoft: Color(0xfff4f5ef),
    surfaceMuted: Color(0xffe9ebe2),
    ink: Color(0xff10120d),
    inkSoft: Color(0xff393d33),
    inkMuted: Color(0xff74796d),
    rule: Color(0xffdde1d4),
    ruleSoft: Color(0xffecefe5),
    lime: Color(0xff8fbd20),
    limeDeep: Color(0xff5f850f),
    limeSoft: Color(0xffe7f5c4),
    limeWash: Color(0xfff3fae4),
    leaf: Color(0xff407f19),
    water: Color(0xff087fa0),
    orange: Color(0xffb85f14),
    mint: Color(0xff238f67),
    coral: Color(0xffd5485a),
    yellow: Color(0xff846000),
  );

  static const dark = FreshPalette(
    appBg: Color(0xff000000),
    screen: Color(0xff000000),
    surface: Color(0xff0a0a0a),
    surfaceSoft: Color(0xff111111),
    surfaceMuted: Color(0xff1a1a1a),
    ink: Color(0xffffffff),
    inkSoft: Color(0xffb8b8b8),
    inkMuted: Color(0xff6e6e6e),
    rule: Color(0xff1f1f1f),
    ruleSoft: Color(0xff161616),
    lime: Color(0xffc8e14c),
    limeDeep: Color(0xffb8d142),
    limeSoft: Color(0xff1f2410),
    limeWash: Color(0xff13160a),
    leaf: Color(0xffc8e14c),
    water: Color(0xffc8e14c),
    orange: Color(0xffc8e14c),
    mint: Color(0xffc8e14c),
    coral: Color(0xffff6f80),
    yellow: Color(0xffc8e14c),
  );

  final Color appBg;
  final Color screen;
  final Color surface;
  final Color surfaceSoft;
  final Color surfaceMuted;
  final Color ink;
  final Color inkSoft;
  final Color inkMuted;
  final Color rule;
  final Color ruleSoft;
  final Color lime;
  final Color limeDeep;
  final Color limeSoft;
  final Color limeWash;
  final Color leaf;
  final Color water;
  final Color orange;
  final Color mint;
  final Color coral;
  final Color yellow;

  @override
  FreshPalette copyWith({
    Color? appBg,
    Color? screen,
    Color? surface,
    Color? surfaceSoft,
    Color? surfaceMuted,
    Color? ink,
    Color? inkSoft,
    Color? inkMuted,
    Color? rule,
    Color? ruleSoft,
    Color? lime,
    Color? limeDeep,
    Color? limeSoft,
    Color? limeWash,
    Color? leaf,
    Color? water,
    Color? orange,
    Color? mint,
    Color? coral,
    Color? yellow,
  }) {
    return FreshPalette(
      appBg: appBg ?? this.appBg,
      screen: screen ?? this.screen,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkMuted: inkMuted ?? this.inkMuted,
      rule: rule ?? this.rule,
      ruleSoft: ruleSoft ?? this.ruleSoft,
      lime: lime ?? this.lime,
      limeDeep: limeDeep ?? this.limeDeep,
      limeSoft: limeSoft ?? this.limeSoft,
      limeWash: limeWash ?? this.limeWash,
      leaf: leaf ?? this.leaf,
      water: water ?? this.water,
      orange: orange ?? this.orange,
      mint: mint ?? this.mint,
      coral: coral ?? this.coral,
      yellow: yellow ?? this.yellow,
    );
  }

  @override
  FreshPalette lerp(ThemeExtension<FreshPalette>? other, double t) {
    if (other is! FreshPalette) return this;
    return FreshPalette(
      appBg: Color.lerp(appBg, other.appBg, t)!,
      screen: Color.lerp(screen, other.screen, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      ruleSoft: Color.lerp(ruleSoft, other.ruleSoft, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      limeDeep: Color.lerp(limeDeep, other.limeDeep, t)!,
      limeSoft: Color.lerp(limeSoft, other.limeSoft, t)!,
      limeWash: Color.lerp(limeWash, other.limeWash, t)!,
      leaf: Color.lerp(leaf, other.leaf, t)!,
      water: Color.lerp(water, other.water, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
    );
  }
}

extension FreshPaletteLookup on BuildContext {
  FreshPalette get freshPalette {
    return Theme.of(this).extension<FreshPalette>() ?? FreshPalette.light;
  }

  Color freshShadowColor({
    required double lightAlpha,
    required double darkAlpha,
  }) {
    final palette = freshPalette;
    final isDark = Theme.of(this).brightness == Brightness.dark;
    return (isDark ? Colors.black : palette.ink).withValues(
      alpha: isDark ? darkAlpha : lightAlpha,
    );
  }

  List<BoxShadow> freshElevationShadow({
    required double lightAlpha,
    required double darkAlpha,
    required double blurRadius,
    required Offset offset,
  }) {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    if (!isDark) return const [];
    return [
      BoxShadow(
        color: freshShadowColor(lightAlpha: lightAlpha, darkAlpha: darkAlpha),
        blurRadius: isDark ? blurRadius * 0.65 : blurRadius,
        offset: isDark ? Offset(offset.dx, offset.dy * 0.55) : offset,
      ),
    ];
  }
}

class FreshSpacing {
  const FreshSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class FreshRadii {
  const FreshRadii._();

  static const sm = 10.0;
  static const md = 18.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class FreshPageLayout {
  const FreshPageLayout({
    required this.headerPadding,
    required this.contentPadding,
    required this.leadingGap,
    required this.actionGap,
    required this.actionSpacing,
  });

  static const standard = FreshPageLayout(
    headerPadding: EdgeInsets.fromLTRB(20, 18, 20, 8),
    contentPadding: EdgeInsets.fromLTRB(20, 12, 20, 28),
    leadingGap: FreshSpacing.md,
    actionGap: FreshSpacing.md,
    actionSpacing: FreshSpacing.sm,
  );

  static const compact = FreshPageLayout(
    headerPadding: EdgeInsets.fromLTRB(16, 12, 16, 6),
    contentPadding: EdgeInsets.fromLTRB(16, 8, 16, 20),
    leadingGap: 9,
    actionGap: 9,
    actionSpacing: 6,
  );

  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry contentPadding;
  final double leadingGap;
  final double actionGap;
  final double actionSpacing;
}

class FreshPage extends StatelessWidget {
  const FreshPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.subtitle,
    this.maxWidth = 760,
    this.leading,
    this.layout = FreshPageLayout.standard,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final Widget? leading;
  final FreshPageLayout layout;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return ColoredBox(
      color: palette.screen,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: layout.headerPadding,
                    child: FreshHeader(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                      leading: leading,
                      layout: layout,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: layout.contentPadding,
                  sliver: SliverToBoxAdapter(child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FreshSliverPage extends StatelessWidget {
  const FreshSliverPage({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.subtitle,
    this.maxWidth = 760,
    this.leading,
    this.layout = FreshPageLayout.standard,
  });

  final String title;
  final String? subtitle;
  final List<Widget> slivers;
  final List<Widget> actions;
  final double maxWidth;
  final Widget? leading;
  final FreshPageLayout layout;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return ColoredBox(
      color: palette.screen,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: layout.headerPadding,
                    child: FreshHeader(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                      leading: leading,
                      layout: layout,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: layout.contentPadding,
                  sliver: SliverMainAxisGroup(slivers: slivers),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kept for API compatibility; AMOLED redesign uses a pure black screen.
class FreshScreenBackdrop extends StatelessWidget {
  const FreshScreenBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return ColoredBox(color: palette.screen);
  }
}

class FreshHeader extends StatelessWidget {
  const FreshHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.layout = FreshPageLayout.standard,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final FreshPageLayout layout;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, SizedBox(width: layout.leadingGap)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.inkMuted,
                    height: 1.1,
                  ),
                ),
              Text(
                title,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  color: palette.ink,
                ),
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          SizedBox(width: layout.actionGap),
          Wrap(spacing: layout.actionSpacing, children: actions),
        ],
      ],
    );
  }
}

class FreshCard extends StatelessWidget {
  const FreshCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.radius = FreshRadii.lg,
    this.onTap,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final borderRadius = BorderRadius.circular(radius);
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: borderRadius,
        border: Border.all(color: palette.rule),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return decorated;
    return FreshPressable(
      borderRadius: borderRadius,
      onTap: onTap,
      child: decorated,
    );
  }
}

class FreshMotionCard extends StatelessWidget {
  const FreshMotionCard({
    super.key,
    required this.child,
    this.offset = const Offset(0, 8),
    this.duration = FreshMotion.normal,
  });

  final Widget child;
  final Offset offset;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return FreshFadeSlide(offset: offset, duration: duration, child: child);
  }
}

class FreshIconButton extends StatelessWidget {
  const FreshIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final fg = foregroundColor ?? palette.ink;
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: size >= 48 ? 22 : 18),
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor ?? Colors.transparent,
          foregroundColor: fg,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: palette.inkMuted,
          shape: const CircleBorder(),
          side: BorderSide(color: palette.rule),
          elevation: 0,
        ),
      ),
    );
  }
}

class FreshIconChip extends StatelessWidget {
  const FreshIconChip({
    super.key,
    required this.icon,
    required this.color,
    this.backgroundColor,
    this.size = 42,
  });

  final IconData icon;
  final Color color;
  final Color? backgroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: color == FreshColors.ink ? palette.ink : color,
        size: size * 0.5,
      ),
    );
  }
}

class FreshMetricCard extends StatelessWidget {
  const FreshMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.sparkline,
  });

  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final Widget? sparkline;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      padding: const EdgeInsets.all(16),
      radius: FreshRadii.lg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FreshIconChip(icon: icon, color: color),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(color: palette.ink),
                ),
              ),
            ],
          ),
          if (sparkline != null) ...[
            const SizedBox(height: FreshSpacing.md),
            sparkline!,
          ],
          const Spacer(),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 4,
            children: [
              Text(
                value,
                style: textTheme.headlineMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(unit, style: textTheme.bodyMedium),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FreshStatusBanner extends StatelessWidget {
  const FreshStatusBanner({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.color = FreshColors.lime,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FreshIconChip(icon: icon, color: color),
        const SizedBox(width: FreshSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.bodyLarge?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: FreshSpacing.xs),
                Text(
                  message!,
                  style: textTheme.bodyMedium?.copyWith(color: palette.inkSoft),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: FreshSpacing.sm),
                action!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class FreshProgressRing extends StatelessWidget {
  const FreshProgressRing({
    super.key,
    required this.progress,
    required this.center,
    this.size = 90,
    this.color = FreshColors.lime,
    this.trackColor,
    this.strokeWidth,
  });

  final double progress;
  final Widget center;
  final double size;
  final Color color;
  final Color? trackColor;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final targetProgress = progress.clamp(0, 1).toDouble();
    final reduceMotion = FreshMotion.disableAnimations(context);
    if (reduceMotion) {
      return _ProgressRingFrame(
        progress: targetProgress,
        center: center,
        size: size,
        color: color,
        trackColor: trackColor ?? palette.rule,
        strokeWidth: strokeWidth,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetProgress),
      duration: FreshMotion.medium,
      curve: FreshMotion.easeOutQuart,
      builder: (context, value, child) {
        return _ProgressRingFrame(
          progress: value,
          center: child!,
          size: size,
          color: color,
          trackColor: trackColor ?? palette.rule,
          strokeWidth: strokeWidth,
        );
      },
      child: center,
    );
  }
}

class _ProgressRingFrame extends StatelessWidget {
  const _ProgressRingFrame({
    required this.progress,
    required this.center,
    required this.size,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Widget center;
  final double size;
  final Color color;
  final Color trackColor;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: progress,
                color: color,
                trackColor: trackColor,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
          center,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double? strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = strokeWidth ?? size.width * 0.13;
    final rect = Offset.zero & size;
    final insetRect = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(insetRect, -math.pi / 2, math.pi * 2, false, trackPaint);
    canvas.drawArc(
      insetRect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class FreshMiniBars extends StatelessWidget {
  const FreshMiniBars({
    super.key,
    required this.values,
    this.color = FreshColors.mint,
    this.height = 46,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<double>(0, math.max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final value in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FractionallySizedBox(
                  heightFactor: maxValue == 0
                      ? 0
                      : (value / maxValue).clamp(0.08, 1).toDouble(),
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FreshFoodStack extends StatelessWidget {
  const FreshFoodStack({super.key, this.assets = const [], this.size = 38});

  final List<String> assets;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    if (assets.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: palette.surfaceSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.restaurant_menu_rounded,
          color: palette.inkMuted,
          size: size * 0.5,
        ),
      );
    }
    return SizedBox(
      width: size + (assets.length - 1) * (size * 0.62),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < assets.length; i++)
            Positioned(
              left: i * size * 0.62,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surface, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(assets[i], fit: BoxFit.cover),
              ),
            ),
        ],
      ),
    );
  }
}

class FreshEmptyState extends StatelessWidget {
  const FreshEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          FreshIconChip(icon: icon, color: FreshColors.lime),
          const SizedBox(height: FreshSpacing.md),
          Text(
            title,
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FreshSpacing.sm),
          Text(
            message,
            style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class FreshSectionTitle extends StatelessWidget {
  const FreshSectionTitle({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
