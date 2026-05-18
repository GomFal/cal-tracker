# Drizzle Migration

Status: executed on 18/05/2026.

## Decisions

- Backend runtime now uses Drizzle over postgres-js through `apps/backend/src/db/client.ts`.
- Existing migrations in `infra/db/migrations` are immutable legacy history and still run first.
- New schema changes are created with Drizzle Kit in `infra/db/drizzle`.
- Reserved/runtime-unused tables are retained so future backend work can use them without data loss.
- `apps/backend/src/db/schema.ts` mirrors the current migrated PostgreSQL schema, including reserved tables.

## Implemented Flow

1. Start from the existing database shape by running all legacy SQL migrations.
2. Introspect the migrated database with `drizzle-kit pull` and compare it to `apps/backend/src/db/schema.ts`.
3. Keep `infra/db/drizzle/0000_baseline_existing_schema.sql` as a no-op baseline for Drizzle metadata.
4. Add all new forward migrations under `infra/db/drizzle` with Drizzle Kit:
   - `bun run --cwd apps/backend db:generate` for schema-derived migrations.
   - `bun run --cwd apps/backend db:generate:custom -- --name=<name>` for hand-authored PostgreSQL SQL that Drizzle cannot express cleanly.
5. Run `bun run db:migrate`; the runner applies legacy migrations first, then Drizzle migrations.

## Backend Runtime Changes

- `PostgresRepository` keeps the app repository contract stable while using a Drizzle database instance.
- Drizzle query builders are used in scripts where they operate on app tables.
- Repository SQL now runs through Drizzle's parameterized `sql` objects instead of postgres-js templates. Query builders should be preferred for new ordinary CRUD, while existing repository SQL fragments remain where preserving behavior and PostgreSQL-specific features is important:
  - pgvector distance operators.
  - pg_trgm similarity and trigram operators.
  - partial-conflict upserts, raw JSONB casts, and existing multi-step repository workflows.
  - trusted migration bodies and schema setup.
- `createUser()` is transactional.
- `updateTrustedMode()` writes the requested value instead of always disabling trusted mode.
- Daily summaries query the requested date range in SQL instead of filtering a fixed recent-meal window in TypeScript.
- Meal and template list mapping batch-loads child rows instead of issuing one child query per parent.
- TypeScript database scripts now use the shared Drizzle client and Drizzle query builders for app-table access.

## Implemented Files

- `apps/backend/drizzle.config.ts`: Drizzle Kit configuration.
- `apps/backend/src/db/client.ts`: shared postgres-js + Drizzle client.
- `apps/backend/src/db/schema.ts`: Drizzle schema for all current PostgreSQL app tables.
- `apps/backend/scripts/migrate.ts`: legacy migrations followed by Drizzle migrations.
- `infra/db/drizzle/`: new Drizzle migration directory and metadata snapshots.
- `apps/backend/scripts/seed.ts`, `embed-food-items.ts`, and `benchmark-agent-foods.ts`: converted to the shared Drizzle client where they query app data.

## New Drizzle Migrations

- `0000_baseline_existing_schema.sql`: no-op baseline matching the schema produced by legacy migrations.
- `0001_food_search_documents_sync.sql`: adds a PostgreSQL trigger/function that keeps `food_search_documents` synchronized when `food_items` is inserted or updated, including data loaded outside the runtime repository.

## Verification Completed On 18/05/2026

- `bun run --cwd apps/backend typecheck`
- `bun run --cwd apps/backend test`
- `bun run --cwd apps/backend db:check`
- `bun run --cwd apps/backend db:generate`
- `bun run --cwd apps/backend build`
- Compared `apps/backend/src/db/schema.ts` to live PostgreSQL after `bun run db:migrate`, excluding Drizzle's own `__drizzle_migrations` table.
- Verified 31 application tables and 301 application columns matched the live database.
- Verified Drizzle's `__drizzle_migrations` table contains the baseline and food-search sync migrations.
- Verified the food search document trigger creates a synchronized `food_search_documents` row from a `food_items` insert.

## Rules Going Forward

- Do not edit or regenerate `infra/db/migrations`.
- Do not use `drizzle-kit push` against shared environments.
- Do not drop reserved tables unless product and data-retention decisions explicitly require it.
- Commit Drizzle SQL migrations and `infra/db/drizzle/meta` snapshots together.
- Prefer Drizzle query builders for ordinary CRUD and joins; use `sql` only when the database feature requires it.
