# Agent Chat History Current Status

Berry evidence run: `fd9d9d1523d99616`.

This document describes the current implementation status for chat history between the user and the conversational agent.

## Current Backend Storage

Agent conversations are stored in `agent_conversations`, and individual user, assistant, and tool messages are stored in `agent_messages`. The current history migration adds `hidden_from_user_at` to conversations and adds first-class correlation fields to messages: `trace_id`, `turn_id`, `input_mode`, `source`, and `active_proposal_id`. It also adds indexes for visible conversation lookup and turn/correlation lookup. [S2]

The Drizzle schema mirrors those fields and indexes in the TypeScript schema for `agentConversations` and `agentMessages`. [S3]

## Conversation Visibility And Deletion

Conversation list/detail reads only return conversations where `hidden_from_user_at IS NULL`. Message reads join through the conversation and also require the conversation to be visible. Message insertion only succeeds if the target conversation is still visible. [S4]

Deleting a conversation from the app is implemented as a hide operation: `hideAgentConversationFromUser` sets `hidden_from_user_at` and updates `updated_at`; it does not hard-delete the conversation row or message rows. [S4]

The HTTP API exposes:

- `GET /v1/agent/conversations`
- `GET /v1/agent/conversations/:id`
- `DELETE /v1/agent/conversations/:id`

The detail endpoint returns `404 agent_conversation_not_found` when the conversation is absent or hidden. The delete endpoint returns `{ ok, deleted, hidden }`. [S5]

## Turn Correlation

Each `AgentChatService.chat` request resolves an existing conversation or creates a new one, then creates a turn-level correlation object containing:

- `traceId`
- `turnId`
- `inputMode`
- `source`
- `conversationId`
- optional `activeProposalId`

The user message is persisted with this correlation. [S6]

The shared `messageCorrelation` helper writes the same correlation into first-class message columns and into `metadata`, so future telemetry/admin work can connect a conversation, turn, trace, source, input mode, and active proposal from either structured columns or metadata JSON. [S8]

Tool error messages are also persisted through `addAgentConversationMessage` with the same correlation helper plus tool/action metadata. [S7]

## Conversation Creation

A new backend conversation is created lazily when the user sends a message without a `conversationId`. The new conversation title is derived from the first message text, normalized and truncated, with a fallback title of `Nutrition chat`. [S7] [S8]

This means pressing "new chat" on mobile clears local state immediately, but the backend row is not created until the first message of that new chat is sent.

## Mobile Session And Cache Behavior

The mobile app constructs and provides two chat-history stores:

- `AgentChatSessionStore`
- `AgentChatCacheStore`

They are registered in the app provider tree and constructed as part of app composition. [S16] [S17]

When an authenticated user becomes active, the app activates both chat stores for that user. When the authenticated user leaves the session, it deactivates both stores. [S18]

`AgentChatSessionStore` stores the active session payload with `conversationId`, `lastInteractionAt`, optional `lastCompletedAt`, and `unfinished`. Its storage key is derived from an active user key, and it clears corrupt or incompatible stored payloads. [S9]

`AgentChatCacheStore` stores cached conversation summaries and conversation details. It uses schema-versioned envelopes, `cachedAt`, an expiry window, and user-keyed storage keys. It can remove one conversation from cache or clear all cached data for the active user. [S10]

## Mobile Entry And Resume Rules

The mobile view model uses a two-minute `inactivityTimeout`. On entering the chat screen, it refreshes history, reads the active session, and:

- clears current state when there is no active session;
- loads the previous conversation when the session should resume;
- starts a new local conversation when the session should not resume. [S11]

The resume heuristic returns true when the session is marked `unfinished`. Otherwise, it returns true only when the last interaction is within the two-minute inactivity timeout. [S13]

The current unfinished criteria are based on structured UI/result state:

- the agent is still sending;
- recording is active or stopping;
- the assistant has suggestions;
- the latest result kind is `proposal`, `usual_food_draft`, `usual_meal_draft`, `confirmation_required`, or `clarification_required`;
- a tool entry failed. [S13]

After stream completion, the view model saves the active session with `unfinished` set from that structured state and refreshes history in the background. [S12]

## Mobile History UI

The chat header includes:

- a new-chat button keyed `agent_chat_new_chat_button`, which calls `startNewConversation`;
- a history button keyed `agent_chat_history_button`, which opens the history sheet. [S14]

The history sheet refreshes conversation history, shows loading/refreshing/empty states, lists cached or fresh conversations, loads a selected conversation, and exposes a delete button for each conversation. [S15]

The mobile repository wraps the backend history endpoints through `listAgentConversations`, `getAgentConversation`, and `deleteAgentConversation`. Delete treats any `ok`, `deleted`, or `hidden` true response as success. [S19]

## Test Coverage

Backend tests assert that persisted conversation details include the expected title, message roles, a shared `turnId`, present `traceId`, `inputMode`, `source`, and tool metadata such as `actionId`, `actionCallId`, and `resultKind`. [S20]

Backend tests also assert that deleting a conversation returns `{ ok: true, deleted: true, hidden: true }`, removes it from user list/detail responses, and retains stored messages internally. [S21]

Mobile tests assert that:

- a stale completed session starts blank, clears the active session, and does not fetch the old conversation;
- a stale unfinished session resumes and loads its stored message;
- manual new chat clears the previous `conversationId`, so the next send passes `conversationId: null`. [S22] [S23]

## Current Boundaries

This feature implements chat history and correlation-ready storage. It does not yet implement the future admin-panel views that aggregate or inspect chat history. The new database columns make that work possible by carrying `conversationId`, `turnId`, `traceId`, `inputMode`, `source`, and `activeProposalId` through stored messages. [S2] [S8]

The backend does not currently decide when a conversation is finished based on time. The current cutoff is a mobile entry-time heuristic: unfinished sessions resume regardless of age, while completed sessions resume only within the two-minute timeout. [S11] [S13]
