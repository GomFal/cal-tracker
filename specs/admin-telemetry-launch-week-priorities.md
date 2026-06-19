# Admin Telemetry Launch Week Priorities

## Purpose

This document is the living implementation plan for the BetterCalories
administration panel telemetry that should be available for the private beta
launch. It captures what the current system already tracks, what the current
system already stores but does not expose in admin, and what needs to be added
so we can understand how beta users interact with the application and the
conversational agent.

The private beta is a controlled environment with friends and close users who
understand that their use of the application will be inspected for product and
quality improvement. For that reason, this plan intentionally includes raw user
messages, transcriptions, agent interactions, tool calls, food search queries,
and candidate-resolution details as admin-inspectable data.

## Current Foundation

The first telemetry/admin-panel slice already provides a useful operational
foundation:

- `telemetry_events`: generic backend, mobile, STT, voice, food resolver, and
  client-ingested events.
- `llm_runs`: single-turn `AgentService` run summaries, including model,
  selected/executed tool, result kind, timings, token counts, and provider/tool
  failure flags.
- `food_search_events`: food-search summary records, including query hash,
  query length, locale, barcode presence, result count, candidate group count,
  top score/source/type, zero-result flag, low-confidence flag, and duration.
- Admin endpoints for overview, recent events, LLM runs, food search events,
  and trace lookup.
- Static admin panel views for overview, events, LLM runs, food search, and
  trace lookup.
- Client telemetry ingestion through `POST /v1/telemetry/client-events`.
- Mobile request correlation via `X-Request-Id`, app version/build/platform,
  and client session headers.
- Backend request telemetry for `/v1/*` routes, including route, method,
  status/severity, duration, user id, trace id, app metadata, and user agent.
- STT and voice meal run telemetry summaries for start/completion/failure,
  audio metadata, provider/model, transcript length, result kind, timings, and
  error stage.
- Food resolver provider-error telemetry so swallowed provider failures do not
  look like legitimate zero-result searches.

The current foundation tracks some token metrics on `llm_runs`, but it does not
yet provide reliable monetary cost tracking by provider call, user,
conversation, turn, model, or feature surface.

## Important Current Nuance

The current conversational chat feature already persists full chat
conversations in the application database.

The `/v1/agent/chat` and `/v1/agent/chat/audio` flows store:

- conversations in `agent_conversations`;
- user messages in `agent_messages`;
- voice-chat transcriptions as user messages;
- assistant messages;
- assistant tool calls as JSON on assistant messages;
- tool result messages;
- tool metadata such as `actionId` and `actionCallId`.

The gap is that this stored conversation data is not currently exposed in the
admin panel and is not presented as telemetry. The launch-week priority is not
to build conversation persistence from scratch. The priority is to make the
already persisted conversation timeline inspectable and correlated with trace,
LLM, action-call, and food-search telemetry.

## Launch Week Priorities

### Priority 1: Conversations / Agent Turns View

Add an admin view for the current chat agent conversation history.

The view should let an admin inspect a private-beta user's full agent
conversation timeline:

- user id and conversation id;
- conversation created/updated timestamps;
- each user text message;
- each voice-chat transcription;
- each assistant message;
- each assistant tool call;
- parsed tool-call arguments;
- each tool result message;
- tool call status when available;
- linked `actionId`;
- linked `actionCallId`;
- linked `traceId` for the turn/request;
- visible error states for invalid tool arguments, unavailable tools, provider
  failures, repeated tool calls, action errors, and max-step failures.

The view should support filtering by:

- user id;
- conversation id;
- trace id;
- date/time range;
- input mode, such as text or voice;
- action/tool id;
- error-only conversations;
- conversations with unresolved food matches;
- conversations with corrections after proposal creation.

### Priority 2: Correlate Conversations With Telemetry and Action Calls

Make the admin panel connect the full chain:

```text
user message or transcription
  -> agent LLM decision
  -> tool call name and arguments
  -> ActionExecutor action call
  -> food resolver / database search
  -> candidate results shown or selected
  -> proposal, clarification, commit, correction, or failure
```

The trace detail view should include:

- generic telemetry events;
- LLM run or agent-turn records;
- stored conversation messages for that trace/turn;
- action calls from `action_calls`;
- audit events where useful;
- food search events;
- food candidate drilldown records;
- transcription records.

Action-call detail should show:

- `actionId`;
- source, such as `flutter` or `internal_agent`;
- `input_json`;
- `output_json`;
- `error_json`;
- confirmation status;
- latency;
- `traceId`;
- creation timestamp.

The admin panel should make `actionCallId` clickable wherever it appears.

### Priority 3: Raw Transcription Tracking

Add DB-visible transcription tracking for private beta.

Track:

- trace id;
- user id;
- conversation id when applicable;
- input surface, such as standalone STT, voice meal run, or chat audio;
- raw transcript text;
- transcript length;
- provider;
- model;
- detected/requested language when available;
- audio filename;
- audio MIME type;
- audio byte size;
- audio duration if available from the recorder or backend;
- transcription duration;
- downstream route/result kind;
- downstream conversation turn id or action call id when applicable;
- error code/message for failed transcription.

Admin should show a Transcriptions view with:

- recent transcriptions;
- user filter;
- route/surface filter;
- language/provider/model filter;
- error-only filter;
- trace/conversation/action links;
- raw transcript text visible in detail.

### Priority 4: Food Resolution and Candidate Drilldown

Current `food_search_events` records summarize food searches, but launch-week
analysis needs candidate-level detail.

Track for direct food search and agent-driven food resolution:

- raw search query or raw food mention text;
- normalized query;
- language/locale;
- barcode when present;
- resolver/search path;
- normalized-search feature flag and scope;
- provider id;
- candidate group count;
- mention count for meal-resolution flows;
- unresolved mention count;
- unsupported unit / no database match reasons;
- top N candidates per mention/query;
- candidate id;
- candidate display name;
- brand if available;
- external source and external id;
- result type;
- score/confidence;
- rank;
- whether the candidate was selected automatically;
- whether the candidate was shown to the user;
- whether the candidate was later confirmed, edited, rejected, corrected, or
  committed.

Admin should support a Food Candidate Drilldown view:

- filter zero-result and low-confidence cases;
- inspect each food mention/query;
- inspect candidates returned by the database;
- see why the agent/backend selected a candidate;
- see what the user did afterward.

### Priority 5: Agent Turn and LLM Instrumentation for Chat

The current `llm_runs` table is strongest for the older single-turn
`AgentService`. The newer multi-step chat agent should be first-class in admin
telemetry.

Track per chat turn:

- conversation id;
- turn id;
- trace id;
- user id;
- input mode;
- raw input text;
- active proposal id;
- model;
- provider/routing metadata where available;
- iteration count;
- tool call count;
- available tools count/list;
- selected tools by iteration;
- final result kind;
- stop reason;
- prompt/message/tool JSON character counts;
- prompt/completion/total/reasoning tokens;
- provider-reported cost when available;
- computed estimated cost when provider cost is not available;
- pricing snapshot used for the estimate;
- currency, normally USD;
- first byte latency;
- first tool call latency;
- largest stream gap;
- LLM duration;
- action duration;
- total duration;
- assistant final text;
- provider error details;
- invalid tool argument details;
- disallowed tool details;
- repeated tool-call skips;
- max-iteration failures.

Admin should present this as an Agent Turns view and link each row to the full
conversation timeline.

### Priority 6: LLM Cost Tracking

Track the amount of money spent on LLM/provider calls as a first-class admin
metric. This is one of the most important private-beta telemetry goals because
future pricing, quota, and plan design should be based on actual usage data.

Cost tracking should work at these aggregation levels:

- per provider request;
- per LLM iteration inside a multi-step chat turn;
- per agent turn;
- per conversation;
- per trace;
- per action/tool call when a provider call caused that tool call;
- per user;
- per day/week/month;
- per model/provider;
- per feature surface, such as chat text, chat audio, voice meal run, usual
  food drafting, usual meal drafting, or legacy single-turn meal input.

Track per provider request:

- provider name;
- provider route/base URL when useful;
- model requested;
- model actually served if different;
- provider routing details;
- generation/request id returned by the provider;
- prompt tokens;
- completion tokens;
- total tokens;
- reasoning tokens;
- cached input tokens if reported;
- audio/image/input modality tokens if reported by the provider;
- raw provider-reported cost if present in the response;
- computed cost estimate if raw provider cost is not present;
- input token unit price used;
- output token unit price used;
- reasoning/cached/audio token unit prices used when applicable;
- currency;
- pricing source/version/date;
- whether the cost is `provider_reported`, `estimated`, or `unknown`;
- error status, because failed provider calls may still have partial cost.

The cost model must preserve both token metrics and monetary metrics. If
provider-reported spend is available, store it. If not, calculate an estimate
from stored token counts and a versioned pricing table. The admin panel should
clearly label estimated cost so it is not confused with provider-billed cost.

Admin should expose:

- total LLM spend over the selected date range;
- spend by user;
- spend by conversation;
- spend by model/provider;
- spend by feature surface;
- average spend per conversation;
- average spend per agent turn;
- average spend per successful meal logged;
- high-cost conversations and users;
- provider calls with missing/unknown cost;
- token totals next to spend totals.

### Priority 7: Mobile Interaction Telemetry

Expand mobile telemetry beyond failures and food-search summaries so admin can
understand how beta users actually navigate and interact.

Track:

- app start;
- app foreground/background;
- auth login/register/logout success/failure;
- screen/view opened;
- tab changes;
- agent chat opened;
- prompt chip tapped;
- text message submitted;
- voice recording started;
- voice recording stopped;
- voice recording cancelled or failed;
- audio upload started/completed/failed;
- stream started;
- first assistant token received;
- first tool card shown;
- stream completed;
- stream failed;
- proposal viewed;
- proposal edited;
- proposal confirmed;
- proposal dismissed;
- candidate option tapped;
- meal committed;
- meal correction started/completed;
- usual food or usual meal draft reviewed/saved/cancelled;
- settings/goal changes;
- cache hit/miss/stale render for important server-backed screens.

Events should include:

- session id;
- trace id when tied to an API request;
- route or screen id;
- action id where applicable;
- duration;
- status;
- error code/message;
- compact metadata.

### Priority 8: Per-User Timeline

Add an admin User Timeline view that lets us inspect one beta user's activity
across the whole product.

The timeline should merge:

- mobile interaction events;
- backend request events;
- agent conversations;
- agent turns;
- transcriptions;
- action calls;
- food search/candidate events;
- proposals;
- committed meals;
- corrections;
- errors and abandonments;
- LLM/provider cost events.

The goal is to answer:

- What did this user try to do?
- Where did they hesitate or abandon?
- Did voice transcription match what they intended?
- Did the agent choose the right tool?
- Did the food search return sensible candidates?
- Did the user confirm, edit, correct, or give up?
- How much did this user's agent usage cost?

### Priority 9: Failure and Abandonment Review

Add admin views or filters focused on problems.

Track and surface:

- API failures;
- provider failures;
- STT failures;
- transcription-empty cases;
- empty tool calls;
- invalid tool arguments;
- disallowed tools;
- repeated tool calls;
- max-step agent failures;
- action execution errors;
- zero-result food searches;
- low-confidence food matches;
- unresolved food mentions;
- unsupported-unit clarifications;
- proposal abandoned after creation;
- candidate selection abandoned;
- voice recording started but not submitted;
- chat stream started but not completed;
- user correction immediately after meal commit.

For each problem, admin should show the related conversation, transcript,
action call, food search candidates, and user outcome.

## Recommended Admin Views

The admin panel should evolve toward these views:

1. Overview
   - Existing view, expanded with private-beta KPIs and problem rates.

2. Events
   - Existing generic telemetry table.

3. Traces
   - Existing trace lookup, expanded into a full correlated trace timeline.

4. LLM Runs
   - Existing single-turn run table, eventually joined with chat turns and
     provider cost records.

5. Food Search
   - Existing summary table, expanded with candidate drilldown links.

6. Conversations
   - Full conversation timeline from `agent_conversations` and
     `agent_messages`.

7. Agent Turns
   - Per-turn LLM/tool/timing/cost summary for the conversational agent.

8. LLM Cost
   - Spend and token usage by user, conversation, model, provider, feature,
     trace, and provider request.

9. Action Calls
   - `ActionExecutor` input/output/error records and timing.

10. Transcriptions
   - Raw transcript inspection and downstream correlation.

11. Food Candidate Drilldown
    - Per-query/per-mention candidate search details.

12. User Timeline
    - Cross-surface chronological view for one user.

13. Failure Review
    - Error, abandoned, low-confidence, and correction-heavy flows.

## Suggested Data Model Additions

The exact schema can be revised during implementation, but these are the
missing admin-facing concepts.

### Agent Turns

Create an agent-turn telemetry representation for current chat:

- `id`
- `conversation_id`
- `trace_id`
- `user_id`
- `input_mode`
- `input_text`
- `assistant_text`
- `model`
- `source`
- `locale`
- `timezone`
- `active_proposal_id`
- `iteration_count`
- `tool_call_count`
- `result_kind`
- `stop_reason`
- `prompt_chars`
- `messages_json_chars`
- `tools_json_chars`
- `prompt_tokens`
- `completion_tokens`
- `total_tokens`
- `reasoning_tokens`
- `provider_cost_amount`
- `estimated_cost_amount`
- `cost_currency`
- `cost_source`
- `pricing_snapshot_json`
- `first_byte_ms`
- `first_tool_call_ms`
- `largest_stream_gap_ms`
- `llm_ms`
- `action_ms`
- `total_ms`
- `metadata_json`
- `created_at`

### Agent Tool Calls

Create or expose structured tool-call records:

- `id`
- `agent_turn_id`
- `conversation_id`
- `trace_id`
- `user_id`
- `tool_call_id`
- `action_call_id`
- `action_id`
- `arguments_json`
- `result_summary_json`
- `status`
- `error_message`
- `started_at`
- `completed_at`
- `duration_ms`

### LLM Provider Calls

Create provider-call cost records so costs can be aggregated independently of
chat, legacy single-turn agent runs, and future LLM-powered features:

- `id`
- `trace_id`
- `user_id`
- `conversation_id`
- `agent_turn_id`
- `action_call_id`
- `feature_surface`
- `provider`
- `provider_request_id`
- `provider_generation_id`
- `requested_model`
- `served_model`
- `routing_json`
- `input_mode`
- `prompt_tokens`
- `completion_tokens`
- `total_tokens`
- `reasoning_tokens`
- `cached_input_tokens`
- `audio_tokens`
- `image_tokens`
- `provider_cost_amount`
- `estimated_cost_amount`
- `cost_currency`
- `cost_source`
- `input_token_unit_price`
- `output_token_unit_price`
- `reasoning_token_unit_price`
- `cached_input_token_unit_price`
- `audio_token_unit_price`
- `image_token_unit_price`
- `pricing_source`
- `pricing_version`
- `pricing_effective_at`
- `status`
- `error_code`
- `error_message`
- `duration_ms`
- `metadata_json`
- `created_at`

### Transcriptions

Create transcription telemetry records:

- `id`
- `trace_id`
- `user_id`
- `conversation_id`
- `surface`
- `provider`
- `model`
- `language`
- `audio_mime_type`
- `audio_bytes`
- `audio_duration_ms`
- `transcript_text`
- `transcript_length`
- `duration_ms`
- `status`
- `error_code`
- `error_message`
- `downstream_result_kind`
- `metadata_json`
- `created_at`

### Food Candidate Events

Create candidate-level food search/resolution records:

- `id`
- `trace_id`
- `user_id`
- `action_call_id`
- `food_search_event_id`
- `query_text`
- `normalized_query`
- `mention_text`
- `mention_index`
- `candidate_rank`
- `food_item_id`
- `display_name`
- `brand`
- `external_source`
- `external_id`
- `result_type`
- `score`
- `confidence`
- `selected`
- `shown_to_user`
- `user_outcome`
- `metadata_json`
- `created_at`

## Acceptance Criteria

The launch-week admin telemetry work is useful when an admin can answer these
questions from the panel:

- What full conversation did a beta user have with the agent?
- What exactly did the user type or say?
- What transcription did the backend produce from their audio?
- Which LLM/model handled the turn?
- Which tool did the agent choose?
- What arguments did the agent pass to that tool?
- Which backend action call executed?
- What food queries or mentions were searched?
- What candidates came back from the database?
- Which candidate was selected or shown?
- Did the user confirm, edit, correct, abandon, or fail?
- Where did the flow spend time?
- Which provider/tool/search failures happened?
- Which flows created zero-result searches or low-confidence matches?
- Which users are repeatedly hitting the same problem?
- How much money did each user spend in LLM/provider calls?
- How much did each conversation, turn, model, provider, and feature cost?
- Which conversations or users are unusually expensive?
- Which provider calls have unknown or estimated cost?

## Implementation Order

1. Add admin read endpoints for existing `agent_conversations`,
   `agent_messages`, and `action_calls`.
2. Add Conversations and Action Calls views to the admin panel.
3. Extend trace lookup to include conversation messages and action calls.
4. Add chat agent-turn telemetry for `/v1/agent/chat` and
   `/v1/agent/chat/audio`.
5. Add provider-call cost tracking and LLM Cost admin views.
6. Add raw transcription records and Transcriptions admin view.
7. Add food candidate-level tracking and drilldown view.
8. Add mobile interaction telemetry for chat, voice, proposals, candidates,
   and screen/session behavior.
9. Add User Timeline and Failure Review views.

## Non-Goals for This Planning Document

- This document does not implement schema migrations.
- This document does not change admin endpoints.
- This document does not change privacy policy or consent copy.
- This document does not replace `specs/admin-telemetry-panel-plan.md`; it is a
  launch-week priority layer on top of that foundation.
