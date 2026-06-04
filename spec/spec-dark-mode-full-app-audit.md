# Dark Mode Full App Audit

## Goal

Ensure every Flutter UI surface follows the active theme palette in dark mode,
including auth, create meal, manual food search, shared food search, meal item
editing, habituals, dashboard, history, settings, dialogs, and bottom sheets.

## Implementation Notes

- Feature and shared UI code must use `context.freshPalette` or
  `Theme.of(context).colorScheme` for visible colors.
- `FreshColors.*` is limited to design-system/theme definitions and must not be
  used directly in feature screens.
- `Colors.white` and `Colors.black` are not allowed in feature UI; use palette
  surfaces/ink and alpha-adjusted palette shadows instead.
- Explicit `Color(...)` constants outside the design system are allowed only
  where a widget intentionally chooses paired light/dark values in the same
  code path.

## Reviewed Surfaces

- Auth/login route
- App shell and central voice action
- Create meal flow, manual add-food search, food matches, proposal editor,
  nutrition editor, and meal label sheet
- Shared `FoodSearchPanel` and `MealItemEditorSheet`
- Dashboard, water intake, calorie target, macro distribution, and hydration
  goal surfaces
- History list, action sheet, delete dialog, and edit ingredients sheet
- Usual meals/ingredients list and editors
- Settings, language/theme sheets, and update dialog theme inheritance

## Acceptance Criteria

- `flutter analyze` passes.
- Flutter tests include dark-mode coverage for auth, habituals, create meal,
  dashboard, settings, and static color usage.
- APK can be built and installed on the physical ADB device with local backend
  forwarding.
