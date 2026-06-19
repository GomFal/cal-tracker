# Agent Chat History and Smart Reset Implementation Plan

## Objective

Implement agent chat histories so users can see, resume, and delete prior conversations, while preventing the current single infinite conversation from growing indefinitely and increasing LLM context cost.

The launch-week behavior should be:

- A new backend conversation is created whenever the user starts a fresh agent session.
- The mobile app resumes the last conversation only when it is still recent or structurally unfinished.
- A completed conversation older than 2 minutes is not reused automatically.
- The user can manually start a new chat at any time.
- The user can open a history view, select a prior conversation, and continue it.
- Existing proposal/meal draft/clarification flows are not cut off just because 2 minutes passed.

This plan is intended to be implemented from a separate branch/worktree.

## Current State

The backend already has most of the persistence foundation:

- `agent_conversations` and `agent_messages` tables already exist.
- `apps/backend/src/repository/postgres.ts` already implements:
  - `createAgentConversation`
  - `getAgentConversation`
  - `listAgentConversations`
  - `addAgentConversationMessage`
  - `listAgentConversationMessages`
  - `deleteAgentConversation`
- `apps/backend/src/repository/inMemory.ts` mirrors these methods for tests.
- `apps/backend/src/http/app.ts` already exposes:
  - `GET /v1/agent/conversations`
  - `GET /v1/agent/conversations/:id`
  - `DELETE /v1/agent/conversations/:id`
  - `POST /v1/agent/chat`
  - `POST /v1/agent/chat/audio`
- `apps/backend/src/agent/agentChatService.ts` already accepts optional `conversationId` and creates a new conversation when the request omits it.
- `agent_messages` already has `metadata_json`, but it does not currently have first-class correlation columns such as `trace_id`, `turn_id`, `input_mode`, `source`, or `active_proposal_id`.
- `deleteAgentConversation` currently hard-deletes the conversation row, which cascades to messages. That is not acceptable for private-beta telemetry because it would erase future admin-inspectable chat history.

The main problem is mobile state:

- `apps/mobile/lib/app/app.dart` provides one app-level `AgentChatViewModel`.
- `AgentChatViewModel` keeps one `conversationId`.
- Every text/audio turn passes that same `conversationId` to the backend.
- Therefore the backend keeps loading the same full conversation in `AgentChatService.messagesForModel()`.
- This creates unbounded context growth and higher LLM spend.

## Important Product Decisions

Use these defaults:

- Inactivity timeout: `2 minutes`.
- Automatic entry behavior: smart resume/new.
- Unfinished conversation policy: state-aware.
- Manual new chat always wins.

Do not add natural-language or regex intent parsing for detecting finished meals or user intent. The project explicitly forbids brittle food parsing. The finished/unfinished decision must use structured app state and structured agent result kinds.

## Backend Changes

### Storage Decision for Future Admin Telemetry

Use a hybrid model that matches the existing telemetry architecture:

- Keep full chat content in `agent_conversations` and `agent_messages`. These are the canonical tables for conversation history.
- Do not duplicate full user/assistant/tool message content into `telemetry_events`. The telemetry tables are optimized for event summaries, filters, traces, LLM runs, food-search runs, and future cost records.
- Add first-class correlation columns to the chat tables now so future admin telemetry can join reliably without scraping JSON.
- Continue using `metadata_json` only for flexible per-message payloads such as provider routing, suggestions, raw tool metadata, or debug details.

This mirrors the existing telemetry foundation:

- `telemetry_events`, `llm_runs`, and `food_search_events` store frequently filtered fields as columns.
- They keep extra event-specific details in `metadata_json`.
- Chat history should follow the same principle: stable correlation keys are columns; variable payload is metadata.

Do not create the future admin views or full cost telemetry tables as part of this history feature. The history feature only needs to preserve the data and identifiers that make those later joins clean.

### Database Migration

Add a migration for chat-history correlation and soft deletion.

Target tables:

- `agent_conversations`
- `agent_messages`

Add to `agent_conversations`:

```sql
ALTER TABLE agent_conversations
  ADD COLUMN IF NOT EXISTS hidden_from_user_at timestamptz;
```

Add indexes:

```sql
CREATE INDEX IF NOT EXISTS agent_conversations_user_visible_updated_idx
  ON agent_conversations(user_id, hidden_from_user_at, updated_at DESC);
```

Semantics:

- `hidden_from_user_at IS NULL`: visible in the user's chat history.
- `hidden_from_user_at IS NOT NULL`: hidden/deleted from the user's app, but retained for future admin telemetry inspection.

Add to `agent_messages`:

```sql
ALTER TABLE agent_messages
  ADD COLUMN IF NOT EXISTS trace_id text,
  ADD COLUMN IF NOT EXISTS turn_id uuid,
  ADD COLUMN IF NOT EXISTS input_mode text,
  ADD COLUMN IF NOT EXISTS source text,
  ADD COLUMN IF NOT EXISTS active_proposal_id uuid;
```

Add indexes:

```sql
CREATE INDEX IF NOT EXISTS agent_messages_trace_id_idx
  ON agent_messages(trace_id);

CREATE INDEX IF NOT EXISTS agent_messages_turn_id_idx
  ON agent_messages(turn_id);

CREATE INDEX IF NOT EXISTS agent_messages_conversation_turn_idx
  ON agent_messages(conversation_id, turn_id, created_at);
```

Column meanings:

- `trace_id`: backend request trace id for the chat request that created the message.
- `turn_id`: generated once per `/v1/agent/chat` or `/v1/agent/chat/audio` request and shared by all messages produced by that user turn.
- `input_mode`: `text` or `voice`.
- `source`: request source such as `flutter`, `ios_appintents`, `android_appfunctions`, or `internal_agent` where applicable.
- `active_proposal_id`: active proposal id supplied with the turn, if any.

Also update the TypeScript schema/types and repository mappers:

- `apps/backend/src/db/schema.ts`
- `apps/backend/src/repository/types.ts`
- `apps/backend/src/repository/postgres.ts`
- `apps/backend/src/repository/inMemory.ts`

Backfill behavior:

- Existing rows can keep these new columns as `NULL`.
- Do not try to infer old `turn_id` or `input_mode` from message text.
- Future admin tooling can show old conversations with partial correlation.

### `apps/backend/src/agent/agentChatService.ts`

Change conversation creation so new conversations get a useful title.

Edit `chat(...)`:

- Pass the initial user text into `resolveConversation(...)`.

Change:

```ts
const conversation = await this.resolveConversation(
  input.context.actorUserId,
  input.conversationId,
);
```

To:

```ts
const conversation = await this.resolveConversation(
  input.context.actorUserId,
  input.conversationId,
  input.text,
);
```

Change `resolveConversation(...)` signature:

```ts
private async resolveConversation(
  userId: string,
  conversationId?: string,
  initialText?: string,
): Promise<AgentConversationRecord>
```

When `conversationId` is absent, create the conversation with a title derived from the first message:

```ts
return this.repository.createAgentConversation(userId, {
  title: conversationTitleFromInput(initialText),
});
```

Add constants/helpers:

```ts
const MAX_CONVERSATION_TITLE_CHARS = 64;

function conversationTitleFromInput(input?: string): string {
  const title = (input ?? "").replace(/\s+/g, " ").trim();
  if (!title) return "Nutrition chat";
  if (title.length <= MAX_CONVERSATION_TITLE_CHARS) return title;
  return `${title.slice(0, MAX_CONVERSATION_TITLE_CHARS - 1).trimEnd()}...`;
}
```

Use ASCII `...` unless the file already adopts Unicode ellipsis.

Do not infer meal names, ingredients, language, or intent from the text. This helper is only a trimmed display title.

Generate and persist turn correlation data.

At the start of every `chat(...)` request, generate a turn id:

```ts
import { randomUUID } from "node:crypto";

const turnId = randomUUID();
const inputMode = input.inputMode ?? "text";
```

Every message written during that request should include these first-class fields:

```ts
{
  traceId: input.context.traceId,
  turnId,
  inputMode,
  source: input.context.source,
  activeProposalId: input.activeProposalId,
}
```

Also include the same values in `metadata` for compatibility with flexible admin/debug tooling:

```ts
const baseMessageMetadata = {
  traceId: input.context.traceId,
  turnId,
  inputMode,
  source: input.context.source,
  conversationId: conversation.id,
  activeProposalId: input.activeProposalId,
};
```

When adding per-message metadata, merge it with the base metadata:

- User message: base metadata.
- Assistant final message: base metadata plus result/stop details if available.
- Assistant tool-call message: base metadata plus provider routing and iteration number.
- Assistant suggestions message: base metadata plus suggestions.
- Tool result message: base metadata plus `actionId`, `actionCallId`, `toolCallId`, iteration number, and tool-call index.
- Tool error message: base metadata plus `actionId`, `toolCallId`, error code/message when available.

The future admin panel should be able to join:

```text
agent_conversations.id
  -> agent_messages.conversation_id
  -> agent_messages.turn_id
  -> telemetry/llm/action/cost records that also carry turn_id
```

Do not add future admin endpoints in this history implementation. The goal here is to make the data model joinable.

### `apps/backend/src/http/app.ts`

Keep existing route behavior, but improve the detail and delete response shapes.

Change `GET /v1/agent/conversations/:id` to return both the conversation and messages:

```ts
app.get("/v1/agent/conversations/:id", async (c) => {
  const user = c.get("authUser");
  const id = c.req.param("id");
  const conversation = await repository.getAgentConversation(user.id, id);
  if (!conversation) {
    throw new HTTPException(404, { message: "agent_conversation_not_found" });
  }
  return c.json({
    conversation,
    messages: await repository.listAgentConversationMessages(user.id, id),
  });
});
```

Change `DELETE /v1/agent/conversations/:id` so it hides the conversation from user history instead of hard-deleting it.

The external API can keep user-facing delete semantics, but the repository operation must update `hidden_from_user_at` rather than deleting the row.

Expected response:

```ts
const hidden = await repository.hideAgentConversationFromUser(user.id, id);
return c.json({ ok: hidden, deleted: hidden, hidden });
```

The `deleted` field is retained for mobile/backward compatibility, but internally it means "hidden from the user's history", not "physically removed from the database".

Update `GET /v1/agent/conversations` and user-facing `GET /v1/agent/conversations/:id` so hidden conversations are not visible to the user. Future admin endpoints may include hidden conversations.

### Repository Soft-Delete Changes

Prefer adding a clearer repository method:

```ts
hideAgentConversationFromUser(
  userId: string,
  conversationId: string,
): Promise<boolean>;
```

Keep `deleteAgentConversation(...)` only if too much existing code depends on it, but change its implementation to soft-delete/hide. The important invariant is:

- User-facing delete never removes `agent_messages`.
- User-facing list/detail routes ignore hidden conversations.
- Future admin routes can read hidden conversations for beta analysis.

### `packages/contracts/src/api.ts`

Add contract schemas:

```ts
export const agentConversationSummarySchema = z.object({
  id: uuidSchema,
  userId: uuidSchema.optional(),
  title: z.string(),
  hiddenFromUserAt: isoDateTimeSchema.nullable().optional(),
  createdAt: isoDateTimeSchema,
  updatedAt: isoDateTimeSchema,
});

export const agentConversationMessageSchema = z.object({
  id: uuidSchema,
  conversationId: uuidSchema,
  userId: uuidSchema.optional(),
  role: z.enum(["user", "assistant", "tool"]),
  content: z.string(),
  toolCalls: z.unknown().optional(),
  toolCallId: z.string().nullable().optional(),
  traceId: z.string().nullable().optional(),
  turnId: uuidSchema.nullable().optional(),
  inputMode: z.string().nullable().optional(),
  source: z.string().nullable().optional(),
  activeProposalId: uuidSchema.nullable().optional(),
  metadata: z.unknown().optional(),
  createdAt: isoDateTimeSchema,
});

export const agentConversationsResponseSchema = z.object({
  conversations: z.array(agentConversationSummarySchema),
});

export const agentConversationDetailResponseSchema = z.object({
  conversation: agentConversationSummarySchema,
  messages: z.array(agentConversationMessageSchema),
});

export const deleteAgentConversationResponseSchema = z.object({
  ok: z.boolean(),
  deleted: z.boolean().optional(),
  hidden: z.boolean().optional(),
});
```

Add exported types:

```ts
export type AgentConversationSummary = z.infer<typeof agentConversationSummarySchema>;
export type AgentConversationMessage = z.infer<typeof agentConversationMessageSchema>;
export type AgentConversationsResponse = z.infer<typeof agentConversationsResponseSchema>;
export type AgentConversationDetailResponse = z.infer<typeof agentConversationDetailResponseSchema>;
export type DeleteAgentConversationResponse = z.infer<typeof deleteAgentConversationResponseSchema>;
```

### `packages/contracts/src/generate-openapi.ts`

Import the new schemas.

Add component schemas:

- `AgentConversationSummary`
- `AgentConversationMessage`
- `AgentConversationsResponse`
- `AgentConversationDetailResponse`
- `DeleteAgentConversationResponse`

Add OpenAPI paths:

- `GET /v1/agent/conversations`
  - `operationId: "listAgentConversations"`
  - bearer auth
  - `200` response: `AgentConversationsResponse`
- `GET /v1/agent/conversations/{id}`
  - `operationId: "getAgentConversation"`
  - bearer auth
  - path parameter `id` as UUID string
  - `200` response: `AgentConversationDetailResponse`
- `DELETE /v1/agent/conversations/{id}`
  - `operationId: "deleteAgentConversation"`
  - bearer auth
  - path parameter `id` as UUID string
  - `200` response: `DeleteAgentConversationResponse`
  - user-facing delete semantics; internally this hides the conversation with `hidden_from_user_at` and retains rows for future admin telemetry

After editing contracts, run:

```bash
rtk pnpm generate:openapi
rtk pnpm generate:flutter-client
```

Expected generated files include:

- `packages/contracts/openapi.json`
- `apps/mobile/lib/generated/api/openapi.json`
- `apps/mobile/lib/generated/api/cal_tracker_api.dart`

If the Flutter client generator does not add the conversation methods automatically, add them manually to `CalTrackerApiClient` and keep the OpenAPI paths present for future generation.

## Mobile API Client Changes

### `apps/mobile/lib/generated/api/cal_tracker_api.dart`

Expected methods:

```dart
Future<Map<String, Object?>> listAgentConversations() {
  return _get('/v1/agent/conversations');
}

Future<Map<String, Object?>> getAgentConversation(String conversationId) {
  return _get('/v1/agent/conversations/$conversationId');
}

Future<Map<String, Object?>> deleteAgentConversation(String conversationId) {
  return _delete('/v1/agent/conversations/$conversationId');
}
```

These should preserve existing auth refresh, request-id headers, telemetry, and `_decode(...)` behavior.

The mobile method can keep the `deleteAgentConversation` name because it represents the user's action. The backend must treat it as "hide from this user's chat history", not hard deletion.

## Mobile Repository Changes

### `apps/mobile/lib/data/repositories/nutrition_repository.dart`

Add models near the existing agent chat models:

```dart
class AgentConversationSummary {
  const AgentConversationSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AgentConversationSummary.fromJson(Map<String, Object?> json) { ... }
  Map<String, Object?> toJson() { ... }
}
```

```dart
class AgentConversationMessage {
  const AgentConversationMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
    this.metadata,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String role;
  final String content;
  final Object? toolCalls;
  final String? toolCallId;
  final Object? metadata;
  final DateTime createdAt;

  factory AgentConversationMessage.fromJson(Map<String, Object?> json) { ... }
  Map<String, Object?> toJson() { ... }
}
```

```dart
class AgentConversationDetail {
  const AgentConversationDetail({
    required this.conversation,
    required this.messages,
  });

  final AgentConversationSummary conversation;
  final List<AgentConversationMessage> messages;
}
```

Add repository methods:

```dart
Future<List<AgentConversationSummary>> listAgentConversations() async { ... }
Future<AgentConversationDetail> getAgentConversation(String conversationId) async { ... }
Future<void> deleteAgentConversation(String conversationId) async { ... }
```

Expected parsing:

- `listAgentConversations()` reads `json['conversations']`.
- `getAgentConversation()` reads `json['conversation']` and `json['messages']`.
- For backward compatibility during rollout, if `json['conversation']` is absent, synthesize a minimal `AgentConversationSummary` from the requested id and message timestamps.
- `deleteAgentConversation()` treats `{ ok: true }`, `{ deleted: true }`, or `{ hidden: true }` as success.
- Repository/client naming can stay "delete" for user-facing language, but implementation semantics are "hide from user history and retain backend records".

Refactor the existing private `_parseAgentRunResult(...)` into a reusable helper:

```dart
AgentRunResult agentRunResultFromJson(Map<String, Object?> json) { ... }
```

Then update existing call sites to use this helper:

- `logText(...)`
- `runVoiceMeal(...)`
- `_parseAgentChatStreamEvent(...)`

This lets the view model reconstruct stored tool result cards from persisted tool messages.

## Mobile Cache and Session Stores

### Add `apps/mobile/lib/data/services/agent_chat_session_store.dart`

Purpose:

- Persist the active conversation id per user.
- Record enough state to decide whether entry should resume or start fresh.

Use `AppPreferencesStorage`.

Use user-scoped keys like `NutritionCacheStore`:

```dart
static const _schemaVersion = 1;
static const _keyPrefix = 'agent_chat_session:v1';
```

Data class:

```dart
class AgentChatSession {
  const AgentChatSession({
    required this.conversationId,
    required this.lastInteractionAt,
    this.lastCompletedAt,
    required this.unfinished,
  });

  final String conversationId;
  final DateTime lastInteractionAt;
  final DateTime? lastCompletedAt;
  final bool unfinished;
}
```

Store API:

```dart
class AgentChatSessionStore {
  AgentChatSessionStore({
    required AppPreferencesStorage storage,
    DateTime Function()? now,
  });

  void activateUser(String userId);
  void deactivateUser();
  Future<AgentChatSession?> readActiveSession();
  Future<void> writeActiveSession(AgentChatSession session);
  Future<void> clearActiveSession();
  Future<void> clearActiveUserData();
}
```

Behavior:

- If no active user, reads return `null` and writes no-op.
- Invalid JSON or schema version mismatch clears the stored session.
- Dates are stored as UTC ISO strings.

### Add `apps/mobile/lib/data/services/agent_chat_cache_store.dart`

Purpose:

- Cache conversation summaries and last-loaded details per user.
- Keep the history UI cache-first and stale-while-revalidate, per project rules.

Use `AppPreferencesStorage`.

Use user-scoped keys:

```dart
static const _schemaVersion = 1;
static const _keyPrefix = 'agent_chat_cache:v1';
```

Store API:

```dart
class AgentChatCacheStore {
  AgentChatCacheStore({
    required AppPreferencesStorage storage,
    DateTime Function()? now,
    Duration maxEntryAge = const Duration(days: 7),
  });

  void activateUser(String userId);
  void deactivateUser();
  Future<List<AgentConversationSummary>> readConversationSummaries();
  Future<void> writeConversationSummaries(List<AgentConversationSummary> conversations);
  Future<AgentConversationDetail?> readConversationDetail(String conversationId);
  Future<void> writeConversationDetail(AgentConversationDetail detail);
  Future<void> removeConversation(String conversationId);
  Future<void> clearActiveUserData();
}
```

Behavior:

- Cached summaries are displayed immediately.
- Cached details are used immediately when selecting a history item if available.
- Backend refresh updates the cache.
- Expired/corrupt entries are removed.

## App Wiring

### `apps/mobile/lib/app/app.dart`

Import the new stores:

```dart
import '../data/services/agent_chat_cache_store.dart';
import '../data/services/agent_chat_session_store.dart';
```

Extend `_CalTrackerComposition` with:

```dart
final AgentChatSessionStore agentChatSessionStore;
final AgentChatCacheStore agentChatCacheStore;
```

Create both stores in `_CalTrackerComposition.create(...)` using `AppPreferencesStorage`.

Inject them into `AgentChatViewModel`:

```dart
AgentChatViewModel(
  nutritionRepository: composition.nutritionRepository,
  audioRecorderService: composition.audioRecorderService,
  sessionStore: composition.agentChatSessionStore,
  cacheStore: composition.agentChatCacheStore,
)
```

In `_AuthenticatedDataPreloaderState._handleAuthChanged()`:

When a user logs in:

```dart
composition.agentChatSessionStore.activateUser(userId);
composition.agentChatCacheStore.activateUser(userId);
```

When a user logs out:

```dart
composition.agentChatSessionStore.deactivateUser();
composition.agentChatCacheStore.deactivateUser();
context.read<AgentChatViewModel>().reset();
```

If user data should be cleared on logout, call the stores' `clearActiveUserData()` before deactivation. Match the existing nutrition cache clearing behavior.

## Agent Chat ViewModel Changes

### `apps/mobile/lib/ui/features/agent_chat/view_models/agent_chat_view_model.dart`

Update constructor:

```dart
AgentChatViewModel({
  required NutritionRepository nutritionRepository,
  required AudioRecorderService audioRecorderService,
  required AgentChatSessionStore sessionStore,
  required AgentChatCacheStore cacheStore,
  DateTime Function()? now,
})
```

Add fields:

```dart
final AgentChatSessionStore _sessionStore;
final AgentChatCacheStore _cacheStore;

static const inactivityTimeout = Duration(minutes: 2);

final List<AgentConversationSummary> _conversations = [];
List<AgentConversationSummary> get conversations => List.unmodifiable(_conversations);

bool isLoadingHistory = false;
bool isRefreshingHistory = false;
bool isLoadingConversation = false;
```

Add reset:

```dart
void reset() {
  _typingTimer?.cancel();
  _typingTimer = null;
  _pendingAssistantText = '';
  _typingCompleter = null;
  _entries.clear();
  _conversations.clear();
  conversationId = null;
  isSending = false;
  isRecording = false;
  isStoppingRecording = false;
  isLoadingHistory = false;
  isRefreshingHistory = false;
  isLoadingConversation = false;
  errorMessage = null;
  statusMessage = null;
  _entryCounter = 0;
  _activeAssistantEntryId = null;
  notifyListeners();
}
```

Add public methods:

```dart
Future<void> prepareForEntry()
Future<void> refreshConversationHistory()
Future<void> loadConversation(String conversationId)
Future<void> startNewConversation()
Future<void> deleteConversation(String conversationId)
```

### `prepareForEntry()`

Behavior:

1. If sending, recording, or stopping recording, return without changing the current chat.
2. Read active session from `_sessionStore`.
3. If no session exists, clear current conversation state but do not clear cached history.
4. If the session is unfinished, load that conversation.
5. If the session is finished but `now - lastInteractionAt <= 2 minutes`, load that conversation.
6. If the session is finished and older than 2 minutes, start blank by clearing `conversationId` and entries.
7. Start `refreshConversationHistory()` in the background.

### `refreshConversationHistory()`

Behavior:

1. Load cached summaries from `_cacheStore`.
2. If cached summaries exist, display them immediately and set `isRefreshingHistory = true`.
3. Fetch fresh summaries from `NutritionRepository.listAgentConversations()`.
4. Update `_conversations`.
5. Write summaries to `_cacheStore`.
6. If backend refresh fails and cached summaries exist, keep showing cached data.
7. If backend refresh fails and no cache exists, set `errorMessage`.

### `loadConversation(String id)`

Behavior:

1. If busy or recording, return.
2. Try `_cacheStore.readConversationDetail(id)`.
3. If cached detail exists, reconstruct entries immediately.
4. Fetch fresh detail from backend.
5. Write fresh detail to cache.
6. Reconstruct entries again from fresh messages.
7. Set `conversationId = id`.
8. Save active session with `unfinished = _isCurrentConversationUnfinished()`.

### `startNewConversation()`

Behavior:

1. If busy or recording, return.
2. Clear current entries and `conversationId`.
3. Clear active session.
4. Keep cached history.
5. Next text/audio send must omit `conversationId`, causing backend to create a new conversation.

### `deleteConversation(String id)`

Behavior:

1. If busy or recording, return.
2. Call `NutritionRepository.deleteAgentConversation(id)`.
3. Remove it from `_cacheStore`.
4. Remove it from `_conversations`.
5. If `id == conversationId`, call `startNewConversation()`.

This only removes the conversation from the user's visible history. It must not imply physical deletion of `agent_conversations` or `agent_messages`.

### Stream Integration

Update `sendText(...)`:

- Add the user entry as today.
- Before streaming, save `lastInteractionAt`.
- Pass current `conversationId`.
- If `conversationId == null`, omit it and let backend create a new conversation.
- On `conversation_started`, save the returned id in session store.
- On `done`, save session with `unfinished = _isCurrentConversationUnfinished()`.
- After completion, refresh history in the background.

Update `stopRecording()` similarly:

- Voice transcript is still added when `transcription_completed` arrives.
- The active conversation/session handling must match text input.

Update `_applyEvent(...)`:

- On every event with `conversationId`, set local `conversationId`.
- On `conversation_started`, persist active session.
- On `tool_call_completed`, update unfinished/finished state from the structured result.
- On `error`, treat session as unfinished so the user can retry/resume.
- On `done`, persist final session state.

### Finished and Unfinished Detection

Add helpers:

```dart
bool _isCurrentConversationUnfinished()
bool _isResultKindUnfinished(String? kind)
bool _isResultKindTerminal(String? kind)
```

Suggested unfinished result kinds:

- `proposal`
- `usual_food_draft`
- `usual_meal_draft`
- `confirmation_required`
- `clarification_required`

Suggested terminal result kinds:

- `meal_committed`
- `meal_corrected`
- `meal_deleted`
- `summary`
- `remaining_targets`
- `history`
- `food_memory`
- `nutrition_search`
- `usual_foods`
- `templates`
- `template_saved`
- `template_deleted`

Also treat as unfinished if:

- `isSending`
- `isRecording`
- `isStoppingRecording`
- latest tool entry failed
- latest assistant entry has suggestions

Do not inspect natural-language text to decide whether a user is done.

### Reconstructing History Entries

Add helpers:

```dart
List<AgentChatEntry> _entriesFromStoredMessages(List<AgentConversationMessage> messages)
AgentToolCallFeedback? _toolFeedbackFromStoredMessage(AgentConversationMessage message)
AgentRunResult? _resultFromStoredToolMessage(AgentConversationMessage message)
List<AgentChatSuggestion> _suggestionsFromMetadata(Object? metadata)
```

Mapping:

- `role == "user"` -> user bubble.
- `role == "assistant"` with non-empty `content` -> assistant bubble.
- `role == "assistant"` with `metadata.suggestions` -> assistant bubble with suggestions.
- `role == "tool"` -> tool card.

Stored tool message content is produced by backend `safeToolContent(...)` and normally has:

```json
{
  "actionId": "...",
  "input": { ... },
  "result": { ... },
  "rawOutput": { ... }
}
```

For tool cards:

- Parse `content` as JSON.
- Use `actionId` from `metadata.actionId` or parsed content.
- Use parsed `input`.
- Use parsed `result` via `agentRunResultFromJson(...)`.
- Create a completed tool call with a generic label if exact original label is unavailable.

Suggested label helper:

```dart
String _toolLabelForAction(String actionId) {
  return actionId
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
```

This is acceptable because it formats an action id for display; it does not parse food intent.

If JSON is truncated/corrupt, show a completed or failed tool card with the raw content summary rather than crashing.

## Agent Chat Screen Changes

### `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart`

In `_AgentChatScreenState.initState()`:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    unawaited(context.read<AgentChatViewModel>().prepareForEntry());
  });
}
```

Add header actions to `FreshHeader`:

- New chat button:
  - Key: `agent_chat_new_chat_button`
  - Icon: `Icons.add_comment_rounded`
  - Tooltip: `context.l10n.agentChatNewChatTooltip`
  - Disabled while busy/recording.
  - Calls `viewModel.startNewConversation()`.
- History button:
  - Key: `agent_chat_history_button`
  - Icon: `Icons.history_rounded`
  - Tooltip: `context.l10n.agentChatHistoryTooltip`
  - Calls `_showConversationHistory(context, viewModel)`.

If `FreshHeader` does not support multiple trailing actions, extend it in the design system in the smallest compatible way, or wrap the action buttons beside the existing header title. Keep the visual style consistent with the current header.

Add method:

```dart
Future<void> _showConversationHistory(
  BuildContext context,
  AgentChatViewModel viewModel,
) async { ... }
```

History bottom sheet requirements:

- Key: `agent_chat_history_sheet`.
- Title uses `agentChatHistoryTitle`.
- Show cached conversations immediately.
- Show a small refresh indicator if `isRefreshingHistory`.
- Empty state uses `agentChatHistoryEmpty`.
- Each row:
  - Key: `agent_chat_history_item_$index`.
  - Shows title.
  - Shows updated time.
  - Tap loads conversation and closes sheet.
- Delete button:
  - Key: `agent_chat_history_delete_$index`.
  - Tooltip: `agentChatHistoryDeleteTooltip`.
  - Calls `deleteConversation(id)`.

Avoid a full-screen blocking loader when cached data or current entries exist.

## Localization

Edit:

- `apps/mobile/lib/l10n/app_en.arb`
- `apps/mobile/lib/l10n/app_es.arb`

Add English keys:

```json
"agentChatNewChatTooltip": "New chat",
"agentChatHistoryTooltip": "Chat history",
"agentChatHistoryTitle": "Chat history",
"agentChatHistoryEmpty": "No previous chats yet.",
"agentChatHistoryDeleteTooltip": "Delete chat",
"agentChatHistoryLoadError": "Could not load this chat.",
"agentChatHistoryUpdatedAt": "Updated {time}",
"agentChatHistoryRefreshing": "Refreshing..."
```

Add Spanish equivalents:

```json
"agentChatNewChatTooltip": "Nuevo chat",
"agentChatHistoryTooltip": "Historial de chats",
"agentChatHistoryTitle": "Historial de chats",
"agentChatHistoryEmpty": "Todavia no hay chats anteriores.",
"agentChatHistoryDeleteTooltip": "Eliminar chat",
"agentChatHistoryLoadError": "No se pudo cargar este chat.",
"agentChatHistoryUpdatedAt": "Actualizado {time}",
"agentChatHistoryRefreshing": "Actualizando..."
```

Use the same placeholder metadata style as existing ARB entries for `{time}`.

Regenerate localization output:

```bash
rtk cd apps/mobile
rtk flutter gen-l10n
```

If this project relies on `flutter test`/`flutter pub get` for generation instead, use the established project command.

## Tests To Add Or Update

### Backend Tests

Edit `apps/backend/src/tests/agentChat.test.ts`.

Add tests:

- Sending two chat requests without `conversationId` creates two different conversations.
- Sending with an existing `conversationId` resumes that conversation.
- `GET /v1/agent/conversations` returns conversations sorted by newest `updatedAt`.
- `GET /v1/agent/conversations/:id` returns both `conversation` and `messages`.
- `DELETE /v1/agent/conversations/:id` returns `{ ok: true, deleted: true, hidden: true }` and retains the conversation/messages in storage.
- Conversation title is derived from first message and capped at 64 characters.
- Cross-user access to another user's conversation remains blocked or empty, matching existing repository behavior.

Run:

```bash
rtk cd apps/backend
rtk bun test src/tests/agentChat.test.ts
```

### Mobile Store Tests

Add `apps/mobile/test/agent_chat_session_store_test.dart`.

Cover:

- Active user scoping.
- Read/write active session.
- Clear active session.
- Corrupt JSON clears and returns null.
- User A session does not leak to user B.

Add `apps/mobile/test/agent_chat_cache_store_test.dart`.

Cover:

- Read/write conversation summaries.
- Read/write conversation detail.
- Remove conversation removes summary and detail.
- User scoping.
- Expired/corrupt cache handling.

### Mobile ViewModel and Widget Tests

Edit `apps/mobile/test/agent_chat_test.dart`.

Update constructor calls for `AgentChatViewModel` to pass fake stores.

Add tests:

- `prepareForEntry()` starts blank after a completed session older than 2 minutes.
- `prepareForEntry()` resumes a completed session within 2 minutes.
- `prepareForEntry()` resumes unfinished sessions even after 2 minutes.
- `startNewConversation()` clears `conversationId`; next send passes `conversationId: null`.
- `conversation_started` persists the backend-created id in `AgentChatSessionStore`.
- Quick reply still sends with the active conversation id.
- Active proposal id behavior still works.
- History button opens the bottom sheet.
- Cached history rows render immediately without a blocking loader.
- Tapping a history row loads and reconstructs prior messages.
- Deleting active conversation clears the visible chat.
- Deleting inactive conversation removes it from history but keeps the current chat.

Run:

```bash
rtk cd apps/mobile
rtk flutter test test/agent_chat_test.dart test/agent_chat_session_store_test.dart test/agent_chat_cache_store_test.dart
```

## Validation Commands

From repo root:

```bash
rtk pnpm generate:openapi
rtk pnpm generate:flutter-client
rtk cd apps/backend
rtk bun test
rtk cd ../mobile
rtk flutter test
```

If UI changed, visually inspect the agent screen on Flutter after tests:

- Open `/agent`.
- Confirm blank state on first entry.
- Send a message.
- Navigate away for less than 2 minutes and return; confirm it resumes.
- Navigate away for more than 2 minutes after a terminal result; confirm it starts blank.
- Create a proposal/clarification, wait more than 2 minutes, return; confirm it resumes.
- Open history and load a previous chat.
- Delete a previous chat.

## Bottlenecks And Constraints

### This Does Not Fully Solve Long Single Conversations

Splitting sessions prevents indefinite cross-day growth, but a single active conversation can still grow large. `AgentChatService.messagesForModel()` still loads all stored messages for the selected conversation.

Future follow-up:

- Add a message/token budget.
- Summarize older messages.
- Keep recent turns verbatim and older turns as a structured summary.
- Track token and cost by conversation to decide the cutoff empirically.

### Correlation Columns vs Metadata JSON

Do not store future admin-critical identifiers only inside `metadata_json`.

Stable identifiers that admin will filter, join, or aggregate by should be columns:

- `conversation_id`
- `user_id`
- `trace_id`
- `turn_id`
- `input_mode`
- `source`
- `active_proposal_id`
- `created_at`
- `hidden_from_user_at`

Keep flexible or provider-specific details in `metadata_json`:

- provider routing payloads;
- assistant suggestions;
- raw tool/debug details;
- stop reasons not yet promoted to first-class columns;
- temporary instrumentation details.

This avoids a future admin implementation that has to perform slow JSON scans or infer turn boundaries from message order.

### Do Not Duplicate Full Chat Content Into Telemetry Tables

The canonical full conversation transcript should remain in `agent_conversations` and `agent_messages`.

Telemetry/admin tables should later reference conversations through `conversation_id`, `turn_id`, `trace_id`, and `user_id`, then store operational summaries such as:

- LLM provider request metrics;
- token and cost records;
- food-search events;
- action-call events;
- transcription records;
- failure/problem classifications.

Duplicating complete user and assistant messages into `telemetry_events` would make retention, deletion visibility, and admin rendering harder to reason about.

### Stored Tool Messages Are Not Perfect UI Events

Live UI receives rich stream events. Stored messages are persisted as assistant/user/tool messages. Tool result JSON can be truncated by `STORED_TOOL_RESULT_MAX_CHARS`.

Implication:

- History reconstruction should be best-effort.
- It must not crash on corrupt/truncated JSON.
- It should display useful generic tool cards when exact details are unavailable.

### Existing Conversations May Have Generic Titles

Old rows may be titled `"Nutrition chat"`. Do not migrate these for launch week unless necessary. New conversations should get first-message titles after this feature lands.

### User Delete Is Not Telemetry Delete

User-facing deletion hides the conversation from the mobile history list by setting `hidden_from_user_at`.

It must not physically delete:

- `agent_conversations`;
- `agent_messages`;
- message metadata;
- tool result messages.

This preserves private-beta observability for the later admin panel while still giving users a clean history UI.

### Timeout Is Mobile-Side

The 2-minute timeout is evaluated on the client. It can be affected by device clock changes.

Accept this for launch week because the timeout is a UX/cost-control heuristic, not a security boundary.

Future follow-up:

- Persist server-side `lastCompletedAt`.
- Add server-side automatic session rollover if needed.

### Cache Rules Matter

Project rules require server-backed Flutter user data to be cache-first/stale-while-revalidate. The history list and loaded conversation detail must not rely only on in-memory state.

### Do Not Add Food Intent Parsing

Do not use regexes or language-specific shortcuts to decide whether a meal was completed. Use structured result kinds and UI state only.

### Generated Client Drift

The OpenAPI generator may not fully generate new convenience methods. If that happens:

- Keep OpenAPI contracts updated.
- Add the small `CalTrackerApiClient` methods manually.
- Avoid large manual generated-client rewrites.

## Acceptance Criteria

- Opening agent chat with no active session shows the blank welcome state.
- After a new text/audio message, the backend returns a new `conversationId` and mobile stores it.
- Returning within 2 minutes resumes the last completed conversation.
- Returning after more than 2 minutes from a completed conversation starts a blank new chat.
- Returning after more than 2 minutes from an unfinished proposal/draft/clarification resumes it.
- Manual new chat clears the current `conversationId`.
- The next message after manual new chat omits `conversationId`.
- Users can open chat history, see previous conversations, select one, and continue it.
- Users can delete previous conversations.
- User deletion sets `hidden_from_user_at` or equivalent soft-delete state and does not remove stored conversation messages.
- Messages created by a chat request include first-class `traceId`, `turnId`, `inputMode`, `source`, and `activeProposalId` fields where applicable.
- All messages produced by the same `/v1/agent/chat` or `/v1/agent/chat/audio` request share the same `turnId`.
- Cached history displays immediately when available.
- Existing quick reply, active proposal, voice transcript, tool-call card, and draft review flows continue to work.
- No implementation introduces deterministic food parsing or natural-language completion heuristics.
