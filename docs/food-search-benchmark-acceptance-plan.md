# Food Search Benchmark and Acceptance Plan

## Summary

Add a reusable backend benchmark script for ingredient search that compares normalized sample search against the legacy flag-off PostgreSQL search path in the same branch and database. The script records latency, top-k ranking quality, source/result-type mix, data-quality violations, duplicate display-name flooding, and explicit acceptance checks across a broad English/Spanish ingredient set.

Benchmark cases may be explicit fixtures. Runtime search logic must remain generic: no query-specific, ingredient-specific, or language-shortcut ranking rules are allowed in production code.

## Key Changes

- Add `apps/backend/scripts/benchmark-food-search.ts`.
- Add package script `benchmark:food-search`.
- Add `apps/backend/scripts/validate-food-search-primary-position.ts`.
- Add package script `validate:food-search-primary`.
- Compare:
  - `legacy`: `PostgresRepository(..., { normalizedSearchEnabled: false })`
  - `normalized`: `PostgresRepository(..., { normalizedSearchEnabled: true, normalizedSearchSampleSet })`
- Keep `FoodSearchCandidate` unchanged. After repository search returns IDs, query DB metadata for quality status, normalized docs, sample membership, and raw `food_items` fields.
- Write ignored reports under `data/food-search-benchmarks/`:
  - JSON with full per-query results.
  - Markdown with summary tables and failed checks.
- Write primary-position validation reports under `data/food-search-benchmarks/secondary-token-conflicts/`:
  - generated validation queries
  - extracted conflict candidates
  - full top-k result evidence
  - markdown summary with failed query and candidate-review tables

## Benchmark Behavior

- Default CLI:
  - `--mode compare`
  - `--top-k 10`
  - `--warmup 1`
  - `--iterations 5`
- Supported CLI:
  - `--mode legacy|normalized|compare`
  - `--case <id>`
  - `--top-k <n>`
  - `--iterations <n>`
  - `--warmup <n>`
  - `--repeat <n>`
  - `--report-only`
  - `--output-dir <path>`
- Use a fixed benchmark user namespace with no food preferences. Vary the user ID per measured iteration so repository cache does not hide DB search cost.
- Cases include the plan queries and broader generic coverage:
  - `rice`, `arroz`, `arroz goya`, `chicken breast`, `egg`, `milk`, `apple`, `yogur natural`
  - oats, lentils/lentejas, beans/frijoles, potato/patata, tomato/tomate, banana/platano, olive oil/aceite oliva, bread/pan, salmon, tuna
  - representative barcode case discovered dynamically from eligible sampled product docs

## Exhaustive Primary-Position Validation

Run `validate:food-search-primary` after every search-ranking change. This script iterates every eligible row in `normalized_search_v1`, extracts normalized tokens from the normalized base/variant names, and generates validation queries from:

- generic primary aliases
- product aliases that collide with conflict tokens
- tokens that appear as non-primary tokens in one row but as leading primary tokens in another row

The validation gate is intentionally general. It must not contain ingredient-specific expected rows, token stoplists, exact query exceptions, or language shortcuts. It accepts:

- normal primary aliases and names at the first position
- generic USDA category-prefix rows where the first token is a simple alphabetic category-like entity and the searched single token is the second normalized base token, such as source shapes like `Fish Tuna` or `Cereals Oats`

It rejects brand-shaped or product-line category-prefix boosts, such as first entities containing punctuation or symbols. This keeps restaurant/product-line USDA rows from outranking actual first-position product names.

## Recorded Metrics

- query, locale, mode, top-k, iterations
- latency min/p50/p90/p99/max/average
- top result and top-k rows
- returned display name, raw name, brand, barcode, source, external source, data type
- result type: `generic_food`, `product`, or `custom_food`
- quality status and flags
- source/result-type mix
- duplicate display-name maximum and unique-display ratio
- quarantined/ineligible counts
- sample membership violations in normalized mode
- optional MRR/nDCG when relevance grades are defined

## Acceptance Gates

- Normalized mode must return no quarantined or ineligible rows.
- Normalized mode must return no rows outside `normalized_search_v1`.
- Normalized top 10 must not be flooded by duplicate display names:
  - max duplicate display-name count <= 2
  - unique display-name ratio >= 0.8
- Broad generic ingredient cases with sampled generic coverage must have a `generic_food` row in top 3.
- Broad generic ingredient cases with enough sampled generic base-name coverage must have at least as many generic rows as product rows in top 10. Generic coverage is counted from normalized `base_name`, not incidental matches in ingredients/category/search text. If fewer than half of top-k sampled generic base-name matches exist, all available matches must appear before the product-domination gate is considered satisfied.
- Brand-intent cases must allow product rows to beat generic rows:
  - `arroz goya` must return `Arroz - Goya` at rank 1.
- Barcode case must return the exact barcode match at rank 1.
- The known bad zero-calorie OpenFoodFacts rice row must never appear.
- Normalized p50 and p90 latency must be at least 25% faster than legacy overall.

## Continuous Validation Loop

1. Run `bun --env-file=.env run validate:food-search-primary`.
2. If it fails, inspect the generated report and classify failures by generic behavior class.
3. Apply only generic runtime or validator fixes. Do not add exact ingredient/query fixes, stopword lists, hardcoded normalization, or exact token exceptions.
4. Run `bun --env-file=.env run benchmark:food-search -- --mode compare`.
5. Fix failed quality gates before speed.
6. Optimize slow normalized queries through generic search changes only.
7. Rerun both scripts after every change.
8. Stop when gates pass or the remaining optimization would require a product/data-quality decision.

Forbidden runtime fixes:

- `if query === "rice"` or equivalent query-specific code.
- ingredient-specific repository boosts.
- regex-based food intent parsing.
- deterministic ingredient inference in meal proposal/search flows.

## Verification

- Add unit tests for benchmark helper functions:
  - percentile calculation
  - duplicate display-name flood detection
  - source/result-type aggregation
  - acceptance gate evaluation
  - MRR/nDCG calculation with synthetic graded relevance
- Run:
  - `bun run typecheck`
  - `bun run test`
  - `bun --env-file=.env run validate:food-search-primary`
  - `bun --env-file=.env run benchmark:food-search -- --mode compare`
  - `bun --env-file=.env run benchmark:food-search -- --mode normalized --case arroz-goya`
  - `git diff --check`
