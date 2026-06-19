---
title: Voice Log Screen Decomposition Plan
version: 1.0
date_created: 2026-06-18
last_updated: 2026-06-18
owner: Mobile engineering
tags: [architecture, flutter, voice-log, refactor]
---

# Introduction

This specification defines how to decompose `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart` without changing the voice meal logging user flow.

## 1. Purpose & Scope

`voice_log_screen.dart` is currently a large Flutter UI file of approximately 2590 lines. It is not the LLM agent. It contains the screen and many private widgets for recording status, manual search, clarification, proposal editing, labels, summary cards, candidate swaps, and meal lines.

The scope is to split UI widgets and small helpers into feature-local files while keeping `VoiceLogViewModel` behavior stable.

## 2. Definitions

- **Screen shell**: The public `MealCreateScreen` and its state class.
- **Proposal editor**: UI for editing `MealProposal` ingredients before commit.
- **Candidate resolution**: UI for selecting/swapping food candidates returned by resolver/agent flows.
- **Manual food search**: UI for searching and adding foods manually.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: Keep `MealCreateScreen` as the public route widget.
- **REQ-002**: Keep public navigation inputs compatible, including `MealCreateInitialItems` until a later model extraction.
- **REQ-003**: Move private widgets with minimal logic first; do not change ViewModel state machine in this phase.
- **REQ-004**: All moved widgets must preserve keys, semantics labels, localization calls, and visual layout.
- **REQ-005**: Existing tests in `voice_log_screen_test.dart` and `voice_log_view_model_test.dart` must continue to pass.
- **CON-001**: Do not introduce deterministic food inference or regex parsing fallbacks.
- **CON-002**: Do not call real backend from tests.

## 4. Interfaces & Data Contracts

### Files to touch

Primary:

- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
- `apps/mobile/lib/ui/features/voice_log/view_models/voice_log_view_model.dart` only if imports/types require minor cleanup; no state machine changes in this phase.
- `apps/mobile/lib/ui/features/voice_log/voice_log_helpers.dart`
- `apps/mobile/test/voice_log_screen_test.dart`
- `apps/mobile/test/voice_log_view_model_test.dart` only if type locations change.

New files to create:

- `apps/mobile/lib/ui/features/voice_log/views/widgets/voice_transcript_card.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/manual_food_search_panel.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/manual_draft_ingredient_row.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/resolver_clarification_card.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/voice_food_search_box.dart` or remove if replaced by shared `FoodSearchPanel` in the consolidation spec.
- `apps/mobile/lib/ui/features/voice_log/views/widgets/candidate_list.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/candidate_meal_line.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/voice_status_banners.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/voice_summary_cards.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/meal_label_sheet.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/proposal_card.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/proposal_editor_sheet.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/candidate_swap_strip.dart`
- `apps/mobile/lib/ui/features/voice_log/views/widgets/meal_line.dart`

### Current private classes to move

| Current lines | Symbol | Target file |
|---:|---|---|
| 257 | `_VoiceTranscriptCard` | `voice_transcript_card.dart` |
| 305 | `_ManualFoodSearchPanel` | `manual_food_search_panel.dart` |
| 464 | `_ManualDraftIngredientRow` | `manual_draft_ingredient_row.dart` |
| 617 | `_VoiceQuantityButton` | shared with manual/proposal widgets or `voice_quantity_button.dart` |
| 687 | `_ResolverClarificationCard` | `resolver_clarification_card.dart` |
| 814 | `_ClarificationFoodSearch` | `resolver_clarification_card.dart` or shared food search file |
| 871 | `_FoodSearchBox` | prefer replacement via shared `FoodSearchPanel` |
| 1091 | `_FoodSearchResultLine` | shared food search line or local widget |
| 1155 | `_CandidateList` | `candidate_list.dart` |
| 1188 | `_FoodCandidateStrip` | `candidate_list.dart` |
| 1282 | `_CandidateMealLine` | `candidate_meal_line.dart` |
| 1435 | `_MealCreateVoiceActionButton` | `voice_action_button.dart` if feature-local |
| 1525-1581 | banners | `voice_status_banners.dart` |
| 1597-1720 | summary/cards | `voice_summary_cards.dart` |
| 1761-1883 | `_MealLabelSelection`, `_MealLabelSheet` | `meal_label_sheet.dart` |
| 1896 | `_ProposalCard` | `proposal_card.dart` |
| 1982 | `_ProposalEditorSheet` | `proposal_editor_sheet.dart` |
| 2167 | `_EditableIngredientRow` | shared ingredient editor or `proposal_editor_sheet.dart` |
| 2337 | `_CandidateSwapStrip` | `candidate_swap_strip.dart` |
| 2372 | `_InlineReplacementFoodSearch` | replace with shared component |
| 2486 | `_MetricBlock` | `voice_summary_cards.dart` |
| 2535 | `_MealLine` | `meal_line.dart` |

## 5. Acceptance Criteria

- **AC-001**: `voice_log_screen.dart` contains `MealCreateScreen`, `_MealCreateScreenState`, route-level orchestration, and no more than a small set of screen-specific builders.
- **AC-002**: No moved widget changes user-visible text, keys, localization, or layout behavior.
- **AC-003**: Existing voice log widget and ViewModel tests pass.
- **AC-004**: New files have clear imports and no circular dependencies.
- **AC-005**: `MealCreateInitialItems` is either left in place temporarily or moved with all route/test imports updated.

## 6. Test Automation Strategy

Run:

```bash
cd apps/mobile
flutter analyze
flutter test test/voice_log_screen_test.dart test/voice_log_view_model_test.dart
flutter test test/voice_global_routing_test.dart
```

If shared components are introduced, also run their widget tests.

## 7. Rationale & Context

The file is the highest priority god file. Splitting it first reduces merge conflicts and makes later behavior changes safer. It should be done mostly by moving code, not by rethinking the flow.

## 8. Dependencies & External Integrations

- `VoiceLogViewModel` remains the state source.
- `NutritionRepository` remains the backend/data gateway.
- `FoodSearchPanel` consolidation may be done before or during this phase.

## 9. Examples & Edge Cases

- Clarification flow with candidate selection.
- Manual item add/remove with quantity editing.
- Proposal editor sheet with candidate swap.
- Meal label sheet with custom “Other” input and keyboard.

## 10. Validation Criteria

The refactor is complete when voice log tests pass and `voice_log_screen.dart` no longer owns all private UI classes.

## 11. Related Specifications / Further Reading

- `spec-design-food-search-editor-consolidation.md`
- `review/flutter-size-complexity.md`
- `review2/flutter-size-complexity.md`

