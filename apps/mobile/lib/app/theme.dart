import 'package:flutter/material.dart';

import '../ui/core/design_system.dart';

class CalTrackerScrollBehavior extends MaterialScrollBehavior {
  const CalTrackerScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

ThemeData buildTheme() => buildLightTheme();

ThemeData buildLightTheme() {
  const palette = FreshPalette.light;
  return _buildFreshTheme(
    brightness: Brightness.light,
    palette: palette,
    colorScheme: ColorScheme.light(
      primary: palette.lime,
      onPrimary: palette.ink,
      primaryContainer: palette.limeSoft,
      onPrimaryContainer: palette.ink,
      secondary: palette.water,
      onSecondary: palette.surface,
      secondaryContainer: palette.limeWash,
      onSecondaryContainer: palette.ink,
      surface: palette.surface,
      onSurface: palette.ink,
      surfaceContainerHighest: palette.surfaceSoft,
      error: palette.coral,
      onError: palette.surface,
      errorContainer: const Color(0xffffe5e8),
      onErrorContainer: palette.ink,
      outline: palette.rule,
      outlineVariant: palette.ruleSoft,
    ),
  );
}

ThemeData buildDarkTheme() {
  const palette = FreshPalette.dark;
  return _buildFreshTheme(
    brightness: Brightness.dark,
    palette: palette,
    colorScheme: ColorScheme.dark(
      primary: palette.lime,
      onPrimary: const Color(0xff061000),
      primaryContainer: palette.limeSoft,
      onPrimaryContainer: palette.ink,
      secondary: palette.water,
      onSecondary: const Color(0xff061000),
      secondaryContainer: palette.limeWash,
      onSecondaryContainer: palette.ink,
      surface: palette.surface,
      onSurface: palette.ink,
      surfaceContainerHighest: palette.surfaceSoft,
      error: palette.coral,
      onError: const Color(0xff1d0307),
      errorContainer: const Color(0xff321016),
      onErrorContainer: palette.ink,
      outline: palette.rule,
      outlineVariant: palette.ruleSoft,
    ),
  );
}

ThemeData _buildFreshTheme({
  required Brightness brightness,
  required FreshPalette palette,
  required ColorScheme colorScheme,
}) {
  final textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w700,
      height: 1.16,
      letterSpacing: 0,
      color: palette.ink,
    ),
    headlineLarge: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      height: 1.14,
      letterSpacing: 0,
      color: palette.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.16,
      letterSpacing: 0,
      color: palette.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.18,
      letterSpacing: 0,
      color: palette.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0,
      color: palette.ink,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.35,
      letterSpacing: 0,
      color: palette.inkSoft,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.35,
      letterSpacing: 0,
      color: palette.inkSoft,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0,
      color: palette.ink,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1,
      letterSpacing: 0,
      color: palette.inkMuted,
    ),
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: palette.screen,
    fontFamily: 'SF Pro Text',
    fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
    textTheme: textTheme,
    useMaterial3: true,
    extensions: <ThemeExtension<dynamic>>[
      palette,
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: palette.screen,
      foregroundColor: palette.ink,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.18,
        letterSpacing: 0,
        color: palette.ink,
        fontFamily: 'SF Pro Display',
        fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceSoft,
      labelStyle: TextStyle(color: palette.inkMuted),
      hintStyle: TextStyle(color: palette.inkMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: palette.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: palette.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: palette.lime, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: palette.coral),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: palette.coral, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      color: palette.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.rule),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.lime,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: brightness == Brightness.dark
            ? palette.surfaceSoft
            : palette.surfaceMuted,
        disabledForegroundColor: palette.inkMuted,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.rule),
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.ink,
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.ink,
        backgroundColor: Colors.transparent,
        shape: const CircleBorder(),
        side: BorderSide(color: palette.rule),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.screen,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: palette.rule),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.screen,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: palette.rule),
      ),
    ),
  );
}
