# Investigation — Navigation / route stack and the "Edit Ingredients" sheet (Home)

Scope: `apps/mobile/lib`, focused on the "Edit Ingredients" flow triggered from the Home (Dashboard) tab.
No fixes are proposed; this is a code-anchored map of the current navigation.

## TL;DR

- The app uses **go_router 14.x** with a `StatefulShellRoute` (4 branches: dashboard, history, templates, settings). Branches are mounted under a `PageView`-based `SlidingBranchContainer` (a custom analogue of `IndexedStack` that animates between branches).
- The `MealItemEditorSheet` from the Home tab is opened with `showModalBottomSheet(...)` **without `useRootNavigator`** (defaults to `false`). It is therefore pushed onto the **branch's inner Navigator**, not the root Navigator.
- A `ShellModalLockObserver` watches every branch Navigator and toggles a `ShellModalLockController.isLocked` flag whenever a `PopupRoute` is on the branch stack. The lock is read by `SlidingBranchContainer` only to switch the `PageView` between `null` and `NeverScrollableScrollPhysics`. It does not block pops.
- The "good" reference sheets inside the dashboard (`CalorieTargetSheet`, `MacroDistributionSheet`) open their *child* sheets with `useRootNavigator: true`, but the dashboard's own `showModalBottomSheet` calls (including the one for the editor) do **not**.
- Nothing in the navigation stack prevents `Navigator.pop` from dismissing the editor. The likely culprit for "drag the drag handle → sheet does not close" sits inside the sheet content layout (no drag-to-dismiss affordance above the scroll view, see "Hipótesis" below), not in the router/shell.

---

## 1. Configuración del router y shell

### Router entrypoint — `apps/mobile/lib/app/router.dart`

- `buildRouter` (lines 17–22) creates a shared `ShellModalLockController` and a `modalLockObservers()` factory that returns a single `ShellModalLockObserver` instance per call site.
- The root `GoRouter` (lines 23–53) is built with:
  - `navigatorKey: navigatorKey` — the only root `NavigatorState` (created in `app/app.dart` at line 167: `final _navigatorKey = GlobalKey<NavigatorState>();`).
  - `observers: modalLockObservers()` (line 25) — observes root-level popups.
  - `initialLocation: '/dashboard'` (line 26).
  - `redirect` (lines 28–40) — only `/auth` ↔ `/dashboard` switching; no per-tab redirect.
- Top-level routes (lines 41–51):
  - `GoRoute('/auth', ...)`.
  - `GoRoute('/meal/create', ...)` — `MealCreateScreen` is a *root* route (not in a branch), so it lives on the root Navigator, not the branch Navigator.
  - `GoRoute('/templates/ingredients/scan', ...)` — also on the root Navigator.
  - `StatefulShellRoute(...)` — the main tabbed shell.
- `StatefulShellRoute` (lines 52–196):
  - `builder` returns `_AuthRestoreGate(child: AppShell(navigationShell: navigationShell))`.
  - `navigatorContainerBuilder` (lines 59–77) returns a `SlidingBranchContainer` whose `userScrollEnabled` is `!modalLockController.isLocked`. Whenever the lock flips, the `PageView`'s `physics` switches between `null` (default) and `NeverScrollableScrollPhysics()`. **It does not call `goBranch`.**
  - Four `StatefulShellBranch`es, one per tab:
    - `/dashboard` → `DashboardScreen` (lines 81–93).
    - `/history` → `MealHistoryScreen` (lines 95–106).
    - `/templates` → `MealTemplatesScreen` (lines 108–180, with 4 nested `GoRoute`s for ingredient/meal editor).
    - `/settings` → `SettingsScreen` (lines 182–193).
  - Every branch gets `observers: modalLockObservers()` (lines 83, 97, 110, 184). **Each branch has its own `ShellModalLockObserver`, but they all share the same `ShellModalLockController`.**
- `_tabPage` helper (lines 218–221) wraps each tab's page in `NoTransitionPage<void>(key: state.pageKey, child: child)`. No `pageBuilder` is used for the nested `/templates/...` routes — they use plain `builder`.

### App shell — `apps/mobile/lib/ui/core/app_shell.dart`

- `AppShell` (lines 30–65) is just a `Scaffold` whose body is `navigationShell` and whose `bottomNavigationBar` is a custom 5-slot row (`_FreshBottomNav`, lines 67–108) with the center slot being a `_CenterVoiceButton` (the mic/FAB).
- On wide screens (>= 720) the layout switches to a side nav (`_FreshSideNav`, lines 110–146). Both delegate to `_go` (lines 60–63) which calls `navigationShell.goBranch(index)`.
- `SlidingBranchContainer` (lines 67–199) — this is the most important piece for the bug:
  - It holds a `PageController` (line 73) and tracks the current page locally in `_pageIndex` (line 74).
  - `initState` seeds `_pageIndex` from `widget.currentIndex` and the controller at that page.
  - `didUpdateWidget` (lines 80–91) animates the controller to the new `currentIndex` whenever the shell tells it to (e.g. tab tap → `goBranch`).
  - `_handlePageChanged` (lines 117–125) only forwards to `widget.onPageChanged` if `_programmaticTargetIndex == null` — i.e. it ignores programmatic jumps and only fires for **user swipes**. The shell's `onPageChanged` (router.dart line 70) calls `navigationShell.goBranch(index)`.
  - The visible branch is wrapped in `_BranchSlot` (lines 128–148) which extends `AutomaticKeepAliveClientMixin` and disables `TickerMode` for inactive branches (a `RepaintBoundary` wraps each branch).
- `_FreshBottomNav._NavButton` (lines 158–203) — no `Navigator.push` here, just `onTap: () => onSelected(...)`.

### Shell modal lock — `apps/mobile/lib/ui/core/shell_modal_lock.dart`

- `ShellModalLockController` (lines 3–40): a `ChangeNotifier` that maintains a `Set<Route<dynamic>>` of currently active `PopupRoute`s. `isLocked` is `true` iff the set is non-empty. `track`/`untrack`/`replace` update the set and notify.
- `ShellModalLockObserver` (lines 42–73): a `NavigatorObserver` that wires `didPush`/`didPop`/`didRemove`/`didReplace` into the controller. It filters non-`PopupRoute`s in `track`.
- **The lock only gates the `PageView`'s `physics`.** It is read in `router.dart` line 64 (`userScrollEnabled: !modalLockController.isLocked`) and never re-pops anything. There is no `WillPopScope`/`PopScope` on the shell.

### MaterialApp.router binding — `apps/mobile/lib/app/app.dart`

- `_CalTrackerAppState` (lines 147–194) builds `MaterialApp.router` with `routerConfig: _router!`. The root `navigatorKey` is `_navigatorKey` (line 167). The `builder` (lines 183–193) wraps the child in `MobileUpdateDialogHost` and an authenticated-data preloader. **There is no `WidgetsApp.builder` shim that re-routes or re-stacks navigators.**

---

## 2. Cadena de llamada al editor de ingredientes desde el dashboard

All paths below refer to `apps/mobile/lib`.

### Trigger on the Home tab

- `DashboardScreen` is the widget mounted at `/dashboard` (router.dart line 86). Its build is in `ui/features/dashboard/views/dashboard_screen.dart`.
- The meal list is rendered by `_MealSection` → `_MealRow` (dashboard_screen.dart lines 875–900 and 902–1003). For each meal, two `FreshIconButton`s are emitted:
  - `dashboard_delete_meal_${meal.id}` → `onDelete` → `_confirmDeleteMeal` (lines 121–147).
  - `dashboard_edit_meal_${meal.id}` → `onEdit` → `_showMealItemEditor` (lines 100–112) (key + tooltip: `l10n.dashboardEditIngredientsTooltip`, lines 994–998).

### The actual `showModalBottomSheet` call (the bug-relevant call site)

`dashboard_screen.dart` lines 100–112:

```dart
Future<void> _showMealItemEditor(
  BuildContext context,
  DashboardViewModel viewModel,
  Meal meal,
) async {
  final items = await showModalBottomSheet<List<MealItem>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => MealItemEditorSheet(
      meal: meal,
      keyPrefix: 'dashboard',
      searchFoods: viewModel.searchFoods,
    ),
  );
  if (!context.mounted || items == null) return;
  await viewModel.correctMealItems(meal, items);
}
```

- `context` is the `BuildContext` of `_DashboardScreenState.build`. That context sits under the `/dashboard` `NoTransitionPage`, which is mounted as the root of the dashboard `StatefulShellBranch`'s Navigator. Therefore `Navigator.of(context)` resolves to the **dashboard branch Navigator**, not the root Navigator.
- `useRootNavigator` is **not** passed → defaults to `false` → `showModalBottomSheet` walks up to the closest `NavigatorState` and pushes a `ModalBottomSheetRoute<List<MealItem>>` there (the branch's inner Navigator).
- `isScrollControlled: true` → the sheet is not constrained to half height.
- `useSafeArea: true` → the sheet's content gets a `SafeArea` wrapper inside the modal route.
- The `MealItemEditorSheet` widget is the **content** of the modal. It does not call any `showModalBottomSheet` itself at the top level (it does open a `NutritionEditSheet` *inside*, see below).

### `MealItemEditorSheet` — `ui/shared/meal_item_editor_sheet.dart`

- A `StatefulWidget` (lines 20–28) that owns a `List<EditableMealItemController>` initialised from `widget.meal.items` (lines 33–44). It does not wrap its content in any extra `Navigator`; the `BuildContext` inside the sheet is the modal route's child context.
- `build` (lines 52–180) returns:
  ```dart
  DecoratedBox(
    decoration: BoxDecoration(color: palette.surfaceSoft),
    child: Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, bottomInset + 18),
      child: SingleChildScrollView(
        child: Column(
          ...
          Center( // drag handle
            child: Container(width: 44, height: 4, ...),
          ),
          ...
        ),
      ),
    ),
  );
  ```
  - The "drag handle" is a **decorative** `Container(width: 44, height: 4, ...)` rendered at the top of the `Column` *inside* the `SingleChildScrollView` (lines 65–74). It is not a `BottomSheetDragHandle` and is not wired to any gesture. It exists purely as a visual affordance.
  - The scrollable is a plain `SingleChildScrollView` (vertical). The sheet's bottom-anchored content includes a "Save edits" `FilledButton` (lines 175–180) that calls `_save()`.
- `_save()` (lines 183–207) calls `Navigator.of(context).pop(edited)`. The `context` here is the sheet's `BuildContext`, so it resolves to the **branch Navigator** that owns the modal route — the same one that pushed the sheet. There is no `useRootNavigator: true` here, no `GoRouter.of(context).pop()`, and no `context.maybePop()`.
- Inside each ingredient card, the "Edit details" button opens a *nested* `NutritionEditSheet` (lines 486–512):
  ```dart
  final edited = await showModalBottomSheet<NutritionEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => NutritionEditSheet(
      initialNutrition: item.currentNutrition(),
      ...
    ),
  );
  ```
  This is also `useRootNavigator` (default `false`), and `NutritionEditSheet._save()` (lines 305–317) pops with `Navigator.of(context).pop(nutrition)`. This second sheet is therefore a child of the first sheet on the same branch Navigator. There is no `Navigator` widget manually inserted.

### Editable controller

- `EditableMealItemController` (`ui/shared/editable_meal_item_controller.dart`) is a pure helper class. It owns 3 `TextEditingController`s and an optional nutrition override, and exposes `toValidatedMealItem()` / `toMealItemWith(...)` (lines 116–167). It has no `Navigator`/`GoRouter` references.

### Dashboard-side completion

- After `showModalBottomSheet` resolves, `_showMealItemEditor` calls `viewModel.correctMealItems(meal, items)` (dashboard_screen.dart line 110). On the success path there is no further navigation; the await chain returns to `_DashboardScreenState.build`'s next rebuild. **No `context.go`/`context.pop` is invoked.**

---

## 3. Cómo se invoca `showModalBottomSheet` (root navigator o no)

Exhaustive list of `showModalBottomSheet` call sites in `lib/ui`:

| Caller file | Line | `useRootNavigator` | `isScrollControlled` | `useSafeArea` |
| --- | --- | --- | --- | --- |
| `ui/features/dashboard/views/dashboard_screen.dart` | 100 | **default (false)** | true | true |
| `ui/features/dashboard/views/dashboard_screen.dart` | 154 | default (false) | true | true |
| `ui/features/dashboard/views/dashboard_screen.dart` | 186 | default (false) | — | true |
| `ui/features/dashboard/views/dashboard_screen.dart` | 194 | default (false) | true | true |
| `ui/features/dashboard/views/calorie_target_sheet.dart` | 175 | **true** | true | true |
| `ui/features/dashboard/views/calorie_target_sheet.dart` | 185 | **true** | true | true |
| `ui/features/dashboard/views/calorie_target_sheet.dart` | 264 | **true** | true | true |
| `ui/features/dashboard/views/macro_distribution_sheet.dart` | 146 | **true** | true | true |
| `ui/features/meal_history/views/meal_history_screen.dart` | 103 | default (false) | — | — (sheet wraps in `SafeArea` manually) |
| `ui/features/meal_history/views/meal_history_screen.dart` | 150 | **default (false)** | true | true |
| `ui/features/settings/views/settings_screen.dart` | 190, 209, 232, 255, 271, 347, 412 | all default (false) | mixed | mixed |
| `ui/features/voice_log/views/voice_log_screen.dart` | 188, 204, 409, 2125 | all default (false) | true | mixed (some `useSafeArea: true` on the child `NutritionEditSheet`) |
| `ui/shared/meal_item_editor_sheet.dart` | 503 (nested `NutritionEditSheet`) | default (false) | true | true |

Pattern:
- **Top-level sheets opened from a tab screen use the branch's inner Navigator** (no `useRootNavigator`).
- **Top-level sheets opened from inside another sheet use `useRootNavigator: true`** (only `calorie_target_sheet.dart` and `macro_distribution_sheet.dart`). This is the difference vs. the "Edit Ingredients" flow.

`showDialog` is used in two places (`dashboard_screen.dart` line 116, `meal_history_screen.dart` line 164); neither sets `useRootNavigator`.

There is no manual `Navigator.push`, `Navigator(pages: ...)`, or `showCupertinoModalPopup` in `lib/ui`. The only places that use `context.go` / `context.pop` / `context.maybePop` with go_router are:
- `voice_log_screen.dart` line 63 (`context.canPop() ? context.pop() : context.go('/dashboard')`).
- `meal_templates/views/meal_template_editor_screen.dart` lines 315–319.
- `meal_templates/views/usual_food_editor_screen.dart` line 450.
- `app_shell.dart` line 53 (`globalVoiceRoutingDestinationFor` builds a destination then `_stopAndOpen` calls `context.go(...)`, line 379).

None of these touch the meal-editor flow.

---

## 4. Sheets de referencia que SÍ funcionan (drag-to-dismiss no reportado)

### `CalorieTargetSheet` — `ui/features/dashboard/views/calorie_target_sheet.dart`

- Triggered from dashboard as `showModalBottomSheet<CalorieTargetSelection>(context: context, isScrollControlled: true, useSafeArea: true, builder: ...)` with default `useRootNavigator` (dashboard_screen.dart lines 153–163).
- Internally it can open a calculator flow (`_showCalculator`, lines 173–202):
  ```dart
  final estimate = await showModalBottomSheet<CalorieEstimate>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,                 // <-- root navigator
    builder: (context) => CalorieCalculatorWizard(...),
  );
  if (estimate == null || !mounted) return;
  final macroConfig = await showModalBottomSheet<MacroDistributionConfig>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,                 // <-- root navigator
    builder: (context) => _CalculatorMacroPrompt(calories: estimate.targetCalories),
  );
  if (!mounted) return;
  Navigator.of(context).pop(CalorieTargetSelection(...));
  ```
  Note that the *outer* `Navigator.of(context).pop(...)` (line 195) is `useRootNavigator: false` semantics (default), but the inner sheets are rooted.
- `_CalculatorMacroPrompt` (lines 220–290) opens a third sheet with the same `useRootNavigator: true` pattern (lines 264–273), and its pop uses `Navigator.of(context).pop(config)` (line 276).
- The action sheet "Save" / "Skip" buttons (lines 282–287, 340–348) use `Navigator.of(context).pop(...)` on the local sheet context (no root override).
- The food search close button (line 460) uses `Navigator.of(context).maybePop()`.
- The `_submit` method (line 211) and the save inside the "choose your macros" prompt (line 938, line 964 with `maybePop()`) close by popping the local context.

### `MacroDistributionSheet` — `ui/features/dashboard/views/macro_distribution_sheet.dart`

- Triggered from dashboard with `showModalBottomSheet<MacroDistributionConfig>(context: context, isScrollControlled: true, useSafeArea: true, useRootNavigator: true, ...)` (lines 146–155). Note this is the **only** dashboard-level sheet that opens itself rooted.
- `_openPersonalizedSheet` (lines 145–159) opens a second-level sheet the same way (`useRootNavigator: true`).
- `_save` (line 713) calls `Navigator.of(context).pop(_config)`.
- The constructor also exposes `presetOnly: true` (line 152) and an alternate title — this is the variant used by `_CalculatorMacroPrompt` (calorie_target_sheet.dart line 271).

### Other "good" behaviour

- `MealHistoryScreen._showMealItemEditor` (meal_history_screen.dart lines 148–161) uses the *same* pattern as the dashboard: `showModalBottomSheet` with no `useRootNavigator` and a `MealItemEditorSheet` child. So the same flow exists on the History tab too, with the same `useRootNavigator` choice.
- `VoiceLogScreen._showProposalEditor` (voice_log_screen.dart lines 186–197) also opens a sheet with default `useRootNavigator: false`. There is no public bug report on that path.

---

## 5. Hipótesis sobre por qué no se vuelve a la pestaña anterior

The user's phrasing is "al arrastrar el drag handle del sheet 'Edit Ingredients' en el Home, 'no se vuelve a la pestaña anterior' (no se cierra el modal)". The clarification in parentheses (no se cierra el modal) tells us the modal stays open. The references to "pestaña anterior" almost certainly mean "the dashboard tab that was visible before the sheet was opened".

What I can rule out by reading the code:

- **No `WillPopScope` / `PopScope` blocks the pop** anywhere in the editor (`grep -n "WillPopScope\|PopScope\|onWillPop" lib/` finds none in `ui/shared/meal_item_editor_sheet.dart`, `nutrition_edit_sheet.dart`, or `editable_meal_item_controller.dart`; the only `PopScope` in the app is on `usual_food_scan_screen.dart` line 185, unrelated).
- **The `ShellModalLockController` only flips `userScrollEnabled`** on the `PageView` (router.dart line 64, `app_shell.dart` line 188 in `SlidingBranchContainer.build`). It does not call `Navigator.pop`/`maybePop`/`canPop` and does not mutate any branch index. After the modal is pushed, `isLocked == true`; when the modal is popped (via drag or save), `isLocked` flips back to `false`. The lock therefore cannot prevent the sheet from closing.
- **The save button is wired correctly** to `Navigator.of(context).pop(edited)` (meal_item_editor_sheet.dart line 206). The widget tests in `dashboard_cleanup_widget_test.dart` "dashboard meal cards edit explicit ingredients" (line 374) and the "adds an ingredient" / "replaces an ingredient" tests (lines 451, 523) all reach `save_dashboard_item_edits_button` and confirm the future resolves with the corrected items, which implies the pop does fire in tests when the button is tapped.
- **The router does not push any extra route while the sheet is open** (no `context.go`/`context.push` is invoked from `MealItemEditorSheet` or from `DashboardViewModel.correctMealItems`). The branch's `currentIndex` cannot change just because a sheet was pushed.
- **No overlay-based tab switcher** — the only tab controls are `_FreshBottomNav`/`_FreshSideNav` (app_shell.dart lines 67–146) which call `onSelected(index)` → `_go(context, index)` → `navigationShell.goBranch(index)` (lines 60–63). They do not fire while a modal is open because the modal is on top of the branch Navigator and consumes taps in its own region.

What remains as the most plausible structural cause (described, not proposed as a fix):

- `MealItemEditorSheet` (meal_item_editor_sheet.dart lines 56–181) renders the **drag handle as a decorative `Container(width: 44, height: 4, ...)` inside a `Column` inside a `SingleChildScrollView`** (lines 62–76). There is no `BottomSheetDragHandle`, no `showDragHandle: true` on a `BottomSheet`, and no explicit `enableDrag` argument on the `showModalBottomSheet` call.
- With `isScrollControlled: true`, the `ModalBottomSheetRoute` delegates the `enableDrag` plumbing to the sheet's own scrollable. The vertical drag gesture originating on the handle therefore lands on the `SingleChildScrollView`'s `VerticalDragGestureRecognizer` rather than on the modal's dismiss gesture. From the modal route's perspective, the drag is a "scroll inside the sheet", not a "drag to dismiss". This is consistent with the user's report that "dragging the handle" does nothing.
- A secondary contributor is the absence of a `useRootNavigator: true` like the one used by `CalorieTargetSheet`/`MacroDistributionSheet` (calorie_target_sheet.dart line 179, macro_distribution_sheet.dart line 150). That choice is independent of the drag issue but does mean the modal lives on the branch Navigator rather than the root Navigator. In theory, popping from the branch Navigator should still reveal the dashboard; in practice, this only matters if some other consumer is observing the branch Navigator and re-pushing or re-routing — and `ShellModalLockObserver` does not do that.
- A tertiary candidate is that some other gesture (e.g. `_QuantityStepButton`'s `TextButton` on the ingredient row, meal_item_editor_sheet.dart lines 458–473) is consuming tap/drag in the handle region. The handle is in a `Column` above the first ingredient card, so this is unlikely to be the trigger.

Re-stating the hypotheses in one paragraph: nothing in the router, `AppShell`, `SlidingBranchContainer`, or `ShellModalLockObserver` is wired to keep the sheet open or to change the active branch. The most likely reason the modal does not close on a handle drag is that the handle is a non-interactive visual element inside a `SingleChildScrollView`; the drag gesture is consumed by the scroll view, and the modal's `enableDrag` path is never exercised. The mismatch with the "good" sheets is that those either (a) push nested sheets with `useRootNavigator: true` so the drag is handled by the root `Navigator`'s modal route, or (b) wrap their content in ways that leave room for a non-scrolling drag region. The "Edit Ingredients" sheet does neither.

---

## 6. Tests existentes

### `apps/mobile/test/dashboard_cleanup_widget_test.dart` (39.5K)

- Bootstraps `DashboardScreen` inside a `MaterialApp(home: Scaffold(body: child))` (lines 791–800). **It does not use `CalTrackerBootstrap` and does not mount a `GoRouter` or `AppShell`** — see `_testApp` at lines 791–800. So tabs, `SlidingBranchContainer`, and `ShellModalLockController` are not exercised.
- Tabs that touch the editor sheet:
  - `testWidgets('dashboard meal cards edit explicit ingredients', ...)` (line 374) — taps `dashboard_edit_meal_meal-1` (line 406), asserts `find.text('Edit ingredients')` (line 409), then walks through details editor and finally taps `save_dashboard_item_edits_button` (line 442). It verifies the pop future resolves and `nutritionRepository.lastCorrectedItems` is set.
  - `testWidgets('dashboard meal editor adds an ingredient from food search', ...)` (line 451) — same `dashboard_edit_meal_meal-1` entry point, then exercises `dashboard_item_0_search_*` and saves with `save_dashboard_item_edits_button`.
  - `testWidgets('dashboard meal editor replaces an ingredient from food search', ...)` (line 523) — same shape, replaces an existing item.

  All three close the sheet via the `FilledButton` (`save_dashboard_item_edits_button`). **None of them tests the drag-to-dismiss path** (`tester.drag(...)` on the handle) nor verifies that the branch Navigator's stack length returns to 1.

### `apps/mobile/test/meal_history_widget_test.dart` (11.7K)

- `testWidgets('edits history meals with explicit ingredients', ...)` (line 18) — opens the editor by tapping a row → "Edit ingredients" action sheet, then saves. Same pattern: closes via the `FilledButton`. No drag-to-dismiss test.

### `apps/mobile/test/sliding_branch_container_test.dart` (7.9K)

- Tests `SlidingBranchContainer` and `ShellModalLockController` in isolation.
- Modal-lock unit tests:
  - `'modal lock observer locks until all popup routes close'` (lines 161–183) — drives `didPush`/`didPop`/`didRemove` directly and asserts `isLocked`.
  - `'modal lock controller tracks popup routes across observers'` (lines 185–201) — multiple observers sharing the same controller.
  - `'modal lock observer syncs replacements'` (lines 203–215) — `didReplace` cleanup.
- Drag-to-branch tests (lines 16–158) verify `PageView` swipes and `userScrollEnabled: false`. **No test asserts that opening a `PopupRoute` actually toggles `isLocked`** in a real `GoRouter` setup, because the harness uses a bare `MaterialApp` + `SlidingBranchContainer`.

### `apps/mobile/test/voice_log_screen_test.dart` (52.3K) and `meal_template_editor_widget_test.dart` (17.5K)

- Both exercise sheets in widget tests. None of them tests drag-to-dismiss on a sheet's drag handle.

### `apps/mobile/test/flutter_test_config.dart` (221B)

- Only sets `WidgetController.hitTestWarningShouldBeFatal = true`. A `tester.drag` that misses the handle because the handle is a non-interactive `Container` would surface as a hit-test warning, which becomes a test failure in this configuration.

### Tests that *do* test drag dismissal

- None found. `grep -rn "draggable\|drag.*handle\|DragDown" apps/mobile/test/` returns no matches.

---

## Files Retrieved (key paths and line ranges)

1. `apps/mobile/lib/main.dart` (lines 1–12) — bootstrap, runs `CalTrackerBootstrap`.
2. `apps/mobile/lib/app/app.dart` (lines 147–194) — `_CalTrackerAppState`, root `navigatorKey`, `MaterialApp.router` wiring.
3. `apps/mobile/lib/app/router.dart` (lines 17–221) — `GoRouter`, `StatefulShellRoute`, `SlidingBranchContainer` host, `modalLockObservers()`.
4. `apps/mobile/lib/ui/core/app_shell.dart` (lines 30–203) — `AppShell`, `SlidingBranchContainer`, `_FreshBottomNav`, `_NavButton`, branch-preservation via `AutomaticKeepAliveClientMixin`.
5. `apps/mobile/lib/ui/core/shell_modal_lock.dart` (lines 1–73) — `ShellModalLockController` and `ShellModalLockObserver`.
6. `apps/mobile/lib/ui/core/content_frame.dart` (lines 1–25) — thin wrapper around `FreshPage`.
7. `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart` (lines 1–200, 875–1003) — `DashboardScreen`, `_showMealItemEditor` (100–112), `_MealRow` and the two `FreshIconButton`s with keys `dashboard_edit_meal_<id>` and `dashboard_delete_meal_<id>`.
8. `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart` (lines 1–207, 486–512) — sheet body, drag handle inside `SingleChildScrollView`, save via `Navigator.of(context).pop`, nested `NutritionEditSheet` opener.
9. `apps/mobile/lib/ui/shared/nutrition_edit_sheet.dart` (lines 1–317) — nested sheet body, save via `Navigator.of(context).pop`.
10. `apps/mobile/lib/ui/shared/editable_meal_item_controller.dart` (lines 1–167) — controller, no nav references.
11. `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart` (lines 173–290, 938, 964) — `useRootNavigator: true` pattern.
12. `apps/mobile/lib/ui/features/dashboard/views/macro_distribution_sheet.dart` (lines 145–213, 713) — `useRootNavigator: true` pattern.
13. `apps/mobile/lib/ui/features/meal_history/views/meal_history_screen.dart` (lines 95–165) — same `_showMealItemEditor` pattern, no `useRootNavigator`.
14. `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart` (lines 186–213, 409–430, 2125–2145) — same `useRootNavigator`-less pattern; one `context.go('/dashboard')` on line 63 (mic voice routing).
15. `apps/mobile/test/dashboard_cleanup_widget_test.dart` (lines 1–100, 374–593, 791–820) — `_testApp` harness and three "edit explicit ingredients" tests.
16. `apps/mobile/test/meal_history_widget_test.dart` (lines 1–100) — "edits history meals with explicit ingredients" test.
17. `apps/mobile/test/sliding_branch_container_test.dart` (lines 1–215) — branch container + modal lock observer tests.
18. `apps/mobile/test/flutter_test_config.dart` (lines 1–7) — `hitTestWarningShouldBeFatal = true`.

## Architecture (1-paragraph)

`MaterialApp.router` hosts a `GoRouter` (router.dart) with a `StatefulShellRoute` and four `StatefulShellBranch`es. Each branch owns its own `Navigator` (implicitly created by go_router) and its own `ShellModalLockObserver`, all sharing one `ShellModalLockController`. The shell (`AppShell`) is a `Scaffold` whose body is a `SlidingBranchContainer`: a `PageView` with `AutomaticKeepAliveClientMixin` per slot, gated by `physics: userScrollEnabled ? null : NeverScrollableScrollPhysics()`. The dashboard tab page is a `NoTransitionPage` hosting `DashboardScreen`, whose `BuildContext` resolves `Navigator.of(context)` to the dashboard branch Navigator. `showModalBottomSheet` calls without `useRootNavigator` therefore push modal routes onto that branch Navigator; the modal's drag-to-dismiss relies on the sheet's own scrollable, and `_save` uses `Navigator.of(sheetContext).pop(...)` to close.

## Start Here (for the next agent)

- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart` — read the `_showMealItemEditor` call (lines 100–112) and the `_MealRow` `FreshIconButton` wiring (lines 985–999). That is the only path that produces the `MealItemEditorSheet` from the Home tab.
- `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart` — start with `build` (lines 52–180), then `_save` (lines 183–207). Compare the drag handle rendering (lines 65–74) with how `NutritionEditSheet` (same file family) and `CalorieTargetSheet` render theirs.
- `apps/mobile/lib/app/router.dart` — `StatefulShellRoute` + `navigatorContainerBuilder` (lines 52–77) and the per-branch observers (lines 83, 97, 110, 184) are the structural pieces relevant to the bug.
- `apps/mobile/lib/ui/core/shell_modal_lock.dart` — full file, to confirm that the lock does not block pops.
