# Agent Chat Token Inefficiency Audit

Last updated: 2026-06-19

## Purpose

This document ranks the current high token augmenters in the agent chat system and explains why they happen, how to fix them, and why the fixes should reduce token usage without reducing the quality of the LLM conversation.

The main focus is the duplicated nutrition-search tool result path, where the same candidate foods can be serialized several times into the tool message that is sent back to the LLM and persisted into later conversation context.

## Ranked Token Augmenters

### 1. Duplicated nutrition search tool result payloads

Current source points:

- `apps/backend/src/actions/executor.ts` returns `items`, `candidates`, and `candidateGroups` for `search_nutrition_database`.
- `apps/backend/src/agent/agentChatService.ts` maps that output into another `nutrition_search` result with `items` and `options`.
- `apps/backend/src/agent/agentChatService.ts` stores the tool message as `{ actionId, input, result, rawOutput }`.
- `apps/backend/src/agent/agentChatService.ts` caps stored tool content at 12,000 characters, but only after duplicating and JSON-stringifying the payload.

Why it happens:

`search_nutrition_database` currently returns aliased candidate fields for compatibility, then the chat layer wraps the same data in a UI-friendly mapped result, then the stored tool message includes both the mapped result and the raw action output. For one search, the same candidates can appear in all of these places:

- `result.items`
- `result.options[0].candidates`
- `rawOutput.items`
- `rawOutput.candidates[0].candidates`
- `rawOutput.candidateGroups[0].candidates`

The resolver caps a single food search to the top 10 candidates, so this is usually not 100 unique candidates for one ingredient. The problem is that those 10 candidates can be repeated several times, and each candidate is a full `MealItem` with nutrition, provenance, match scores, IDs, source details, optional display details, and other metadata.

How to solve it:

Create a compact LLM-facing tool result serializer that is separate from the live UI payload. The LLM-facing message should contain only the action id, compact input, result kind, counts, a short summary, and a deduplicated list of compact candidates. The full UI payload can still be streamed to the mobile app, and if needed for history reconstruction, stored outside the LLM-facing `content` field, for example in message metadata or a dedicated tool-result table.

Why this stays performant:

The LLM does not need all candidate fields to continue a natural conversation. It needs to know that a search ran, whether matches exist, which short candidate labels are available, and whether the user should choose. The mobile UI can own full candidate selection. If the user selects the 6th candidate and only the first 5 were summarized to the LLM, the client should send the selected item or a backend-issued candidate token to a deterministic backend action. The LLM can then receive a compact follow-up such as "selected candidate rank 6, proposal updated" instead of needing to remember the full list.

### 2. Bulky tool messages are replayed in every later provider call

Current source points:

- `AgentChatService.messagesForModel()` prepends the system prompt and then maps all stored conversation messages into the provider message array.
- `PostgresRepository.listAgentConversationMessages()` returns all visible messages in the conversation ordered by `created_at, id`.
- `chatAgentProvider.formatProviderMessages()` sends user, assistant, and tool messages to OpenRouter as chat-completion messages.

Why it happens:

The provider API is stateless. Each LLM call receives the full current context. Once a bulky tool message is persisted into `agent_messages.content`, it becomes part of every later LLM request for that conversation.

How to solve it:

Keep persisted `tool` message `content` compact by design. Add a separate conversation compaction strategy later: recent turns verbatim, older turns summarized, and large historical tool outputs represented by structured summaries.

Why this stays performant:

The model keeps the conversational facts and recent decisions, but it stops re-reading raw candidate arrays or full meal lists that are no longer needed for reasoning.

### 3. Candidate groups returned for successful meal proposals and revisions

Current source points:

- `propose_meal_log` returns `proposal`, `autoCommittedMeal`, and `candidateGroups` even on resolved proposal paths.
- `revise_meal_proposal` accumulates `revisionCandidateGroups` and returns merged candidate groups after successful updates.
- `draft_usual_meal` returns `draft`, `resolvedItems`, `options`, and `candidateGroups`.

Why it happens:

The backend uses candidate groups for UI confidence, clarification, and auditability. That is useful, but the chat tool-message path currently treats UI display data and LLM context data as the same object.

How to solve it:

For LLM-facing tool content, include full candidate groups only when the LLM must ask the user for clarification. On successful proposal/revision paths, store a compact summary: proposal id, title, item count, item names, total calories/macros, and whether additional candidate alternatives were available.

Why this stays performant:

The LLM can explain the created proposal and ask for confirmation without seeing every alternative match. The UI can still display detailed candidate choices when the user needs them.

### 4. `get_daily_summary` returns full meals when many questions only need totals

Current source points:

- `get_daily_summary` returns `DailySummary`.
- `DailySummary` includes `meals: z.array(mealSchema)`.
- Each `Meal` includes full `items`.

Why it happens:

The summary contract is useful for the dashboard, but it is large for chat answers like "how am I doing today?" or "how many calories are left?"

How to solve it:

Prefer `get_remaining_targets` when the user's question is about remaining calories/macros. Add a compact daily-summary-for-agent shape for chat, or compact `get_daily_summary` tool content before storing/sending it to the LLM.

Why this stays performant:

The model still receives the numbers needed for the answer. It only loses full meal item details when those details are not needed.

### 5. `get_meal_history` can return many full meal objects

Current source points:

- `getMealHistoryInputSchema.limit` defaults to 25 and allows up to 100.
- `ActionExecutor` returns full `meals`.
- `Meal` includes full `items`.

Why it happens:

History lookup is designed as a general tool. If the model requests a large limit, every meal and item enters the tool message.

How to solve it:

Reduce the default agent-facing history limit, add explicit guidance to request a small limit unless the user asks for more, and compact stored tool content to meal summaries: id, title, time, calories/macros, and maybe top item names.

Why this stays performant:

Most chat history questions need recent examples or totals, not every item field. If the user asks for detailed history, the UI/backend can fetch details deterministically.

### 6. `get_usual_foods` and `get_usual_meals` are unbounded

Current source points:

- `PostgresRepository.listUsualFoods()` returns all user-owned usual ingredients.
- `PostgresRepository.listTemplates()` returns all user-owned meal templates.
- `MealTemplate` includes full `items` and aliases.

Why it happens:

The actions are list-all APIs. That is convenient for UI screens, but chat may only need matching templates or a small shortlist.

How to solve it:

Add agent-specific query/list tools with search text and limits, or compact the tool content before it is stored and sent back to the LLM. For template lookup, prefer memory/query tools over listing every template.

Why this stays performant:

The LLM gets the relevant subset while preserving the ability to search or fetch more when needed.

### 7. `query_food_memory` can include full templates

Current source points:

- `PostgresRepository.queryMemory()` limits matches to 5.
- Each memory match can include a full meal template.

Why it happens:

Memory retrieval returns template objects so the backend can use them immediately for proposal creation.

How to solve it:

Keep full templates inside backend execution, but send the LLM compact memory matches: label, confidence, template id, template title, item count, and nutrition summary.

Why this stays performant:

The model can decide whether a memory is relevant without reading the full template item payload.

