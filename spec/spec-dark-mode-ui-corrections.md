# Dark Mode UI Corrections

## Goal

Bring the app's dark mode in line with the existing BetterCalories visual system: restrained, readable, and free of light-mode artifacts.

## Requirements

- Theme selection lives in Menu settings, not as a dashboard toggle.
- Theme options are: device default, light, and dark.
- Device default is selected when no saved preference exists.
- Dark surfaces use dark shadows only; no white or pale glow shadows.
- Water intake uses a darker cyan surface and contained teal accent in dark mode.
- Pale green accents in dark mode are darker and less saturated than the light palette.
- Settings, dashboard, and shared card components resolve visible text, surfaces, chips, and muted metadata from the active `FreshPalette`.

## Validation

- Widget tests cover the default theme mode, settings theme picker, and dashboard without the old toggle.
- Flutter analyze and targeted widget tests pass.
- The dev APK is installed on the Android emulator through ADB without running full E2E.
