# Database and Vector Architecture

Status: updated to the implemented project state on 18/05/2026.

## Current Architecture

```text
Flutter app
  -> Bun + TypeScript backend
  -> Drizzle ORM over postgres-js
  -> PostgreSQL 16 + pgvector in Docker
```

PostgreSQL is the source of truth. pgvector is retrieval infrastructure. Flutter never connects directly to PostgreSQL, never executes vector search, and never generates embeddings.

The backend owns:

- authentication and session persistence,
- action execution and audit logging,
- nutrition lookup and meal/proposal/template persistence,
- local food search,
- embedding provider calls,
- pgvector queries,
- Drizzle schema and forward migrations.

## Local Database

Local development uses `docker-compose.yml`:

```text
image: pgvector/pgvector:0.8.2-pg16-bookworm
database: cal_tracker
user: cal_tracker
password: cal_tracker
host port: 5432
volume: cal_tracker_postgres
```

The init SQL and migrations ensure pgvector is available:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

## Migration Ownership

There are now two migration histories:

- `infra/db/migrations`: immutable legacy SQL migrations, applied first and tracked in `schema_migrations`.
- `infra/db/drizzle`: Drizzle-owned forward migrations and snapshots, applied second and tracked in `__drizzle_migrations`.

The migration runner is `apps/backend/scripts/migrate.ts`. It creates the configured schema, applies legacy SQL files, then calls Drizzle's migrator for `infra/db/drizzle`.

Do not edit or regenerate existing files in `infra/db/migrations`. New schema changes should use:

```bash
bun run --cwd apps/backend db:generate
bun run --cwd apps/backend db:generate:custom -- --name=<name>
bun run --cwd apps/backend db:migrate
```

`drizzle-kit push` must not be used against shared environments.

## Drizzle Schema

The canonical TypeScript schema is:

```text
apps/backend/src/db/schema.ts
```

It was verified against the local migrated database on 18/05/2026:

```text
31 application tables
301 application columns
0 table mismatches
0 column mismatches
0 nullability mismatches
```

Drizzle's internal `__drizzle_migrations` table is intentionally excluded from the application schema.

## Current Tables

Application tables:

```text
action_calls
agent_connections
audit_events
auth_identities
auth_sessions
confirmation_requests
corrections
daily_goal_snapshots
food_aliases
food_item_embeddings
food_items
food_memories
food_memory_embeddings
food_portions
food_search_documents
meal_items
meal_proposal_items
meal_proposals
meal_template_items
meal_templates
meals
nutrition_targets
outbox_jobs
password_reset_tokens
reference_data_imports
schema_migrations
user_credentials
user_food_feedback_events
user_food_preferences
users
```

Migration metadata table managed by Drizzle:

```text
__drizzle_migrations
```

Reserved tables are retained even when not actively used by current runtime logic:

```text
agent_connections
confirmation_requests
corrections
food_aliases
food_memory_embeddings
outbox_jobs
```

These reserved tables should not be dropped unless a product and data-retention decision explicitly requires it.

## Runtime Table Groups

Identity and auth:

```text
users
user_credentials
auth_identities
auth_sessions
password_reset_tokens
```

Goals and summaries:

```text
nutrition_targets
daily_goal_snapshots
```

Food data and search:

```text
food_items
food_portions
food_search_documents
reference_data_imports
food_item_embeddings
user_food_feedback_events
user_food_preferences
```

Meals and memory:

```text
meal_proposals
meal_proposal_items
meals
meal_items
meal_templates
meal_template_items
food_memories
```

Audit, operations, and reserved future use:

```text
action_calls
audit_events
agent_connections
confirmation_requests
corrections
food_aliases
food_memory_embeddings
outbox_jobs
```

## Vector Implementation

The active embedding configuration is a single global vector space:

```text
enabled: false by default
provider: openrouter
model: baai/bge-m3
dimensions: 1024
```

The vector columns are:

```text
food_item_embeddings.embedding vector(1024)
food_memory_embeddings.embedding vector(1024)
```

`food_item_embeddings` is prepared for hybrid food search. Runtime embeddings are currently disabled while costs are evaluated, so food search relies on lexical exact/prefix/trigram matching unless `EMBEDDINGS_ENABLED=true`. When enabled, the backend uses OpenRouter `baai/bge-m3` embeddings and combines:

- lexical exact/prefix/trigram matches from `food_search_documents`,
- pgvector similarity from `food_item_embeddings`,
- user preference scores from `user_food_preferences`.

`food_memory_embeddings` exists for future semantic memory work. Current memory lookup primarily uses normalized text matching through `food_memories`; the memory retrieval service probes the embedding provider for availability but does not yet persist or query memory vectors in production runtime logic.

## Food Search Documents

`food_search_documents` is the lexical search projection for `food_items`.

Legacy migration `0014_food_search_documents.sql` created and backfilled the table and indexes. Drizzle migration `0001_food_search_documents_sync.sql`, added on 18/05/2026, now creates a PostgreSQL trigger/function so inserts and updates to `food_items` keep `food_search_documents` synchronized even when data is loaded outside `PostgresRepository`.

The sync function updates:

```text
food_item_id
user_id
locale
scope
search_text
rank_bucket
source
external_source
data_type
food_key
updated_at
```

Important indexes include trigram indexes for generic Spanish, generic English, and market search, plus scope/locale/rank and user indexes.

## Query Safety

Backend runtime code no longer uses direct postgres-js templates in `PostgresRepository`. It uses:

- Drizzle database transactions,
- Drizzle query builders in scripts and new CRUD-style paths,
- Drizzle parameterized `sql` objects for PostgreSQL-specific operations.

Raw SQL remains appropriate for:

- pgvector operators such as `<=>`,
- pg_trgm similarity and `%`,
- JSONB casts,
- partial conflict targets,
- trusted migration files,
- schema setup helpers.

User-provided values must always be bound parameters through Drizzle or postgres-js templates. Do not concatenate user values into SQL strings.

## Retrieval Flow

Food resolution currently follows this shape:

```text
1. Normalize request text.
2. Search local food documents by locale/scope.
3. Use barcode lookup when a barcode is present.
4. Use vector search when lexical search is insufficient and embeddings are available.
5. Rerank by lexical score, vector score, and user preference score.
```

Meal memory currently follows this shape:

```text
1. Normalize memory phrase.
2. Query `food_memories` by exact/fuzzy normalized text for the authenticated user.
3. Return linked templates when confidence is sufficient.
4. Treat vector memory as unavailable until memory embeddings are fully implemented.
```

## Production Boundary

Production starts with self-hosted PostgreSQL + pgvector on the VPS. PostgreSQL must not be publicly exposed; only the backend should reach it over an internal network or localhost.

Minimum operational requirements before production launch:

- persistent PostgreSQL storage,
- encrypted backups,
- restore test,
- disk and container health monitoring,
- migration procedure,
- upgrade procedure,
- no public `5432` exposure.
