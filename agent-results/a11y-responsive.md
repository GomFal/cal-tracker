# A11y / responsive / i18n batch result

## Initial status

Registered `git status --short` before edits. Worktree already had many dirty AMOLED changes, including `voice_log_screen.dart`; I did not edit `voice_log_screen.dart`.

## Changes made

- `apps/mobile/lib/ui/core/app_shell.dart`
  - Added explicit `Semantics` to bottom/side navigation buttons with button role, selected state, label, and tap action.
  - Added explicit semantics to the global bottom agent/mic button with button role, tap action, localized label, and recording value.
- `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart`
  - Added slider semantics to the custom painted height/weight ruler, including label, current value, increased/decreased values, and increment/decrement actions.
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`
  - When dashboard load fails with no visible/cached summary, suppresses calorie/macro/water/meal sections so default fallback values are not presented as real data.
- `apps/mobile/lib/ui/features/meal_templates/widgets/scan_viewfinder_overlay.dart`
  - Added semantics for the canvas-painted nutrition-label frame and hint.
- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_scan_screen.dart`
  - Added semantics for the OCR crop selector using existing localized scan labels/hints.
- Tests updated:
  - `apps/mobile/test/bottom_mic_bubble_widget_test.dart`
  - `apps/mobile/test/calorie_calculator_wizard_test.dart`
  - `apps/mobile/test/dashboard_cleanup_widget_test.dart`

No new user-visible strings were added, so ARB/generation was not required for this batch.

## Commands run

- `pwd && git status --short` — passed; recorded starting dirty worktree.
- Read spec: `sed -n '1,240p' /home/antonio/code/cal-tracker/spec/flutter-technical-debt/spec-design-flutter-accessibility-responsive.md` — passed.
- `cd apps/mobile && dart format ...` — passed.
- `cd apps/mobile && flutter analyze` — passed, `No issues found!`.
- `cd apps/mobile && flutter test test/bottom_mic_bubble_widget_test.dart test/dashboard_cleanup_widget_test.dart test/calorie_calculator_wizard_test.dart` — passed, `All tests passed!`.
- `cd apps/mobile && flutter test test/features/meal_templates/usual_food_scan_screen_test.dart` — passed, `All tests passed!`.
- `graphify update .` — failed safely; graphify refused to overwrite because the new graph had fewer nodes than the existing graph (`15660` vs `15982`). No force update attempted.

## Risks / notes

- `progress.md` is outside the isolated worktree cwd, so I did not modify it to satisfy the stop rule.
- Existing dirty files outside this batch remain dirty; notably `voice_log_screen.dart` was pre-existing dirty and was not touched.
- Dart format caused style-only churn in touched dirty files; functional changes are limited to the bullets above.
