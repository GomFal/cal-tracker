# Saved editors UI cleanup implementation report

## Summary

- Converted the saved ingredient editor sections from boxed cards to open form sections with plain titles, direct fields, and dividers.
- Converted the saved meal editor details, ingredient item blocks, and save summary from stacked surface cards to flat section/form rows.
- Reworked nutrition-label scanner state messaging from white/red Material cards to dark translucent HUD panels with camera-friendly controls.

## Files changed

- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_editor_screen.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/meal_template_editor_screen.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_scan_screen.dart`
- `apps/mobile/test/features/meal_templates/usual_food_scan_screen_test.dart`
- `apps/mobile/test/meal_template_editor_widget_test.dart`
- `apps/mobile/test/meal_templates_widget_test.dart`

## Validation

- `cd apps/mobile && flutter pub get` — passed; generated local package config needed for this worktree.
- `cd apps/mobile && flutter analyze --no-pub` — failed on pre-existing unrelated `prefer_const_constructors` info in `lib/app/theme.dart:244:23`.
- `cd apps/mobile && flutter analyze --no-pub lib/ui/features/meal_templates/views/usual_food_editor_screen.dart lib/ui/features/meal_templates/views/meal_template_editor_screen.dart lib/ui/features/meal_templates/views/usual_food_scan_screen.dart test/meal_template_editor_widget_test.dart test/meal_templates_widget_test.dart test/features/meal_templates/usual_food_scan_screen_test.dart` — passed, no issues.
- `cd apps/mobile && flutter test --no-pub test/meal_template_editor_widget_test.dart test/meal_templates_widget_test.dart test/features/meal_templates/usual_food_scan_screen_test.dart` — passed, 31 tests.
- `git diff --check` — passed.

## Notes

- Routes, field keys, save/delete/scan behavior, and repository/view-model logic were preserved.
- No backend, Settings, History, voice, or agent files were edited.
- No food parsing or ingredient inference logic was changed.
- `graphify update .` was attempted but refused to overwrite the existing graph because the regenerated graph had fewer nodes than the checked-in graph.
