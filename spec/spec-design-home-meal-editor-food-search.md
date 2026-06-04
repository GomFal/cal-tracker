---
title: Home Meal Editor Food Search
version: 1.0
date_created: 2026-06-04
last_updated: 2026-06-04
owner: Cal Tracker
tags: [design, mobile, flutter, food-search, meal-editing]
---

# Introduction

This specification defines how the Home meal ingredient editor must support food search when users add or replace ingredients in an already logged meal. The implementation must reuse the existing database-backed food search behavior used in meal proposal and meal template editing flows, instead of requiring users to type all ingredient nutrition values manually.

## 1. Purpose & Scope

The purpose is to make Home meal correction faster and more reliable by letting users search for a food, select a database result, and apply that result to the editable meal items before saving.

Scope includes:

- The Home dashboard flow that opens `MealItemEditorSheet` from `DashboardScreen`.
- Adding a searched food as a new ingredient in the sheet.
- Replacing an existing ingredient in the sheet with a searched food.
- Reusing existing `NutritionRepository.searchFoods` results and `MealItem` data.
- Widget tests for Home meal editing.

Scope excludes:

- Backend food search changes.
- New natural-language parsing or deterministic ingredient inference.
- Changes to meal proposal creation semantics.
- End-to-end or Patrol test coverage.

## 2. Definitions

- **Home meal editor**: The bottom sheet created by `MealItemEditorSheet` when a user taps an edit action on a meal card in `DashboardScreen`.
- **Meal item**: A `MealItem` containing name, quantity, unit, calories, macros, and optional external source metadata.
- **Food search**: The existing repository call `NutritionRepository.searchFoods(query, limit: 10)`.
- **Add from search**: Selecting a search result and appending it as a new editable ingredient.
- **Replace from search**: Selecting a search result and overwriting one existing editable ingredient with the result.
- **Blank ingredient**: An editable row created without database search, using the current manual input behavior.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: The Home meal editor must expose a search affordance before the editable ingredient list. The affordance must let the user search database foods and add a selected result as a new ingredient.
- **REQ-002**: Each existing ingredient row in the Home meal editor must expose a replacement search affordance. Selecting a result must replace that row's name, quantity, unit, calories, protein, carbs, fat, and source metadata from the selected `MealItem`.
- **REQ-003**: The existing blank manual add flow must remain available through the current `commonAddIngredient` action.
- **REQ-004**: Search must call `NutritionRepository.searchFoods` through the Home flow's view model layer. `DashboardViewModel` should expose a `searchFoods(String query, {int limit = 10})` method that delegates to the repository.
- **REQ-005**: The selected search result must update the editable state only. It must not call `correctMealItems` until the user taps the existing save button.
- **REQ-006**: Meal total calories and macros must update immediately after adding or replacing a searched ingredient.
- **REQ-007**: Empty queries must not call the repository.
- **REQ-008**: Empty search results must show the existing localized `foodSearchEmpty` message.
- **REQ-009**: Search failures must show the existing localized `foodSearchError` message and keep current editable items unchanged.
- **REQ-010**: The search UI must use existing localized food search strings where possible: `foodSearchHint`, `foodSearchAddAction`, `foodSearchHideSearch`, `foodSearchEmpty`, and `foodSearchError`.
- **CON-001**: Do not hardcode ingredients, ingredient translations, meal names, fallback nutrition, or deterministic parsing rules.
- **CON-002**: Do not mutate committed meal history until the existing save action returns a valid edited item list.
- **CON-003**: Do not create a second backend endpoint for this feature.
- **CON-004**: Do not make the search feature Home-only by embedding repository access directly in `MealItemEditorSheet`.
- **GUD-001**: Prefer extracting the existing meal template `_FoodSearchPanel` behavior into a shared widget, for example `FoodSearchPanel`, that accepts a search callback, a selection callback, a close callback, a key prefix, and optional copy overrides.
- **GUD-002**: Keep the manual row editor as the source of truth after selection. A selected search result should populate the same controllers and nutrition override fields currently saved by `_EditableMealItem.toMealItem()`.
- **GUD-003**: Search UI should collapse after a successful add or replacement, matching the current meal template editor behavior.

## 4. Interfaces & Data Contracts

### Dashboard View Model

`DashboardViewModel` must provide a food search method:

```dart
Future<FoodSearchResult> searchFoods(String query, {int limit = 10});
```

Behavior:

- Delegates to `NutritionRepository.searchFoods(query, limit: limit)`.
- Does not change dashboard loading state.
- Does not alter `summary`, `_lastLoadedAt`, or meal correction state.
- Propagates errors to the caller so the sheet can render `foodSearchError`.

### Meal Item Editor Sheet

`MealItemEditorSheet` must accept an optional search callback:

```dart
typedef MealItemFoodSearch = Future<FoodSearchResult> Function(
  String query, {
  int limit,
});
```

Suggested constructor addition:

```dart
const MealItemEditorSheet({
  required Meal meal,
  String keyPrefix = 'meal',
  MealItemFoodSearch? onSearchFoods,
});
```

Behavior:

- If `onSearchFoods` is provided, show add and replace search affordances.
- If `onSearchFoods` is null, preserve the current manual-only behavior. This protects existing callers such as History until they opt in.

### Required Test Keys

The implementation must provide stable keys for Home widget tests:

| Element | Key |
| --- | --- |
| Add from search button | `dashboard_add_from_search_button` |
| Add search field | `dashboard_food_search_field` |
| Add search submit | `dashboard_food_search_submit` |
| Add search result at index N | `dashboard_food_search_result_N` |
| Add search close | `dashboard_food_search_close` |
| Replace search toggle for item N | `dashboard_item_N_search_toggle` |
| Replace search field for item N | `dashboard_item_N_search_field` |
| Replace search result at index M for item N | `dashboard_item_N_search_result_M` |
| Replace search collapse for item N | `dashboard_item_N_search_collapse` |

## 5. Acceptance Criteria

- **AC-001**: Given a logged meal is visible on Home, when the user opens its ingredient editor, then the editor shows both the current manual add button and an add-from-search button.
- **AC-002**: Given the user opens add-from-search and searches `rice`, when `NutritionRepository.searchFoods('rice', limit: 10)` returns a `MealItem`, then selecting the first result appends that item to the editable ingredient list and updates the meal total preview.
- **AC-003**: Given the user selects a search result, when the user dismisses the sheet without saving, then `correctMealItems` is not called.
- **AC-004**: Given the user adds a searched ingredient and taps save, then `DashboardViewModel.correctMealItems` receives the original items plus the selected `MealItem`, and Home reloads using the existing correction flow.
- **AC-005**: Given the user opens replacement search on item 0 and selects `Bread`, then item 0's editable name, quantity, unit, calories, protein, carbs, and fat reflect the selected `MealItem`.
- **AC-006**: Given replacement search updates item 0 and the user taps save, then `correctMealItems` receives the replacement item instead of the original item.
- **AC-007**: Given search returns no results, then the sheet shows `foodSearchEmpty` and does not add or replace any ingredient.
- **AC-008**: Given search throws, then the sheet shows `foodSearchError` and leaves all existing editable fields unchanged.
- **AC-009**: Given a user manually adds a blank ingredient, then the current manual validation and nutrition detail editing behavior remains unchanged.

## 6. Test Automation Strategy

- **Widget tests**: Extend `apps/mobile/test/dashboard_cleanup_widget_test.dart`.
- **Repository fake**: Add `searchFoods` support to the dashboard fake nutrition repository, including query capture and configurable returned items/errors.
- **Required tests**:
  - Add a searched food from Home meal editor and save it.
  - Replace an existing Home meal ingredient with a searched food and save it.
  - Search empty result renders localized empty message and does not save.
  - Search error renders localized error message and preserves existing item fields.
  - Manual blank ingredient editing still works.
- **Not required**: Patrol, ADB visual validation, backend integration tests, or E2E tests.

## 7. Rationale & Context

The current Home editor supports correcting explicit ingredients but requires manual entry for new or changed ingredients. Other flows already let users search public foods and apply a selected `MealItem`, which is faster and reduces manual nutrition entry errors.

The feature should reuse the existing structured food search output. This follows the project rule that food understanding must come from structured LLM/tool output, database-backed resolution, explicit user input, or clarification/error responses.

## 8. Dependencies & External Integrations

### External Systems

- **EXT-001**: Existing backend food search endpoint accessed through `NutritionRepository.searchFoods`.

### Data Dependencies

- **DAT-001**: `FoodSearchResult.items` must contain `MealItem` values with enough nutrition fields to pass `MealItemEditorSheet` validation.

### Platform Dependencies

- **PLT-001**: Flutter widget tests using `WidgetTester` and existing Provider-based view model injection.

## 9. Examples & Edge Cases

```dart
// Add from search:
// Original items: [Oats]
// Search result: Public rice, 100 g, 130 kcal
// Editable items after selection: [Oats, Public rice]
// Persisted only after save: correctMealItems(meal.id, [Oats, Public rice])
```

```dart
// Replace from search:
// Original item 0: Chicken breast, 150 g, 248 kcal
// Search result: Bread, 100 g, 265 kcal
// Editable item 0 after selection: Bread, 100 g, 265 kcal
// Persisted only after save: correctMealItems(meal.id, [Bread, ...])
```

Edge cases:

- A selected item has a non-gram unit. The editor must preserve the unit and use existing quantity controls for non-gram units.
- A selected item has candidate/source metadata. The metadata must be retained by `toMealItem()` if the current `MealItem` model supports it.
- The search panel is open and the user deletes another row. Keys and callbacks must remain bound to the correct current index after rebuild.
- The keyboard is visible. The bottom sheet must remain scrollable and preserve the existing `MediaQuery.viewInsetsOf(context).bottom` behavior.

## 10. Validation Criteria

- The feature passes targeted Flutter widget tests for Home meal editing.
- `flutter analyze` reports no new issues.
- No backend contracts or OpenAPI files change.
- No deterministic food inference, ingredient translation maps, or regex parsing is introduced.
- Home editing, History editing, and Meal Template editing remain functional.

## 11. Related Specifications / Further Reading

- `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart`
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`
- `apps/mobile/lib/ui/features/dashboard/view_models/dashboard_view_model.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/meal_template_editor_screen.dart`
- `apps/mobile/lib/data/repositories/nutrition_repository.dart`
