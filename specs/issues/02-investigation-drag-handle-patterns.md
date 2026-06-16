# Drag handle & bottom sheet dismissal — Investigation

Scope: `/home/antonio/code/cal-tracker/apps/mobile/lib`.
Date: 2026-06-15.
Flutter toolchain: 3.41.9 / Dart 3.11.5 (verified via `flutter --version`).

This document only **documents findings**. It does not propose or evaluate fixes.

---

## 1. Ripgrep inventory of bottom-sheet APIs

| API | Hits | Notes |
| --- | --- | --- |
| `DraggableScrollableSheet` | 0 | Not used anywhere in the app. |
| `showModalBottomSheet` | 23 (across 8 files) | Only entry point used to open sheets. |
| `showBottomSheet` | 0 | Never used. |
| `BottomSheet(` (raw widget) | 0 | Never used. |
| `enableDrag` | 0 | Never passed explicitly; relies on default `true`. |
| `barrierDismissible` | 0 | Never passed explicitly; relies on default `true`. |
| `isScrollControlled` | 19 (17 callers) | Always `true` for the result-bearing sheets. |
| `useRootNavigator` | 5 (2 files) | `calorie_target_sheet.dart:179, 188, 268` and `macro_distribution_sheet.dart:150`. Used only when the calculator/macro sub-sheets are stacked. |
| `useSafeArea` | 19 (8 files) | Almost always `true` on the wrapper `showModalBottomSheet` call. |
| `dragHandle` / `drag_handle` / `drag handle` | 0 | The string does not appear. The app draws a custom 44×4 pill `Container`. |
| `BottomSheetDragHandle` (Flutter widget) | 0 | Native drag handle widget never used. |
| `showDragHandle` (Flutter API) | 0 | Native showDragHandle flag never used. |
| `onVerticalDrag` / `onPanUpdate` / `onPanEnd` | 0 | No custom drag-to-dismiss gesture handler. |
| `NotificationListener<…>` | 0 | No overscroll/scroll-based dismissal. |
| `ScrollController` (non-`FixedExtent`) | 0 | No programmatic scroll-position logic. |

The `width: 44, height: 4` pill (the "handle") is duplicated in **every** sheet that wants one — 14 occurrences across 8 files. Search anchor: `grep "width: 44" lib --include="*.dart"`.

The bottom-sheet theme is centralized in `lib/app/theme.dart:235` (see §6).

---

## 2. Per-sheet inventory

Every sheet in the project is a `showModalBottomSheet` (no `DraggableScrollableSheet`, no `showBottomSheet`, no raw `BottomSheet` widget). The list below is exhaustive — it covers all 23 call sites plus the 2 nested pop-ups opened from inside sheets.

### 2.1 Wrapper call sites

| # | File:line | Result type | `isScrollControlled` | `useSafeArea` | `useRootNavigator` | `enableDrag` / `barrierDismissible` | Builder widget |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `voice_log_screen.dart:188` | `List<MealItem>` | `true` | _default_ | _default_ | _default / default_ | `_ProposalEditorSheet` |
| 2 | `voice_log_screen.dart:204` | `_MealLabelSelection` | `true` | `true` | _default_ | _default_ | `_MealLabelSheet` |
| 3 | `voice_log_screen.dart:409` | `NutritionEdit` | `true` | _default_ | _default_ | _default_ | `NutritionEditSheet` (with `useSafeArea: true`) |
| 4 | `voice_log_screen.dart:2125` | `NutritionEdit` | `true` | _default_ | _default_ | _default_ | `NutritionEditSheet` (with `useSafeArea: true`) |
| 5 | `dashboard_screen.dart:100` | `List<MealItem>` | `true` | `true` | _default_ | _default_ | `MealItemEditorSheet` |
| 6 | `dashboard_screen.dart:154` | `CalorieTargetSelection` | `true` | `true` | _default_ | _default_ | `CalorieTargetSheet` |
| 7 | `dashboard_screen.dart:186` | `bool` | _default_ | `true` | _default_ | _default_ | `PostCalorieSaveMacroPrompt` |
| 8 | `dashboard_screen.dart:194` | `MacroDistributionConfig` | `true` | `true` | _default_ | _default_ | `MacroDistributionSheet` |
| 9 | `calorie_target_sheet.dart:175` | `CalorieEstimate` | `true` | `true` | `true` | _default_ | `CalorieCalculatorWizard` |
| 10 | `calorie_target_sheet.dart:185` | `MacroDistributionConfig` | `true` | `true` | `true` | _default_ | `_CalculatorMacroPrompt` |
| 11 | `calorie_target_sheet.dart:264` | `MacroDistributionConfig` | `true` | `true` | `true` | _default_ | `MacroDistributionSheet(presetOnly: true)` |
| 12 | `macro_distribution_sheet.dart:146` | `MacroDistributionConfig` | `true` | `true` | `true` | _default_ | `_PersonalizedMacroSheet` |
| 13 | `settings_screen.dart:190` | `double` | `true` | `true` | _default_ | _default_ | `HydrationGoalSheet` |
| 14 | `settings_screen.dart:209` | `CalorieTargetSelection` | `true` | `true` | _default_ | _default_ | `CalorieTargetSheet` |
| 15 | `settings_screen.dart:232` | `bool` | _default_ | `true` | _default_ | _default_ | `PostCalorieSaveMacroPrompt` |
| 16 | `settings_screen.dart:255` | `bool` | _default_ | `true` | _default_ | _default_ | `_MacroRequiresCaloriesSheet` |
| 17 | `settings_screen.dart:271` | `MacroDistributionConfig` | `true` | `true` | _default_ | _default_ | `MacroDistributionSheet` |
| 18 | `settings_screen.dart:347` | `void` | _default_ | `true` | _default_ | _default_ | Theme mode sheet (inline) |
| 19 | `settings_screen.dart:412` | `void` | _default_ | `true` | _default_ | _default_ | Language sheet (inline) |
| 20 | `meal_history_screen.dart:103` | `String` | _default_ | _default_ | _default_ | _default_ | Inline action sheet (`SafeArea` inside builder) |
| 21 | `meal_history_screen.dart:150` | `List<MealItem>` | `true` | `true` | _default_ | _default_ | `MealItemEditorSheet` |
| 22 | `meal_item_editor_sheet.dart:503` | `NutritionEdit` | `true` | `true` | _default_ | _default_ | `NutritionEditSheet` (with `useSafeArea: false`) |

### 2.2 Per-sheet classification (what's inside the builder)

Legend:
- **Handle**: a `Container(width: 44, height: 4, decoration: BoxDecoration(color: palette.rule, borderRadius: BorderRadius.circular(999)))` inside `Center`.
- **Body container**: top-level widget of the sheet body.
- **Scrollable around handle**: whether the handle is **descended from** a `SingleChildScrollView` / `ListView` / `CustomScrollView` / `NestedScrollView`.

| Sheet | File:line of handle | Body container | Scrollable around handle? | Height strategy | `useSafeArea` (in builder)? |
| --- | --- | --- | --- | --- | --- |
| `MealItemEditorSheet` (HOME bug) | `meal_item_editor_sheet.dart:67-76` | `DecoratedBox → Padding → SingleChildScrollView → Column` | **YES** (handle is the first child of the `SingleChildScrollView` at line 62) | intrinsic (`mainAxisSize: min`) inside a `SingleChildScrollView` | n/a (caller uses `useSafeArea: true`) |
| `NutritionEditSheet` (HOME bug, nested) | `nutrition_edit_sheet.dart:135-144` | `Padding → SingleChildScrollView → Column` | **YES** (handle is the first child of the `SingleChildScrollView` at line 130) | intrinsic inside a `SingleChildScrollView` | caller toggles per use (e.g. `meal_item_editor_sheet.dart:506` `useSafeArea: true`, `voice_log_screen.dart:429,2145` `useSafeArea: true`) |
| `_ProposalEditorSheet` (voice log) | `voice_log_screen.dart:2034-2043` | `SafeArea → Padding → SingleChildScrollView → Column` | **YES** (handle is inside the `SingleChildScrollView` at line 2030) | intrinsic inside a `SingleChildScrollView` | n/a (`SafeArea` is built into the sheet) |
| `CalorieTargetSheet` (good reference) | `calorie_target_sheet.dart:80-89` | `Padding → SizedBox(height: 0.86·screen) → Column` (no scrollable) | **NO** | fixed `MediaQuery.sizeOf(context).height * 0.86` | n/a |
| `_CalculatorMacroPrompt` (good reference) | `calorie_target_sheet.dart:236-245` | `Padding → Column` (no scrollable) | **NO** | intrinsic | n/a |
| `PostCalorieSaveMacroPrompt` (good reference) | `calorie_target_sheet.dart:309-318` | `Padding → Column` (no scrollable) | **NO** | intrinsic | n/a |
| `CalorieCalculatorWizard` | _no handle_ | `Material → AnimatedPadding → SizedBox(height: 0.94·screen) → Column` | n/a | fixed height | n/a (uses internal `_WizardTopBar` for navigation) |
| `MacroDistributionSheet` (good reference) | `macro_distribution_sheet.dart:64-73` | `Material → Padding → SizedBox(height: 0.9·screen) → Column` (scrollable is `Expanded(child: SingleChildScrollView)` **below** the handle) | **NO** (handle is sibling of the `Expanded`/`SingleChildScrollView`, not a descendant) | fixed `MediaQuery.sizeOf(context).height * 0.9` | n/a |
| `_PersonalizedMacroSheet` (good reference) | `macro_distribution_sheet.dart:311-320` | `Material → Padding → SizedBox(height: 0.9·screen) → Column` (scrollable is `Expanded(child: SingleChildScrollView)` **below** the handle) | **NO** | fixed `0.9·screen` | n/a |
| `_MealLabelSheet` (good reference) | `voice_log_screen.dart:1804-1813` | `Padding → Column(mainAxisSize: min)` (no scrollable) | **NO** | intrinsic | n/a |
| Inline action sheet (history) | `meal_history_screen.dart:110-118` | `SafeArea → Padding → Column(mainAxisSize: min)` (no scrollable) | **NO** | intrinsic | n/a (inline `SafeArea` inside builder) |
| `_MacroRequiresCaloriesSheet` (good reference) | `settings_screen.dart:568-577` | `Padding → Column(mainAxisSize: min)` (no scrollable) | **NO** | intrinsic | n/a |
| Theme mode sheet (inline) | `settings_screen.dart:359-368` | `Padding → Column(mainAxisSize: min)` (no scrollable) | **NO** | intrinsic | n/a |
| Language sheet (inline) | `settings_screen.dart:424-433` | `Padding → Column(mainAxisSize: min)` (no scrollable) | **NO** | intrinsic | n/a |
| `HydrationGoalSheet` (good reference) | `hydration_goal_sheet.dart:52-61` | `Padding → SizedBox(height: 0.86·screen) → Column` (no scrollable) | **NO** | fixed `0.86·screen` | n/a |

### 2.3 Dismissal wiring (none of the sheets wire their own dismissal)

- **No sheet passes `enableDrag: false`.** All of them implicitly use the Flutter default `true` for the modal route, so the modal route's drag-to-dismiss gesture should fire from any point **above** the sheet body. There is no per-sheet opt-out.
- **No sheet uses `onDismiss` / `barrierColor` / `barrierLabel`** — defaults apply.
- **No sheet uses `DraggableScrollableSheet`**, so no `initialChildSize` / `minChildSize` / `maxChildSize` / `snap` / `expand` configuration exists.
- **No sheet installs a custom `NotificationListener`, `ScrollController`, or `onVerticalDrag` handler** to manually pop on overscroll.
- **No sheet wraps the handle in a `GestureDetector`**. The handle is a bare `Container` inside a `Center` (or a `Column` whose `crossAxisAlignment` is `stretch`, with the `Container` being the only child of a `Center`).

The only programmatic dismissal paths in the sheets are the **action button `onPressed: () => Navigator.of(context).pop(...)`** calls (e.g. `meal_item_editor_sheet.dart:217`, `nutrition_edit_sheet.dart:342`).

---

## 3. The good pattern (handle works, drag-to-dismiss fires)

Two concrete exemplars. In all good sheets the handle is **outside** every scrollable, so vertical drag from the handle region is interpreted by the modal route's drag-to-dismiss recognizer.

### 3.1 `MacroDistributionSheet` — fixed-height sheet with scrollable area below the handle

`lib/ui/features/dashboard/views/macro_distribution_sheet.dart:60-119`:

```dart
return Material(
  color: palette.screen,
  child: Padding(
    padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,    // line 63 — fixed 90% of screen
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(                               // line 66 — handle
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text(widget.title ?? l10n.macroSheetTitle, ...),
          ...
          Expanded(                                          // line 90 — scrollable is BELOW the handle
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(...),
            ),
          ),
          const SizedBox(height: FreshSpacing.md),
          FilledButton(...),
        ],
      ),
    ),
  ),
);
```

Key observations:
- The `Column` is the **direct child of a `SizedBox(height: 0.9·screen)`** — its height is fixed and finite. A vertical drag that starts in the handle region ends inside the sheet's flex layout, not in a scrollable, so the modal route's drag-to-dismiss gesture wins.
- The `SingleChildScrollView` is wrapped in `Expanded`, so it only occupies the space below the handle. The handle itself is not scrollable content.

The identical pattern is repeated in `_PersonalizedMacroSheet` (`macro_distribution_sheet.dart:307-368`): `SizedBox(height: 0.9·screen) → Column → [handle, …, Expanded(SingleChildScrollView)]`.

### 3.2 `CalorieTargetSheet` — fixed-height sheet with no scrollable at all

`lib/ui/features/dashboard/views/calorie_target_sheet.dart:74-153`:

```dart
return Padding(
  padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
  child: SizedBox(
    height: maxHeight,                                     // line 76 — fixed maxHeight
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(                                 // line 80 — handle
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: palette.rule,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: FreshSpacing.lg),
        Text(l10n.calorieTargetSheetTitle, ...),
        ...
        FreshCard(...),                                     // static card with the number field
        ...
        FilledButton(...),
      ],
    ),
  ),
);
```

Key observations:
- The whole body is a non-scrollable `Column` inside a `SizedBox(height: 0.86·screen)`.
- There is **no** `SingleChildScrollView` / `ListView` anywhere in this sheet's body. The drag handle is therefore the topmost tappable / draggable widget in the sheet, and the modal route owns the gesture.

`_CalculatorMacroPrompt` (`calorie_target_sheet.dart:230-289`) and `PostCalorieSaveMacroPrompt` (`calorie_target_sheet.dart:301-360`) are simpler variants of the same pattern (`Padding → Column(mainAxisSize: min)` with no scrollable).

### 3.3 Other non-scrollable handles (all good)

- `voice_log_screen.dart:1804-1813` (`_MealLabelSheet`) — `Padding → Column(mainAxisSize: min)`, no scrollable.
- `meal_history_screen.dart:110-118` (inline action sheet) — `SafeArea → Padding → Column(mainAxisSize: min)`, no scrollable.
- `settings_screen.dart:568-577` (`_MacroRequiresCaloriesSheet`) — `Padding → Column(mainAxisSize: min)`, no scrollable.
- `settings_screen.dart:359-368` (theme sheet) and `:424-433` (language sheet) — `Padding → Column(mainAxisSize: min)`, no scrollable.
- `hydration_goal_sheet.dart:52-61` (`HydrationGoalSheet`) — `Padding → SizedBox(height: 0.86·screen) → Column`, no scrollable.

---

## 4. The suspect sheets (handle is broken — drag-to-dismiss does not fire)

The bug is structural: in three sheets the handle is a **direct child of a `SingleChildScrollView`**, so a vertical drag starting on the handle is delivered to the scrollable's gesture recognizer, which consumes it as a scroll gesture (and at the top of the list there is nothing to overscroll, so the modal route never gets the drag).

### 4.1 `MealItemEditorSheet` — primary suspect (the HOME "Edit Ingredients" sheet)

`lib/ui/shared/meal_item_editor_sheet.dart:55-79`:

```dart
return DecoratedBox(                                        // line 55
  decoration: BoxDecoration(color: palette.surfaceSoft),
  child: Padding(
    padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
    child: SingleChildScrollView(                           // line 62 — handle is a child of this
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(                               // line 67 — handle INSIDE scrollable
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: context.freshPalette.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text(l10n.commonEditIngredients, style: textTheme.titleLarge),
          ...
        ],
      ),
    ),
  ),
);
```

Why the drag does not close the sheet:
- The `Column` is a child of `SingleChildScrollView`. The `Column` has `mainAxisSize: MainAxisSize.min`, so its intrinsic height is the sum of its children, but the `SingleChildScrollView` claims all the gesture arena for vertical drags inside its hit area, including the 4-pixel-tall `Container` at the top.
- The modal route's drag-to-dismiss gesture is only invoked when a drag is not consumed by a deeper recognizer. With the handle sitting inside the scrollable, dragging down on the handle is treated as "start of scroll" — the scrollable is at the top of its content, so nothing visible happens, and the sheet stays open.
- This sheet is invoked by `_showMealItemEditor` from two callers that both pass `useSafeArea: true`:
  - `dashboard_screen.dart:100-109` — the **Home screen** "Edit ingredients" entry.
  - `meal_history_screen.dart:150-159` — the History screen's "Edit ingredients" entry.
- There is no `NotificationListener`, no `ScrollController`, no `GestureDetector` around the handle, and no `DraggableScrollableSheet` — confirmed via §1 inventory.

### 4.2 `NutritionEditSheet` — secondary suspect (the nested "Edit nutrition" sheet)

`lib/ui/shared/nutrition_edit_sheet.dart:127-147`:

```dart
final content = Padding(
  padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
  child: SingleChildScrollView(                            // line 130 — handle is a child of this
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Drag handle
        Center(
          child: Container(                                 // line 135 — handle INSIDE scrollable
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: palette.rule,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: FreshSpacing.lg),
        Text(widget.title, style: textTheme.titleLarge),
        ...
      ],
    ),
  ),
);
```

Same structural defect as 4.1. The `NutritionEditSheet` is opened from three call sites:
- `meal_item_editor_sheet.dart:503-521` (per-item "Edit details" inside the HOME editor — also affected by the same bug if the user opens it).
- `voice_log_screen.dart:409-433` (per-row "Edit nutrition" in the manual draft).
- `voice_log_screen.dart:2125-2149` (per-row "Edit nutrition" in the proposal editor).

Note: this sheet is the only one in the project that has an explicit `// Drag handle` comment (`nutrition_edit_sheet.dart:135`), confirming the author was aware the pill is a drag handle but did not connect it to dismissal.

### 4.3 `_ProposalEditorSheet` — tertiary suspect (the voice-log proposal editor)

`lib/ui/features/voice_log/views/voice_log_screen.dart:2023-2076`:

```dart
return SafeArea(
  child: Padding(
    padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
    child: SingleChildScrollView(                           // line 2030 — handle is a child of this
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(                               // line 2034 — handle INSIDE scrollable
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.rule,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text('Edit ingredients', style: textTheme.titleLarge),
          ...
        ],
      ),
    ),
  ),
);
```

Identical defect to 4.1 and 4.2. The comment "Edit ingredients" at line 2045 is the exact same string the user reaches from the Home "Edit Ingredients" entry — these are two functionally identical sheets, both broken.

---

## 5. Key differences between good and bad sheets

| Aspect | Good sheets (e.g. `MacroDistributionSheet`, `CalorieTargetSheet`) | Bad sheets (`MealItemEditorSheet`, `NutritionEditSheet`, `_ProposalEditorSheet`) |
| --- | --- | --- |
| Top-level body | `Padding → SizedBox(fixed height) → Column` or `Padding → Column(mainAxisSize: min)` | `DecoratedBox/Padding/SafeArea → SingleChildScrollView → Column(mainAxisSize: min)` |
| Drag handle widget | `Container(width: 44, height: 4, decoration: …)` | Identical `Container(width: 44, height: 4, decoration: …)` |
| Drag handle's parent | `Center` that is a direct child of the body `Column` | `Center` that is a child of the body `Column`, which is in turn a child of `SingleChildScrollView` |
| Vertical drag starting on the handle | Consumed by the modal route's drag-to-dismiss gesture (no scrollable above it). | Consumed by the `SingleChildScrollView` as a scroll gesture; the modal route never gets the drag because the scrollable wins the gesture arena. |
| Height strategy | Fixed (`0.86·screen` / `0.9·screen`) or intrinsic. Scrolling, if any, is in an `Expanded(SingleChildScrollView)` placed **below** the handle. | Intrinsic inside an unbounded `SingleChildScrollView`. The handle is part of the scrollable content. |
| `useRootNavigator` | Used for stacked sub-sheets (calculator / macro prompts). | Not used at all. |
| `useSafeArea` (caller) | `true` everywhere. | `true` everywhere — the bug is not in the safe-area handling. |
| `isScrollControlled` | `true` for the result-bearing sheets. | `true` for the result-bearing sheets — also not the source of the bug. |
| Custom dismissal | None. | None. |
| `DraggableScrollableSheet` | Not used. | Not used. |
| `onVerticalDrag` / `NotificationListener` / `GestureDetector` on the handle | None. | None. |
| Theme for `bottomSheetTheme` | Centralized `BottomSheetThemeData` in `lib/app/theme.dart:235` with `BorderRadius.vertical(top: Radius.circular(28))`. | Same theme applies. The route is rendered with the standard Material modal-sheet shape, so the drag-to-dismiss area is the whole sheet body — but the gesture is preempted by the `SingleChildScrollView`. |

### Root cause (observed, not prescribed)

In the three bad sheets, the `SingleChildScrollView` is the **outermost** scrollable. It claims the gesture arena for any vertical drag inside its hit area. The drag handle sits inside it, so the modal route's drag-to-dismiss gesture is never reached for drags that start on the handle.

In the good sheets, the body is either a fixed-height `Column` (no scrollable) or a `Column` whose only scrollable is `Expanded` and placed **below** the handle. There the modal route's gesture is the only one competing for the drag, so it fires.

---

## 6. Related infrastructure

- `lib/app/theme.dart:235` — `BottomSheetThemeData` only sets `backgroundColor`, `surfaceTintColor`, and the rounded-top shape. It does **not** configure `showDragHandle`, `modalDragHandle`, or any drag-related knob.
- `lib/ui/core/shell_modal_lock.dart` — `ShellModalLockController` tracks `PopupRoute` instances and notifies a listener (`ShellModalLockObserver`) so the shell can disable user-scrolling between branches while a sheet is open. It does not touch the sheet's drag-to-dismiss behaviour.
  - Controller: `lib/ui/core/shell_modal_lock.dart:3-39`.
  - Observer: `lib/ui/core/shell_modal_lock.dart:41-69`.
  - It is wired into the `GoRouter` in `lib/app/router.dart:9, 21-23` and used by `SlidingBranchContainer` via `userScrollEnabled: !modalLockController.isLocked` (`lib/app/router.dart:39-49`).
  - Effect: the only thing this controller does is prevent the bottom tab switcher from being swipeable while a sheet is on top. It does not affect the sheet's own drag-to-dismiss.
- `lib/ui/core/app_shell.dart` is not involved in sheet dismissal.

---

## 7. Open questions / things to confirm

- The Flutter 3.41.9 `showModalBottomSheet` API supports `showDragHandle: true` (since 3.10) and `BottomSheetThemeData.showDragHandle` (since 3.16). The project does not use either feature. The custom 44×4 `Container` is the only "handle" anywhere.
- No `DraggableScrollableSheet` is used, so there is no `initialChildSize` / `minChildSize` / `maxChildSize` / `snap` / `expand` configuration in the codebase to compare against.
- No widget tests or Patrol tests reference the drag handle (verified with `grep "drag" test/ --include="*.dart"` — no matches).
- The `MealItemEditorSheet` is opened from the Home dashboard via `dashboard_screen.dart:100-109` (`_showMealItemEditor`), and from the Meal History screen via `meal_history_screen.dart:150-159` (`_showMealItemEditor`). Both call sites use the same `MealItemEditorSheet` widget and pass `useSafeArea: true`. The "Home" entry the user reports as broken is the dashboard call site.
- The `NutritionEditSheet` is reached from inside `MealItemEditorSheet` (`meal_item_editor_sheet.dart:503-521`) via the per-item "Edit details" button, with `useSafeArea: false` passed to the sheet. The drag-handle problem still applies because the same `SingleChildScrollView` is used.

---

## 8. Quick navigation table (for the implementation agent)

| Need to look at | File | Why |
| --- | --- | --- |
| See the buggy pattern (the one the user is hitting) | `lib/ui/shared/meal_item_editor_sheet.dart:55-79` | `SingleChildScrollView` is the body; handle is a child of it. |
| See the same bug, nested | `lib/ui/shared/nutrition_edit_sheet.dart:127-147` | Same structure, opened as a child sheet. |
| See the third instance | `lib/ui/features/voice_log/views/voice_log_screen.dart:2023-2076` | Voice-log proposal editor, same structure. |
| See the working pattern (fixed-height) | `lib/ui/features/dashboard/views/macro_distribution_sheet.dart:60-119` | `SizedBox(height: 0.9·screen) → Column → [handle, …, Expanded(SingleChildScrollView)]`. |
| See the working pattern (no scrollable at all) | `lib/ui/features/dashboard/views/calorie_target_sheet.dart:74-153` | `SizedBox(height: 0.86·screen) → Column`, no `SingleChildScrollView` in the body. |
| Confirm theme defaults | `lib/app/theme.dart:235-244` | `BottomSheetThemeData` — does not enable the native drag handle. |
| Confirm no custom dismissal is wired | `lib/ui/core/shell_modal_lock.dart` | Only locks tab swiping; does not affect sheet dismissal. |
