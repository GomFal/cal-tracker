# Settings / History UI cleanup implementation report

## Summary

Finalized the scoped AMOLED cleanup for Settings and History after the async worker exceeded its token budget before committing.

## Files changed

- `apps/mobile/lib/ui/features/settings/views/settings_screen.dart`
- `apps/mobile/lib/ui/features/meal_history/views/meal_history_screen.dart`

## What changed

- Converted Settings from stacked `FreshCard` blocks to a lighter open layout: textual user header, full-width setting rows, subtle dividers, section spacing, and flatter developer/data-source sections.
- Converted History calorie chart from a bordered card into an open section with top/bottom rules.
- Converted History meal cards into rows without decorative leading icon chips and made sheet actions flat rule-separated rows instead of `FreshCard` actions.

## Validation

- `cd apps/mobile && flutter pub get` — passed; restored package resolution for this worktree.
- `cd apps/mobile && dart format lib/ui/features/settings/views/settings_screen.dart lib/ui/features/meal_history/views/meal_history_screen.dart` — passed.
- `cd apps/mobile && flutter analyze --no-pub` — ran; reports only the pre-existing unrelated info `lib/app/theme.dart:244:23 prefer_const_constructors`.
- `cd apps/mobile && flutter test --no-pub test/settings_language_widget_test.dart test/dashboard_cleanup_widget_test.dart` — passed, 23 tests.
- `git diff --check` — passed.
- `graphify update .` — attempted after edits; see `/tmp/amoled-settings-graphify.log` for tool output if needed.

## Residual risks

- Manual emulator/Marionette visual validation was not run.
- Full analyze still reports the existing out-of-scope `theme.dart` info, intentionally left untouched.
