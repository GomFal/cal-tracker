# Food Search Benchmark And Acceptance Runbook

Status: implemented reusable benchmark and validation reference.

This document describes how to reuse the PostgreSQL food search benchmarks after changes to food data quality, normalized search, repository ranking, indexes, or meal proposal ingredient resolution.

Runtime fixes must remain generic. Do not add exact ingredient/query fixes, hardcoded translations, stopword lists, regex food understanding, or deterministic ingredient inference.

## Reusable Scripts

Run from `apps/backend`.

| Script | Purpose |
| --- | --- |
| `bun --env-file=.env run benchmark:food-search` | Measures repository food search quality and latency for legacy and normalized modes. |
| `bun --env-file=.env run validate:food-search-primary` | Exhaustively validates primary-token ranking behavior over normalized docs. |
| `bun --env-file=.env run benchmark:agent-foods` | Measures agent/tool food flows with prompt fixtures. |

One-off benchmark harnesses that are not part of the app should live under ignored `tools/benchmarks/`. They should not be added to `apps/backend/scripts` unless they are intended to be maintained, tested, and shipped in the backend image.

Reports are written under ignored paths:

```text
data/food-search-benchmarks/
data/food-search-benchmarks/secondary-token-conflicts/
logs/agent-benchmarks/
```

## Food Search Benchmark

Default command:

```bash
bun --env-file=.env run benchmark:food-search
```

Default behavior:

- `--mode compare`
- `--scope sample`
- `--top-k 10`
- `--iterations 5`
- `--warmup 1`
- `--repeat 1`

Supported flags:

| Flag | Meaning |
| --- | --- |
| `--mode legacy|normalized|compare` | Run legacy search, normalized search, or both. |
| `--scope sample|full` | Use sample normalized docs or full normalized docs. |
| `--case <id>` | Run one benchmark case. |
| `--top-k <n>` | Number of returned rows to inspect. |
| `--iterations <n>` | Measured iterations per case. |
| `--warmup <n>` | Warmup iterations excluded from latency summaries. |
| `--repeat <n>` | Repeat the selected run set. |
| `--sample-set <name>` | Sample set for normalized sample scope. |
| `--output-dir <path>` | Override report output directory. |
| `--baseline-db-url <url>` | Compare against a separate baseline database URL. |
| `--candidate-db-url <url>` | Compare against a separate candidate database URL. |
| `--baseline-label <label>` | Label for baseline database reports. |
| `--candidate-label <label>` | Label for candidate database reports. |
| `--profile-sql` | Write `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` SQL profiles for selected normalized queries. |
| `--profile-top-n <n>` | Number of slow/important normalized queries to profile. |
| `--report-only` | Write reports without failing the process on failed acceptance checks. |

Useful examples:

```bash
# Compare legacy vs normalized sample search locally.
bun --env-file=.env run benchmark:food-search -- --mode compare --scope sample

# Validate full normalized search after full backfill.
bun --env-file=.env run benchmark:food-search -- --mode normalized --scope full --profile-sql

# Focus one known brand-intent case.
bun --env-file=.env run benchmark:food-search -- --mode normalized --scope full --case arroz-goya

# Compare two database URLs, for example pro-like baseline vs normalized dev clone.
bun --env-file=.env run benchmark:food-search -- \
  --scope full \
  --baseline-db-url "$BASELINE_DATABASE_URL" \
  --candidate-db-url "$CANDIDATE_DATABASE_URL" \
  --baseline-label pro-legacy \
  --candidate-label dev-normalized \
  --profile-sql
```

The benchmark records:

- query, locale, mode, scope, top-k, iterations, and target database label;
- latency min/p50/p90/p99/max/average;
- top result and full top-k rows;
- raw and normalized display fields, source, external source, data type, brand, and barcode;
- result type mix: `generic_food`, `product`, `custom_food`;
- quality status and quality flags;
- duplicate display-name flooding;
- quarantined/ineligible rows;
- normalized sample membership violations when scope is `sample`;
- SQL profile files when `--profile-sql` is enabled.

Acceptance gates include:

- no quarantined or ineligible rows in normalized results;
- no sample membership violations in sample scope;
- no duplicate display-name flooding;
- generic ingredient cases return generic rows near the top when generic coverage exists;
- brand-intent cases can rank products above generic foods;
- barcode cases return exact barcode matches;
- known invalid zero-calorie rice rows do not appear;
- normalized search must be materially faster or quality-improved against legacy for the measured set.

## Primary-Position Validation

Run this after any ranking, normalization, or search-index change:

```bash
bun --env-file=.env run validate:food-search-primary
```

Default behavior:

- `--scope sample`
- `--sample-set normalized_search_v1`
- `--top-k 10`
- no mutation of review rows

Supported flags:

| Flag | Meaning |
| --- | --- |
| `--scope sample|full` | Validate sample or full normalized docs. |
| `--sample-set <name>` | Sample set for sample scope. |
| `--top-k <n>` | Number of returned rows to inspect. |
| `--output-dir <path>` | Override report output directory. |
| `--query <text>` | Validate one generated or manual query. |
| `--max-queries <n>` | Limit generated validation queries. |
| `--include-all-products` | Include product-heavy conflicts that are normally reduced for signal. |
| `--mark-review-issues` | Mutate `food_normalization_review` with discovered review issues. |
| `--report-only` | Write reports without failing the process on failed validation. |

`--mark-review-issues` is intentionally mutating. Do not use it during normal benchmarking unless the objective is to update review rows.

The validator generates general query cases from normalized documents. It does not encode expected ingredient names or exact rows. It checks that rows whose normalized primary identity starts with the query token are not consistently outranked by rows where that token is secondary, embedded later in the name, or product-line noise.

Useful examples:

```bash
# Exhaustive sample validation.
bun --env-file=.env run validate:food-search-primary

# Full-scope validation after full apply.
bun --env-file=.env run validate:food-search-primary -- --scope full

# Inspect one query without failing the process.
bun --env-file=.env run validate:food-search-primary -- --scope full --query "butter" --report-only
```

## Agent Food Benchmark

`benchmark:agent-foods` exercises agent/tool flows rather than only repository search. It is useful when a change might affect the route from user prompt to tool call, food resolution, or result kind.

Default output is under `logs/agent-benchmarks/`.

Use it after changes to:

- food-related tool schemas;
- agent prompt/tool orchestration;
- meal proposal ingredient resolution;
- correction flows that call food search;
- nutrition search actions exposed through the agent.

## Validation Loop

Use this loop for future normalized search changes:

1. Run `validate:food-search-primary`.
2. Classify failures by generic behavior class.
3. Fix data quality, normalization, indexing, or ranking generically.
4. Run `benchmark:food-search -- --mode compare --scope full --profile-sql`.
5. Inspect failed gates before optimizing latency.
6. Use SQL profile JSON to identify query/index bottlenecks.
7. Rerun validation and benchmark after every search change.

Do not accept a speed improvement that reintroduces invalid rows, duplicate flooding, or query-specific overfitting.
