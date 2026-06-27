# Scroll boundary overscroll fix

## Implementation

- Added `CalTrackerScrollBehavior` in `apps/mobile/lib/app/theme.dart`.
  - `buildOverscrollIndicator` returns the child directly, disabling Material glow/stretch indicators globally.
  - `getScrollPhysics` returns `ClampingScrollPhysics`, removing bounce/stretch at scroll extents across platforms while preserving normal scrolling.
- Installed the behavior at the app root via `MaterialApp.router(scrollBehavior: const CalTrackerScrollBehavior())` in `apps/mobile/lib/app/app.dart`.
- Replaced the remaining explicit `BouncingScrollPhysics` uses in dashboard bottom-sheet/wizard scroll views with `ClampingScrollPhysics` so those screens do not bypass the global default.
- Added a widget test in `apps/mobile/test/app_bootstrap_lifecycle_test.dart` asserting the bootstrap uses `CalTrackerScrollBehavior` and clamps scroll physics.

## Files changed for this task

- `apps/mobile/lib/app/theme.dart`
- `apps/mobile/lib/app/app.dart`
- `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart`
- `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart`
- `apps/mobile/test/app_bootstrap_lifecycle_test.dart`

Note: this worktree already had other AMOLED/light-mode edits before this task; they were left in place.

## Validation

- `dart format lib/app/app.dart lib/app/theme.dart lib/ui/features/dashboard/views/calorie_target_sheet.dart lib/ui/features/dashboard/views/macro_distribution_sheet.dart test/app_bootstrap_lifecycle_test.dart` — passed. Initial run before `flutter pub get` warned about unresolved lint package, then formatting completed after dependencies were available.
- `flutter analyze` — passed, no issues found.
- `flutter test test/app_bootstrap_lifecycle_test.dart` — passed.
- `flutter test` — passed, all tests passed.

## Residual risks / notes

- I did not run device/emulator visual validation; automated Flutter analysis and widget tests passed.
- `graphify update .` was attempted after code changes, but graphify refused to overwrite the existing graph because the regenerated graph had fewer nodes than the existing graph (`15606` vs `15982`) and suggested `--force`. I did not force-overwrite the graph artifacts.
