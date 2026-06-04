# Food Data Quality Cleanse Findings

Generated from the local `cal_tracker_dev` database on 2026-05-29.

Source audit artifact:

```text
data/food-quality/audit-2026-05-29T14-51-43.629Z.json
```

Command used:

```bash
cd apps/backend
bun --env-file=.env run food-quality audit
```

## Current Operational Status

The cleanse is now implemented by `apps/backend/scripts/food-data-quality.ts` and exposed through:

```bash
cd apps/backend
bun --env-file=.env run food-quality audit
bun --env-file=.env run food-quality apply
```

`audit` computes the same classification and writes a JSON report under ignored `data/food-quality/`. `apply` also upserts the derived classification into `food_item_quality`.

For dev/pro/VPS operations, pass script guards on mutating runs:

```bash
bun --env-file=.env run food-quality apply --require-db-name cal_tracker --require-schema cal_tracker_dev
```

The quality layer does not delete or rewrite source `food_items`. It marks canonical search eligibility so downstream normalization and runtime search can require `food_item_quality.is_search_eligible = true`.

The audit uses `food-quality-v1`. It does not delete imported source rows. It classifies each row for search eligibility so normalization and search can ignore rows that are duplicated, incomplete, suspicious, or nutritionally invalid.

## Headline Result

The local food corpus has `1,299,484` rows.

| Status | Rows | Share | Meaning |
| --- | ---: | ---: | --- |
| `valid` | 1,011,978 | 77.87% | Search-eligible canonical rows. |
| `suspicious` | 128,481 | 9.89% | Not obviously impossible, but weak metadata or nutrition mismatch requires review/exclusion from the first normalized sample. |
| `duplicate` | 104,656 | 8.05% | Non-canonical duplicates that should not flood search results. |
| `quarantined` | 54,369 | 4.18% | Rows with invalid or impossible nutrition/name data; should not appear in search or meal proposal resolution. |

Total excluded from default search after the cleanse: `287,506` rows, or `22.13%` of the corpus.

## Source Coverage

| Source | Rows | Eligible | Excluded | Excluded % |
| --- | ---: | ---: | ---: | ---: |
| Open Food Facts | 841,608 | 622,557 | 219,051 | 26.03% |
| USDA Branded | 449,928 | 381,550 | 68,378 | 15.20% |
| USDA SR Legacy | 7,793 | 7,725 | 68 | 0.87% |
| USDA Foundation | 153 | 146 | 7 | 4.58% |
| Open Food Facts rows missing `data_type` | 2 | 0 | 2 | 100.00% |

The important pattern is that USDA generic data is mostly usable, while product sources need aggressive quality filtering. Open Food Facts has the largest absolute and relative exclusion rate. USDA branded is better, but still has meaningful duplicate and invalid nutrition rows.

## Duplicate Findings

The cleanse marks `104,656` rows as duplicates. These are not deleted; they point to a canonical row through the quality metadata.

| Duplicate kind | Source | Rows |
| --- | --- | ---: |
| Product identity duplicate | Open Food Facts | 55,623 |
| Product identity duplicate | USDA Branded | 27,552 |
| Barcode duplicate | USDA Branded | 16,677 |
| Barcode duplicate | Open Food Facts | 4,797 |
| USDA generic identity duplicate | USDA Foundation | 7 |

Duplicate flags:

| Flag | Rows |
| --- | ---: |
| `duplicate_product` | 83,182 |
| `duplicate_barcode` | 21,474 |

The biggest duplicate clusters are common commodity products with weak or missing brand metadata. The top group in the audit is `extra virgin olive oil` with `225` duplicate rows under the same product-identity key. Other large groups include `tomato ketchup`, `honey`, `olive oil`, `whole milk`, `diced tomatoes`, `vegetable oil`, `orange juice`, and `chicken breast tenderloins`.

Engineering implication: full-corpus search must query only canonical, quality-eligible rows by default. Otherwise common products will flood top-k results with repeated near-identical rows.

## Invalid Nutrition Findings

The cleanse quarantines `54,369` rows. These are the rows that should be treated as invalid for default search and meal proposal resolution.

Quarantine flag counts are not mutually exclusive; a row can have more than one flag.

| Invalid flag | Rows | Interpretation |
| --- | ---: | --- |
| `zero_nutrition` | 42,512 | Calories, protein, carbs, and fat are all zero for imported rows. |
| `zero_calories_with_macros` | 8,209 | Calories are zero but at least one macro is positive. |
| `impossible_macros` | 3,336 | One macro exceeds plausible per-100g bounds, or macro sum exceeds plausible total mass. |
| `impossible_calories` | 1,300 | Calories exceed `1000 kcal` per `100g`. |

Invalid nutrition is concentrated in product imports:

| Flag | Open Food Facts | USDA Branded | USDA SR Legacy |
| --- | ---: | ---: | ---: |
| `zero_nutrition` | 25,293 | 17,193 | 26 |
| `zero_calories_with_macros` | 4,861 | 3,337 | 11 |
| `impossible_macros` | 3,078 | 258 | 0 |
| `impossible_calories` | 1,233 | 67 | 0 |

The rice example is real. The audit found `75` Open Food Facts rice/arroz rows with `0 kcal`; all `75` are quarantined. Of those, `23` have zero calories but positive macros, and `52` have full zero nutrition.

Engineering implication: normalization alone is not enough. If invalid product rows are normalized into nice display names, they will still be wrong search results. The quality layer must run before full-corpus normalized search document generation.

## Suspicious Metadata Findings

Suspicious rows are excluded from the first normalized sample but are not automatically impossible. These flags are review/ranking signals.

Flag counts are not mutually exclusive.

| Suspicious flag | Rows | Interpretation |
| --- | ---: | --- |
| `low_metadata` | 128,532 | Product row has weak source metadata, no brand, no useful category, and no ingredients. |
| `missing_brand_for_product` | 31,410 | Product source has no brand and collides with many same-name products. |
| `macro_energy_mismatch` | 15,341 | Macro-derived calories differ from stored calories by more than `max(75 kcal, 50%)`. |

Open Food Facts contains `264,274` rows with no brand. Among those, `120,483` are suspicious and `163,302` are excluded from default search by the quality layer.

Engineering implication: Open Food Facts product naming cannot be trusted as a clean search corpus without brand and metadata cleanup. For marketed products, `Product Name - Brand` is still the right display direction, but only when the brand is actually present and reliable.

## What The Cleanse Says About The Database

The database is usable, but it is not clean enough to normalize and search as a single raw corpus.

The strongest part of the corpus is USDA generic data. SR Legacy and Foundation have very low exclusion rates and should remain the backbone for generic ingredient search.

The weakest part is imported product data, especially Open Food Facts rows with missing brand, missing metadata, duplicate commodity names, or impossible nutrition. This explains failures where product rows or low-quality variants can outrank better generic ingredients if search is run directly over raw names.

The cleanse also confirms that duplicate removal is not optional. More than `100k` rows are non-canonical duplicates. Without canonicalization, top-k search quality will degrade even if the text ranking algorithm is good.

## Required Rule Before Full Normalization

Before normalizing the full database, normalized search document generation should include only:

- `quality_status = 'valid'`
- `is_search_eligible = true`
- canonical rows only

Rows marked `duplicate`, `suspicious`, or `quarantined` should not be included in default normalized search documents. Suspicious rows can be revisited later with a separate review flow or lower-confidence/ranking path, but they should not be mixed into the first full normalized rollout.
