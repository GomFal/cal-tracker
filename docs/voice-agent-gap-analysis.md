# Voice Input and Agent Orchestration Gap Analysis

## Purpose

This document explains why voice meal logging and backend agent capabilities do not currently work as described in the MVP implementation plan, and what must be implemented to make the app follow the intended architecture.

The short version:

```text
Current app:
  Flutter text field -> /v1/agent/runs -> hard-coded propose_meal_log action -> deterministic local nutrition estimate

Intended MVP:
  Flutter text or recorded audio
    -> backend STT when audio
    -> backend OpenRouter tool-calling agent
    -> canonical backend action executor
    -> proposal / confirmation / commit / correction / summary
```

The missing behavior is not only caused by absent API keys. Real `OPENAI_API_KEY` and `OPENROUTER_API_KEY` values are required, but the code does not yet call either provider for STT or agent reasoning.

## Current Implementation State

### Flutter Voice UI

Relevant files:

* `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
* `apps/mobile/lib/ui/features/voice_log/view_models/voice_log_view_model.dart`
* `apps/mobile/pubspec.yaml`
* `apps/mobile/android/app/src/main/AndroidManifest.xml`

What exists:

* The meal logging screen has a text input and a microphone icon.
* `permission_handler` and `record` are listed in `pubspec.yaml`.
* Android has `RECORD_AUDIO` permission.
* The microphone button calls `VoiceLogViewModel.requestVoicePermission()`.

What is missing:

* No audio recorder instance is created.
* No recording lifecycle exists: start, stop, cancel, elapsed time, waveform/status, file path, or cleanup.
* No audio file is uploaded to the backend.
* No transcription result is displayed or submitted.
* No voice-specific error states exist for recording failure, upload failure, transcription failure, or unsupported platform.
* The `record` dependency is installed but unused in the current code path.

Current microphone behavior is therefore only permission handling. It is not voice meal logging.

### Flutter API Client

Relevant files:

* `apps/mobile/lib/generated/api/cal_tracker_api.dart`
* `apps/mobile/lib/data/repositories/nutrition_repository.dart`

What exists:

* `CalTrackerApiClient.runAgent(String text)` posts JSON to `/v1/agent/runs`.
* `NutritionRepository.logText(String text)` calls `runAgent`.

What is missing:

* No multipart upload method exists.
* No `transcribeAudio` API method exists.
* No method sends recorded audio bytes to the backend.
* The generated client is currently a hand-written wrapper over JSON endpoints, not a full generated client that supports multipart OpenAPI operations.

### Backend Agent Route

Relevant file:

* `apps/backend/src/http/app.ts`

Current implementation:

```ts
app.post("/v1/agent/runs", async (c) => {
  const user = c.get("authUser");
  const body = agentRunRequestSchema.parse(await c.req.json());
  const context = buildActionContext(c, user, body.source);
  const result = await actionExecutor.execute("propose_meal_log", { text: body.text }, { ...context, source: "internal_agent" });
  ...
});
```

This route does not call an LLM. It always executes `propose_meal_log` directly.

What is missing:

* No OpenRouter HTTP client.
* No chat/tool-calling abstraction.
* No prompt or system instruction.
* No tool schema conversion from action metadata.
* No loop for model-selected tool calls.
* No policy layer that restricts which actions the agent may call.
* No agent run persistence beyond the action calls created by the deterministic executor.
* No support for agent decisions such as:
  * use `get_meal_history` for "same lunch as yesterday",
  * use `get_remaining_targets` for "how many calories do I have left",
  * use `delete_meal` for "delete the snack I just added",
  * use `correct_meal` for "no, the chicken was 200 grams".

### Backend Action Executor

Relevant file:

* `apps/backend/src/actions/executor.ts`

What exists:

* Canonical action metadata is loaded from `packages/contracts`.
* Inputs are validated by Zod.
* Permission scopes are checked.
* Action calls and audit events are recorded.
* `propose_meal_log`, `commit_meal`, `correct_meal`, `delete_meal`, summaries, history, and templates have deterministic handlers.

What is limited:

* `propose_meal_log` is marked as `agent_assisted` in contracts, but its implementation is deterministic.
* It handles only a narrow class of food phrases through local nutrition estimation and exact memory lookup.
* It does not delegate ambiguous parsing to an agent.
* Correction parsing is hard-coded for chicken grams.
* Delete and summary intent selection are not reachable from `/v1/agent/runs` because that route always calls `propose_meal_log`.

The action executor is the right foundation, but it is currently being used as a direct endpoint handler rather than as the tool substrate for an agent.

### Nutrition Providers

Relevant file:

* `apps/backend/src/nutrition/provider.ts`

What exists:

* `LocalNutritionProvider` estimates meals using seeded generic foods.
* It recognizes only simple terms such as chicken, rice, egg, oats, and milk.
* `OpenFoodFactsProvider` and `UsdaNutritionProvider` are stubs returning empty arrays.

What is missing:

* No provider chain implements the planned priority order:

```text
user templates/custom foods
  -> OpenFoodFacts branded/barcode
  -> manual user values
  -> USDA/generic
  -> backend estimates
  -> LLM-only fallback requiring confirmation
```

* No external nutrition API integration exists.
* No LLM fallback proposal path exists.
* No source confidence or trust metadata is carried deeply enough to enforce all planned auto-commit rules.

### Backend STT

Relevant files:

* No backend STT provider files currently exist.
* `apps/backend/src/config/env.ts` requires `OPENAI_API_KEY`, but no code uses it for transcription.

What is missing:

* No `SpeechToTextProvider` interface.
* No OpenAI-compatible transcription implementation.
* No route accepting audio.
* No multipart parser or upload size/type validation.
* No transcription audit/action record.
* No tests for transcription provider behavior.

The current `.env` contains development placeholders, so even if an STT client existed, it would fail until real credentials were supplied.

Terminology note: there is no separate "Whisper key" in this implementation plan. The backend should use a normal provider API key, such as `OPENAI_API_KEY`, with a configured transcription model. If we later choose a different Whisper-compatible vendor, that should be represented as a separate STT provider and env var rather than leaking vendor details into Flutter.

### OpenRouter Configuration

Relevant files:

* `apps/backend/src/config/env.ts`
* `.env`
* `.env.example`

What exists:

* `OPENROUTER_API_KEY` and `OPENROUTER_MODEL` are required by config validation.
* Local `.env` currently uses placeholder development values.

What is missing:

* No provider validates the key by making a real request.
* No OpenRouter client consumes `OPENROUTER_API_KEY`.
* No model-specific tool-call response parser exists.
* No fallback behavior exists when the key is absent, invalid, rate-limited, or the model does not return valid tool calls.

Therefore, setting a real key is necessary but not sufficient.

## Why The User-Visible Feature Fails

### Voice Does Not Work

When the user taps the microphone:

```text
VoiceLogScreen mic button
  -> VoiceLogViewModel.requestVoicePermission()
  -> Permission.microphone.request()
  -> done
```

The app never records audio and never sends anything to the backend.

Expected flow:

```text
VoiceLogScreen mic button
  -> start recording with record
  -> stop recording
  -> upload audio to backend
  -> backend transcribes audio
  -> Flutter displays transcript
  -> transcript is submitted to /v1/agent/runs
```

### Agent Capabilities Do Not Work

When the user submits text:

```text
Flutter runAgent(text)
  -> POST /v1/agent/runs
  -> backend directly executes propose_meal_log
  -> deterministic nutrition proposal
```

The LLM never sees the request and never chooses an action.

Expected flow:

```text
Flutter runAgent(text)
  -> POST /v1/agent/runs
  -> AgentService sends messages + action tool schemas to OpenRouter
  -> model selects one or more allowed actions
  -> ActionExecutor validates and executes selected actions
  -> AgentService returns proposal, meal, summary, deletion confirmation, or correction result
```

### Trusted Auto-Commit Is Only Partially Reachable

The action executor has a trusted auto-commit check for template-based proposals, but the user path depends on exact memory/template matching and direct `propose_meal_log`.

Missing pieces:

* Agent does not decide that a phrase maps to a template.
* Vector memory retrieval is not implemented as a usable runtime provider.
* Flutter does not expose full undo/correct affordances after an auto-commit.
* Nutrition trust source metadata is too limited for the full policy in the plan.

## Required Architecture To Match The MVP Plan

### Runtime Components

Add these backend components:

```text
apps/backend/src/agent/
  agentService.ts
  openRouterProvider.ts
  toolSchemas.ts
  agentPolicy.ts
  agentMessages.ts

apps/backend/src/stt/
  speechToTextProvider.ts
  openAiTranscriptionProvider.ts
  audioValidation.ts

apps/backend/src/nutrition/
  nutritionProviderChain.ts
  openFoodFactsProvider.ts
  usdaProvider.ts
  llmNutritionFallback.ts

apps/backend/src/memory/
  memoryRetrievalService.ts
  embeddingProvider.ts
  outboxWorker.ts
```

Add or extend Flutter components:

```text
apps/mobile/lib/data/services/audio_recorder_service.dart
apps/mobile/lib/data/repositories/transcription_repository.dart
apps/mobile/lib/ui/features/voice_log/view_models/voice_log_view_model.dart
apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart
apps/mobile/lib/generated/api/cal_tracker_api.dart
```

### Backend Interfaces

The backend should define provider interfaces before concrete provider code.

```ts
export type TranscriptionResult = {
  text: string;
  language?: string;
  durationSeconds?: number;
  provider: "openai";
  model: string;
};

export interface SpeechToTextProvider {
  transcribe(input: {
    audio: Blob | Buffer;
    filename: string;
    mimeType: string;
    userId: string;
    traceId: string;
  }): Promise<TranscriptionResult>;
}
```

```ts
export type AgentRunResult =
  | { kind: "proposal"; proposal: MealProposal; message: string }
  | { kind: "meal_committed"; meal: Meal; message: string }
  | { kind: "summary"; summary: DailySummary; message: string }
  | { kind: "history"; meals: Meal[]; message: string }
  | { kind: "confirmation_required"; actionId: string; input: unknown; message: string }
  | { kind: "clarification_required"; message: string; options?: unknown[] };

export interface ChatAgentProvider {
  runWithTools(input: {
    messages: AgentMessage[];
    tools: AgentToolDefinition[];
    model: string;
    traceId: string;
  }): Promise<AgentToolDecision>;
}
```

The concrete OpenRouter provider should use `OPENROUTER_API_KEY` and `OPENROUTER_MODEL`, but the rest of the backend should depend on `ChatAgentProvider`.

### API Contracts

Current contract:

```ts
agentRunRequestSchema = {
  text: string,
  source: "flutter" | "ios_appintents" | "android_appfunctions"
}
```

Needed additions:

1. Keep `/v1/agent/runs` for text input.
2. Add a backend-owned transcription endpoint:

```text
POST /v1/stt/transcriptions
Content-Type: multipart/form-data
Authorization: Bearer <accessToken>

fields:
  audio: file
  source: flutter

returns:
  transcript: string
  provider: string
  model: string
  traceId: string
```

3. Optionally add a combined voice-agent endpoint after the separate route works:

```text
POST /v1/agent/runs/audio
Content-Type: multipart/form-data

audio -> STT -> AgentService -> action executor
```

The separate STT route is easier to test and debug first. It also lets Flutter show the transcript before submitting the agent request.

### Agent Tool Execution Flow

The intended flow should be:

```text
AgentService.run(text, context)
  1. Build safe user context:
       timezone, locale, trusted mode flag, today date
       no password/session tokens
       no raw database credentials

  2. Build tool schemas from packages/contracts actionDefinitions.

  3. Filter tools by:
       authenticated user's scopes
       source
       safety policy
       destructive/confirmation policy

  4. Send messages + tools to OpenRouter.

  5. Parse tool call:
       actionId
       JSON input

  6. Validate input through ActionExecutor.

  7. Execute deterministic action handler.

  8. Return normalized AgentRunResult to Flutter.

  9. Record:
       action_calls for every action
       audit_events for every mutation
       agent run metadata for model/provider/latency/tool decision
```

The agent must never receive direct repository access. It only receives action schemas and safe context, then asks the backend to execute actions.

### Agent Policy

Agent policy should enforce these rules before any tool call executes:

| Request type | Agent may select | Confirmation |
| --- | --- | --- |
| New ambiguous meal | `propose_meal_log` | Required |
| Known trusted template | `propose_meal_log` | Auto-commit only if policy passes |
| Correction | `correct_meal` | Required |
| Delete | `delete_meal` | Required, destructive confirmation token |
| Daily summary | `get_daily_summary` or `get_remaining_targets` | Never |
| Meal history lookup | `get_meal_history` | Never |
| Template management | template actions | Required for writes |

The backend should reject model-selected destructive writes unless the request has explicit user confirmation.

### OpenRouter Provider Behavior

The OpenRouter provider should:

* Send only action schemas and safe context.
* Use strict JSON tool call parsing.
* Treat malformed tool calls as recoverable agent errors.
* Retry only safe transient failures.
* Never ask the model to invent nutrition database facts as authoritative values.
* Require confirmation for LLM-only nutrition fallback.

Minimum request shape:

```ts
POST https://openrouter.ai/api/v1/chat/completions
Authorization: Bearer ${OPENROUTER_API_KEY}
Content-Type: application/json

{
  "model": OPENROUTER_MODEL,
  "messages": [...],
  "tools": [...],
  "tool_choice": "auto"
}
```

The provider should be isolated so a future model vendor change does not affect action handlers.

### STT Provider Behavior

The STT provider should:

* Accept only bounded audio sizes.
* Accept explicit MIME types such as `audio/m4a`, `audio/mp4`, `audio/wav`, or `audio/webm`, depending on what Flutter records on each platform.
* Upload audio from the backend to the transcription provider.
* Return plain transcript text plus provider metadata.
* Avoid storing raw audio unless a future privacy setting explicitly enables it.
* Record audit metadata without including raw audio.

The backend should own the STT API key. Flutter must not call OpenAI directly.

### Flutter Voice Flow

Implement this state machine in `VoiceLogViewModel`:

```text
idle
  -> requestingPermission
  -> ready
  -> recording
  -> stopping
  -> transcribing
  -> transcriptReady
  -> agentRunning
  -> proposalReady | autoCommitted | clarificationRequired | error
```

UI behavior:

* Mic button starts recording when idle.
* Stop button stops recording.
* The transcript appears in the text box before submission.
* User may edit the transcript.
* Submit sends text to `/v1/agent/runs`.
* Errors are recoverable without losing the transcript.
* The text path must continue working without microphone permissions.

Implementation sketch:

```dart
final recorder = AudioRecorder();
await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
final path = await recorder.stop();
final transcript = await transcriptionRepository.transcribe(File(path));
controller.text = transcript;
await nutritionRepository.logText(transcript);
```

The exact encoder/container should be tested on Android and iOS because supported output formats differ by platform.

## Implementation Slices

### Slice 1: Make Voice Record Locally

Backend not required.

Tasks:

* Add `AudioRecorderService`.
* Implement start/stop/cancel.
* Store temporary audio under app cache.
* Show recording state and elapsed time.
* Add widget tests for permission states and button transitions.
* Manually verify recording creates a file on Android emulator.

Exit criteria:

* Tapping mic starts recording.
* Tapping stop creates a non-empty audio file.
* Denied permission shows recoverable UI.

### Slice 2: Add Backend STT

Tasks:

* Add `SpeechToTextProvider` interface.
* Add `OpenAiTranscriptionProvider`.
* Add `POST /v1/stt/transcriptions`.
* Add multipart parsing.
* Add size/type validation.
* Add auth requirement.
* Add tests with a fake STT provider.

Exit criteria:

* Flutter can upload a recorded file.
* Backend returns a transcript from a fake provider in tests.
* Backend returns a clear error when `OPENAI_API_KEY` is placeholder/missing in development.

### Slice 3: Wire Flutter Voice To STT

Tasks:

* Add multipart method to `CalTrackerApiClient`.
* Add `TranscriptionRepository`.
* Send recorded audio to `/v1/stt/transcriptions`.
* Display transcript in the text field.
* Keep text submission user-controlled.

Exit criteria:

* User can record voice.
* User sees transcript.
* User can edit transcript.
* User can submit transcript through existing text path.

### Slice 4: Replace Fake Agent Route With AgentService

Tasks:

* Add `AgentService`.
* Add `OpenRouterChatProvider`.
* Convert action metadata to tool schemas.
* Add policy-filtered tool list.
* Update `/v1/agent/runs` to call `AgentService.run`.
* Keep deterministic direct action routes unchanged.
* Add fake provider tests for golden requests.

Exit criteria:

* "How many calories do I have left?" calls `get_remaining_targets`.
* "Chicken and rice" calls `propose_meal_log`.
* "Delete the snack I just added" returns confirmation-required, not a direct delete.
* All tool calls go through `ActionExecutor`.

### Slice 5: Complete Nutrition Provider Chain

Tasks:

* Implement provider chain order.
* Implement OpenFoodFacts branded/barcode search.
* Add USDA adapter or explicit stub response that is surfaced as unavailable.
* Add LLM nutrition fallback only as low-trust, confirmation-required estimates.
* Carry `source` and trust metadata on items.

Exit criteria:

* Known local foods still work offline.
* External branded/barcode search works when configured.
* LLM-only nutrition proposals never auto-commit.

### Slice 6: Memory And Embeddings

Tasks:

* Implement exact normalized memory lookup first.
* Implement temporal lookup for "same as yesterday".
* Implement optional embedding generation through OpenRouter using `baai/bge-m3`.
* Store vectors in `food_memory_embeddings`.
* Add outbox job processing or synchronous dev mode.
* Add confidence/reranking rules.

Exit criteria:

* "usual breakfast" resolves to a user template.
* "same lunch as yesterday" resolves from meal history.
* Low-confidence matches ask for clarification.

## Environment And Secrets

The current `.env` uses placeholders:

```text
OPENROUTER_API_KEY=dev-openrouter-key
OPENAI_API_KEY=dev-openai-key
```

For real voice and agent functionality, local development needs:

```text
OPENROUTER_API_KEY=<real OpenRouter key>
OPENROUTER_MODEL=<tool-calling-capable model>
OPENAI_API_KEY=<real OpenAI key>
OPENAI_TRANSCRIPTION_MODEL=<chosen transcription model>
EMBEDDING_PROVIDER=openrouter
EMBEDDINGS_ENABLED=false
EMBEDDING_MODEL=baai/bge-m3
EMBEDDING_DIMENSIONS=1024
```

Recommended config changes:

* Add `OPENAI_TRANSCRIPTION_MODEL`.
* Do not accept known placeholder strings in providers.
* Keep config fail-fast for missing env vars.
* Let tests inject fake providers so CI does not require real API keys.

## Tests To Add

Backend unit tests:

* STT route rejects unauthenticated requests.
* STT route rejects missing/oversized/unsupported audio.
* STT route returns fake transcript.
* AgentService maps "chicken and rice" to `propose_meal_log`.
* AgentService maps "calories left" to `get_remaining_targets`.
* AgentService maps "delete snack" to confirmation-required delete flow.
* AgentService rejects model-selected actions outside user scopes.
* AgentService records action calls and audit events through the executor.

Backend integration tests:

* Real PostgreSQL migration still applies.
* `/v1/agent/runs` works with fake OpenRouter provider and real repository.
* `/v1/stt/transcriptions` works with fake STT provider and auth.

Flutter tests:

* Mic permission denied state.
* Recording start/stop state transitions.
* Transcript display after upload.
* Text submission after transcript edit.
* Agent response proposal display.
* Confirmation commit flow.
* API error state for STT failure.

Manual acceptance:

* User records "chicken and rice".
* App displays transcript.
* Agent creates a meal proposal.
* User confirms proposal.
* Dashboard summary updates.
* User asks "how many calories do I have left?" by text.
* Agent returns remaining targets instead of creating a meal proposal.

## Definition Of Done

Voice and agent functionality should not be considered complete until:

* A recorded audio file is actually created on Android and iOS.
* Audio is sent only to the backend, never directly from Flutter to OpenAI.
* Backend STT returns a transcript with provider metadata.
* `/v1/agent/runs` uses an agent service and OpenRouter provider, not direct `propose_meal_log`.
* The agent only executes tools through `ActionExecutor`.
* Destructive or ambiguous actions require confirmation.
* LLM-only nutrition values cannot auto-commit.
* All new API shapes are reflected in contracts/OpenAPI and Flutter client code.
* Backend and Flutter tests cover the primary voice-to-proposal flow.
