---
title: Food Search and Ingredient Editor Consolidation Plan
version: 1.0
date_created: 2026-06-18
last_updated: 2026-06-18
owner: Mobile engineering
tags: [design, flutter, food-search, refactor]
---

# Introduction

This specification defines how to remove duplicated food search and editable ingredient UI from the Flutter app.

## 1. Purpose & Scope

The app currently has a shared `FoodSearchPanel`, a shared `MealItemEditorSheet`, and several private reimplementations inside voice log and editor flows. This plan consolidates them into reusable components and neutral data models.

## 2. Definitions

- **Food search result**: Search result used by UI components when selecting a food candidate.
- **Editable ingredient row/card**: UI for editing quantity, unit, calories/macros, and replacement food.
- **Normalized text**: A helper used for matching/display comparisons; currently duplicated.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: `ui/shared` must not depend directly on `data/repositories/nutrition_repository.dart` for UI-facing result models.
- **REQ-002**: Food search UI must expose configurable callbacks for query, select, clear, empty state, and error state.
- **REQ-003**: Ingredient editor UI must support both meal item editing and voice proposal editing.
- **REQ-004**: Existing debounce behavior and empty/error states must be preserved.
- **CON-001**: Do not infer ingredients deterministically or add regex intent parsing.
- **CON-002**: Do not change backend API contracts in this phase.

## 4. Interfaces & Data Contracts

### Files to touch

Primary:

- `apps/mobile/lib/ui/shared/food_search_panel.dart`
- `apps/mobile/lib/ui/shared/meal_item_editor_sheet.dart`
- `apps/mobile/lib/ui/shared/nutrition_edit_components.dart`
- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
- `apps/mobile/lib/data/repositories/nutrition_repository.dart`
- `apps/mobile/lib/domain/models/nutrition_models.dart` or new domain file.

Tests:

- `apps/mobile/test/voice_log_screen_test.dart`
- `apps/mobile/test/meal_template_editor_widget_test.dart`
- `apps/mobile/test/meal_history_widget_test.dart`
- `apps/mobile/test/nutrition_repository_test.dart` if `FoodSearchResult` moves.

New files to create:

- `apps/mobile/lib/domain/models/food_search_models.dart`
- `apps/mobile/lib/ui/shared/editable_ingredient_row.dart` or `editable_ingredient_card.dart`
- `apps/mobile/lib/ui/shared/text_normalization.dart` or move helper to an existing neutral utility file.

### Model movement

Move or duplicate temporarily then remove:

```dart
// Current location:
// apps/mobile/lib/data/repositories/nutrition_repository.dart
class FoodSearchResult { ... }

// Target location:
// apps/mobile/lib/domain/models/food_search_models.dart
class FoodSearchResult { ... }
```

Update imports in:

- `nutrition_repository.dart`
- `food_search_panel.dart`
- `voice_log_screen.dart`
- `meal_item_editor_sheet.dart`
- tests and fakes using search results.

### Duplicate UI to remove

- `voice_log_screen.dart` `_FoodSearchBox` and `_FoodSearchBoxState`.
- `voice_log_screen.dart` `_InlineReplacementFoodSearch` and state.
- `meal_item_editor_sheet.dart` `_InlineReplacementFoodSearch` can be replaced by the shared configurable component.
- `voice_log_screen.dart` `_EditableIngredientRow` and `meal_item_editor_sheet.dart` `_IngredientEditorCard` should share lower-level row/card components.

## 5. Acceptance Criteria

- **AC-001**: `FoodSearchPanel` no longer imports `NutritionRepository`.
- **AC-002**: There is one canonical `FoodSearchResult` model outside repository implementation.
- **AC-003**: There is one canonical normalized text helper.
- **AC-004**: Voice log and meal item editor flows both use shared food search/editor components.
- **AC-005**: Tests for voice log and meal item editor still pass.

## 6. Test Automation Strategy

Run:

```bash
cd apps/mobile
flutter analyze
flutter test test/voice_log_screen_test.dart
flutter test test/meal_template_editor_widget_test.dart test/meal_history_widget_test.dart
flutter test test/nutrition_repository_test.dart
```

Add focused widget tests for the shared search panel if behavior is not already covered through screen tests.

## 7. Rationale & Context

The audit found duplicated search/editor implementations and a layer leak: shared UI imports the repository only to obtain a result type. Consolidating this first lowers the complexity of splitting `voice_log_screen.dart`.

## 8. Dependencies & External Integrations

- Backend search response remains unchanged.
- Repository maps backend results into the moved domain model.
- ViewModels and widgets consume the same model.

## 9. Examples & Edge Cases

- Empty search query.
- Search error.
- Debounced query cancellation.
- Candidate with portion choice.
- Replacement of an ingredient while preserving manual quantity.

## 10. Validation Criteria

The refactor is complete when duplicated private search widgets are removed and all callers use the shared component/model.

## 11. Related Specifications / Further Reading

- `spec-architecture-voice-log-decomposition.md`
- `review/flutter-size-complexity.md`
- `review2/flutter-size-complexity.md`

