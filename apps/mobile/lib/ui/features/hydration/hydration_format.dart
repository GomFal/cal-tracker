String formatHydrationLiters(double value) {
  final rounded = (value * 4).round() / 4;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

double roundHydrationLiters(double value) {
  return ((value * 4).round() / 4).clamp(0, 10).toDouble();
}
