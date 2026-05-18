# Application Specification and Architecture

## Architectural Review Corrections Applied

This document keeps the original product direction, but corrects several architectural risks:

* The Markdown wrapper fences and stray prompt text were removed so the document is a valid specification.
* Mobile OS integrations are now described as future adapters, not as assumptions the MVP depends on.
* The `app_intents` Flutter package is treated as a candidate adapter library, not as the source of truth or an unavoidable dependency.
* User identity was removed from action input payloads. The backend must inject identity, permissions, locale, timezone, and trust settings through an authenticated `ActionContext`.
* Shared TypeScript schemas are no longer assumed to be directly consumable by Flutter. Flutter must consume generated Dart DTOs or an OpenAPI-generated client.
* Flutter is specified as an MVVM presentation client with API repositories and thin platform adapters. It must not perform agent reasoning, nutrition calculation, database access, or vector retrieval.
* Write actions are now proposal-first, idempotent, auditable, and transaction-backed.
* Privacy, security, observability, testing, and deployment boundaries were made explicit.

## Project Summary

The project is a Flutter mobile calorie and nutrition tracking application designed around an agent-operable action layer.

The app should not be a traditional calorie tracker with a chatbot bolted on. The product should expose structured nutrition capabilities that can be operated safely by:

* the Flutter UI,
* the backend internal agent,
* future Android AppFunctions,
* future iOS App Intents,
* future trusted REST or automation clients.

For the MVP, the primary agent is an internal backend agent. Future mobile OS agents must be thin adapters over the same backend action API.

## Product Vision

The target user experience is natural meal logging:

```text
"I had my usual breakfast."
"Log 150 grams of chicken and rice."
"Same lunch as yesterday."
"I had two eggs, toast, and a protein shake."
"After the gym I ate my normal chicken meal."
"Actually, the chicken was 200 grams, not 150."
"Delete the snack I just added."
"How many calories do I have left today?"
```

The ideal flow is:

```text
User speaks or types
  -> backend agent interprets the request
  -> backend action layer retrieves relevant user memory
  -> backend creates a structured meal proposal
  -> user confirms or corrects
  -> backend commits the meal
  -> memory/templates improve when appropriate
```

The UI should minimize manual data entry, but it must preserve user trust. Confirmation, correction, history, permission controls, and auditability are product features, not secondary details.

## Core Principles

* One canonical action layer, many interfaces.
* Backend action handlers are the only place where writes happen.
* The LLM may select tools and propose structured data, but it must not directly mutate the database.
* Flutter owns presentation, user interaction, and thin platform bridges only.
* PostgreSQL is the source of truth.
* pgvector is semantic retrieval infrastructure, not application truth.
* All user memory and action execution must be scoped to the authenticated user.
* Ambiguous or destructive operations require confirmation.
* Nutrition values must come from known nutrition sources, user custom foods, templates, or explicit user input. The LLM must not invent authoritative nutrition facts.

## MVP Scope

The MVP must prove this product hypothesis:

```text
Users can log recurring meals faster and more reliably through an agentic flow than through a traditional calorie tracking UI.
```

MVP must include:

* Flutter mobile app.
* Android and iOS mobile launch targets.
* Bun + TypeScript backend.
* PostgreSQL + pgvector.
* Docker Compose local development.
* Internal backend agent.
* Replaceable LLM provider abstraction.
* Text input, with voice input added once the action flow is stable.
* Canonical action registry.
* Meal proposal generation.
* User confirmation, correction, and rejection.
* Meal commit flow.
* Daily calorie and macro summary.
* Basic meal templates and semantic memory.
* Audit logging for action calls and mutations.
* Generated API contracts or DTOs for Flutter.

MVP should not require:

* production Android AppFunctions support,
* production iOS App Intents support,
* MCP server,
* photo recognition,
* barcode scanning,
* wearable integrations,
* nutritionist dashboard,
* medical claims,
* microservices.

## Tech Stack

### Mobile Frontend

```text
Flutter
Dart
Generated API client / DTOs
Candidate OS intent adapter: app_intents
Native Kotlin/Swift adapters as fallback
```

Flutter responsibilities:

* voice/text input UI,
* proposal confirmation and correction UI,
* dashboard,
* meal history,
* meal template management UI,
* settings and permission controls,
* API calls to the backend,
* thin Android/iOS platform action adapters.

Flutter must not:

* connect directly to PostgreSQL,
* perform vector search,
* own nutrition calculations,
* run the canonical action executor,
* bypass backend confirmation policy,
* duplicate Android/iOS action business logic.

### Backend

```text
Bun
TypeScript
PostgreSQL
pgvector
Docker
Optional Redis
```

Backend responsibilities:

* authentication and user context resolution,
* internal agent orchestration,
* LLM provider integration,
* STT provider integration if voice audio is sent to the backend,
* canonical action registry,
* action permission checks,
* action execution,
* nutrition lookup and calculation,
* meal proposal, commit, correction, and delete workflows,
* user-specific meal memory,
* vector retrieval and reranking,
* audit logging,
* confirmation policy,
* API endpoints,
* future mobile OS adapter support.

Redis is optional and should be used only for operational concerns such as background jobs, rate limits, short-lived caches, or queues. Redis must not become the source of truth for nutrition or meal data.

### Database

```text
PostgreSQL 16 or newer
pgvector extension
SQL migrations managed by the backend
```

PostgreSQL stores users, meals, meal items, proposals, templates, food memories, nutrition targets, action calls, confirmations, corrections, audit events, and custom foods.

pgvector stores embeddings used to retrieve user-specific semantic memories. Vector rows must point back to structured relational records.

Embedding generation is provided by OpenRouter using `openai/text-embedding-3-small`. The model is not hosted by us; the backend requests embeddings from OpenRouter and stores the returned 1536-dimensional vectors for multilingual food memory retrieval. Flutter must never generate embeddings or call an embedding model provider directly.

### LLM Provider

The initial provider may be OpenRouter with a low-latency model, but the backend must not be hardcoded to OpenRouter, DeepSeek, or any single model.

Use a provider abstraction:

```ts
interface LLMProvider {
  runToolCalling(input: ToolCallingInput): Promise<ToolCallingResult>;
}
```

Possible implementations:

```text
OpenRouterProvider
OpenAIProvider
GeminiProvider
AnthropicProvider
LocalProvider
```

Provider requirements:

* supports structured tool calling or a reliable structured-output fallback,
* has timeout and retry controls,
* exposes latency, token, and cost metrics,
* supports model configuration outside code,
* can be swapped without changing action handlers.

### Speech-to-Text

Initial STT options:

```text
Whisper-compatible API
OpenAI audio transcription
Groq Whisper-compatible endpoint
Deepgram
Native mobile speech APIs later if useful
```

Use a provider abstraction:

```ts
interface STTProvider {
  transcribe(audio: AudioInput): Promise<TranscriptionResult>;
}
```

The MVP should support typed input before voice. This validates the agent and action flow before adding audio latency, permission prompts, and device-specific speech behavior.

## System Architecture

Current MVP flow:

```text
Flutter app
  -> backend API
  -> internal backend agent
  -> canonical action registry
  -> deterministic action executor
  -> PostgreSQL + pgvector + nutrition providers
```

Future mobile OS flow:

```text
Gemini / Siri / Apple Intelligence
  -> Android AppFunction or iOS App Intent
  -> Flutter/native adapter
  -> backend action API
  -> same deterministic action executor
  -> same PostgreSQL + pgvector + nutrition providers
```

The future OS path must not introduce a second action system.

## Repository Structure

Recommended monorepo:

```text
cal-tracker/
  README.md
  AGENTS.md
  .env.example
  docker-compose.yml

  docs/
    README.md
    app-description.md
    db-vector-architecture.md

    architecture/
      # Future split: action layer, backend agent, mobile OS integrations

  apps/
    mobile/
      # Flutter app

    backend/
      # Bun + TypeScript backend

  packages/
    contracts/
      # TypeScript source schemas and generated OpenAPI/JSON Schema

    prompts/
      # Versioned agent prompts and evaluation fixtures

  infra/
    db/
      init.sql
    nginx/
    scripts/
```

`packages/contracts` is the canonical contract package for backend and API schemas. Flutter should consume generated Dart models or an OpenAPI-generated client. Flutter should not import TypeScript or Zod directly.

## Canonical Action Layer

Every app capability that an agent can operate must be represented as a canonical backend action.

Each action definition must include:

* stable ID,
* semantic version,
* title and description,
* input schema,
* result schema,
* permission scope,
* confirmation policy,
* side-effect classification,
* deterministic backend handler.

The action executor receives an authenticated context from the backend. Action input schemas must not include `userId` fields supplied by the client or LLM.

```ts
type ActionSource =
  | "flutter"
  | "internal_agent"
  | "android_appfunctions"
  | "ios_appintents"
  | "rest";

type ActionContext = {
  actorUserId: string;
  actorType: "user" | "internal_agent" | "external_agent";
  source: ActionSource;
  scopes: string[];
  timezone: string;
  locale: string;
  trustedModeEnabled: boolean;
  traceId: string;
  idempotencyKey?: string;
};

type AppActionDefinition<Input, Result> = {
  id: string;
  version: string;
  title: string;
  description: string;
  inputSchema: unknown;
  resultSchema: unknown;
  permissionScope: string;
  confirmationPolicy:
    | "never"
    | "before_commit"
    | "always"
    | "trusted_mode_only";
  sideEffect: "read" | "propose" | "write" | "delete";
  executionMode: "foreground" | "background" | "either";
  handler: (ctx: ActionContext, input: Input) => Promise<Result>;
};
```

The LLM sees action names, descriptions, and input schemas. It must not receive direct database access, service clients, or privileged context fields.

## Initial Canonical Actions

| Action | Side effect | Confirmation | Purpose |
| --- | --- | --- | --- |
| `query_food_memory` | read | never | Retrieve user-scoped semantic meal memories. |
| `search_nutrition_database` | read | never | Search food data sources and custom foods. |
| `propose_meal_log` | propose | before_commit | Create a pending meal proposal from text or resolved memory. |
| `commit_meal` | write | before_commit / trusted_mode_only | Commit a pending proposal to meal records. |
| `correct_meal` | write | before_commit | Apply a correction to a proposal or meal. |
| `delete_meal` | delete | always | Soft-delete or remove a meal. |
| `get_daily_summary` | read | never | Return calories/macros for a day. |
| `get_remaining_targets` | read | never | Return remaining daily targets. |
| `get_meal_history` | read | never | Return committed meal history. |
| `get_usual_meals` | read | never | Return templates and aliases. |
| `create_meal_template` | write | before_commit | Create a reusable meal template. |
| `update_meal_template` | write | before_commit | Update a recurring template. |
| `delete_meal_template` | delete | always | Archive a template and its semantic aliases. |
| `update_nutrition_targets` | write | always | Modify calorie and macro targets. |
| `export_user_data` | read | always | Export user data. |
| `delete_account` | delete | always | Delete account data and embeddings. |

## Action Examples

`propose_meal_log` input should omit `userId`:

```ts
type ProposeMealLogInput = {
  text: string;
  occurredAt?: string;
  mealType?: "breakfast" | "lunch" | "dinner" | "snack" | "post_workout" | "unknown";
};
```

The backend derives `actorUserId`, timezone, locale, scopes, and source from `ActionContext`.

Expected output:

```ts
type MealProposalResult = {
  proposalId: string;
  items: Array<{
    foodName: string;
    quantity: number;
    unit: string;
    state?: "raw" | "cooked" | "unknown";
    calories: number;
    proteinG: number;
    carbsG: number;
    fatG: number;
    confidence: number;
    source: "nutrition_database" | "user_template" | "manual" | "unknown";
  }>;
  totalCalories: number;
  totalProteinG: number;
  totalCarbsG: number;
  totalFatG: number;
  confidence: number;
  requiresConfirmation: boolean;
  reason?: string;
};
```

`commit_meal` should accept only a proposal ID and confirmation metadata:

```ts
type CommitMealInput = {
  proposalId: string;
  confirmationSource: "user_tap" | "user_voice" | "trusted_auto_commit" | "external_agent_confirmed";
};
```

The handler must verify that the proposal belongs to `ctx.actorUserId`.

## Backend Architecture

Recommended backend structure:

```text
apps/backend/
  src/
    index.ts
    server.ts

    config/
      env.ts

    db/
      client.ts
      migrations/
      schema/

    modules/
      auth/
      users/
      actions/
      agent/
      confirmations/
      meals/
      memory/
      nutrition/
      summaries/
      audit/
      jobs/

    integrations/
      llm/
      stt/
      nutrition_sources/
      embeddings/

    routes/
      health.routes.ts
      agent.routes.ts
      actions.routes.ts
      meals.routes.ts
      summaries.routes.ts
      templates.routes.ts
```

Backend implementation rules:

* Action handlers must be deterministic and unit-testable without LLM calls.
* The agent module can decide which action to call, but it cannot bypass the action executor.
* Every write action must log an `action_call` and an `audit_event`.
* Write actions must use database transactions.
* Commit/correction/delete endpoints must be idempotent where retries are possible.
* Nutrition calculation should live in the nutrition module, not in agent prompts.
* Prompt text and model names must be versioned and logged for agent-initiated action calls.

## Flutter Architecture

Recommended Flutter structure:

```text
apps/mobile/
  lib/
    main.dart

    app/
      app.dart
      router.dart
      theme.dart

    data/
      models/
      repositories/
      services/

    domain/
      models/
      use_cases/

    ui/
      core/
      features/
        voice_log/
          view_models/
          views/
        meal_confirmation/
          view_models/
          views/
        dashboard/
          view_models/
          views/
        meal_history/
          view_models/
          views/
        meal_templates/
          view_models/
          views/
        settings/
          view_models/
          views/

    platform/
      intents/
        action_bridge.dart
        android_appfunctions_adapter.dart
        ios_appintents_adapter.dart

    generated/
      api/
```

Flutter should use an MVVM-style presentation layer:

* Views render UI and handle local visual state only.
* ViewModels expose immutable state snapshots and command methods.
* Repositories call backend API services and transform DTOs into domain models.
* Platform adapters translate Android/iOS intent invocations into backend action requests.

No meal parsing, nutrition reasoning, vector retrieval, or committed data mutation should happen inside Flutter.

### Flutter Development Skills

Flutter implementation work must use the existing project skills under `.agents/skills` when the task matches them:

* Use `flutter-apply-architecture-best-practices` when creating or refactoring the Flutter MVVM structure.
* Use `flutter-setup-declarative-routing` when adding app navigation, deep links, or route guards.
* Use `flutter-use-http-package` when implementing backend API access outside the generated client runtime.
* Use `flutter-build-responsive-layout` for mobile/tablet layout work and adaptive screens.
* Use `flutter-fix-layout-issues` whenever Flutter reports layout overflow or unbounded constraint errors.
* Use `flutter-add-widget-test` for component-level widget behavior and rendering tests.
* Use `flutter-add-integration-test` only for the small set of device-backed flows that cannot be covered with widget tests, such as native permissions, microphone/recording, OS-agent adapters, deep links, platform views, and pre-release smoke tests.
* Use `flutter-add-widget-preview` when building reusable or visually complex widgets.
* Use `flutter-setup-localization` before introducing user-visible strings that need localization.
* Use `flutter-implement-json-serialization` only for small manual DTOs not covered by the generated OpenAPI client.

## Mobile OS Agent Integrations

### Platform Reality Check

As of this review on 2026-05-08:

* Android AppFunctions are an Android 16 / API 36+ capability and must be feature-detected.
* Authorized Android callers require the platform permission to discover and execute AppFunctions.
* Apple App Intents are the native route for exposing app capabilities to Siri, Shortcuts, Spotlight, widgets, controls, and Apple Intelligence experiences.
* The current `app_intents` Flutter package advertises iOS App Intents and Android AppFunctions support, but also lists iOS 17+ and Android API 36+ requirements.

Therefore, OS-agent integration must be a feature-flagged adapter layer. The MVP must remain fully usable through the Flutter UI and backend internal agent on devices that do not support these OS features.

The intended stance is:

```text
Do not depend on OS integrations for MVP usability.
Do prototype OS integrations during the MVP if tooling and devices allow it.
```

The MVP may include an experimental App Intents/AppFunctions spike as long as it remains a thin adapter over the backend action layer and does not block the core Flutter + backend agent flow.

### Experimental MVP Spike

Goal:

```text
Prove that the backend action registry can be exposed through real mobile OS action systems without changing backend business logic.
```

Required constraints:

* The spike must be feature-flagged.
* The app must work without the spike.
* The spike must call the same backend action API used by Flutter and the internal agent.
* The spike must not commit meals directly from native Kotlin, Swift, or Flutter adapter code.
* The spike must not duplicate nutrition lookup, memory retrieval, confirmation policy, or action execution.
* Any native/generated declarations must be treated as adapters generated from or mapped to the canonical action registry.

Recommended initial OS-exposed actions:

| Action | Why | Confirmation behavior |
| --- | --- | --- |
| `get_daily_summary` | Read-only and easy to validate. | No confirmation. |
| `get_usual_meals` | Read-only and useful for OS agent/entity tests. | No confirmation. |
| `propose_meal_log` | Tests natural app capability without permanent writes. | Creates proposal only. |

Do not expose these actions in the first spike:

```text
commit_meal
delete_meal
update_nutrition_targets
delete_account
export_user_data
```

Those require the confirmation system, session handling, user messaging, and audit trail to be mature first.

Spike success criteria:

* A real iOS App Intent can call the backend and return a result through Shortcuts/Siri where supported.
* A real Android AppFunction can call the backend on API 36+ tooling/device support where available.
* The backend logs each OS-originated action with source `ios_appintents` or `android_appfunctions`.
* The same action handler produces equivalent results when called by Flutter, the internal agent, and the OS adapter.
* Unsupported devices hide or disable OS integration entry points without affecting the core app.

### Android AppFunctions

Android AppFunctions are an adapter for Android devices that support the platform feature. The MVP app must not require AppFunctions to work, but an experimental AppFunction spike may be included.

Android flow:

```text
Gemini / authorized Android caller
  -> Android AppFunction
  -> Kotlin adapter or generated app_intents adapter
  -> Flutter action bridge if app process is available
  -> backend action API
  -> canonical action executor
```

Implementation rules:

* Keep Android-specific declarations under `apps/mobile/android/`.
* Treat AppFunctions availability as feature-detected and feature-flagged.
* Target Android API 36+ only for AppFunctions-specific code.
* Keep the normal Flutter app minimum Android version independent from AppFunctions support.
* Prefer generated Kotlin declarations from `app_intents_codegen` only if the generated code cleanly maps to backend action definitions.
* Do not duplicate backend action logic in Kotlin.
* The adapter must call the backend with the currently authenticated app user.
* The backend must still enforce scopes, confirmation policy, and ownership.
* If an AppFunction is invoked while the user is not authenticated, return a structured "authentication required" result and request foreground continuation where the platform supports it.
* Test with one read action before exposing proposal actions.

### iOS App Intents

iOS App Intents are an adapter for Siri, Shortcuts, Spotlight, widgets, and Apple Intelligence experiences. The MVP app must not require Siri/App Intents to work, but an experimental App Intent spike should be prioritized before Android if only one OS spike is feasible because iOS App Intents can be tested through Shortcuts/Siri flows today.

iOS flow:

```text
Siri / Shortcuts / Apple Intelligence
  -> App Intent
  -> Swift declaration or generated adapter
  -> Flutter action bridge if available
  -> backend action API
  -> canonical action executor
```

Implementation rules:

* Keep iOS-specific declarations under `apps/mobile/ios/`.
* Expect some static Swift declarations or generated Swift code for discoverability.
* Prefer generated Swift declarations from `app_intents_codegen` only if the generated code cleanly maps to backend action definitions.
* Use App Groups only if an extension process needs shared state.
* Do not put nutrition or action execution logic in Swift.
* The backend must still enforce scopes, confirmation policy, and ownership.
* If an App Intent is invoked while the user is not authenticated, return a clear authentication-required dialog/result and open the app when supported.
* Test first with `get_daily_summary`, then `propose_meal_log`.
* Treat Siri/Apple Intelligence natural language behavior as platform-dependent. The deterministic test surface is the App Intent appearing and running from Shortcuts.

### `app_intents` Package Position

The `app_intents` Flutter package can be evaluated as an adapter because it advertises iOS App Intents and Android AppFunctions support. It should not be treated as the core architecture because:

* the backend action layer is the source of truth,
* OS API availability is platform- and version-dependent,
* native declarations/code generation may still be needed,
* the package may need fallback native implementations if it lacks required behavior.

Before production use, pin the package version, build a proof of concept for one read action and one write/proposal action, and verify behavior on real Android and iOS devices.

The evaluation should answer:

* Can action declarations be generated from the canonical backend action registry or a shared contract?
* Can iOS App Intents and Android AppFunctions call Dart/Flutter reliably enough, or is direct native-to-backend code simpler?
* Can authentication-required states open the app cleanly?
* Can results be returned in a user-friendly format to Shortcuts/Siri/Gemini surfaces?
* Does the package impose OS version constraints that are acceptable for optional adapters?
* Does the package require native changes that should be owned under `apps/mobile/ios/` and `apps/mobile/android/`?

## API Requirements

Minimum backend routes:

```text
GET    /v1/health

GET    /v1/actions
POST   /v1/actions/:actionId/execute

POST   /v1/agent/runs

POST   /v1/meals/proposals
POST   /v1/meals/proposals/:id/commit
POST   /v1/meals/proposals/:id/correct
POST   /v1/meals/:id/correct
DELETE /v1/meals/:id

GET    /v1/summary/daily
GET    /v1/meals
GET    /v1/meal-templates
POST   /v1/meal-templates
PATCH  /v1/meal-templates/:id
DELETE /v1/meal-templates/:id

GET    /v1/agent-connections
POST   /v1/agent-connections
DELETE /v1/agent-connections/:id
```

All authenticated routes must derive the user from the session or access token. Do not trust `userId` in request bodies.

`/v1/agent/runs` is used by the internal backend agent.

`/v1/actions/:actionId/execute` is used by Flutter UI commands and future adapters.

Both must use the same action executor.

## Data Model Requirements

Minimum tables are defined in `docs/db-vector-architecture.md`.

At application level, the model must support:

* users,
* user credentials,
* auth sessions,
* password reset tokens,
* nutrition targets,
* food items and custom foods,
* meal proposals,
* meal proposal items,
* committed meals,
* committed meal item nutrition snapshots,
* meal templates,
* meal template item snapshots,
* user semantic memories,
* embeddings,
* corrections,
* action calls,
* confirmation requests,
* audit events,
* agent connections,
* outbox/background jobs.

Committed meals and meal items must store nutrition snapshots. If a food provider changes nutrition data later, historical meal totals must remain stable unless the user explicitly recalculates them.

## Memory System

Use hybrid memory:

```text
PostgreSQL = source of truth
pgvector = semantic retrieval
templates = structured recurring user defaults
nutrition providers = factual nutrition source
LLM = interpretation and tool-selection layer
OpenRouter openai/text-embedding-3-small = multilingual embedding generation
```

Vector memory is for fuzzy retrieval of:

* usual meal phrases,
* meal aliases,
* repeated meal patterns,
* vague references,
* contextual habits.

Vector memory is not for:

* committed calories,
* source-of-truth meal items,
* account state,
* permissions,
* audit history,
* deterministic temporal lookup such as "same lunch as yesterday".

## Nutrition Data

Initial sources:

```text
USDA FoodData Central
Open Food Facts
custom user foods
manual entries
```

USDA FoodData Central is the authoritative provider for single-ingredient basic foods and generic ingredient nutrition. Open Food Facts is the provider for branded, packaged, supermarket, and barcode-based products. For Spain and Europe, Open Food Facts and custom foods are important because packaged product coverage is stronger there than USDA generic data. The app should support metric units by default.

Nutrition lookup priority:

```text
1. User-confirmed meal templates and user custom foods.
2. USDA FoodData Central cached generic ingredient match for basic single-ingredient foods.
3. USDA FoodData Central live lookup when the generic ingredient is not cached.
4. Open Food Facts barcode or exact branded/packaged product match.
5. Manual user-provided nutrition values for explicit custom foods.
```

The backend must not use LLM-only nutrition values or unprovenanced seed values as authoritative nutrition data. If the backend cannot resolve nutrition values from USDA FoodData Central, Open Food Facts, user custom foods, or user-confirmed templates, the proposal must ask for clarification or explicit manual nutrition values rather than inventing calories/macros.

Provider roles:

| Food type | Provider |
| --- | --- |
| Single-ingredient generic foods such as eggs, rice, chicken, oats, vegetables, fruit, oil, butter, and milk | USDA FoodData Central |
| Generic household/count units such as cup rice, one egg, one banana, tbsp oil | USDA FoodData Central food portion metadata |
| Branded packaged products, supermarket products, barcode scans, label nutrition | Open Food Facts |
| User recipes, personal foods, usual meals | User-confirmed custom foods/templates |

Food rows imported into the database must preserve provider provenance:

* `external_source`,
* `external_id`,
* source URL when available,
* license,
* fetch/import timestamp,
* normalized serving gram weight,
* provider portion metadata when used for non-metric unit conversion.

Rows without provider provenance may exist only as explicit user custom foods or test fixtures. They must not be labeled as USDA or Open Food Facts data.

The system must support:

* generic foods,
* branded foods,
* user custom foods,
* raw/cooked state,
* grams, milliliters, pieces, servings, and common household units,
* conversion to normalized gram or milliliter quantities where possible,
* correction-based personalization.

Do not over-optimize food search before validating the logging loop. The core advantage is personal meal memory plus low-friction correction.

## Internal Agent Requirements

The internal agent must:

1. receive authenticated user input,
2. load available action definitions,
3. load safe user context through backend services,
4. call the LLM provider with allowed tool schemas,
5. validate selected tool/action arguments,
6. execute deterministic backend actions through the executor,
7. return a structured response to Flutter.

Expected flow:

```text
User: "Log my usual breakfast."

Backend agent:
1. calls query_food_memory({ concept: "usual breakfast" })
2. calls propose_meal_log({ text: "usual breakfast", mealType: "breakfast" })
3. returns a meal proposal
```

The agent must not directly update the database outside the action executor.

## Safety Rules

The LLM must not:

* directly write to the database,
* invent nutrition values when lookup or user-specific data is available,
* bypass confirmation policy,
* delete meals without confirmation,
* modify nutrition targets without confirmation,
* expose one user's data to another user,
* silently commit ambiguous meals,
* receive raw secrets or database credentials,
* receive user data that is not needed for the requested action.

The LLM may:

* interpret natural language,
* select tools/actions,
* ask clarification questions,
* summarize results,
* propose structured meal logs,
* explain uncertainty.

## Confirmation Policy

The default write flow is proposal-first:

```text
Natural language input
  -> meal proposal
  -> user confirmation or correction
  -> committed meal
```

Confirmation levels:

| Level | Name | Behavior | Examples |
| --- | --- | --- | --- |
| 0 | Read-only | No confirmation needed. | `get_daily_summary`, `get_meal_history` |
| 1 | Safe proposal | Agent can create pending proposal. | `propose_meal_log` |
| 2 | Trusted write | Commit only if user enabled trusted mode and confidence is high. | "Log my usual breakfast." |
| 3 | Sensitive/destructive | Always confirm. | delete meal, modify targets, export, delete account |

Trusted auto-commit is an MVP feature, but it must be disabled by default. Users must explicitly opt in, and the UI must make it easy to turn off.

## Permissions

Design for scoped action access:

```text
nutrition.read.summary
nutrition.read.history
nutrition.read.memory
nutrition.write.propose
nutrition.write.commit
nutrition.write.correct
nutrition.write.delete
nutrition.targets.modify
nutrition.export
account.delete
```

Default policy:

* Read summary: allowed with scope.
* Query memory: allowed with scope.
* Propose meal: allowed with scope.
* Commit meal: confirmation required unless trusted mode allows it.
* Delete meal: confirmation required.
* Modify targets: confirmation required.
* Export history: explicit confirmation required.
* Delete account: explicit confirmation required.

## Privacy and Security Requirements

The app handles health-adjacent personal data. It must support:

* custom backend-owned authenticated sessions,
* HTTPS in production,
* server-side authorization on every route,
* data export,
* delete account,
* delete all user embeddings and memory,
* revoke agent connections,
* audit agent actions,
* redact sensitive data in logs,
* provider API keys stored only on the backend,
* no medical diagnosis or treatment claims.

If a user deletes account data, related embeddings and semantic memories must be deleted too.

## Scoped Architecture Decisions

### Authentication

Decision: the MVP will use custom backend-owned authentication sessions instead of an external auth provider.

Scope:

* The Bun + TypeScript backend owns registration, login, logout, session issuance, session validation, refresh/rotation, password reset, and account deletion.
* PostgreSQL stores users, password credentials, session records, password reset tokens, and security audit events.
* Flutter authenticates only through backend API endpoints and stores session material using platform secure storage.
* Backend routes derive the application user from the validated session. Request bodies must not provide trusted user identity.
* The action executor receives identity through `ActionContext.actorUserId`.

Minimum security requirements:

* Passwords must be hashed with a modern password hashing algorithm such as Argon2id or bcrypt with appropriate work factors.
* Sessions must be random, high-entropy, revocable, expiring, and rotated when refreshed.
* Password reset tokens must be one-time-use, short-lived, hashed at rest, and audited.
* Login, registration, and reset endpoints must have rate limits and abuse protection.
* Session invalidation must support logout from the current device and revocation of all sessions.
* Authentication events must create audit events for login success, login failure, logout, password reset request, password reset completion, and suspicious activity.

Non-goals for the MVP:

* OAuth/social login.
* SAML or enterprise SSO.
* Multi-factor authentication unless added later as a security hardening milestone.
* Delegating identity to Supabase Auth, Clerk, Firebase Auth, Auth0, Cognito, or another external auth provider.

### Target Launch Platforms and Minimum OS Versions

Decision: the MVP launches as a mobile app for Android and iOS only.

Core app support:

| Platform | Minimum supported version | Reason |
| --- | --- | --- |
| Android | Android 10 / API 29 | Broad enough device support while avoiding old Android storage, permission, TLS, and background-behavior edge cases. |
| iOS | iOS 17.0 | Keeps the iOS MVP aligned with the current `app_intents` adapter/codegen path and avoids maintaining a lower iOS target while experimenting with App Intents. |

Build targets:

* Android should use `minSdk` 29.
* Android should use `compileSdk` 36 or newer so AppFunctions-specific code can compile.
* Android should use the latest stable `targetSdk` required by Google Play at submission time. If API 36 is stable and required/appropriate at launch, use `targetSdk` 36.
* iOS should set the Flutter/Xcode deployment target to iOS 17.0.

Optional OS-agent adapter support:

| Adapter | Minimum OS/API | MVP status |
| --- | --- | --- |
| Android AppFunctions | Android 16 / API 36+ | Experimental, feature-flagged spike only. |
| iOS App Intents | iOS 17+ for the initial Flutter adapter/codegen approach | Experimental, feature-flagged spike included in MVP development. |

Rules:

* AppFunctions availability must not raise the normal Android install minimum above API 29.
* Android AppFunctions code must be guarded behind API checks and feature flags.
* iOS App Intents can be part of the iOS 17+ MVP, but the app must remain usable without invoking Siri, Shortcuts, Spotlight, or Apple Intelligence.
* Apple Intelligence-specific behavior must be treated as platform-dependent and not required for MVP acceptance.
* Web, desktop, tablet-first layouts, watch apps, widgets, and wearables are not MVP launch targets.

Minimum test matrix:

| Platform | Required test target |
| --- | --- |
| Android minimum | Android 10 / API 29 emulator or device |
| Android common | Android 14/15 emulator or device |
| Android OS-agent spike | Android 16 / API 36 emulator or device when available |
| iOS minimum | iOS 17 simulator or device |
| iOS current | Latest stable iOS simulator or device available during development |
| iOS OS-agent spike | iOS 17+ Shortcuts/App Intent test |

### Initial Nutrition Source Priority

Decision: the MVP will use a deterministic source-priority order optimized for Spain/EU users while preserving user-specific overrides.

Priority order:

```text
1. User-confirmed meal templates and user custom foods.
2. USDA FoodData Central cached generic ingredient match for basic single-ingredient foods.
3. USDA FoodData Central live lookup when the generic ingredient is not cached.
4. Open Food Facts barcode or exact branded/packaged product match.
5. Manual user-provided nutrition values for explicit custom foods.
```

Rules:

* User-confirmed templates and custom foods override public databases for that user.
* USDA FoodData Central is the authoritative public source for generic whole foods and single ingredients such as eggs, chicken, rice, oats, vegetables, fruit, dairy, oils, and basic pantry ingredients.
* USDA FoodData Central portion metadata is the authority for validating household/count units for generic foods.
* Open Food Facts is preferred for branded packaged foods, supermarket products, and barcode flows, especially Spain/EU products.
* Manual user-provided values can be used when the user explicitly enters calories/macros or creates a custom food.
* Backend calculations must be traceable to provider facts, user-provided values, quantities, and conversion assumptions.
* LLM-only nutrition values and unprovenanced seed nutrition values must not be used as authoritative meal-item nutrition.
* Cached provider data must store provenance fields and must be refreshable.

### Production Database Hosting

Decision: production starts with self-hosted PostgreSQL + pgvector running in a Docker container on the VPS, not managed Postgres.

Scope:

* The production database runs in the project-owned VPS environment.
* PostgreSQL must use persistent storage, not ephemeral container storage.
* PostgreSQL must not expose port `5432` publicly.
* The backend is the only service that connects to the database.
* Docker Compose or equivalent deployment configuration must define health checks and restart policy.
* Database credentials must be provided through production secrets, not committed files.

Operational requirements:

* Automated encrypted backups must be configured before production use.
* Restore testing must be performed before production use and repeated after backup changes.
* Disk usage monitoring and alerts are required.
* PostgreSQL and pgvector upgrade procedures must be documented.
* The deployment must include a clear full-reset procedure for staging only, never production.

Non-goal:

* Managed Postgres providers such as Supabase, Neon, Railway, Render, AWS RDS, Cloud SQL, or DigitalOcean Managed PostgreSQL are not part of the MVP production plan.

### Trusted Auto-Commit

Decision: trusted auto-commit is included in the MVP as an optional user-controlled setting for safe familiar actions only.

Default:

```text
trusted_mode_enabled = false
```

Users must explicitly enable trusted mode in settings. The app must clearly explain that trusted mode allows the system to commit selected familiar meals without a confirmation tap.

Eligible actions:

```text
commit_meal for a proposal created from a high-confidence recurring meal template
```

Eligible user requests:

```text
"Log my usual breakfast."
"Same protein shake as always."
"Log my normal chicken meal."
```

Ineligible actions:

```text
delete_meal
correct_meal
update_nutrition_targets
delete_account
export_user_data
any ambiguous new meal
any low-confidence proposal
any proposal using LLM-only nutrition values
```

Eligibility requirements:

* User has enabled trusted mode.
* The action is whitelisted for trusted mode.
* The matched meal template belongs to the current user.
* The template has been confirmed by the user before.
* The memory/template match exceeds the configured confidence threshold.
* Nutrition values come from trusted sources, user templates, custom foods, or prior confirmed snapshots.
* The request is not destructive, privacy-sensitive, or target-modifying.

UX requirements:

* Auto-committed meals must show an immediate "logged" state.
* The UI must offer fast undo and correction.
* Users must be able to disable trusted mode from settings.
* Users must be able to disable trusted mode for a specific usual meal/template later.

Audit requirements:

* Every trusted auto-commit must create an `action_call`.
* Every trusted auto-commit must create an `audit_event`.
* The audit metadata must include matched template, confidence, source phrase, trusted-mode status, and whether undo/correction was later used.

Non-goal:

* Trusted mode must not allow autonomous destructive or account-level actions.

## Observability Requirements

Track:

```text
voice_to_transcript_latency
transcript_to_proposal_latency
proposal_to_confirmation_latency
confirmed_without_edit_rate
correction_rate
usual_meal_hit_rate
food_resolution_confidence
action_success_rate
action_error_rate
llm_provider_latency
llm_cost_per_log
stt_latency
commit_rate
retention_metrics
```

Every action call should have a trace ID so logs, audit events, LLM calls, and database mutations can be correlated.

## Testing Requirements

Use a fast-first testing pyramid:

* backend API/integration tests for business behavior, auth, permissions, persistence, contracts, and error fixtures;
* Flutter unit tests for pure Dart logic, ViewModels, repositories, and services;
* Flutter widget tests as the main UI validation layer for rendering, forms, taps, drags, navigation, and loading/success/empty/error states;
* selective golden and semantics tests for visual and accessibility-sensitive surfaces;
* minimal Patrol/integration tests for native/device behavior and final release confidence.

Backend tests must cover:

* action schema validation,
* permission checks,
* proposal creation,
* proposal commit transaction,
* correction flow,
* delete confirmation behavior,
* trusted-mode policy,
* memory retrieval,
* deterministic temporal references,
* nutrition calculation,
* audit logging,
* idempotent retries.

Flutter tests must cover:

* voice/text input UI,
* proposal display,
* confirmation flow,
* correction flow,
* loading states,
* API error states,
* permission/trusted-mode states,
* disabled/enabled controls,
* navigation between critical Flutter screens,
* accessibility labels and tap targets for important controls.

Flutter widget tests must use fake repositories or mocked services at the Provider/ViewModel boundary. They must not call the real backend. Mock HTTP/generated API clients only in repository/API-client tests. Use `.hitTestable()` or `ensureVisible` for interactions that can otherwise match offstage or covered widgets.

Patrol tests must stay selective and should cover only flows that need a real device/emulator or native UI, such as startup smoke, one critical auth/backend path, microphone permission/recording, OS-agent integrations, deep links, and release smoke.

Agent golden tests must include:

```text
"I had my usual breakfast."
"Same lunch as yesterday."
"Chicken and rice."
"Delete the snack I just added."
"No, the chicken was 200 grams."
"How many calories do I have left?"
```

Each agent test should verify:

* correct action selected,
* correct proposal structure,
* confirmation required when appropriate,
* memory used only when appropriate,
* no direct database mutation by the LLM.

## Development Order

Recommended implementation order:

```text
1. Create monorepo structure.
2. Add backend config, health route, and database connection.
3. Add SQL migrations for core tables.
4. Create contracts package and API schema generation.
5. Implement action registry and executor.
6. Implement propose_meal_log without LLM.
7. Implement commit_meal transaction.
8. Implement correct_meal.
9. Implement get_daily_summary.
10. Add basic meal templates and memory retrieval.
11. Add internal agent endpoint.
12. Build Flutter text input screen.
13. Build Flutter proposal confirmation screen.
14. Add voice input.
15. Prototype iOS App Intent for get_daily_summary behind a feature flag.
16. Prototype iOS App Intent for propose_meal_log behind a feature flag.
17. Prototype Android AppFunction equivalents when API 36 tooling/device support is available.
```

## Development Rules for AI Coding Agents

When working on this repo:

* Do not move backend agent logic into Flutter.
* Do not duplicate action logic in Android/iOS adapters.
* Do not put nutrition reasoning inside Flutter intent handlers.
* Define or update contracts before adding new action handlers.
* Add backend tests for action handlers before wiring an LLM to them.
* Keep provider integrations behind interfaces.
* Keep deterministic logic testable without external provider calls.
* Avoid microservices until a real scaling boundary appears.
* Use the installed Flutter development skills before implementing matching Flutter architecture, routing, networking, layout, localization, preview, widget test, or integration test work.

## Open Decisions

No open decisions currently block implementation planning.

## Non-Negotiable Principle

The app must not be designed as:

```text
A calorie app with an AI chatbot
```

It must be designed as:

```text
A calorie/nutrition capability layer that agents can operate safely
```

The internal backend agent is the first agent. Future mobile OS agents should call the same capabilities through adapters with minimal architectural change.
