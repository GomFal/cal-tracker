## Implementation Plan: Stateful Nutrition Candidate Selection

### Goal

Fix the duplicated `search_nutrition_database` tool-result inefficiency without reducing live UI quality or preventing the user from selecting any candidate shown by the app.

The chosen implementation treats ingredient candidate lists as backend/UI state, not LLM context. The LLM sees an accepted high-confidence item or a compact pending-selection state. It does not see full candidate arrays.

### Non-goals

- Do not remove rich candidate lists from the live mobile UI.
- Do not rely on the LLM to remember every candidate.
- Do not introduce natural-language or regex food parsing.
- Do not break direct action endpoints that mobile or tests already consume.

### Design Principle

Separate three payloads that are currently conflated:

1. Action output: canonical backend result from `ActionExecutor`.
2. UI payload: rich data streamed to the mobile app for rendering and selection.
3. LLM tool content: compact context sent back to the model and persisted in `agent_messages.content`.
4. Candidate registry metadata: full candidate rows stored in `agent_messages.metadata_json`, available for deterministic selection but not sent to the LLM.

Only the third payload needs aggressive token control.

### Step 1. Add a compact tool-content serializer

Add a helper near `safeToolContent()` in `apps/backend/src/agent/agentChatService.ts`:

```ts
function toolContentForModel(input: {
  actionId: string;
  toolInput: unknown;
  mappedResult: AgentChatMappedResult;
  rawOutput: unknown;
}): string {
  return safeToolContent(compactToolResult(input));
}
```

`compactToolResult()` should return a structured object, not a pre-rendered string.

Use this helper instead of directly storing:

```ts
safeToolContent({
  actionId,
  input: parsedInput,
  result: mapped,
  rawOutput: result.output,
})
```

### Step 2. Special-case `search_nutrition_database`

For `search_nutrition_database`, store only one candidate collection in the LLM tool message:

```json
{
  "actionId": "search_nutrition_database",
  "input": { "query": "pan" },
  "result": {
    "kind": "nutrition_search",
    "message": "I found matching nutrition items.",
    "candidateCount": 10,
    "candidateGroups": [
      {
        "mention": { "originalText": "pan", "canonicalName": "pan" },
        "candidates": [
          {
            "rank": 1,
            "name": "Pan blanco",
            "quantity": 100,
            "unit": "g",
            "calories": 265,
            "proteinGrams": 9,
            "carbsGrams": 49,
            "fatGrams": 3,
            "confidence": 0.92,
            "matchScore": 0.92,
            "externalSource": "usda_fdc",
            "externalId": "..."
          }
        ]
      }
    ]
  }
}
```

Do not include:

- `rawOutput`
- duplicated `candidates` alias
- duplicated top-level `items` when the same items already appear inside `candidateGroups`
- `sourceUrl`
- `license`
- `displayDetails`
- verbose provenance fields that the LLM does not need

Do not send candidate lists to the LLM for low-confidence results. The live UI event carries all candidates returned by the resolver, and the LLM receives only a `selectionState` with `searchRef`, counts, threshold, and status.

### Step 3. Preserve full UI behavior

Keep the existing streamed `tool_call_completed` event rich enough for the mobile UI:

```ts
yield {
  type: "tool_call_completed",
  conversationId,
  toolCall,
  result: mapped,
  widget,
};
```

This means the current turn can still render all candidates.

For history or resume, do not require `agent_messages.content` to contain the full UI payload. If a pending clarification must survive screen reload with full options, store a UI-specific payload outside the LLM-facing content:

- short-term option: put `uiResult` or `uiWidget` in `agent_messages.metadata_json`;
- cleaner long-term option: create an `agent_tool_results` table keyed by `conversation_id`, `turn_id`, and `tool_call_id`.

`messagesForModel()` must continue to send only compact `content` to the LLM.

### Step 4. Support user selection beyond compacted candidates

When the user taps any candidate shown in the UI, the selection is handled deterministically.

Implemented approach:

- Store backend-issued candidate references in `agent_messages.metadata_json`.
- Add `candidateSelection` to `/v1/agent/chat` requests.
- The mobile app sends `searchRef`, `groupIndex`, and `candidateIndex`; it does not send the full candidate object.
- The backend resolves the full candidate from metadata and injects only the selected `MealItem` into the next LLM turn.
- A chat-only internal `resolve_candidate_reference` tool handles typed references such as "use the 6th one".

The LLM follow-up should receive only a compact result:

```json
{
  "actionId": "resolve_candidate_reference",
  "result": {
    "kind": "candidate_reference",
    "message": "Selected nutrition candidate resolved.",
    "selectedItem": {
      "rank": 6,
      "name": "Pan integral",
      "calories": 247
    }
  }
}
```

This keeps the conversation coherent without requiring the model to remember every candidate in the original list.

### Step 5. Remove or deprecate duplicated aliases in action output

After the compact tool-content path is covered by tests, clean up the action output shape:

- Prefer `candidateGroups` as the canonical field.
- Stop adding both `candidates` and `candidateGroups` in new code.
- Keep compatibility parsing on the mobile side during rollout.
- Update tests that explicitly assert `candidateGroups` equals `candidates`.

This is lower priority than compacting the LLM tool message, because the direct action output does not become provider context unless the agent stores it.

### Step 6. Add chat token payload instrumentation

Mirror the one-shot agent input stats that already exist in `AgentService` for chat runs:

- message JSON characters
- approximate message tokens
- largest message by role/action id
- compacted vs raw tool-content character count
- whether truncation happened

Record these stats in local run logs and/or telemetry metadata for `agent.chat`.

This lets future token work be ranked from production evidence instead of source inspection only.

### Step 7. Tests

Backend tests should cover:

- `search_nutrition_database` tool content contains no `rawOutput`.
- The stored tool message contains one candidate collection, not `items` plus `candidates` plus `candidateGroups`.
- Compact candidates include only approved fields.
- The live `tool_call_completed` event still contains enough data for UI rendering.
- Stored compact tool content remains valid JSON and does not truncate mid-object.
- Conversation continuation still sends the compact stored tool message to the fake LLM provider.
- Selecting a candidate outside the compacted top N can still update/create a proposal through a deterministic backend path.

Mobile tests should cover:

- Candidate list rendering still uses the rich streamed payload.
- Candidate selection sends the selected candidate or candidate token through a deterministic path.
- Reconstructed history does not crash when full UI payload is absent from tool message content.

### Step 8. Acceptance Criteria

- A single `search_nutrition_database` tool call no longer persists `rawOutput`.
- The persisted tool message has no duplicate candidate arrays.
- The LLM receives compact candidate summaries only.
- The mobile UI can still show all candidates returned by the backend in the live turn.
- A user can select any visible candidate, including one not included in the compact LLM summary.
- The backend can continue the conversation after selection using a compact result message.
- Chat logs expose enough payload-size metrics to verify the token reduction.

## Recommended First Patch

The smallest high-impact patch is:

1. Add `compactToolResult()` and `compactMealItemForModel()` in `AgentChatService`.
2. Use them only for stored/sent tool message content.
3. Special-case `search_nutrition_database`, `propose_meal_log`, `revise_meal_proposal`, and `draft_usual_meal` candidate groups.
4. Keep live stream event payloads unchanged.
5. Add backend tests around `agentChat.test.ts` with a fake provider and a fake bulky search result.

This should reduce token usage immediately while preserving current UI behavior.
