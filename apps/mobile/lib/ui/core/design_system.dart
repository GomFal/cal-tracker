import 'dart:math' as math;

import 'package:flutter/material.dart';

class FreshColors {
  const FreshColors._();

  static const appBg = Color(0xfff0f0ef);
  static const screen = Color(0xfff7f7f5);
  static const surface = Color(0xfffbfbf8);
  static const surfaceSoft = Color(0xfff3f3f1);
  static const surfaceMuted = Color(0xffecedea);
  static const ink = Color(0xff080907);
  static const inkSoft = Color(0xff2f312d);
  static const inkMuted = Color(0xff72756f);
  static const rule = Color(0xffe3e5df);
  static const ruleSoft = Color(0xffeef0eb);
  static const lime = Color(0xff9ad32a);
  static const limeDeep = Color(0xff78a51b);
  static const limeSoft = Color(0xffd8f3a0);
  static const limeWash = Color(0xffedf8d2);
  static const leaf = Color(0xff4f9b1f);
  static const water = Color(0xff10c7f5);
  static const orange = Color(0xfff08b2b);
  static const mint = Color(0xff4fd6a2);
  static const coral = Color(0xffe94f5f);
  static const yellow = Color(0xfffff0b6);
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
    appBg: FreshColors.appBg,
    screen: FreshColors.screen,
    surface: FreshColors.surface,
    surfaceSoft: FreshColors.surfaceSoft,
    surfaceMuted: FreshColors.surfaceMuted,
    ink: FreshColors.ink,
    inkSoft: FreshColors.inkSoft,
    inkMuted: FreshColors.inkMuted,
    rule: FreshColors.rule,
    ruleSoft: FreshColors.ruleSoft,
    lime: FreshColors.lime,
    limeDeep: FreshColors.limeDeep,
    limeSoft: FreshColors.limeSoft,
    limeWash: FreshColors.limeWash,
    leaf: FreshColors.leaf,
    water: FreshColors.water,
    orange: FreshColors.orange,
    mint: FreshColors.mint,
    coral: FreshColors.coral,
    yellow: FreshColors.yellow,
  );

  static const dark = FreshPalette(
    appBg: Color(0xff10140d),
    screen: Color(0xff141811),
    surface: Color(0xff1d2318),
    surfaceSoft: Color(0xff252d1f),
    surfaceMuted: Color(0xff303828),
    ink: Color(0xfff3f7ee),
    inkSoft: Color(0xffd6dfcd),
    inkMuted: Color(0xffa2ac98),
    rule: Color(0xff3d4734),
    ruleSoft: Color(0xff2d3527),
    lime: Color(0xff8fbd3a),
    limeDeep: Color(0xff9cc94b),
    limeSoft: Color(0xff354b21),
    limeWash: Color(0xff243318),
    leaf: Color(0xff6fb24a),
    water: Color(0xff56b7ca),
    orange: Color(0xffe4a15d),
    mint: Color(0xff58bd8a),
    coral: Color(0xffff7f8c),
    yellow: Color(0xff5c4d25),
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
    return [
      BoxShadow(
        color: freshShadowColor(
          lightAlpha: lightAlpha,
          darkAlpha: darkAlpha,
        ),
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

const _lightSoftShadow = [
  BoxShadow(
    color: Color(0x14080907),
    blurRadius: 14,
    offset: Offset(0, 8),
  ),
];

const _darkSoftShadow = [
  BoxShadow(
    color: Color(0x66000000),
    blurRadius: 12,
    offset: Offset(0, 7),
  ),
];

class FreshPage extends StatelessWidget {
  const FreshPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.subtitle,
    this.maxWidth = 760,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: FreshHeader(
                    title: title,
                    subtitle: subtitle,
                    actions: actions,
                    leading: leading,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                sliver: SliverToBoxAdapter(child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FreshHeader extends StatelessWidget {
  const FreshHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: FreshSpacing.md),
        ],
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
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: FreshSpacing.md),
          Wrap(spacing: FreshSpacing.sm, children: actions),
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
        boxShadow: shadow
            ? Theme.of(context).brightness == Brightness.dark
                ? _darkSoftShadow
                : _lightSoftShadow
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: decorated,
      ),
    );
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
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: size >= 48 ? 22 : 18),
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor ?? palette.surface,
          foregroundColor: foregroundColor ?? palette.ink,
          disabledBackgroundColor: palette.surfaceMuted,
          disabledForegroundColor: palette.inkMuted,
          shape: const CircleBorder(),
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
    final textTheme = Theme.of(context).textTheme;
    return FreshCard(
      color: color.withValues(alpha: 0.16),
      shadow: false,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FreshIconChip(icon: icon, color: color),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleMedium),
                if (message != null) ...[
                  const SizedBox(height: FreshSpacing.xs),
                  Text(message!, style: textTheme.bodyMedium),
                ],
                if (action != null) ...[
                  const SizedBox(height: FreshSpacing.sm),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
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
  });

  final double progress;
  final Widget center;
  final double size;
  final Color color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: progress.clamp(0, 1).toDouble(),
                color: color,
                trackColor: trackColor ?? palette.surface,
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
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.13;
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
        oldDelegate.trackColor != trackColor;
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
  const FreshFoodStack({
    super.key,
    this.assets = const [],
    this.size = 38,
  });

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
    return FreshCard(
      color: palette.surface,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            FreshIconChip(icon: icon, color: FreshColors.limeDeep),
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
      ),
    );
  }
}

class FreshSectionTitle extends StatelessWidget {
  const FreshSectionTitle({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
