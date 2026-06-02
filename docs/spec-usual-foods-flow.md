---
title: Usual Foods and Usual Meals Flow Specification
version: 1.0
date_created: 2026-05-30
last_updated: 2026-05-30
owner: BetterCalories
tags:
  - product
  - backend
  - flutter
  - food-search
  - agent
  - usual-foods
---

# Usual Foods and Usual Meals Flow Specification

## 1. Purpose

This document specifies the implementation work for adding user-owned usual ingredients to the existing usual meals area.

The current app has an area for "usual meals". In the current domain model, usual meals are complete meal templates with one or more items. This task adds a sibling concept: usual ingredients, also called usual foods in this document. A usual ingredient is a user-created single food/product with explicit nutrition values, such as "Arroz Hacendado" or "Leche desnatada Mercadona".

The feature must let the user:

- create usual ingredients manually;
- optionally use AI to fill a draft faster from explicit user-provided text;
- view, edit, and delete usual ingredients;
- keep existing usual meal template behavior;
- make usual ingredients rank before public database foods in search and meal logging;
- use usual ingredients when adding foods to a meal, including natural-language agent flows such as "anademe 150 g de arroz al almuerzo".

The first implementation must not create usual ingredients automatically from usage frequency, meal history, or inferred habits.

## 2. Scope

### 2.1 In Scope

- Backend contracts for usual ingredient CRUD.
- Backend repository support for user-owned food items as usual ingredients.
- Search priority rules so user-owned usual ingredients appear before public foods for the same user.
- Food resolver behavior so meal proposals prefer user-owned usual ingredients when resolving mentions.
- Flutter UI changes to the existing usual meals section so it also contains usual ingredients.
- Manual usual ingredient creation and editing forms.
- Optional AI-assisted draft filling from explicit user text.
- Localization updates for English and Spanish ARB files.
- Backend and Flutter tests.
- Documentation alignment after implementation.

### 2.2 Out of Scope

- Automatic creation of usual ingredients from repeated usage.
- Automatic promotion of public foods into usual ingredients.
- Background jobs that infer favorites, habits, or usual ingredients.
- Barcode scanning as a required entry point.
- External nutrition API enrichment for missing values.
- Trusted auto-commit changes for usual ingredients.
- Building recipe/plated-food composition beyond the existing meal template model.
- Using LLM output as authoritative nutrition unless the user explicitly supplied the nutrition values and confirmed the saved draft.

## 3. Current Implementation Snapshot

This section documents the relevant current code surfaces so implementation agents can start from the existing architecture.

| Area | Current file(s) | Current behavior |
| --- | --- | --- |
| Database food entity | `apps/backend/src/db/schema.ts` | `food_items` already supports `user_id`, nutrition per serving, brand, barcode, source, and search metadata. |
| Search documents | `apps/backend/src/db/schema.ts`, `apps/backend/src/repository/postgres.ts` | `food_search_documents` supports user-scoped documents. User-owned foods have rank bucket `0`. |
| Repository contract | `apps/backend/src/repository/types.ts` | `AppRepository` has `listFoods`, `searchFoods`, `searchFoodsHybrid`, and `upsertFoodItem`, but no explicit usual ingredient CRUD. |
| Search implementation | `apps/backend/src/repository/postgres.ts`, `apps/backend/src/repository/inMemory.ts` | Search allows foods where `user_id IS NULL OR user_id = current user`. User-owned docs are ordered before generic docs before final scoring. |
| Resolver | `apps/backend/src/nutrition/foodResolver.ts` | Meal proposal resolution calls `searchFoodsHybrid` with user id and food mention. |
| Existing usual meals | `meal_templates`, `meal_template_items`, `food_memories` | Usual meals are complete meal templates. Aliases are stored in `food_memories`. |
| Existing usual meals actions | `packages/contracts/src/actions.ts`, `apps/backend/src/actions/executor.ts` | `get_usual_meals`, `create_meal_template`, `update_meal_template`, and `delete_meal_template` exist. |
| Existing usual meals UI | `apps/mobile/lib/ui/features/meal_templates/...` | UI lists templates and can create a placeholder template with hardcoded chicken/rice items. This hardcoded placeholder must be removed during this task. |
| Mobile repository | `apps/mobile/lib/data/repositories/nutrition_repository.dart` | Exposes search, templates, meal proposal, commit, correction, and deletion calls. |
| Contracts | `packages/contracts/src/common.ts`, `packages/contracts/src/api.ts` | `mealItemSchema` and `nutritionSnapshotSchema` currently include calories, protein, carbs, and fat. Sodium/salt is not part of the core snapshot contract. |

## 4. Definitions

| Term | Definition |
| --- | --- |
| Usual meal | A user-owned reusable complete meal template, stored as a `meal_template` with one or more `meal_template_items`. |
| Usual ingredient | A user-owned single food/product that the user manually saves for repeated use. It is stored as a user-scoped food item, not as a meal template. |
| Public food | A food item imported from reference data such as USDA or Open Food Facts, where `food_items.user_id` is null. |
| User-owned food | A food item created by a specific user, where `food_items.user_id` equals the authenticated user id. |
| Manual entry | A form where the user explicitly enters food name, serving size, and nutrition values. |
| AI-assisted draft | A structured draft created from explicit user text. The draft must be reviewed and saved by the user before it becomes a usual ingredient. |
| Authoritative nutrition | Nutrition values allowed to be saved or used in committed meal snapshots. For usual ingredients, values are authoritative only because the user explicitly provided and confirmed them. |
| Food resolver | Backend logic that turns structured food mentions into meal items using user foods, public databases, portions, and explicit values. |
| Search priority | Ranking behavior where user-owned usual ingredients are returned before public foods when both match the query. |

## 5. Product Requirements

- **REQ-001**: The existing usual meals area must support two resource types: usual meals and usual ingredients.
- **REQ-002**: Usual meals must continue to represent complete meal templates with one or more ingredients.
- **REQ-003**: Usual ingredients must represent a single user-owned food or product with explicit nutrition values.
- **REQ-004**: The user must be able to create a usual ingredient manually from the UI.
- **REQ-005**: The user must be able to view all usual ingredients they created.
- **REQ-006**: The user must be able to edit a usual ingredient.
- **REQ-007**: The user must be able to delete or archive a usual ingredient.
- **REQ-008**: Deleting a usual ingredient must not mutate historical meals or historical meal item nutrition snapshots.
- **REQ-009**: The UI must make clear whether the user is looking at usual meals or usual ingredients.
- **REQ-010**: Search results must prioritize usual ingredients owned by the current user over public database entries when the query matches both.
- **REQ-011**: Food resolution for meal proposals must prefer current-user usual ingredients over public foods when confidence is comparable or higher.
- **REQ-012**: When a user asks to add/log a food by name and a matching usual ingredient exists, the meal proposal item must use the usual ingredient's nutrition source before public foods.
- **REQ-013**: AI-assisted draft creation may be added only as a user-initiated helper for the manual form.
- **REQ-014**: AI-assisted draft creation must never save a usual ingredient without explicit user confirmation.
- **REQ-015**: AI-assisted draft creation must support explicit user-provided nutrition values, for example calories, protein, carbohydrates, fat, serving size, brand, and optional additional label fields.
- **REQ-016**: The first implementation must not infer usual ingredients from frequency, history, repeated searches, selected foods, or logged meals.
- **REQ-017**: Usual ingredient CRUD must be scoped to the authenticated user.
- **REQ-018**: The backend must not expose usual ingredients created by one user to another user.
- **REQ-019**: Usual ingredient search must continue to allow public foods when no user-owned match exists.
- **REQ-020**: Existing meal template creation must stop using hardcoded chicken/rice placeholder items. The user must provide real items, choose foods, or use a validated draft.

## 6. Non-Negotiable Constraints

- **CON-001**: Do not hardcode ingredient names, translations, meal titles, natural-language parsing fallbacks, or food inference shortcuts.
- **CON-002**: Do not use regex-based intent parsing for creating or filling usual ingredients.
- **CON-003**: Do not use deterministic language-specific shortcuts to infer nutrition values.
- **CON-004**: Do not create usual ingredients automatically from "most used" or repeated user behavior in this task.
- **CON-005**: Do not use LLM-only nutrition values as authoritative nutrition.
- **CON-006**: If the user did not explicitly provide a nutrition value and no trusted database value exists, the UI must leave that field empty, show a validation error, or ask for clarification.
- **CON-007**: Public database search must remain available after user-owned prioritization.
- **CON-008**: Historical meal snapshots must remain stable if a usual ingredient is later edited or deleted.
- **CON-009**: Flutter must not perform nutrition reasoning or food resolution. Flutter may collect inputs, display draft data, and call backend actions.
- **CON-010**: All new user-visible strings must be added to both English and Spanish ARB files and generated localization output must be refreshed.

## 7. Data Model

### 7.1 Recommended Persistence Model

Use the existing `food_items` table for usual ingredients.

The recommended representation is:

```text
food_items.user_id = authenticated user id
food_items.source = "user_custom"
food_items.external_source = null
food_items.external_id = null unless a future import/link feature supplies one
food_items.name = user-visible usual ingredient name
food_items.normalized_name = normalized name for search
food_items.canonical_name = optional canonical display/search name
food_items.brand = optional brand/store/manufacturer
food_items.serving_grams = grams represented by the saved nutrition values
food_items.calories/protein_grams/carbs_grams/fat_grams = explicit saved nutrition values for serving_grams
food_items.nutrients_json = optional extra label data
```

This avoids creating a second source of truth for user foods and reuses the existing search-document synchronization.

### 7.2 Required Additional Fields

The current schema is sufficient for MVP usual ingredients if `source = "user_custom"` is used consistently.

If product requirements need stronger lifecycle semantics, add these fields in a migration:

| Field | Type | Required | Purpose |
| --- | --- | --- | --- |
| `deleted_at` | timestamp with timezone | Optional | Soft-delete user-owned foods without deleting historical references. |
| `updated_at` | timestamp with timezone | Optional | Support edit timestamps and cache invalidation. |

MVP implementation may use hard delete only if no meal/proposal/template rows reference the food item. Soft delete is preferred because meal proposal items already have optional `food_item_id` references.

### 7.3 Extra Nutrients

Core app totals currently track:

- calories;
- protein grams;
- carbohydrate grams;
- fat grams.

The user may provide label fields such as salt, sodium, fiber, sugar, saturated fat, or serving description. For this task:

- **MVP requirement**: store extra values in `food_items.nutrients_json` if provided.
- **MVP non-requirement**: do not add salt/sodium to `NutritionSnapshot`, meal totals, dashboard totals, or macro targets.
- **Validation rule**: extra nutrients must not be required to save a usual ingredient.

Recommended `nutrients_json` shape:

```json
{
  "saltGrams": 0.5,
  "sodiumMilligrams": 200,
  "fiberGrams": 3.1,
  "sugarsGrams": 1.2,
  "servingDescription": "100 g"
}
```

## 8. Backend Contracts

### 8.1 New Contract Types

Add contract schemas in `packages/contracts/src/common.ts` or a dedicated food contract module.

Recommended object:

```ts
type UsualFood = {
  id: string;
  name: string;
  canonicalName?: string;
  brand?: string;
  barcode?: string;
  servingGrams: number;
  nutrition: {
    calories: number;
    proteinGrams: number;
    carbsGrams: number;
    fatGrams: number;
  };
  nutrients?: Record<string, unknown>;
  aliases: string[];
  createdAt?: string;
  updatedAt?: string;
};
```

Aliases are optional for MVP. If aliases are included, they must be stored as explicit user-owned search aliases, not hardcoded translations.

### 8.2 REST Endpoints

Add these authenticated endpoints:

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/usual-foods` | List usual ingredients for current user. |
| `POST` | `/v1/usual-foods` | Create a usual ingredient from explicit user input. |
| `PUT` | `/v1/usual-foods/:id` | Update a current user's usual ingredient. |
| `DELETE` | `/v1/usual-foods/:id` | Delete/archive a current user's usual ingredient. |
| `POST` | `/v1/usual-foods/draft` | Optional AI-assisted draft endpoint. It returns a draft only; it does not persist. |

Endpoint names use `usual-foods` instead of `frequent-foods` to avoid implying automatic frequency-based behavior.

### 8.3 Action Layer

Add canonical actions so Flutter, REST, and future OS agents use the same backend behavior.

| Action id | Side effect | Confirmation policy | Purpose |
| --- | --- | --- | --- |
| `get_usual_foods` | none | never | List current user's usual ingredients. |
| `create_usual_food` | write | required | Create one usual ingredient from explicit structured input. |
| `update_usual_food` | write | required | Update one current-user usual ingredient. |
| `delete_usual_food` | destructive | required | Archive/delete one current-user usual ingredient. |
| `draft_usual_food` | none | never | Optional AI-assisted draft fill from user text. No persistence. |

The action executor remains the implementation authority for writes.

### 8.4 Create Request

```json
{
  "name": "Arroz Hacendado",
  "canonicalName": "arroz blanco",
  "brand": "Hacendado",
  "servingGrams": 100,
  "nutrition": {
    "calories": 360,
    "proteinGrams": 7.0,
    "carbsGrams": 79.0,
    "fatGrams": 1.0
  },
  "nutrients": {
    "saltGrams": 0.01
  },
  "aliases": ["mi arroz", "arroz de casa"]
}
```

### 8.5 Draft Request

The draft endpoint receives explicit user text and returns structured data.

```json
{
  "text": "Crea mi arroz Hacendado: por 100 g tiene 360 kcal, 79 g de carbohidratos, 7 g de proteina, 1 g de grasa y 0.01 g de sal."
}
```

Draft response:

```json
{
  "draft": {
    "name": "Arroz Hacendado",
    "brand": "Hacendado",
    "servingGrams": 100,
    "nutrition": {
      "calories": 360,
      "proteinGrams": 7.0,
      "carbsGrams": 79.0,
      "fatGrams": 1.0
    },
    "nutrients": {
      "saltGrams": 0.01
    },
    "missingRequiredFields": []
  },
  "requiresReview": true
}
```

If required fields are missing:

```json
{
  "draft": {
    "name": "Arroz Hacendado",
    "brand": "Hacendado",
    "missingRequiredFields": ["servingGrams", "calories", "proteinGrams", "carbsGrams", "fatGrams"]
  },
  "requiresReview": true,
  "message": "Missing required nutrition values. Please complete them before saving."
}
```

### 8.6 Validation Rules

- `name` is required and must be non-empty after trimming.
- `servingGrams` is required and must be positive.
- `calories` is required, integer, and non-negative.
- `proteinGrams`, `carbsGrams`, and `fatGrams` are required and non-negative.
- Optional extra nutrient values must be numeric if represented as numeric fields.
- `brand`, `canonicalName`, `barcode`, and aliases must be trimmed.
- Empty optional strings must be stored as null or omitted.
- The authenticated user id must be taken from auth context, never from request body.

## 9. Search and Resolution Rules

### 9.1 Search Priority

When searching foods for a user:

1. Include current-user usual ingredients.
2. Include public foods.
3. Exclude foods owned by other users.
4. Rank exact or high-confidence current-user usual ingredients above public foods.
5. Keep public foods available below user-owned matches.

Expected examples:

| User query | User-owned usual ingredient exists | Expected first result |
| --- | --- | --- |
| `arroz` | `Arroz Hacendado` | `Arroz Hacendado` |
| `arroz hacendado` | `Arroz Hacendado` | `Arroz Hacendado` |
| `leche desnatada` | `Leche desnatada Mercadona` | `Leche desnatada Mercadona` |
| `milk` | no user-owned milk | best public milk result |

### 9.2 Resolver Priority

For meal proposals, a structured food mention must resolve in this order:

1. Current-user usual ingredient with strong lexical, alias, barcode, or brand/name match.
2. Public branded/barcode match when the mention clearly has market product intent and no strong user-owned match exists.
3. Public generic food match.
4. Clarification if multiple candidates are plausible and confidence is insufficient.

If the user says "anade 150 g de arroz al almuerzo" and the current user has `Arroz Hacendado`, the proposal item should use `Arroz Hacendado` unless the phrase clearly indicates another rice.

### 9.3 Source Metadata

Meal items created from usual ingredients must include source/provenance metadata sufficient for debugging and UI display:

```json
{
  "source": "user_custom",
  "externalSource": "user_custom",
  "externalId": "<food_item_id>",
  "canonicalName": "arroz blanco",
  "confidence": 0.95
}
```

The implementation may choose another exact field mapping if contracts make it cleaner, but the response must clearly indicate that the item came from a user-owned usual ingredient.

## 10. AI-Assisted Draft Rules

AI support is allowed only for draft filling, not automatic creation.

### 10.1 Allowed Behavior

- The user opens the usual ingredient form.
- The user taps an AI helper button or enters a text command in that form.
- The backend calls the configured tool-calling agent or structured LLM provider.
- The model returns structured draft fields.
- The backend validates the draft.
- Flutter displays the draft in editable fields.
- The user reviews and taps Save.
- Only the Save action creates or updates the usual ingredient.

### 10.2 Disallowed Behavior

- Do not silently save from an agent message.
- Do not infer nutrition values not provided by the user.
- Do not guess missing calories/macros from food name.
- Do not create usual ingredients after repeated logs.
- Do not create usual ingredients from selected search results unless the user explicitly chooses "save as usual ingredient" and confirms the form.
- Do not hardcode Spanish or English parsing shortcuts.

### 10.3 Agent Prompt Requirements

The draft action prompt must instruct the model to:

- extract only values explicitly stated by the user;
- preserve units and serving basis;
- map explicit protein/carbohydrate/fat/calorie values into structured fields;
- map salt/sodium/fiber/sugar/etc. into optional nutrients only when explicitly stated;
- return missing required fields instead of guessing;
- never claim a draft is ready to save if required fields are missing.

## 11. Flutter UX Requirements

### 11.1 Navigation

The existing usual meals screen should become a broader saved/usual foods area.

Recommended UI structure:

```text
Habituals / Usual foods
  [Meals] [Ingredients]
```

Spanish product copy can use:

```text
Habituales
  [Platos] [Ingredientes]
```

This avoids calling single ingredients "comidas habituales".

### 11.2 Usual Ingredients List

The ingredients tab must show:

- name;
- brand if present;
- serving basis, for example `per 100 g`;
- calories;
- protein, carbs, and fat;
- optional source label such as `Manual`;
- edit action;
- delete action.

Empty state:

```text
No usual ingredients yet.
Add foods you use often so they appear first in search and meal logging.
```

### 11.3 Create/Edit Form

Required fields:

- name;
- serving grams;
- calories;
- protein grams;
- carbs grams;
- fat grams.

Optional fields:

- brand;
- canonical/display name;
- barcode;
- aliases;
- salt grams;
- sodium milligrams;
- fiber grams;
- sugars grams;
- serving description.

Validation must happen before save and must show actionable field-level errors where possible.

### 11.4 AI Helper Entry Point

If implemented in the first slice, the form may include:

```text
Fill from text
```

The helper opens a text area or bottom sheet:

```text
Paste the nutrition label or describe the food.
Only values you provide will be filled.
```

The helper must not replace manual entry. It only fills editable fields.

### 11.5 Manual First Implementation

The first implementation may omit the AI helper if needed to deliver a correct manual CRUD and search-priority slice. If omitted, the UI and backend must not include hidden deterministic parsing. The next slice should add `draft_usual_food`.

## 12. Existing Usual Meal Changes

The current `MealTemplatesViewModel.createBasicTemplate` creates templates with hardcoded chicken breast and cooked rice. This violates project rules and must be replaced.

Required changes:

- Remove hardcoded food items from template creation.
- Usual meal creation must require user-selected/manual items or a validated proposal/template draft.
- If the current task does not fully redesign usual meal creation, disable the placeholder create path and show a clear message that meal templates require item selection.
- Keep listing and deletion of existing templates working.

## 13. Permissions and Security

- Usual ingredient endpoints require authenticated user context.
- Reads require nutrition memory/read-equivalent permission.
- Writes require nutrition template/write-equivalent permission or a new food-write permission if added.
- The backend must ignore any `userId` supplied by the client body.
- Repository queries must enforce `food_items.user_id = current user` for usual ingredient updates and deletes.
- Search must never return another user's usual ingredients.
- Audit/action call records should include action id, trace id, source, input summary, and write result.

## 14. Testing Requirements

### 14.1 Backend Unit/Integration Tests

Add or update backend tests for:

- creating a usual ingredient stores a user-owned food item;
- listing returns only the current user's usual ingredients;
- editing a usual ingredient updates search documents;
- deleting/archive hides the usual ingredient from list and search;
- another user cannot read, edit, delete, or search the usual ingredient;
- search ranks `Arroz Hacendado` above public rice for that user;
- search still returns public rice when no user-owned match exists;
- resolver uses user-owned usual ingredient for meal proposal item;
- resolver does not use another user's usual ingredient;
- AI draft endpoint returns missing required fields instead of guessing;
- action executor validates create/update/delete inputs.

### 14.2 Flutter Unit and Widget Tests

Add or update Flutter tests for:

- usual foods screen shows tabs/segmented control for meals and ingredients;
- empty ingredient state renders localized text;
- ingredient list renders name, brand, serving basis, and macros;
- create form validates required fields;
- create form calls repository and appends saved item;
- edit form loads existing values and saves changes;
- delete flow asks for confirmation and removes the item on success;
- AI helper fills fields from a fake repository draft response without saving automatically;
- search UI, if present in tested surfaces, shows usual ingredients before public results.

### 14.3 Localization Tests

- English ARB contains all new strings.
- Spanish ARB contains all new strings.
- Generated localization files are updated.

### 14.4 Manual/Visual Validation

For Flutter UI changes:

1. Run `flutter analyze`.
2. Run `flutter test`.
3. Launch the local/debug app.
4. Use Marionette MCP to inspect the usual foods screen.
5. Verify no layout overflow on a phone-sized viewport.
6. Verify create/edit/delete flows visually.

## 15. Acceptance Criteria

- **AC-001**: Given a user with no usual ingredients, when they open the ingredients tab, then an empty state explains that usual ingredients can be added manually.
- **AC-002**: Given a user enters valid usual ingredient fields manually, when they save, then the ingredient appears in their ingredients list.
- **AC-003**: Given a user omits required nutrition fields, when they save, then the UI blocks saving and shows validation errors.
- **AC-004**: Given user A creates `Arroz Hacendado`, when user A searches for `arroz`, then `Arroz Hacendado` appears before public rice entries.
- **AC-005**: Given user A creates `Arroz Hacendado`, when user B searches for `arroz`, then user B does not see user A's ingredient.
- **AC-006**: Given user A has `Leche desnatada Mercadona`, when user A searches for `leche desnatada`, then that user-owned ingredient is the first relevant result.
- **AC-007**: Given a user has `Arroz Hacendado`, when they ask the agent to add `150 g de arroz` to lunch, then the proposal uses the user-owned ingredient unless the user clearly requested another rice.
- **AC-008**: Given a usual ingredient is edited, when historical meals that used its old values are viewed, then their snapshots remain unchanged.
- **AC-009**: Given a usual ingredient is deleted/archived, when historical meals are viewed, then historical meal items remain visible and unchanged.
- **AC-010**: Given the AI helper receives text with all required values, when it returns a draft, then fields are filled but the ingredient is not saved until the user taps Save.
- **AC-011**: Given the AI helper receives text missing macros, when it returns a draft, then missing required fields are reported and no nutrition values are guessed.
- **AC-012**: Given the existing usual meals create button is used, when no real meal items are supplied, then the app must not create a hardcoded chicken/rice template.

## 16. Implementation Plan

### Phase 1: Manual Usual Ingredient Foundation

1. Add contracts for `usualFood`, CRUD request/response schemas, and action outputs.
2. Add repository methods for usual ingredient list/create/update/delete using user-scoped `food_items`.
3. Implement backend action executor cases.
4. Add REST endpoints.
5. Ensure search documents update after create/update/delete.
6. Add backend tests for user scoping and search priority.

### Phase 2: Flutter Manual UI

1. Add domain model for usual ingredients.
2. Add repository methods to call usual ingredient endpoints.
3. Replace the current usual meals-only screen with a two-tab/segmented usuals screen.
4. Add ingredient list, create/edit form, delete confirmation, loading, empty, and error states.
5. Remove hardcoded chicken/rice template creation.
6. Add English and Spanish localization keys and regenerate localization output.
7. Add widget tests.

### Phase 3: Meal Logging Priority

1. Verify `searchFoodsHybrid` ranks user-owned foods first after final scoring.
2. Adjust scoring if needed so a strong user-owned match cannot be pushed below public foods by generic ranking.
3. Ensure `foodResolver` preserves source metadata for user-owned matches.
4. Add tests for meal proposal resolution using usual ingredients.

### Phase 4: AI-Assisted Draft

1. Add `draft_usual_food` contract and action.
2. Add backend service using structured LLM/tool output.
3. Add prompt rules that extract only explicit values.
4. Add Flutter "Fill from text" helper in the manual form.
5. Add fake repository support for widget tests.
6. Add tests for complete draft, missing fields, and no auto-save.

## 17. Open Decisions

| ID | Decision | Recommendation |
| --- | --- | --- |
| OD-001 | Should deletion be hard delete or soft delete for `food_items`? | Prefer soft delete with `deleted_at`; if not added in MVP, block hard delete when referenced. |
| OD-002 | Should aliases for usual ingredients be stored in `food_aliases` or as search document text only? | Prefer `food_aliases` if aliases need independent management; otherwise include aliases in the user-owned search document. |
| OD-003 | Should AI draft be in the first implementation slice? | Manual CRUD and search priority should ship first if time is constrained. |
| OD-004 | Should the top-level screen be renamed from "Usual meals" to "Habituals" / "Habituales"? | Yes, because the screen will contain meals and ingredients. |
| OD-005 | Should salt/sodium become first-class nutrition fields? | No for this task. Store in `nutrients_json` only. |

## 18. Related Documents

- `docs/README.md`
- `docs/app-description.md`
- `docs/db-vector-architecture.md`
- `docs/voice-agent-gap-analysis.md`
- `docs/drizzle-migration.md`
