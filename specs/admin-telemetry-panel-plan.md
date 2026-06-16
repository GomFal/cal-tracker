# Admin Telemetry Panel Implementation Plan

## Status

Planned for implementation on `develop`.

## Purpose

Add a first production-ready telemetry foundation and administration panel for BetterCalories / Cal Tracker. The goal is to understand real user usage, diagnose silent failures, and inspect critical flows such as voice meal logging, LLM tool-calling, food database search, OCR usual-food drafting, cache-backed refreshes, and proposal confirmation.

The implementation must be privacy-aware and useful locally before it is expanded to production-scale analytics.

## Current Architecture Summary

### Backend

Backend source lives in `apps/backend/src`.

Important files:

- `src/http/app.ts`: Hono routes and request context creation.
- `src/actions/executor.ts`: action dispatch, action call persistence, audit events.
- `src/agent/agentService.ts`: LLM tool-calling orchestration and result mapping.
- `src/agent/chatAgentProvider.ts`: OpenRouter streaming provider, timing information, tool call reconstruction.
- `src/nutrition/foodResolver.ts`: food mention resolution and nutrition search via provider.
- `src/repository/postgres.ts`: PostgreSQL persistence and hybrid/normalized food search.
- `src/stt/speechToTextProvider.ts`: remote STT provider.
- `src/observability/localRunLogger.ts`: local JSONL agent run logging.
- `src/observability/profiler.ts`: AsyncLocalStorage profiling spans.
- `src/db/schema.ts`: Drizzle table definitions.

Current observability primitives:

- `requestIdMiddleware` creates/propagates `traceId` via `x-request-id`.
- `action_calls` stores action inputs, outputs, errors, latency, traceId.
- `audit_events` stores side-effect audit events.
- Agent runs can be logged to JSONL via `AGENT_RUN_LOG_ENABLED`.
- `withSpan` exists across action, agent, food search, and repository flows, but request-level profile snapshots are not generally persisted.

Important backend endpoints:

- `POST /v1/agent/runs`
- `POST /v1/voice/meal-runs`
- `POST /v1/stt/transcriptions`
- `POST /v1/foods/search`
- `POST /v1/meals/proposals`
- `POST /v1/meals/proposals/:id/commit`
- `POST /v1/meals/:id/correct`
- `GET /v1/summary/daily`
- `GET /v1/meals`
- `GET /v1/meal-templates`
- `GET /v1/usual-foods`
- `POST /v1/usual-foods/draft`
- `POST /v1/meal-templates/draft`

### Mobile

Flutter app source lives in `apps/mobile/lib`.

Important files:

- `lib/generated/api/cal_tracker_api.dart`: API client, auth refresh, locale header, error decoding.
- `lib/data/repositories/nutrition_repository.dart`: backend-facing repository plus cache write-through and refresh.
- `lib/ui/features/voice_log/view_models/voice_log_view_model.dart`: text/voice meal logging, proposal editing, candidate selection.
- `lib/ui/features/meal_templates/view_models/usual_food_scan_view_model.dart`: camera/OCR/usual-food draft flow.
- `lib/ui/features/dashboard/view_models/dashboard_view_model.dart`: cache-first dashboard refresh.
- `lib/ui/features/meal_history/view_models/meal_history_view_model.dart`: optimistic correction/deletion flows.
- `lib/ui/features/meal_templates/view_models/meal_templates_view_model.dart`: usual foods/templates, optimistic updates.
- `lib/ui/features/settings/view_models/settings_view_model.dart`: settings/goals.

The mobile API client currently receives `traceId` on API errors but does not generate a client request id, does not send app version/platform/session headers, and has no client telemetry queue/endpoint.

## Silent-Failure And Quality Risks To Cover

### 1. Voice Meal Logging

Flow:

```text
Flutter recording
→ /v1/voice/meal-runs
→ STT provider
→ AgentService
→ OpenRouter tool call
→ ActionExecutor
→ FoodResolver / DB search
→ proposal | clarification | commit
```

Events and anomalies to track:

- microphone permission denied
- recording start/stop
- missing audio file
- invalid/unsupported audio upload
- audio bytes and mime type
- STT provider failure
- STT latency
- transcript length, empty transcript, too-short transcript
- LLM provider failure or timeout
- empty tool call
- invalid tool-call JSON
- disallowed selected tool
- selected/executed tool
- result kind: `proposal`, `clarification_required`, `meal_committed`, error
- proposal created but never committed
- repeated correction loops

### 2. Text Agent Runs

Flow:

```text
VoiceLogViewModel.submitText
→ NutritionRepository.logText
→ /v1/agent/runs
→ AgentService
→ ActionExecutor
```

Events and anomalies:

- LLM returns no tool call
- LLM selects unavailable/disallowed action
- JSON parse failure for tool arguments
- action execution error
- `clarification_required` rate
- proposal created with low confidence
- proposal abandoned

### 3. Food Search / Food Resolution

Flow:

```text
UI searchFoods
→ /v1/foods/search
→ search_nutrition_database
→ FoodResolver
→ PostgresRepository.searchFoodsHybrid
→ normalized search / legacy fallback
```

Events and anomalies:

- zero results for frequent queries
- low top score
- normalized search miss followed by legacy fallback
- barcode miss
- unexpected locale/language path
- user selects candidate rank > 1
- user rejects/dismisses candidates
- top result repeatedly corrected later
- usual foods injected into ranking
- provider/search error swallowed as `items: []`

Important: `FoodResolver.resolveMention` currently catches provider errors and turns them into empty items. The implementation must record such provider failures as telemetry so they are not indistinguishable from valid zero-result searches.

### 4. Usual Food / OCR Scan

Flow:

```text
camera capture
→ OCR local ML Kit
→ /v1/usual-foods/draft
→ LLM draft usual food
```

Events and anomalies:

- camera denied/unavailable
- capture failure
- OCR failure
- OCR empty/too short
- usual-food draft provider failure
- draft created but not saved

### 5. Cache-First Mobile Screens

The mobile app intentionally ignores cache write failures in several places to protect UX. Telemetry should report these failures without breaking the UI.

Events and anomalies:

- cache hit/miss
- cache read/write failure
- background refresh failure while visible cached data exists
- optimistic update rollback
- stale data age

## Implementation Scope For This Iteration

Implement a vertical slice that is useful locally and lays the foundation for production.

### Required Backend Scope

1. Add telemetry data model and migrations.
2. Add backend telemetry service/sink.
3. Persist request-level telemetry for API requests.
4. Persist LLM run telemetry from `AgentService`.
5. Persist food search telemetry from `/v1/foods/search`, `FoodResolver`, or repository search path.
6. Persist STT/voice telemetry from `/v1/stt/transcriptions` and `/v1/voice/meal-runs`.
7. Add admin-read API endpoints for overview, events, traces, LLM runs, and food search events.
8. Add a client telemetry ingestion endpoint for future/mobile events.
9. Add admin authorization.
10. Add tests.

### Required Admin UI Scope

Add a minimal local admin panel in `apps/admin` that can be served statically and can inspect local/dev backend telemetry.

The panel must include at least:

- Overview cards.
- Recent events table.
- LLM runs table.
- Food search table.
- Trace lookup by traceId.
- Configurable API base URL and bearer token input persisted in localStorage.

Use vanilla HTML/CSS/JS unless there is already an admin frontend stack. Avoid adding heavy dependencies for the first slice.

### Required Mobile Scope

Add minimal client-side support without overhauling the app:

1. Generate and send `X-Request-Id` on JSON and multipart API requests.
2. Send app/client headers when reasonably available:
   - `X-App-Version`
   - `X-App-Build`
   - `X-Client-Platform`
   - `X-Client-Session-Id`
3. Add a lightweight `ClientTelemetryService` that can send non-blocking events to `POST /v1/telemetry/client-events`.
4. Instrument at least these events:
   - API request failure with status/traceId.
   - voice recording/transcription/agent failure points in `VoiceLogViewModel`.
   - food search result counts in `NutritionRepository.searchFoods`.
   - cache write failures where currently swallowed.

If full mobile telemetry is too large, prioritize request id headers and food/voice events.

## Authorization Requirements

Add admin authorization without exposing telemetry to normal users.

Preferred implementation:

- Add permission scopes in `packages/contracts/src/permissions.ts`:
  - `admin.telemetry.read`
  - `admin.telemetry.write`
- Add config:
  - `ADMIN_EMAILS`, comma-separated, default empty.
- Augment authenticated users whose email is in `ADMIN_EMAILS` with admin telemetry scopes at auth middleware and token issuance time, without changing default scopes for normal users.
- Admin endpoints must require `admin.telemetry.read`.
- Client telemetry ingestion may accept authenticated users with normal scopes; it should not require admin read scope.

## Database Design

Add Drizzle schema entries and migrations under the existing infrastructure path, following current project convention:

```text
infra/db/drizzle
apps/backend/src/db/schema.ts
```

### `telemetry_events`

Suggested columns:

- `id uuid primary key default random`
- `trace_id text not null`
- `user_id uuid null references users(id) on delete set null`
- `session_id text null`
- `event_type text not null`
- `flow text null`
- `surface text not null` — `backend`, `mobile`, `agent`, `stt`, `db`, `admin`
- `severity text not null` — `info`, `warning`, `error`
- `status text null` — `success`, `failure`, `partial`, `abandoned`
- `route text null`
- `method text null`
- `action_id text null`
- `duration_ms integer null`
- `error_code text null`
- `error_message text null` — sanitized only
- `app_version text null`
- `app_build text null`
- `platform text null`
- `locale text null`
- `metadata_json jsonb not null default '{}'::jsonb`
- `created_at timestamptz not null default now()`

Indexes:

- `(created_at desc)`
- `(trace_id)`
- `(user_id, created_at desc)`
- `(event_type, created_at desc)`
- `(severity, created_at desc)`

### `llm_runs`

Suggested columns:

- `id uuid primary key default random`
- `trace_id text not null`
- `user_id uuid null references users(id) on delete set null`
- `source text null`
- `locale text null`
- `timezone text null`
- `model text not null`
- `input_mode text null`
- `active_proposal_id uuid null`
- `decision_source text null`
- `selected_tool text null`
- `executed_tool text null`
- `result_kind text null`
- `action_call_id uuid null`
- `prompt_chars integer null`
- `tools_json_chars integer null`
- `messages_json_chars integer null`
- `request_payload_chars integer null`
- `prompt_tokens integer null`
- `completion_tokens integer null`
- `total_tokens integer null`
- `reasoning_tokens integer null`
- `first_byte_ms integer null`
- `first_tool_call_ms integer null`
- `largest_stream_gap_ms integer null`
- `llm_ms integer null`
- `action_ms integer null`
- `total_ms integer null`
- `empty_tool_call boolean not null default false`
- `invalid_tool_arguments boolean not null default false`
- `provider_error boolean not null default false`
- `metadata_json jsonb not null default '{}'::jsonb`
- `created_at timestamptz not null default now()`

Indexes:

- `(created_at desc)`
- `(trace_id)`
- `(user_id, created_at desc)`
- `(result_kind, created_at desc)`
- `(selected_tool, created_at desc)`

### `food_search_events`

Suggested columns:

- `id uuid primary key default random`
- `trace_id text not null`
- `user_id uuid null references users(id) on delete set null`
- `query_text text null` — sanitize/truncate; no full meal transcript unless acceptable
- `query_hash text null`
- `query_length integer not null default 0`
- `locale text null`
- `barcode_present boolean not null default false`
- `normalized_search_enabled boolean null`
- `normalized_scope text null`
- `path text null` — `normalized`, `legacy`, `normalized_to_legacy`, `barcode`, `resolver_provider_error`, etc.
- `result_count integer not null default 0`
- `candidate_group_count integer null`
- `top_score numeric(8,4) null`
- `top_external_source text null`
- `top_result_type text null`
- `zero_results boolean not null default false`
- `low_confidence boolean not null default false`
- `selected_rank integer null`
- `duration_ms integer null`
- `metadata_json jsonb not null default '{}'::jsonb`
- `created_at timestamptz not null default now()`

Indexes:

- `(created_at desc)`
- `(trace_id)`
- `(user_id, created_at desc)`
- `(zero_results, created_at desc)`
- `(low_confidence, created_at desc)`

## Backend API Requirements

### Admin endpoints

Add routes under `/v1/admin/telemetry`:

```text
GET /v1/admin/telemetry/overview?from=&to=
GET /v1/admin/telemetry/events?limit=&severity=&eventType=&traceId=&userId=
GET /v1/admin/telemetry/traces/:traceId
GET /v1/admin/telemetry/llm-runs?limit=&resultKind=&selectedTool=&traceId=&userId=
GET /v1/admin/telemetry/food-search?limit=&zeroResults=&lowConfidence=&traceId=&userId=
```

Return compact JSON optimized for the admin UI.

### Client telemetry ingestion

Add:

```text
POST /v1/telemetry/client-events
```

Input shape:

```json
{
  "events": [
    {
      "eventType": "mobile.api_request_failed",
      "flow": "voice_meal",
      "surface": "mobile",
      "severity": "warning",
      "status": "failure",
      "traceId": "...",
      "route": "/v1/agent/runs",
      "durationMs": 1234,
      "errorCode": "agent_provider_unavailable",
      "metadata": {}
    }
  ]
}
```

Validation requirements:

- max batch size, e.g. 50
- max metadata size / event size
- sanitize string lengths
- ignore or reject invalid severity/surface/status
- use authenticated user id from JWT

## Privacy Requirements

Do not create a surveillance panel containing unnecessary raw sensitive text.

Rules:

- Never store passwords, auth tokens, refresh tokens, raw Authorization headers, or API keys.
- Do not store raw full audio.
- Do not store raw full OpenRouter request/response in database tables.
- Store short/sanitized snippets only if needed.
- Prefer hashes, lengths, counts, result kinds, and timing metadata.
- If storing search query text, truncate it and treat it as sensitive in admin UI.
- Client telemetry must be best-effort; failures to send telemetry must never break product UX.

## Acceptance Criteria

### Backend

- New telemetry tables exist in `src/db/schema.ts` and migrations under `infra/db/drizzle`.
- Backend typecheck passes.
- Existing backend tests pass.
- New tests cover:
  - admin authorization rejects normal users;
  - admin overview returns data for admin users;
  - client telemetry ingestion persists events;
  - LLM empty-tool-call or provider-error path records telemetry;
  - food search zero-result / low-confidence path records telemetry.
- `traceId` links request events, LLM runs, food search events, and action calls when they happen in the same flow.
- Provider/search errors swallowed for UX are still visible as telemetry.

### Admin UI

- `apps/admin/index.html` or equivalent exists.
- It can be served locally as static files.
- It lets an operator configure API base URL and bearer token.
- It shows overview, recent events, LLM runs, food search events, and trace detail.
- It handles API errors visibly.

### Mobile

- API requests include `X-Request-Id`.
- Multipart voice/STT requests include the same telemetry headers.
- API exceptions still expose server `traceId`.
- Telemetry sending is non-blocking and does not break UX.
- At least voice failure, API failure, food search result counts, and swallowed cache write failure events are instrumented.

### Local validation

The final validation should run at least:

```bash
cd apps/backend
bun test
bun --env-file=.env run db:migrate
bun --env-file=.env run typecheck

cd apps/mobile
flutter test
```

If Flutter full test suite is too slow or environment-blocked, run targeted tests for changed files and report the limitation.

Local setup should include:

- canonical local Postgres via repository `docker-compose.yml`
- migrations applied
- backend started locally on port 3000
- admin panel served locally, e.g. on port 5173 or 8080
- smoke test for `/v1/health`
- if feasible, smoke test admin endpoints with an admin JWT

## Implementation Notes

- Keep telemetry writes best-effort. A telemetry write failure must not fail the user request.
- Add concise helper functions to sanitize/truncate metadata.
- Prefer small DB queries for admin endpoints; avoid loading huge JSON blobs by default.
- Avoid adding heavy frontend dependencies for the first admin slice.
- Keep food/LLM natural-language understanding rules intact: do not add regex parsing fallbacks for food logging or LLM behavior.
- After modifying code, run `graphify update .` if `graphify` is available. If not available, report it.
