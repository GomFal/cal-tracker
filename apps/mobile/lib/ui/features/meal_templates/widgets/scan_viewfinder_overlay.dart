import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations_context.dart';
import '../../../core/design_system.dart';

/// Translucent overlay with a clear rectangular cutout and corner brackets.
///
/// Inspired by QR-code scanner UIs: paints four semi-transparent dark regions
/// around the cutout, corner markers in [FreshColors.lime], and a label above
/// the cutout.
class ScanViewfinderOverlay extends StatelessWidget {
  const ScanViewfinderOverlay({
    super.key,
    this.frameAspectRatio = 1.6,
  });

  /// width / height of the clear cutout region.
  final double frameAspectRatio;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    const overlayAlpha = 0.55;

    return CustomPaint(
      size: Size.infinite,
      painter: _ViewfinderPainter(
        frameAspectRatio: frameAspectRatio,
        overlayColor: palette.ink.withValues(alpha: overlayAlpha),
        bracketColor: palette.lime,
        bracketWidth: 3,
        bracketArm: 22,
        label: l10n.usualFoodsScanFrameLabel,
        hint: l10n.usualFoodsScanHint,
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({
    required this.frameAspectRatio,
    required this.overlayColor,
    required this.bracketColor,
    required this.bracketWidth,
    required this.bracketArm,
    required this.label,
    required this.hint,
  });

  final double frameAspectRatio;
  final Color overlayColor;
  final Color bracketColor;
  final double bracketWidth;
  final double bracketArm;
  final String label;
  final String hint;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;
    final bracketPaint = Paint()
      ..color = bracketColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = bracketWidth
      ..strokeCap = StrokeCap.round;

    // Compute cutout: 86% of width, height derived from aspect ratio.
    final cutW = size.width * 0.86;
    final cutH = cutW / frameAspectRatio;
    final cutLeft = (size.width - cutW) / 2;
    final cutTop = (size.height - cutH) / 2 - 24; // shift up a bit for label
    final cutRect = Rect.fromLTWH(cutLeft, cutTop, cutW, cutH);

    // Draw four dark regions around the cutout.
    // top
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, cutTop), paint);
    // bottom
    canvas.drawRect(
      Rect.fromLTWH(0, cutRect.bottom, size.width, size.height - cutRect.bottom),
      paint,
    );
    // left (between top and bottom)
    canvas.drawRect(
      Rect.fromLTWH(0, cutTop, cutLeft, cutH),
      paint,
    );
    // right
    canvas.drawRect(
      Rect.fromLTWH(cutRect.right, cutTop, size.width - cutRect.right, cutH),
      paint,
    );

    // Corner brackets
    _drawBracket(canvas, bracketPaint, cutRect.left, cutRect.top, 1, 1);
    _drawBracket(canvas, bracketPaint, cutRect.right, cutRect.top, -1, 1);
    _drawBracket(canvas, bracketPaint, cutRect.left, cutRect.bottom, 1, -1);
    _drawBracket(canvas, bracketPaint, cutRect.right, cutRect.bottom, -1, -1);

    // Label above the cutout
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: bracketColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    labelPainter.paint(
      canvas,
      Offset(
        (size.width - labelPainter.width) / 2,
        cutRect.top - 28,
      ),
    );

    // Hint below the cutout
    final hintPainter = TextPainter(
      text: TextSpan(
        text: hint,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 13,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: cutW - 32);
    hintPainter.paint(
      canvas,
      Offset(
        (size.width - hintPainter.width) / 2,
        cutRect.bottom + 16,
      ),
    );
  }

  void _drawBracket(
    Canvas canvas,
    Paint paint,
    double x,
    double y,
    double dirX,
    double dirY,
  ) {
    // Horizontal arm
    canvas.drawLine(
      Offset(x, y),
      Offset(x + dirX * bracketArm, y),
      paint,
    );
    // Vertical arm
    canvas.drawLine(
      Offset(x, y),
      Offset(x, y + dirY * bracketArm),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) =>
      oldDelegate.frameAspectRatio != frameAspectRatio ||
      oldDelegate.label != label ||
      oldDelegate.hint != hint;
}
