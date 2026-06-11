# Trello JGF UI Fixes Implementation Plan

Source: Trello `cal-tracker` board, `to do` list, cards assigned to `jgf2002`.

## Scope

Implement and verify these assigned cards one feature at a time:

1. `1-A.png`
2. `1-A. Correct overlay of the X button with input text border.`
3. `Translate/Semantic fixes.`
4. `3 point button on top right of the Menu does not do anything, remove it.`
5. `Pressing the Add button to an ingredient to a non existent meal in the Meal Proposal Ingredient search doesnt work.`

Each feature must be implemented, tested, reviewed with Berry evidence spans, and justified before starting the next feature.

## Feature 1: `1-A.png`

This card is treated as screenshot evidence for the X-button overlay card because it has no independent description and shares the `1-A` prefix with the overlay fix.

Implementation plan:

1. Use it as visual acceptance context for Feature 2.
2. Do not make a standalone code change unless visual inspection reveals a distinct issue.
3. Record Berry evidence that this was classified as supporting evidence.

Verification:

1. Berry span for the Trello card context.
2. Berry audit confirming no independent implementation is required from the available card data.

## Feature 2: X Button Overlay With Input Border

Context:

The voice-log `_FoodSearchBox` renders search inputs with a leading search icon and a trailing clear X button. The app input theme uses rounded outline borders, so an unconstrained suffix icon can visually collide with the rounded border.

Implementation plan:

1. Update `_FoodSearchBox` in `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`.
2. Keep the clear action and semantics unchanged.
3. Add suffix constraints and/or padding so the X button sits inside the input without overlapping the rounded border.
4. Add or update widget coverage for the populated search input and clear button.

Verification:

1. Run targeted Flutter widget tests for `voice_log_screen_test.dart`.
2. Add Berry spans for the changed input code and test output.
3. Audit that the clear button remains functional and is visually constrained inside the input.

## Feature 3: Translate/Semantic Fixes

Context:

The Menu macro row title is hardcoded as `Macro distribution`; its subtitle composes English macro words. English `templatesTitle` is `Habituals`, while the app already uses `Usual` for the nav label.

Implementation plan:

1. Add localization keys for the Menu macro row title and macro subtitle formats in `app_en.arb` and `app_es.arb`.
2. Replace the hardcoded Menu macro title with the generated localization getter.
3. Localize `_macroDistributionSubtitle`.
4. Change English `templatesTitle` from `Habituals` to `Usuals`; update related user-visible English "habituals" wording where appropriate.
5. Regenerate Flutter localizations.
6. Update widget tests that assert the previous text.

Verification:

1. Run targeted settings and meal-template widget tests.
2. Add Berry spans for ARB changes, generated getter usage, source changes, and test output.
3. Audit that Menu macro text and Usuals text are localized through ARB keys.

## Feature 4: Remove Dead Menu Three-Dot Button

Context:

The Menu header includes a three-dot `FreshIconButton` that has no useful behavior for this screen.

Implementation plan:

1. Remove the Menu `ContentFrame.actions` entry from `SettingsScreen`.
2. Remove the now-unused `settingsMoreTooltip` localization key only if no other code uses it.
3. Add or update a settings widget test asserting the three-dot icon is absent.

Verification:

1. Run targeted settings widget tests.
2. Add Berry spans for the removed action and test output.
3. Audit that the inactive button is no longer rendered.

## Feature 5: Meal Proposal Ingredient Search Add Bug

Context:

The proposal editor can add an empty ingredient row and search for a replacement, but saving routes through `updateProposalItems`. The ViewModel also has separate creation behavior for manual items when no active proposal exists.

Implementation plan:

1. Reproduce and cover the path: proposal editor, add ingredient, search, select result, save.
2. Ensure an empty proposal item row can be populated from search and saved.
3. If a save can occur with no active proposal, route valid items to proposal creation instead of silently returning from update.
4. Keep existing update behavior for active proposals.
5. Add widget and/or ViewModel tests for the failing path.

Verification:

1. Run targeted voice-log widget/ViewModel tests.
2. Add Berry spans for changed ViewModel/UI code and test output.
3. Audit that search-add creates or updates the proposal according to active proposal state.

## Final Verification

After all feature gates pass:

1. Run `flutter test` for the affected mobile test files or the full mobile suite if runtime is acceptable.
2. Run `graphify update .` to refresh the project graph after code changes.
3. Summarize all Berry audits and any remaining assumptions.
