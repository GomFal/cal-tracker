# Food Data Quality and Normalized Search Runbook

Status: implemented PostgreSQL normalized food search reference.

This document describes the food data quality, normalization, and optimized PostgreSQL search functionality implemented from the `feat/food-data-quality-normalized-search` work and now present on `develop`.

Raw imported food rows remain immutable in `food_items`. The implemented flow adds derived quality, normalization, review, and runtime search tables on top of that raw corpus.

## Architecture

The data pipeline is:

```text
food_items
  -> food_item_quality
  -> food_normalization_sample_sets / food_normalization_sample_items
  -> food_normalization_review
  -> food_normalized_search_documents
  -> normalized PostgreSQL search in PostgresRepository
```

The quality layer classifies every food row before normalization:

| Status | Search behavior |
| --- | --- |
| `valid` | Eligible for normalized search documents. |
| `duplicate` | Excluded from default search; points to canonical quality metadata where possible. |
| `suspicious` | Excluded from default search until reviewed. |
| `quarantined` | Excluded from search and meal proposal resolution. |

The normalized search layer writes one runtime document per accepted food item into `food_normalized_search_documents`. Each document carries display identity, base/variant names, brand display, entity aliases, identity token keys, result type, locale, search text, search vector, rank bucket, quality flags, and metadata.

The review layer writes one row per audited item into `food_normalization_review`. Runtime normalized search only reads documents whose matching review row has `review_status = 'valid'` and whose quality row has `is_search_eligible = true`.

The sample layer is retained for rollback and QA. `FOOD_NORMALIZED_SEARCH_SCOPE=sample` restricts runtime search to `normalized_search_v1`; `FOOD_NORMALIZED_SEARCH_SCOPE=full` uses all valid normalized documents.

## Schema And Migrations

The normalized search work is represented in Drizzle migrations under `infra/db/drizzle`:

| Migration | Purpose |
| --- | --- |
| `0010_food_data_quality_normalized_search.sql` | Adds quality, sample, and normalized search document tables. |
| `0011_food_normalized_primary_entity.sql` | Adds primary entity identity fields. |
| `0012_food_normalized_representativeness.sql` | Adds coherence and representativeness ranking fields. |
| `0013_food_normalization_review.sql` | Adds normalization review storage. |
| `0014_food_normalized_identity_trgm_indexes.sql` | Adds trigram identity indexes. |
| `0015_food_normalized_identity_btree_indexes.sql` | Adds lower-case identity btree indexes. |
| `0016_food_normalized_identity_token_keys.sql` | Adds `identity_token_keys` plus GIN indexing. |

The runtime env flags are:

```env
FOOD_NORMALIZED_SEARCH_ENABLED=true
FOOD_NORMALIZED_SEARCH_SCOPE=full
FOOD_NORMALIZED_SEARCH_SAMPLE_SET=normalized_search_v1
```

Use `FOOD_NORMALIZED_SEARCH_ENABLED=false` as the rollback switch. Use `scope=sample` for partial rollout and `scope=full` after the full quality and normalization apply has completed.

## Runtime Search Behavior

`PostgresRepository.searchFoodsHybrid` selects the normalized path when `FOOD_NORMALIZED_SEARCH_ENABLED=true`.

The normalized path:

- handles barcode queries first with exact barcode matching;
- filters every result through `food_item_quality.is_search_eligible` and `food_normalization_review.review_status = 'valid'`;
- applies sample membership only when scope is `sample`;
- searches locales in priority order based on request locale, with `any` and fallback language coverage;
- runs a strong-identity phase before broad text search;
- short-circuits when strong identity returns enough high-quality candidates;
- falls back to normalized full-text search and then trigram fuzzy search when needed;
- deduplicates by normalized display name so repeated products do not flood top-k;
- returns normalized display metadata to the API so the UI can show compact names plus useful details.

The strong-identity phase uses exact normalized identity fields before broad FTS:

- `base_name`
- `display_name`
- `brand_display`
- `primary_entity_aliases`
- `secondary_entity_aliases`
- `identity_token_keys`

Array checks use GIN-friendly containment, for example:

```sql
identity_token_keys @> ARRAY[<query_identity_key>]::text[]
primary_entity_aliases @> ARRAY[<normalized_query>]::text[]
```

This query shape is the main runtime optimization. It avoids expensive broad FTS/window ranking for common exact identity queries such as `milk`, `rice`, `ground beef`, `arroz`, or `olive oil`.

## Operational Commands

Run all commands from `apps/backend`.

Apply migrations first:

```bash
bun --env-file=.env run db:migrate
```

Data quality audit only:

```bash
bun --env-file=.env run food-quality audit
```

Data quality apply:

```bash
bun --env-file=.env run food-quality apply
```

Create or refresh the representative sample:

```bash
bun --env-file=.env run food-normalization:sample
```

Audit normalized sample docs:

```bash
bun --env-file=.env run food-normalization:backfill -- --scope sample --mode audit
```

Apply normalized sample docs:

```bash
bun --env-file=.env run food-normalization:backfill -- --scope sample --mode apply
```

Audit full normalized docs:

```bash
bun --env-file=.env run food-normalization:backfill -- --scope full --mode audit --batch-size 5000
```

Generate long-name candidates from review output:

```bash
bun --env-file=.env run food-normalization:long-name-review -- --mode candidates --scope full --out ../../data/food-normalization/long-name-candidates.jsonl
```

Generate deterministic long-name decisions:

```bash
bun --env-file=.env run food-normalization:long-name-review -- --mode decisions --candidates ../../data/food-normalization/long-name-candidates.jsonl --out ../../data/food-normalization/long-name-decisions.jsonl
```

`--mode suggest` is also available when an intentional remote LLM-assisted suggestion pass is needed. It requires the configured OpenRouter credentials and still writes an offline decision artifact; the runtime backfill and runtime search do not call an LLM.

Apply full normalized docs with long-name decisions and ambiguous product collision exclusion:

```bash
bun --env-file=.env run food-normalization:backfill -- --scope full --mode apply --long-name-decisions ../../data/food-normalization/long-name-decisions.jsonl --exclude-ambiguous-product-collisions
```

Reset derived normalization artifacts when intentionally rebuilding:

```bash
bun --env-file=.env run food-normalization:reset-artifacts
```

For VPS/dev/pro operations, include script guards on mutating commands so the script refuses to run against the wrong database or schema:

```bash
bun --env-file=.env run food-quality apply --require-db-name cal_tracker --require-schema cal_tracker_dev
bun --env-file=.env run food-normalization:sample --require-db-name cal_tracker --require-schema cal_tracker_dev
bun --env-file=.env run food-normalization:backfill -- --scope full --mode apply --require-db-name cal_tracker --require-schema cal_tracker_dev
```

## Reports And Artifacts

Reports are intentionally local and ignored by Git:

| Path | Produced by |
| --- | --- |
| `data/food-quality/` | `food-quality audit|apply` |
| `data/food-normalization/` | sample generation, normalization audit/apply, long-name review |
| `data/food-search-benchmarks/` | search benchmark and primary-position validation |
| `data/meal-proposal-search-benchmarks/` | one-off local end-to-end benchmark reports |
| `tools/benchmarks/` | local-only benchmark harnesses that should not ship in the backend image |

Do not commit generated JSON/JSONL benchmark or audit output unless a separate task explicitly promotes a small fixture into tracked test data.

Long-name decisions are offline artifacts. The normal backfill is deterministic for a given decision file; runtime search must not call an LLM.

## Rollout Sequence

Recommended rollout for a target schema:

1. Back up or clone the target database/schema.
2. Run migrations.
3. Run `food-quality apply` with `--require-db-name` and `--require-schema`.
4. Run full normalization audit.
5. Generate and apply long-name decisions if long-name review issues remain.
6. Run full normalization apply with ambiguous product collisions excluded.
7. Run `validate:food-search-primary -- --scope full`.
8. Run `benchmark:food-search -- --mode compare --scope full --profile-sql`.
9. Enable normalized search with `FOOD_NORMALIZED_SEARCH_ENABLED=true` and `FOOD_NORMALIZED_SEARCH_SCOPE=full`.
10. Keep the env rollback switch available until manual and benchmark validation are stable.

## Engineering Rules

- Do not mutate raw `food_items` during quality or normalization.
- Do not add ingredient-specific, query-specific, language-shortcut, or stopword-based runtime fixes.
- Normalize products as product identity plus brand when brand data is reliable.
- Preserve nutritionally meaningful descriptors in `variant_name`, `display_name`, display details, or metadata; do not hide descriptors that change the food.
- Exclude invalid, duplicate, suspicious, and ambiguous rows from default normalized search instead of trying to rank around bad data.
- Keep reusable scripts under `apps/backend/scripts`; keep one-off exploratory harnesses under ignored `tools/benchmarks`.
