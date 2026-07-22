String formatHydrationLiters(double value) {
  final rounded = (value * 4).round() / 4;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

double roundHydrationLiters(double value) {
  return ((value * 4).round() / 4).clamp(0, 10).toDouble();
}

/// Hydration consumption is stored to the nearest milliliter. Goals remain on
/// the existing quarter-liter scale, but agent-recorded amounts must not lose
/// precision when the dashboard renders or the user adjusts them.
double normalizeHydrationConsumptionLiters(double value) {
  return ((value * 1000).round() / 1000).clamp(0, 10).toDouble();
}

String formatHydrationConsumptionLiters(double value) {
  var formatted = normalizeHydrationConsumptionLiters(value).toStringAsFixed(3);
  while (formatted.contains('.') && formatted.endsWith('0')) {
    formatted = formatted.substring(0, formatted.length - 1);
  }
  if (formatted.endsWith('.')) {
    formatted = formatted.substring(0, formatted.length - 1);
  }
  return formatted;
}
