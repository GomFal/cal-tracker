Files left unchanged. I did not create `reports/amoled-input-redesign-ux-audit.md` because the task explicitly says “do not edit files,” and the report-file request conflicts with that.

# AMOLED input redesign UX audit

## 1. Visual anti-patterns still present

- **Global filled pill inputs still define the app’s form language.** `apps/mobile/lib/app/theme.dart:157-181` sets `InputDecorationTheme` to filled `surfaceSoft` with 24px `OutlineInputBorder`. This means any plain `TextField` reverts to the old rounded-field system unless locally overridden.
- **Inputs were flattened around them, not migrated themselves.** Recent work removed many cards, but fields remain boxed/pill-like in saved editors, meal create, nutrition sheets, goal sheets, search, auth, and chat.
- **Quantity + unit are split into separate boxes.** Amount rows use a number field plus a separate unit field, producing mini form grids instead of one integrated value/unit control.
- **Stepper controls still look like buttons.** `-10g`, `+10g`, hydration plus/minus, and calorie target plus/minus are still outlined/circular button controls rather than inline text controls.
- **Macros are still individual fields, not a 3-column editorial grid.** Protein/carbs/fat are repeated as three boxed text inputs in nutrition edit, meal template editor, usual food editor, and macro distribution editor.
- **Search fields are heavy input pills.** Search uses prefix icons, suffix icon buttons, filled fields, and sometimes a parent `FreshCard`, rather than a simple row/search line.
- **Goal inputs still live inside panels.** Daily calories and hydration use `FreshCard`/nested surfaces around the central value.
- **One absolute-ban violation remains:** `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart:690` uses a 3px left border accent on the proposal success toast.
- **AMOLED tokens use pure black/white.** `apps/mobile/lib/ui/core/design_system.dart:8-16` defines `0xff000000` and `0xffffffff`; the design law asks for tinted near-neutrals, even for dark themes.

## 2. Screens/components likely affected

### Foundation
- `apps/mobile/lib/app/theme.dart:157-181`  
  Global filled rounded `InputDecorationTheme`.
- `apps/mobile/lib/ui/core/design_system.dart:8-18`, `374-413`  
  AMOLED palette, `FreshCard`, and legacy card affordances.

### Saved meal / saved ingredient editors
- `apps/mobile/lib/ui/features/meal_templates/views/meal_template_editor_screen.dart:347-366`  
  Template title/aliases still filled fields.
- `apps/mobile/lib/ui/features/meal_templates/views/meal_template_editor_screen.dart:569-704`  
  Ingredient name, amount, unit, calories, macro fields are still boxed/fill-based.
- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_editor_screen.dart:160-270`, `347-354`  
  Usual food identity, serving, macro, optional nutrient fields all route through generic `TextFormField` with global pill styling.

### Meal create / food search / proposal edit
- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart:527-557`  
  Manual draft ingredient name, quantity, unit fields.
- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart:972-1006`  
  Food search field still a filled search pill with prefix/suffix icons.
- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart:1818-1826`  
  Custom meal type field has prefix icon and pill styling.
- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart:2185-2212`  
  Proposal edit ingredient, quantity, unit fields.

### Shared editors / search
- `apps/mobile/lib/ui/shared/food_search_panel.dart:73-123`  
  Shared search is still a `FreshCard` with a filled field and result `FilledButton`s.
- `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart:323-439`  
  Edit ingredients sheet uses name field, quantity field, unit field, plus button steppers.
- `apps/mobile/lib/ui/shared/nutrition_edit_sheet.dart:168-273`  
  Calories and macros are still filled boxed fields.
- `apps/mobile/lib/ui/shared/nutrition_edit_components.dart:194-203`  
  Macro decoration helper still assumes `InputDecoration` label coloring rather than a real macro grid.

### Goals / settings
- `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart:101-139`  
  Daily calorie target is a `FreshCard` containing a central rounded field with `suffixText`.
- `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart:382-405`, `473-495`, `1105-1114`  
  Macro percentage/gram editors use grouped `surfaceSoft` containers and boxed number fields.
- `apps/mobile/lib/ui/features/settings/views/hydration_goal_sheet.dart:129-230`, `290-396`  
  Hydration goal uses segmented pill controls, `FreshCard`, nested value surface, and info card.

### Other relevant surfaces
- `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart:1118-1126`  
  Agent input bar still inherits filled input styling.
- `apps/mobile/lib/ui/features/auth/views/auth_screen.dart:84-121`  
  Auth fields retain prefix-icon pill inputs. Lower priority, but visually divergent from the editorial input system.

## 3. Recommended design system/tokens

Create a small input layer instead of continuing with raw `TextField` + `InputDecoration`.

Recommended components:

- `FreshUnderlineTextField`: label above, value on baseline, 1px underline, no fill, no rounded border.
- `FreshNumberUnitField`: value and unit share one baseline/underline; unit is text, not a separate field box.
- `FreshAmountStepper`: inline `−10g  150 g  +10g` text controls with large tap targets, no outlined mini buttons.
- `FreshMacroFields`: 3-column grid, each cell label + value + unit + underline. Protein/carbs/fat color only as a tiny label or focus accent.
- `FreshGoalInput`: large central number, unit integrated, subtle minus/plus controls beside or below, no card wrapper.
- `FreshSearchActionField`: search icon, query text, underline, right-side action text/icon. No pill, no parent card.

Token additions:

- `fieldLabel`, `fieldValue`, `fieldLine`, `fieldLineFocused`, `fieldLineError`
- `fieldGap`, `fieldRowHeight`, `sectionRule`, `inlineAction`
- Typography: 12px muted label, 18px field value, 40-52px goal number, tabular numeric figures.
- Color: keep AMOLED but replace pure `#000/#fff` with slightly tinted near-neutrals; use lime only for focus/action/selection.

## 4. Migration checklist by component

### TextField label + value + underline
- Replace global filled `InputDecorationTheme`.
- Migrate usual food editor fields.
- Migrate meal template title/aliases and ingredient name fields.
- Migrate manual/proposal ingredient name fields.
- Migrate auth only after product forms are done.

### NumberField / UnitInput
- Merge quantity + unit pairs in:
  - `MealItemEditorSheet`
  - manual meal create rows
  - proposal edit rows
  - meal template item rows
  - usual food serving grams
- Replace `suffixText` usage in calorie/macro fields with integrated unit text.

### AmountStepper
- Replace `_VoiceQuantityButton`, `_QuantityStepButton`, hydration round step buttons, and calorie target step buttons with inline text controls.
- Keep 44px tap targets via padding, not visible button chrome.

### MacroFields
- Migrate `NutritionEditSheet` first, since it is shared.
- Then migrate meal template item macros.
- Then usual food editor macros/optional nutrients.
- Then macro distribution percentage/gram editor.

### GoalInput
- Migrate `CalorieTargetSheet` daily calories card to flat central number.
- Migrate `HydrationGoalSheet` value control.
- Keep calculator wizard ruler screens mostly as-is, but remove card-like choice controls in a later pass if desired.

### SearchActionField
- Migrate `_FoodSearchBox` in meal create.
- Migrate shared `FoodSearchPanel`.
- Replace “Add from search” `OutlinedButton` collapsed states with a row action.
- Revisit agent chat input after search field vocabulary is stable.

## 5. Visual QA acceptance criteria

- No visible filled rounded input boxes on target form screens, except intentionally deferred auth.
- Field labels sit above values; values sit on a single underline.
- Focus changes underline color/thickness, not a glowing or filled border.
- Error state uses coral underline plus readable message.
- Quantity and unit read as one control, not two adjacent boxes.
- Macro editor reads as one 3-column grid.
- Goal editor has one dominant central number with quiet controls.
- Search reads as a row/line, not a pill or card.
- No parent `FreshCard` exists solely to hold a search field or form group.
- No colored side-stripe borders remain.
- Screens to visually inspect: new/edit usual food, new/edit saved meal, meal create manual search, proposal edit, edit ingredients sheet from dashboard/history, calorie target sheet, hydration goal sheet, macro distribution sheet, agent input bar.