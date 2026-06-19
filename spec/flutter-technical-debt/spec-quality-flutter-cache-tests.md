---
title: Flutter Cache and Validation Test Plan
version: 1.0
date_created: 2026-06-18
last_updated: 2026-06-18
owner: Mobile engineering
tags: [quality, flutter, tests, cache]
---

# Introduction

This specification defines the missing test coverage required before and during the technical-debt refactors.

## 1. Purpose & Scope

The audit found good existing widget/ViewModel coverage, but missing direct coverage for real repository cache behavior, widget-level stale-while-revalidate, some rollback paths, mobile update dialog behavior, semantics, and goldens.

## 2. Definitions

- **Repository cache test**: Test using real repository/cache store with fake API/client dependencies, not only fake repository ViewModels.
- **Widget SWR test**: Widget test proving cached data remains visible while refresh is pending or fails.
- **Rollback test**: Test proving optimistic UI/cache changes are restored when backend mutation fails.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: Tests must not call the real backend.
- **REQ-002**: Use fake repositories/services at Provider boundaries for widget tests.
- **REQ-003**: Mock generated API client only in repository tests.
- **REQ-004**: Keep hit-test warnings fatal.
- **REQ-005**: Add semantics tests for custom/icon-only controls.
- **CON-001**: Do not add Patrol unless native/device behavior is required.

## 4. Interfaces & Data Contracts

### Files to touch

Test files:

- `apps/mobile/test/nutrition_repository_test.dart`
- `apps/mobile/test/nutrition_cache_store_test.dart`
- `apps/mobile/test/data_view_model_cache_test.dart`
- `apps/mobile/test/dashboard_cleanup_widget_test.dart`
- `apps/mobile/test/meal_history_widget_test.dart`
- `apps/mobile/test/bottom_mic_bubble_widget_test.dart`
- `apps/mobile/test/mobile_update_service_test.dart`
- New: `apps/mobile/test/mobile_update_view_model_test.dart`
- New: `apps/mobile/test/mobile_update_dialog_host_widget_test.dart`
- Optional new golden tests under `apps/mobile/test/goldens/` or existing widget test files.

Production files likely touched only for testability:

- `apps/mobile/lib/app/mobile_update_view_model.dart`
- `apps/mobile/lib/ui/core/mobile_update_dialog_host.dart`
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`
- `apps/mobile/lib/ui/features/meal_history/view_models/meal_history_view_model.dart`
- `apps/mobile/lib/data/repositories/nutrition_repository.dart`
- `apps/mobile/lib/data/services/nutrition_cache_store.dart`

### Required test cases

| Area | Required cases |
|---|---|
| `NutritionRepository` cache | cache hit + background refresh, in-flight dedupe, cooldown, `force`, backend failure after cache hit, write-through after mutations |
| `NutritionCacheStore` | usual foods read/write, user scoping, expiry, clear user |
| Dashboard widget SWR | cached summary visible while refresh pending; cached summary remains with error banner if refresh fails |
| Meal history rollback | delete confirmation cancel, delete success, backend failure rollback, backend returns no deleted item rollback |
| Mobile update | VM states, dispose safety, dialog host with fake service, no real update call in bootstrap tests |
| Semantics | global mic, custom nav, scan selector, calorie ruler |
| Goldens | dashboard cards, macro/calorie sheets, meal cards in light/dark and ES where stable |

## 5. Acceptance Criteria

- **AC-001**: `NutritionRepository` cache behavior is covered without backend calls.
- **AC-002**: Dashboard widget tests prove no blocking loader when cached data exists.
- **AC-003**: Meal history delete rollback is covered.
- **AC-004**: Mobile update dialog tests use fakes and cannot hit network/store unintentionally.
- **AC-005**: At least one semantics test covers an icon-only/custom control.

## 6. Test Automation Strategy

Run:

```bash
cd apps/mobile
flutter test test/nutrition_repository_test.dart test/nutrition_cache_store_test.dart test/data_view_model_cache_test.dart
flutter test test/dashboard_cleanup_widget_test.dart test/meal_history_widget_test.dart
flutter test test/bottom_mic_bubble_widget_test.dart
flutter test test/mobile_update_service_test.dart test/mobile_update_view_model_test.dart test/mobile_update_dialog_host_widget_test.dart
```

Full validation:

```bash
cd apps/mobile
flutter analyze
flutter test
```

## 7. Rationale & Context

Refactors that split repository/UI are safer when cache and rollback invariants are directly tested first.

## 8. Dependencies & External Integrations

- Tests use fake API clients, fake repositories, fake storage, and fake services.
- No real backend, device, or Patrol dependency for this spec.

## 9. Examples & Edge Cases

- Backend refresh throws after cached summary loads.
- A mutation succeeds but returned payload differs from optimistic snapshot.
- User A cache must not be visible to User B.
- Widget has large text scale and Spanish strings.

## 10. Validation Criteria

This spec is complete when the listed focused tests pass and full `flutter test` remains green.

## 11. Related Specifications / Further Reading

- `spec-architecture-nutrition-repository-split.md`
- `review/flutter-tests-validation.md`
- `review2/flutter-tests-validation.md`

