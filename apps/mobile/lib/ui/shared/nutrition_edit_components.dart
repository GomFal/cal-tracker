import 'package:flutter/material.dart';

import '../../domain/models/nutrition_edit.dart';
import '../../l10n/app_localizations_context.dart';
import '../core/design_system.dart';

/// Macro kind enum shared between nutrition edit screens.
enum NutritionMacroKind { protein, carbs, fat }

/// Default color mapping used in meal editor (fat → yellow).
Map<NutritionMacroKind, Color> defaultNutritionMacroColors(
  BuildContext context,
) {
  final palette = context.freshPalette;
  return {
    NutritionMacroKind.protein: palette.coral,
    NutritionMacroKind.carbs: palette.orange,
    NutritionMacroKind.fat: palette.yellow,
  };
}

/// Compact macro summary line (e.g. "Protein 20g · Carbs 30g · Fat 10g").
///
/// [baseStyle] controls the overall text style (defaults to `bodyMedium` with
/// `FontWeight.w600`). [overflow] controls text overflow (defaults to clip).
/// [macroColors] maps each [NutritionMacroKind] to its display color; defaults
/// to [defaultNutritionMacroColors].
class NutritionMacroSummaryText extends StatelessWidget {
  const NutritionMacroSummaryText({
    super.key,
    required this.nutrition,
    this.baseStyle,
    this.overflow,
    this.macroColors,
  });

  final NutritionEdit? nutrition;
  final TextStyle? baseStyle;
  final TextOverflow? overflow;
  final Map<NutritionMacroKind, Color>? macroColors;

  @override
  Widget build(BuildContext context) {
    final value = nutrition;
    if (value == null) return const SizedBox.shrink();

    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final effectiveBaseStyle = baseStyle ??
        textTheme.bodyMedium?.copyWith(
          color: context.freshPalette.inkMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        );
    final colors = macroColors ?? defaultNutritionMacroColors(context);

    return RichText(
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: effectiveBaseStyle,
        children: [
          macroSpan(
            color: colors[NutritionMacroKind.protein]!,
            text: '${l10n.commonProtein} ${formatMacro(value.proteinGrams)}g',
          ),
          const TextSpan(text: ' · '),
          macroSpan(
            color: colors[NutritionMacroKind.carbs]!,
            text: '${l10n.commonCarbs} ${formatMacro(value.carbsGrams)}g',
          ),
          const TextSpan(text: ' · '),
          macroSpan(
            color: colors[NutritionMacroKind.fat]!,
            text: '${l10n.commonFat} ${formatMacro(value.fatGrams)}g',
          ),
        ],
      ),
    );
  }
}

/// Warning banner displayed when calories from macros do not match the
/// entered calorie value.
class NutritionMacroWarningBanner extends StatelessWidget {
  const NutritionMacroWarningBanner({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.coral.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FreshRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            FreshIconChip(
              icon: Icons.info_outline_rounded,
              color: palette.coral,
              backgroundColor: palette.coral.withValues(alpha: 0.14),
            ),
            const SizedBox(width: FreshSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: FreshSpacing.xs),
                  Text(
                    message,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Suffix widget shown next to the calorie field when the macro-based
/// calorie suggestion is available.
class NutritionCalorieSuggestionSuffix extends StatelessWidget {
  const NutritionCalorieSuggestionSuffix({
    super.key,
    required this.calories,
    required this.onApply,
  });

  final int calories;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.caloriesValue(calories),
            style: textTheme.labelMedium?.copyWith(
              color: palette.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: FreshSpacing.xs),
          TextButton(
            onPressed: onApply,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: palette.ink,
              backgroundColor: palette.lime,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(context.l10n.mealEditorApplySuggestion),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

/// Input decoration for macro fields.
InputDecoration macroInputDecoration({
  required String label,
  required Color color,
}) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
    floatingLabelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
  );
}

/// Rich-text span for a single macro label.
TextSpan macroSpan({
  required Color color,
  required String text,
  FontWeight fontWeight = FontWeight.w700,
}) {
  return TextSpan(
    text: text,
    style: TextStyle(
      color: color,
      fontWeight: fontWeight,
    ),
  );
}

/// Text style for macro input fields.
TextStyle macroFieldStyle(TextTheme textTheme, Color color) {
  return textTheme.bodyLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ) ??
      TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      );
}

/// Format a macro gram value for display.
/// Whole numbers render without decimals.
String formatMacro(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

/// Format a quantity value for display.
/// Whole numbers render without decimals.
String formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

/// Normalize a text value for comparison.
String normalizedText(String value) => value.trim().toLowerCase();
