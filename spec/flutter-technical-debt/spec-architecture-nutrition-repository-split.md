---
title: Nutrition Repository Split Plan
version: 1.0
date_created: 2026-06-18
last_updated: 2026-06-18
owner: Mobile engineering
tags: [architecture, flutter, data-layer, repository]
---

# Introduction

This specification defines how to split `NutritionRepository` into smaller contracts while preserving cache-first behavior and backend compatibility.

## 1. Purpose & Scope

`apps/mobile/lib/data/repositories/nutrition_repository.dart` currently contains repository methods, UI-facing DTOs, parsing, cache coordination, agent outputs, food search, templates, usual foods, mutations, and telemetry. This plan decomposes it incrementally.

## 2. Definitions

- **Facade repository**: A smaller repository interface for one domain area.
- **Parser**: Pure logic that converts backend JSON/API response objects into domain models.
- **Cache coordinator**: Data-layer component that owns cache read/write/merge/in-flight dedupe/cooldown.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: Preserve public behavior for existing ViewModels.
- **REQ-002**: Keep persistent cache ownership in data layer.
- **REQ-003**: Extract pure parsers before changing repository interfaces.
- **REQ-004**: Prefer adapter/delegation to big-bang migration.
- **REQ-005**: Add tests before or during each extraction.
- **CON-001**: Do not introduce language-specific parsing or deterministic food inference.
- **CON-002**: Do not change backend endpoints in this phase.

## 4. Interfaces & Data Contracts

### Files to touch

Primary:

- `apps/mobile/lib/data/repositories/nutrition_repository.dart`
- `apps/mobile/lib/data/services/nutrition_cache_store.dart`
- `apps/mobile/lib/generated/api/cal_tracker_api.dart` only for imports/types if needed; avoid manual API-client behavior changes.
- `apps/mobile/lib/domain/models/nutrition_models.dart`
- `apps/mobile/lib/domain/models/food_search_models.dart` from the consolidation spec.

ViewModels likely affected by constructor/import changes:

- `apps/mobile/lib/ui/features/dashboard/view_models/dashboard_view_model.dart`
- `apps/mobile/lib/ui/features/meal_history/view_models/meal_history_view_model.dart`
- `apps/mobile/lib/ui/features/meal_templates/view_models/meal_templates_view_model.dart`
- `apps/mobile/lib/ui/features/voice_log/view_models/voice_log_view_model.dart`
- `apps/mobile/lib/ui/features/agent_chat/view_models/agent_chat_view_model.dart`
- `apps/mobile/lib/ui/features/settings/view_models/settings_view_model.dart`

Composition root:

- `apps/mobile/lib/app/app.dart`
- `apps/mobile/lib/local_toolkit/data/local_fakes.dart`

Tests:

- `apps/mobile/test/nutrition_repository_test.dart`
- `apps/mobile/test/nutrition_repository_telemetry_test.dart`
- `apps/mobile/test/nutrition_cache_store_test.dart`
- `apps/mobile/test/data_view_model_cache_test.dart`
- ViewModel tests for affected constructors.

### New files to create

- `apps/mobile/lib/data/repositories/daily_summary_repository.dart`
- `apps/mobile/lib/data/repositories/meal_history_repository.dart`
- `apps/mobile/lib/data/repositories/meal_template_repository.dart`
- `apps/mobile/lib/data/repositories/agent_nutrition_repository.dart`
- `apps/mobile/lib/data/repositories/food_search_repository.dart`
- `apps/mobile/lib/data/repositories/nutrition_cache_coordinator.dart`
- `apps/mobile/lib/data/parsers/agent_result_parser.dart`
- `apps/mobile/lib/data/parsers/usual_food_parser.dart`

### Suggested migration steps

1. Extract pure parsers from `NutritionRepository` without changing public methods.
2. Move `FoodSearchResult` to domain model if not already done.
3. Extract cache coordinator for refresh/dedupe/cooldown/write-through helpers.
4. Add facade classes that delegate to the existing repository/cache coordinator.
5. Migrate ViewModels one by one to smaller facades.
6. Keep `NutritionRepository` as compatibility facade until all callers move.

## 5. Acceptance Criteria

- **AC-001**: Parser tests cover agent/voice/usual food response parsing independently of repository network calls.
- **AC-002**: Cache tests cover user scoping, dedupe, cooldown, force refresh, TTL, and write-through.
- **AC-003**: ViewModels do not need the full `NutritionRepository` if they only use one domain area.
- **AC-004**: `NutritionRepository` shrinks or becomes a thin compatibility facade.
- **AC-005**: No ViewModel serializes/deserializes cache JSON manually.

## 6. Test Automation Strategy

Run:

```bash
cd apps/mobile
flutter analyze
flutter test test/nutrition_repository_test.dart test/nutrition_repository_telemetry_test.dart
flutter test test/nutrition_cache_store_test.dart test/data_view_model_cache_test.dart
flutter test test/voice_log_view_model_test.dart test/agent_chat_test.dart
```

## 7. Rationale & Context

The repository is central to many flows. Splitting it after UI duplication is reduced lowers risk and makes new facades easier to test.

## 8. Dependencies & External Integrations

- Backend REST/SSE contracts remain unchanged.
- `CalTrackerApi` remains the low-level API client.
- `NutritionCacheStore` remains persistent storage implementation.

## 9. Examples & Edge Cases

- Backend refresh fails after cache hit.
- Two ViewModels refresh the same date concurrently.
- Agent result writes meals and summary to cache.
- Template mutation updates templates cache without corrupting daily summary cache.

## 10. Validation Criteria

The split is complete when repository responsibilities are testable independently and ViewModels depend on smaller facades.

## 11. Related Specifications / Further Reading

- `spec-quality-flutter-cache-tests.md`
- `spec-design-food-search-editor-consolidation.md`
- `review/flutter-architecture.md`
- `review2/flutter-context-map.md`

