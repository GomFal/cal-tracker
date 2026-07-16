# Model-Facing Serialization Plus Candidate Registry Storage Plan

## Summary

Implement a model-facing serialization layer that keeps rich JSON for backend/UI/admin paths while sending compact, structured content to the LLM. This feature also moves large candidate registry metadata out of `agent_messages.metadata_json` into a dedicated registry table so database rows stay small without losing deterministic candidate selection.

Implementation happens in this worktree only:

```bash
.worktrees/model-facing-serialization
feature/model-facing-serialization
```

## Representations

1. **Full JSON**
   - Used by action execution, UI widgets, telemetry/admin inspection, and debugging.
   - Never optimized for prompt tokens.

2. **Compact JSON plus TON fields**
   - Default for newly-created LLM-facing tool messages.
   - Keeps a small JSON envelope with `tool`, `kind`, `status`, `message`, refs, compact input, and one or more TON table strings.

3. **Ultra-compact TON**
   - Used only for safe replay of older, repeated tool context.
   - Never used when required refs, errors, clarification reasons, or totals cannot be preserved.

## Key Implementation Decisions

- Use one generalized serializer, not one serializer per tool.
- Add only small generic row profiles:
  - nutrition candidate row;
  - meal item row;
  - meal summary row;
  - template/usual food row;
  - generic object row.
- Preserve required context:
  - tool/action name;
  - result kind/status/message;
  - `searchRef`, `candidateRef`, `proposalId`, `mealId`, `templateId`;
  - clarification reasons;
  - errors;
  - totals/counts;
  - candidate row refs like `g1c1`.
- Keep full candidate registry data outside the LLM content and outside message metadata.
- Store candidate registry rows in a dedicated table and keep a lightweight `candidateRegistryRef` in message metadata.
- Keep legacy fallback for old messages that still have full `candidateRegistry` inside metadata.

## Checkpoints

### 1. Spec Checkpoint

- Commit this plan before implementation.

Validation:

```bash
rtk git status
```

### 2. Migration And Schema Checkpoint

Add migration-first database support for candidate registries.

Create a migration under `infra/db/drizzle` for `agent_candidate_registries`:

- `id uuid primary key default gen_random_uuid()`
- `user_id uuid not null references users(id) on delete cascade`
- `conversation_id uuid not null references agent_conversations(id) on delete cascade`
- `message_id uuid null references agent_messages(id) on delete set null`
- `trace_id text null`
- `turn_id uuid null`
- `action_call_id uuid null`
- `search_ref text not null`
- `action_id text not null`
- `candidate_count integer not null`
- `group_count integer not null`
- `threshold numeric null`
- `registry_json jsonb not null`
- `created_at timestamptz not null default now()`

Indexes:

- `(user_id, search_ref)`
- `(conversation_id, created_at desc)`
- `(turn_id)`
- `(trace_id)`
- unique `(user_id, search_ref)`

Mirror the migration in `apps/backend/src/db/schema.ts`.

Validation:

```bash
rtk err bun run db:check
```

### 3. Repository Checkpoint

Add repository methods:

- `saveAgentCandidateRegistry(...)`
- `getAgentCandidateRegistryBySearchRef(userId, searchRef)`

Implement them in:

- `apps/backend/src/repository/postgres.ts`
- `apps/backend/src/repository/inMemory.ts`
- `apps/backend/src/repository/types.ts`

The saved registry may initially have `messageId = null`, then be linked after the tool message is inserted.

### 4. Serializer Checkpoint

Add:

```text
apps/backend/src/agent/modelFacingSerialization.ts
```

Primary behavior:

- Compute raw full JSON size from `{ actionId, input, result, rawOutput }`.
- Build compact model JSON with TON table fields.
- Omit duplicated arrays from `items`, `options`, `candidateGroups`, and `rawOutput`.
- Return metadata:
  - `serializerVersion`
  - `representation`
  - raw/model chars and approximate tokens
  - compression ratio
  - omitted paths
  - preserved paths
  - TON table metadata
  - candidate registry and selection state when candidates exist

Keep `apps/backend/src/agent/toolContent.ts` as a compatibility facade if useful.

### 5. Agent Integration Checkpoint

Update `AgentChatService`:

- Persist `modelContent` directly as the tool message content.
- Stop embedding full `candidateRegistry` in `agent_messages.metadata_json`.
- Save full candidate registry to `agent_candidate_registries`.
- Store lightweight metadata:
  - `candidateRegistryRef`
  - `searchRef`
  - `candidateCount`
  - `groupCount`
  - serializer metrics
- Keep full UI stream widgets and action telemetry unchanged.

### 6. Candidate Resolution Checkpoint

Update candidate resolution:

- Resolve by registry table first using `searchRef`.
- Fall back to legacy message metadata containing `candidateRegistry`.
- Keep support for short refs such as `g1c6`.
- Return no match cleanly if registry data is unavailable.

### 7. Safe History Replay Checkpoint

Update model message assembly:

- Keep last two turns verbatim.
- Replay older safe tool messages as ultra-compact TON.
- Do not mutate stored messages during replay.
- Malformed legacy JSON becomes a short safe summary.

### 8. Measurement And Validation Checkpoint

Add deterministic measurement for:

- old full content size;
- current compact candidate preview size;
- new compact JSON plus TON size;
- ultra-TON replay size;
- database metadata size before/after registry extraction.

Live/dev validation should compare:

- prompt tokens;
- completion tokens;
- total tokens;
- provider cost;
- iteration count;
- tool-call count;
- result kind;
- failure rate;
- final response quality.

## Tests

Update or add backend tests covering:

- candidate preview remains compact and parseable;
- duplicated candidate arrays are omitted;
- required refs and clarification reasons are preserved;
- candidate registry is saved outside message metadata;
- candidate resolution works from the registry table;
- legacy metadata fallback still works;
- cross-user registry access is blocked;
- old malformed messages do not crash replay;
- UI stream payload remains full JSON.

Validation commands:

```bash
rtk err bun run db:check
rtk test bun --cwd apps/backend test src/tests/agentToolContent.test.ts src/tests/agentChat.test.ts
rtk err bun run --cwd apps/backend typecheck
rtk test bun run test:backend
rtk test bun run admin:validate
rtk summary graphify update .
```

## Acceptance Criteria

- Full JSON remains available to backend/UI/admin/telemetry.
- LLM-facing tool messages use compact JSON plus TON.
- Older safe replay context can use ultra-TON.
- Full candidate registries are stored outside `agent_messages.metadata_json`.
- Candidate references remain deterministic and cross-user safe.
- Existing agent chat behavior remains functionally equivalent or better.
- Token and DB metadata reductions are measurable.
