# Food Data Quality and Full Normalized Search Plan

Status: planning document for the next implementation slice.

This document replaces the original sample-only rollout plan. The data quality layer has already been applied to the full local `cal_tracker_dev` database. The next challenge is extending the normalized food search layer from the approved sample to the whole quality-eligible corpus.

Typesense is not part of this plan. This remains a PostgreSQL-first normalized search rollout.

## Current State

Raw imported rows remain immutable in `food_items`.

The data quality pass now writes one row per food item into `food_item_quality`.

Current local counts:

| Metric | Rows |
| --- | ---: |
| Total `food_items` rows | 1,299,484 |
| Search-eligible valid rows | 1,011,978 |
| Excluded rows | 287,506 |
| Duplicate rows | 104,656 |
| Quarantined rows | 54,369 |
| Suspicious rows | 128,481 |
| Existing normalized docs from sample | 32,200 |
| Eligible rows not yet normalized | 979,778 |

Eligible non-sample rows still requiring full normalization:

| Source | Rows |
| --- | ---: |
| Open Food Facts | 604,377 |
| USDA Branded | 375,401 |
| USDA SR Legacy | 0 |
| USDA Foundation | 0 |

The sample already covers all eligible USDA generic rows. The full-corpus rollout mainly extends product normalization to Open Food Facts and USDA branded rows.

## Goals

- Generate normalized search documents for the full quality-eligible corpus.
- Keep raw `food_items` untouched for provenance and reprocessing.
- Include only `food_item_quality.is_search_eligible = true` rows in default normalized search.
- Apply the same deterministic normalization behavior used for the sample.
- Detect concrete normalization failures, suspicious outliers, and display/search collisions before full runtime usage.
- Store reviewable normalization issues in the database and export JSON reports for manual inspection.
- Keep sample normalized search as rollback while full normalized search is validated.
- Produce a reusable normalization/backfill script that can run on any machine with the application code and database access, including production.
- Avoid ingredient-specific hardcoding, exact food-name fixes, stopword shortcuts, or regex-based food understanding.

## Full-Corpus Normalization Flow

The full flow is:

```text
food_items
  join food_item_quality where is_search_eligible = true
  -> deterministic normalization
  -> per-row invariant checks
  -> batch/global outlier checks
  -> batch/global collision checks
  -> valid docs into food_normalized_search_documents
  -> non-valid docs into food_normalization_review and JSON reports
```

The normalizer must run in three modes:

- `audit`: compute normalized previews and review issues, write DB review rows and JSON, do not modify runtime search docs.
- `apply`: compute normalized previews and review issues, write valid runtime docs, remove stale docs for rows no longer valid, write review rows and JSON.
- `sample`: keep current sample-only behavior for rollback and comparison.

The script should support resumable keyset pagination:

```text
--scope sample|full
--mode audit|apply
--batch-size <number>
--resume-after <food_item_id>
```

Default batch size: `5,000`.

## Portable Production Artifact

The final implementation artifact must not be a local-only data operation. It must be a backend script that can be executed in any environment that has:

- the backend source code
- database connectivity through `DATABASE_URL`
- the target schema configured through `DATABASE_SCHEMA`
- the required migrations already applied

The script must be safe for local, staging/dev, and production use.

Required properties:

- Environment-driven: no hardcoded local paths, database names, hostnames, schema names, sample IDs, or user IDs.
- Idempotent: rerunning the same command with the same normalization version must converge to the same database state.
- Resumable: support keyset continuation with `--resume-after <food_item_id>`.
- Auditable: support `--mode audit` to generate review rows and JSON reports before writing runtime docs.
- Apply-capable: support `--mode apply` to write valid normalized docs and remove stale docs for rows no longer valid.
- Scope-aware: support `--scope sample|full`.
- Versioned: every review row and runtime doc must include the current normalization version.
- Observable: print progress, final counts, report paths, inserted/updated/deleted doc counts, and issue counts.
- Failure-safe: abort on database errors and leave enough progress information to resume from the last completed batch.

Production execution sequence:

```bash
cd apps/backend
bun --env-file=.env run food-quality apply
bun --env-file=.env run food-normalization:backfill -- --scope full --mode audit
bun --env-file=.env run food-normalization:long-name-review -- --mode candidates --scope full --out ../../data/food-normalization/long-name-candidates.jsonl
bun --env-file=.env run food-normalization:long-name-review -- --mode suggest --candidates ../../data/food-normalization/long-name-candidates.jsonl --out ../../data/food-normalization/long-name-decisions.jsonl
bun --env-file=.env run food-normalization:backfill -- --scope full --mode audit --long-name-decisions ../../data/food-normalization/long-name-decisions.jsonl
bun --env-file=.env run food-normalization:backfill -- --scope full --mode apply --long-name-decisions ../../data/food-normalization/long-name-decisions.jsonl
bun --env-file=.env run benchmark:food-search -- --mode normalized --scope full
```

The exact command names may change during implementation, but the final script must provide this operational capability.

## Review Storage

Add a new table named `food_normalization_review`.

Required fields:

- `food_item_id uuid primary key references food_items(id) on delete cascade`
- `normalization_version text not null`
- `review_status text not null`
- `severity text not null`
- `issue_codes text[] not null default '{}'`
- `raw_name text not null`
- `raw_brand text`
- `raw_source text`
- `raw_external_source text`
- `raw_data_type text`
- `display_name text`
- `base_name text`
- `variant_name text`
- `brand_display text`
- `primary_entity_name text`
- `result_type text`
- `normalization_confidence numeric(6, 4)`
- `metrics jsonb not null default '{}'::jsonb`
- `metadata jsonb not null default '{}'::jsonb`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Allowed `review_status` values:

- `valid`: normalized row passes all QA gates.
- `needs_review`: normalized row exists but triggered at least one non-fatal QA issue.
- `failed`: no safe normalized doc can be built.

Allowed `severity` values:

- `info`: valid row, useful for audit/reporting only.
- `warning`: row can be inspected later, but should not enter runtime docs until approved.
- `error`: hard failure; row cannot enter runtime docs.

Indexes:

- `(review_status, severity)`
- GIN on `issue_codes`
- `(normalization_version)`
- `(result_type, lower(display_name))` via expression index if supported in the migration style

JSON report output:

```text
data/food-normalization/review-<timestamp>.json
```

The JSON report must include:

- counts by `review_status`
- counts by `issue_code`
- counts by source/data type
- top collision groups
- top outlier groups
- samples per issue code
- counts and samples for non-blocking observability issue codes
- long-name decision counts and stale-decision samples
- runtime-doc insert/delete counts when running in `apply`

## Concrete QA Gates

The QA gates are intentionally simple and measurable. They do not try to prove that every normalized name is semantically perfect. Their objective is to catch rows where the deterministic normalization is unsafe for default search.

### Per-Row Invariants

A row is `failed` with `severity = error` if any invariant fails.

Issue codes:

| Issue code | Detection |
| --- | --- |
| `empty_display_name` | `displayName` is blank after cleanup. |
| `empty_base_name` | `baseName` is blank after cleanup. |
| `empty_primary_entity` | `primaryEntityName` is blank after cleanup. |
| `empty_search_text` | `searchText` is blank after cleanup. |
| `invalid_result_type` | `resultType` is not `generic_food`, `product`, or `custom_food`. |
| `invalid_locale` | locale is blank or not one of the supported normalized values used by search. |
| `product_empty_name` | `resultType = product` and product display name is blank after cleanup. |
| `generic_empty_name` | `resultType = generic_food` and generic base name is blank after cleanup. |
| `normalizer_returned_no_doc` | deterministic normalizer returns `undefined`. |

Rows with any of these issue codes must not be inserted into `food_normalized_search_documents`.

### Per-Row Outlier Metrics

For each normalized preview, compute and store these metrics:

- `rawTokenCount`
- `displayTokenCount`
- `rawCharLength`
- `displayCharLength`
- `searchTextTokenCount`
- `hiddenDescriptorCount`
- `retainedDescriptorCount`
- `compressionRatio = displayTokenCount / rawTokenCount`
- `charCompressionRatio = displayCharLength / rawCharLength`
- `descriptorLossRatio = hiddenDescriptorCount / max(1, hiddenDescriptorCount + retainedDescriptorCount)`
- `normalizationConfidence`

For product rows, use raw product name + brand as the raw text input for token/character metrics.

For generic rows, use raw USDA name as the raw text input.

Blocking outlier issue codes:

| Issue code | Detection |
| --- | --- |
| `low_confidence` | `normalizationConfidence < 0.68`. |
| `display_too_short` | `rawTokenCount >= 4` and `displayTokenCount = 1`. |
| `display_too_long` | `displayTokenCount > max(18, sample_p99_displayTokenCount)`. |
| `search_text_too_long` | `searchTextTokenCount > max(80, sample_p99_searchTextTokenCount)`. |
| `excessive_descriptor_loss` | `hiddenDescriptorCount >= 4` and `descriptorLossRatio > 0.75`. |
| `overcollapsed_display` | Only blocking when paired with `display_too_short` or `excessive_descriptor_loss`. |

Rows with blocking outlier issue codes are `needs_review` by default. They should not enter runtime docs until fixed or explicitly approved.

Non-blocking observability issue codes:

| Issue code | Detection |
| --- | --- |
| `no_effect_generic_compaction` | `resultType = generic_food`, raw name contains comma segments, and `displayName` normalized text equals raw name normalized text. |
| `product_brand_only_display` | `resultType = product` and normalized display text equals normalized brand text. |
| `product_brand_duplicated` | `resultType = product` and normalized display contains the normalized brand more than once. |
| `overcollapsed_display` | Standalone compression outlier without a concrete loss/collision blocker. |

Non-blocking observability issue codes are stored in review metadata and JSON reports. They do not prevent a row from entering `food_normalized_search_documents` when all blocking QA gates pass.

Sample percentile values must be computed from current approved sample docs before full audit. They must be written into the JSON report metadata so the thresholds are reproducible.

### Long Product Text Decisions

Very long product rows are handled with an offline artifact, not runtime LLM calls.

The flow is:

```text
full audit
  -> candidate JSONL from display_too_long/search_text_too_long review rows
  -> Codex-authored offline compact identity decisions
  -> approved JSONL decisions
  -> audit/apply with --long-name-decisions
```

Codex is the LLM reviewer for this phase. It generates the compact product identity artifact row by row before the full apply. The app runtime and the backfill apply path do not call an LLM; they only load deterministic, signature-checked JSONL decisions.

Decision rows are keyed by:

- `foodItemId`
- `normalizationVersion`
- `inputSignature`

The backfill applies only approved decisions whose signature still matches the current raw row. Missing, rejected, or stale decisions leave the row under the existing blocking long-text review issue.

For approved decisions:

- `displayName`, `baseName`, optional `variantName`, compact aliases, and selected descriptors are used for display/search identity.
- `searchText` is bounded to normalized identity fields, brand, compact aliases, selected descriptors, barcode, and category.
- Raw name, raw brand, ingredients, full normalized description, decision source, and input signature remain in `metadata`.
- No dedicated migration is required for v1 because the normalized document already has `metadata jsonb`.

### Collision Detectors

Collision detectors run after all normalized previews are built for a scope. They operate on grouped normalized output, not ingredient-specific names.

#### Display Nutrition Collision

Group by:

```text
locale
result_type
lower(display_name)
lower(variant_name)
lower(brand_display)
```

Issue code:

```text
display_name_collision_nutrition_divergent
```

Flag every row in the group as `needs_review` when group size is greater than `1` and nutrition diverges materially:

- max calories - min calories > `max(50 kcal, 20% of group median calories)`
- or max protein - min protein > `max(5g, 20% of group median protein)`
- or max carbs - min carbs > `max(5g, 20% of group median carbs)`
- or max fat - min fat > `max(5g, 20% of group median fat)`

This catches cases where normalization hides meaningful preparation, variety, or product differences behind one identical display name.

#### Product Identity Collision

Group by:

```text
locale
lower(base_name)
lower(variant_name)
lower(brand_display)
```

Only apply to `resultType = product`.

Issue code:

```text
product_identity_collision
```

Flag the group when:

- group has more than one distinct barcode or external ID
- and the same nutrition divergence threshold above is exceeded

This catches product displays like `Product Name - Brand` that still represent materially different products.

#### Primary/Secondary Token Collision

Build two token maps from normalized docs:

```text
primary token -> rows where token is part of primaryEntityAliases
secondary token -> rows where token is part of secondaryEntityAliases
```

Issue code:

```text
primary_secondary_token_collision
```

For any token appearing in both maps:

- generate validation queries for that token and locale
- run normalized search with `limit = 100`
- pass only if the best primary-token result ranks before every secondary-token result for that token

Rows do not automatically fail because they contain a secondary collision token. The issue is attached only when the validation query proves the runtime ranking is wrong.

This is the generic detector for the `Cookies Butter` class of failures without hardcoding butter, rice, chicken, or any other ingredient.

#### Duplicate Display Flood

Group top-k search outputs by lowercased display name for acceptance queries and generated collision-token queries.

Issue code:

```text
duplicate_display_flood
```

A query fails if:

- any display name appears more than `2` times in top 10
- or unique display-name ratio in top 10 is below `0.8`

This is a runtime search-quality failure, not a per-row data failure.

## Full Backfill Behavior

The full backfill must:

1. Load only rows with `food_item_quality.is_search_eligible = true`.
2. Normalize rows deterministically using the existing normalization functions.
3. Compute per-row invariant and outlier issue codes.
4. Store all previews and issue codes in `food_normalization_review`.
5. Run collision detectors over the normalized preview set.
6. Update affected `food_normalization_review` rows with collision issue codes.
7. Insert only rows with `review_status = valid` into `food_normalized_search_documents`.
8. Delete existing runtime docs for rows that are no longer valid under the current normalization version.

The backfill should avoid unnecessary repeated work by using a deterministic normalization input signature:

```text
source
external_source
data_type
food_key
name
normalized_name
canonical_name
brand
food_category
market_country
normalization_version
```

Rows with identical signatures can reuse the same normalized preview before adding row-specific metadata such as `food_item_id`, barcode, external ID, and nutrition.

This is an optimization only. It must not change normalization output.

## Runtime Integration

Feature flags:

- `FOOD_NORMALIZED_SEARCH_ENABLED`
- `FOOD_NORMALIZED_SEARCH_SCOPE=sample|full`
- `FOOD_NORMALIZED_SEARCH_SAMPLE_SET=normalized_search_v1`

Runtime behavior:

- When normalized search is disabled, use legacy PostgreSQL search.
- When scope is `sample`, keep the existing sample-set join.
- When scope is `full`, query all `food_normalized_search_documents` rows without joining `food_normalization_sample_items`.
- Always join `food_item_quality` and require `is_search_eligible = true`.
- Never return rows that have `review_status != valid` for the current normalization version.

The old search path remains rollback until full normalized benchmarks pass.

Meal proposal resolution must use the same repository search path as manual ingredient search.

## Ranking Requirements

The normalized search query searches the whole eligible normalized corpus without hard generic/market filters.

Ranking signals:

- exact or prefix match on `base_name`
- exact or prefix match on `primary_entity_aliases`
- trigram and full-text score on `search_text`
- brand/barcode match boost when the query contains brand/barcode evidence
- broad generic-food boost when the query matches a primary generic entity
- normalization confidence
- primary entity representativeness
- category coherence for generic rows
- locale preference
- stable tie-breaker by ID

The ranking algorithm must remain generic. It must not use ingredient-specific boosts or hardcoded food names.

## Implementation Phases

### Phase 1: Documentation Update

- Replace the sample-only plan with this full-corpus plan.
- Keep the data cleanse findings report as a separate reference document.

### Phase 2: Schema

- Add `food_normalization_review`.
- Add schema/types for the new table.
- Add required indexes for status, issue codes, version, and display collision analysis.

### Phase 3: Backfill Script Refactor

- Extend the existing normalized search backfill script to support:
  - `--scope sample|full`
  - `--mode audit|apply`
  - `--batch-size`
  - `--resume-after`
- Ensure the script is environment-portable and production-runnable through `DATABASE_URL` and `DATABASE_SCHEMA`.
- Ensure the script has no dependency on local-only generated files.
- Keep current sample behavior intact.
- Add full-corpus row loading from `food_item_quality`.
- Add signature reuse for repeated normalization inputs.
- Add review DB writes and JSON report output.

### Phase 4: QA Gate Implementation

- Implement invariant checks.
- Implement metric computation.
- Compute sample percentile thresholds from approved sample docs.
- Implement per-row outlier issue codes.
- Implement SQL-based collision grouping.
- Implement primary/secondary token collision validation through the existing search repository.
- Ensure only `review_status = valid` rows are inserted into runtime docs.

### Phase 5: Runtime Full Scope

- Add `FOOD_NORMALIZED_SEARCH_SCOPE`.
- In sample scope, keep sample-set joins.
- In full scope, remove sample-set joins and query all normalized valid docs.
- Preserve old PostgreSQL search as rollback.

### Phase 6: Validation

- Run full audit mode first.
- Inspect JSON and DB review groups.
- Fix only generic normalization issues. Do not add ingredient-specific rules.
- Run full apply mode only after audit counts are acceptable.
- Run benchmarks and app-level verification after full apply.

## Test Plan

### Unit Tests

- Invariants:
  - empty display/base/search text -> `failed`
  - invalid result type -> `failed`
  - product with blank cleaned product name -> `failed`
- Outlier metrics:
  - very low confidence -> `needs_review`
  - excessive descriptor loss -> `needs_review`
  - brand-only product display -> `needs_review`
  - duplicated brand display -> `needs_review`
- Collisions:
  - same display name with divergent nutrition -> `needs_review`
  - same product name + brand with divergent nutrition and multiple barcodes -> `needs_review`
  - primary/secondary token ranking failure -> validation failure

### Integration Tests

- Audit full mode writes review rows and JSON but does not mutate runtime docs.
- Apply full mode writes runtime docs only for `review_status = valid`.
- Stale runtime docs are removed when a row becomes non-valid.
- Backfill commands use configured database/schema values and do not depend on local-only paths or hardcoded machine state.
- Re-running full apply with the same normalization version is idempotent.
- Resume mode continues after the requested `food_item_id` without reprocessing earlier completed batches.
- Sample scope still uses sample-set joins.
- Full scope does not use sample-set joins.
- Both scopes still require `food_item_quality.is_search_eligible = true`.

### Acceptance Benchmarks

Run both sample and full mode for:

- `rice`
- `arroz`
- `arroz goya`
- `chicken`
- `chicken breast`
- `butter`
- `egg`
- `milk`
- `apple`
- `yogur natural`
- representative barcode query
- generated primary/secondary collision-token queries

Track:

- p50, p90, p99 latency
- top-k rows
- source/result-type mix
- whether quarantined/suspicious/duplicate rows appear
- whether review rows appear
- duplicate display-name flooding
- primary-token result rank vs secondary-token result rank

Full mode passes only if:

- no non-eligible rows appear
- no non-valid review rows appear
- no duplicate display flood appears in benchmark top 10
- broad generic queries still rank primary-entity matches above secondary-token matches
- latency remains acceptable for local PostgreSQL search

## Short Appendix: Why Not Review Every Row Manually?

The objective is simple food-name normalization, not a broad entity-resolution project.

The only reason to mention large-scale record linkage/blocking research is to justify avoiding manual review of every row. With roughly one million valid rows, manual row-by-row review is not practical. The implementation should instead normalize every row automatically, then review grouped QA outputs: hard failures, metric outliers, collisions, and benchmark failures.

Useful background:

- Dedupe blocking docs: https://docs.dedupe.io/en/latest/how-it-works/Making-smart-comparisons.html
- Splink blocking docs: https://moj-analytical-services.github.io/splink3_legacy_docs/topic_guides/blocking/blocking_rules.html

These references do not define the product behavior. The concrete QA gates in this document define the product behavior.

## Non-Goals

- No Typesense implementation.
- No physical deletion of imported rows.
- No ingredient-specific hardcoding.
- No exact food-name overrides.
- No stopword lists for food understanding.
- No regex-based intent parsing.
- No production rollout until full audit, full apply, benchmarks, and app verification pass.
