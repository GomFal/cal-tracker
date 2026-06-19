---
title: Flutter Technical Debt Remediation Roadmap
version: 1.0
date_created: 2026-06-18
last_updated: 2026-06-18
owner: Mobile engineering
tags: [architecture, flutter, technical-debt, roadmap]
---

# Introduction

This specification defines the implementation roadmap for removing the Flutter technical debt identified by the parallel audit in `review/`, `review2/`, and `review/flutter-technical-debt-summary.md`.

## 1. Purpose & Scope

The scope is `apps/mobile`. The roadmap prioritizes changes that reduce maintenance cost without changing user-visible product behavior unless explicitly listed as an acceptance criterion.

This plan is implementation-ready for coding agents. Each phase should be implemented as a small batch with focused tests.

## 2. Definitions

- **God file**: A source file containing many unrelated classes/responsibilities, usually >800 LOC.
- **SWR**: Stale-while-revalidate. Cached data is shown immediately while backend refresh runs in the background.
- **Voice log screen**: `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`; this is a Flutter UI screen, not the LLM agent. It renders the voice meal logging flow and proposal editing UI. The agent/LLM communication is orchestrated by `VoiceLogViewModel`, `NutritionRepository`, the generated API client, and backend services.
- **Agent output**: Structured meal/proposal/clarification data returned by backend LLM flows.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: Preserve current user-visible behavior unless the child spec explicitly changes an error/empty/accessibility state.
- **REQ-002**: Split large files incrementally. Do not rewrite entire screens in one pass.
- **REQ-003**: Keep cache-first behavior in repository/data layer; do not move JSON cache serialization into ViewModels.
- **REQ-004**: Maintain English and Spanish localization when strings change.
- **REQ-005**: Add or update tests for every refactor that changes behavior, public contracts, or state ownership.
- **CON-001**: Do not hardcode food parsing/ingredient inference fallbacks.
- **CON-002**: Do not call real backend from Flutter widget/unit tests.
- **CON-003**: Generated files under `l10n/generated/` and generated API code should not be manually rewritten unless explicitly required.

## 4. Phase Plan

| Phase | Spec | Goal | Main files touched |
|---|---|---|---|
| 1 | `spec-design-food-search-editor-consolidation.md` | Remove duplicated food search/editor UI | `voice_log_screen.dart`, `food_search_panel.dart`, `meal_item_editor_sheet.dart`, `nutrition_edit_components.dart`, new shared widgets/models |
| 2 | `spec-architecture-voice-log-decomposition.md` | Split `voice_log_screen.dart` into focused widgets | `voice_log_screen.dart`, new `voice_log/views/widgets/*.dart`, `voice_log_helpers.dart`, voice log tests |
| 3 | `spec-quality-flutter-cache-tests.md` | Add missing tests for cache/SWR/rollback | `nutrition_repository_test.dart`, `nutrition_cache_store_test.dart`, `dashboard_cleanup_widget_test.dart`, `meal_history_widget_test.dart` |
| 4 | `spec-architecture-nutrition-repository-split.md` | Split `NutritionRepository` contracts and parsers | `nutrition_repository.dart`, new data/domain files, API/repository tests |
| 5 | `spec-design-flutter-accessibility-responsive.md` | Fix a11y/responsive/i18n/design tokens | scan, dashboard, calorie wizard, app shell, ARB, widget tests |

## 5. Acceptance Criteria

- **AC-001**: After each phase, `cd apps/mobile && flutter analyze` passes.
- **AC-002**: After each phase, focused `flutter test` commands listed in that phase pass.
- **AC-003**: The largest file `voice_log_screen.dart` is reduced materially after Phase 2, with moved widgets covered by existing or new widget tests.
- **AC-004**: Food search/editor behavior remains unchanged from the user perspective after Phase 1.
- **AC-005**: Repository cache tests cover dedupe, cooldown, force refresh, write-through, and user scoping after Phase 3/4.

## 6. Test Automation Strategy

- Default validation: `flutter analyze` and focused `flutter test`.
- Prefer widget tests over Patrol for Flutter-only UI.
- Add Patrol only when native/device behavior is involved, such as camera, microphone, permissions, or platform intents.
- Add semantics tests for icon-only/custom controls.

## 7. Rationale & Context

The audit found no P0 blockers. The highest return comes from reducing coupling and duplication in the voice logging/food editing path before splitting data-layer repositories. This avoids moving business contracts while the UI still has duplicated components.

## 8. Dependencies & External Integrations

- **PLT-001**: Flutter test framework and provider-based state management.
- **DAT-001**: Local cache behavior via `SharedPreferencesAsync` must remain user-scoped.
- **EXT-001**: Backend contracts for nutrition/agent outputs must not be changed by UI-only refactors.

## 9. Examples & Edge Cases

- Cached dashboard data must stay visible during background refresh.
- Voice proposal editing must keep candidate selection, label selection, and manual item addition behavior.
- Spanish locale and large text scale must be tested for dense sheets.

## 10. Validation Criteria

Run after each phase:

```bash
cd apps/mobile
flutter analyze
flutter test
```

For UI phases, also run focused widget tests touched by the changed files.

## 11. Related Specifications / Further Reading

- `review/flutter-technical-debt-summary.md`
- `spec-architecture-voice-log-decomposition.md`
- `spec-design-food-search-editor-consolidation.md`
- `spec-architecture-nutrition-repository-split.md`
- `spec-quality-flutter-cache-tests.md`
- `spec-design-flutter-accessibility-responsive.md`

