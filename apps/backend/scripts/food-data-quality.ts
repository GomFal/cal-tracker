import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { Sql } from "postgres";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { assertRequiredDatabaseName, assertRequiredSchema, consumeRequireDbNameArg } from "../src/db/scriptGuards.js";
import { FOOD_QUALITY_VERSION } from "../src/foodData/constants.js";

type Command = "audit" | "apply";

type Report = {
  command: Command;
  qualityVersion: string;
  generatedAt: string;
  sourceTotals: unknown[];
  statusCounts: unknown[];
  flagCounts: unknown[];
  topDuplicateGroups: unknown[];
  quarantinedSamples: unknown[];
  badRiceRows: unknown[];
  eligibility: unknown[];
};

const guardArgs = consumeRequireDbNameArg(process.argv.slice(2));
const command = parseCommand(guardArgs.argv[0]);
const config = loadConfig();
const client = createDbClient(config.DATABASE_URL, { max: 1 });

try {
  await assertRequiredDatabaseName(client.sql, guardArgs.requiredDbName);
  await assertRequiredSchema(client.sql, guardArgs.requiredSchema);
  await client.sql`SET statement_timeout = '30min'`;
  await client.sql`SET lock_timeout = '30s'`;
  await createQualityWorkTable(client.sql);
  await markDuplicateRows(client.sql);
  const report = await buildReport(client.sql, command);
  if (command === "apply") {
    await applyQualityRows(client.sql);
  }
  const path = await writeReport(report);
  printReportSummary(report, path);
} finally {
  await client.close();
}

function parseCommand(value: string | undefined): Command {
  if (value === "apply" || value === "audit") return value;
  if (!value) return "audit";
  throw new Error(`Unsupported command "${value}". Use "audit" or "apply".`);
}

async function createQualityWorkTable(sql: Sql): Promise<void> {
  await sql.unsafe("DROP TABLE IF EXISTS tmp_food_item_quality_work");
  await sql.unsafe(`
    CREATE TEMP TABLE tmp_food_item_quality_work AS
    WITH base AS (
      SELECT
        f.id AS food_item_id,
        f.user_id,
        f.name,
        lower(regexp_replace(btrim(coalesce(nullif(f.normalized_name, ''), nullif(f.canonical_name, ''), f.name)), '[[:space:]]+', ' ', 'g')) AS clean_name,
        nullif(btrim(f.brand), '') AS brand_clean,
        lower(nullif(btrim(f.market_country), '')) AS country_clean,
        f.source,
        f.external_source,
        f.data_type,
        f.food_key,
        f.barcode,
        f.food_category,
        f.ingredients,
        f.publication_date,
        f.fetched_at,
        f.created_at,
        f.serving_grams::numeric AS serving_grams,
        f.calories::numeric AS calories,
        f.protein_grams::numeric AS protein_grams,
        f.carbs_grams::numeric AS carbs_grams,
        f.fat_grams::numeric AS fat_grams,
        f.calories::numeric AS calories_per_100g,
        f.protein_grams::numeric AS protein_per_100g,
        f.carbs_grams::numeric AS carbs_per_100g,
        f.fat_grams::numeric AS fat_per_100g,
        (f.protein_grams::numeric * 4 + f.carbs_grams::numeric * 4 + f.fat_grams::numeric * 9) AS macro_calories,
        nutrients.nutrient_count,
        (
          CASE WHEN btrim(coalesce(f.name, '')) <> '' THEN 1 ELSE 0 END +
          CASE WHEN nullif(btrim(f.brand), '') IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN nullif(btrim(f.barcode), '') IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN nullif(btrim(f.source_url), '') IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN nullif(btrim(f.license), '') IS NOT NULL THEN 1 ELSE 0 END
        ) AS identity_score,
        coalesce(f.fetched_at, f.publication_date::timestamptz, f.created_at) AS source_date,
        (
          f.user_id IS NULL
          AND (
            f.external_source = 'openfoodfacts'
            OR f.source = 'openfoodfacts'
            OR f.data_type = 'Branded'
            OR f.source = 'usda_branded'
            OR nullif(btrim(f.barcode), '') IS NOT NULL
            OR nullif(btrim(f.brand), '') IS NOT NULL
          )
        ) AS is_product,
        (
          f.external_source = 'usda_fdc'
          AND f.data_type IN ('SR Legacy', 'Foundation')
        ) AS is_usda_generic
      FROM food_items f
      LEFT JOIN LATERAL (
        SELECT count(*)::int AS nutrient_count
        FROM jsonb_object_keys(
          CASE
            WHEN jsonb_typeof(f.nutrients_json) = 'object' THEN f.nutrients_json
            ELSE '{}'::jsonb
          END
        )
      ) nutrients ON true
    ),
    no_brand_name_counts AS (
      SELECT clean_name, count(*)::int AS same_name_count
      FROM base
      WHERE is_product
        AND brand_clean IS NULL
      GROUP BY clean_name
    ),
    flagged AS (
      SELECT
        b.*,
        array_remove(ARRAY[
          CASE WHEN btrim(coalesce(b.name, '')) = '' THEN 'missing_name' END,
          CASE WHEN b.calories < 0 OR b.protein_grams < 0 OR b.carbs_grams < 0 OR b.fat_grams < 0 THEN 'negative_nutrition' END,
          CASE WHEN b.user_id IS NULL AND b.calories = 0 AND b.protein_grams = 0 AND b.carbs_grams = 0 AND b.fat_grams = 0 THEN 'zero_nutrition' END,
          CASE WHEN b.user_id IS NULL AND b.calories = 0 AND (b.protein_grams > 0 OR b.carbs_grams > 0 OR b.fat_grams > 0) THEN 'zero_calories_with_macros' END,
          CASE WHEN b.calories_per_100g > 1000 THEN 'impossible_calories' END,
          CASE
            WHEN b.protein_per_100g > 120
              OR b.carbs_per_100g > 120
              OR b.fat_per_100g > 120
              OR (b.protein_per_100g + b.carbs_per_100g + b.fat_per_100g) > 130
            THEN 'impossible_macros'
          END
        ]::text[], NULL) AS quarantine_flags,
        array_remove(ARRAY[
          CASE
            WHEN b.calories > 0
              AND b.macro_calories > 0
              AND abs(b.macro_calories - b.calories) > greatest(75::numeric, b.calories * 0.5)
            THEN 'macro_energy_mismatch'
          END,
          CASE
            WHEN b.is_product
              AND b.brand_clean IS NULL
              AND coalesce(n.same_name_count, 0) > 20
            THEN 'missing_brand_for_product'
          END,
          CASE
            WHEN b.is_product
              AND b.brand_clean IS NULL
              AND nullif(btrim(coalesce(b.food_category, '')), '') IS NULL
              AND nullif(btrim(coalesce(b.ingredients, '')), '') IS NULL
            THEN 'low_metadata'
          END
        ]::text[], NULL) AS suspicious_flags,
        coalesce(n.same_name_count, 0) AS same_name_no_brand_product_count
      FROM base b
      LEFT JOIN no_brand_name_counts n ON n.clean_name = b.clean_name
    )
    SELECT
      food_item_id,
      CASE
        WHEN cardinality(quarantine_flags) > 0 THEN 'quarantined'
        WHEN cardinality(suspicious_flags) > 0 THEN 'suspicious'
        ELSE 'valid'
      END::text AS quality_status,
      (cardinality(quarantine_flags) = 0 AND cardinality(suspicious_flags) = 0) AS is_search_eligible,
      NULL::uuid AS canonical_food_item_id,
      round(greatest(0::numeric, least(1::numeric, 1::numeric - cardinality(quarantine_flags)::numeric * 0.4 - cardinality(suspicious_flags)::numeric * 0.15)), 4) AS quality_score,
      (quarantine_flags || suspicious_flags)::text[] AS quality_flags,
      '${FOOD_QUALITY_VERSION}'::text AS quality_version,
      jsonb_build_object(
        'macroCalories', round(macro_calories, 2),
        'macroDeltaKcal', round(abs(macro_calories - calories), 2),
        'caloriesPer100g', round(calories_per_100g, 2),
        'proteinPer100g', round(protein_per_100g, 2),
        'carbsPer100g', round(carbs_per_100g, 2),
        'fatPer100g', round(fat_per_100g, 2),
        'nutrientCount', nutrient_count,
        'identityScore', identity_score,
        'sameNameNoBrandProductCount', same_name_no_brand_product_count
      ) AS metadata,
      nutrient_count,
      identity_score,
      source_date,
      is_product,
      is_usda_generic,
      clean_name,
      brand_clean,
      country_clean,
      calories,
      protein_grams,
      carbs_grams,
      fat_grams
    FROM flagged
  `);
}

async function markDuplicateRows(sql: Sql): Promise<void> {
  await markDuplicateGroup(sql, "duplicate_barcode", "barcode", `
    SELECT
      w.food_item_id,
      lower(btrim(f.barcode)) AS duplicate_key,
      w.quality_status,
      w.nutrient_count,
      w.identity_score,
      w.source_date
    FROM tmp_food_item_quality_work w
    JOIN food_items f ON f.id = w.food_item_id
    WHERE w.is_product
      AND w.quality_status <> 'quarantined'
      AND nullif(btrim(f.barcode), '') IS NOT NULL
  `);

  await markDuplicateGroup(sql, "duplicate_product", "product_identity", `
    SELECT
      w.food_item_id,
      concat_ws('|',
        w.clean_name,
        coalesce(w.brand_clean, ''),
        coalesce(w.country_clean, ''),
        (round(w.calories / 5) * 5)::text,
        round(w.protein_grams * 2)::text,
        round(w.carbs_grams * 2)::text,
        round(w.fat_grams * 2)::text
      ) AS duplicate_key,
      w.quality_status,
      w.nutrient_count,
      w.identity_score,
      w.source_date
    FROM tmp_food_item_quality_work w
    WHERE w.is_product
      AND w.quality_status <> 'quarantined'
      AND w.canonical_food_item_id IS NULL
      AND w.clean_name <> ''
  `);

  await markDuplicateGroup(sql, "duplicate_product", "usda_generic_identity", `
    SELECT
      w.food_item_id,
      concat_ws('|',
        w.clean_name,
        w.calories::text,
        round(w.protein_grams * 10)::text,
        round(w.carbs_grams * 10)::text,
        round(w.fat_grams * 10)::text
      ) AS duplicate_key,
      w.quality_status,
      w.nutrient_count,
      w.identity_score,
      w.source_date
    FROM tmp_food_item_quality_work w
    WHERE w.is_usda_generic
      AND w.quality_status <> 'quarantined'
      AND w.canonical_food_item_id IS NULL
      AND w.clean_name <> ''
  `);
}

async function markDuplicateGroup(sql: Sql, flag: string, duplicateKind: string, sourceQuery: string): Promise<void> {
  await sql.unsafe(`
    WITH duplicate_candidates AS (
      ${sourceQuery}
    ),
    ranked AS (
      SELECT
        food_item_id,
        duplicate_key,
        first_value(food_item_id) OVER (
          PARTITION BY duplicate_key
          ORDER BY
            CASE quality_status WHEN 'valid' THEN 0 WHEN 'suspicious' THEN 1 ELSE 2 END,
            nutrient_count DESC,
            identity_score DESC,
            source_date DESC NULLS LAST,
            food_item_id
        ) AS canonical_id,
        count(*) OVER (PARTITION BY duplicate_key) AS group_size
      FROM duplicate_candidates
    )
    UPDATE tmp_food_item_quality_work w
    SET
      quality_status = 'duplicate',
      is_search_eligible = false,
      canonical_food_item_id = ranked.canonical_id,
      quality_score = 0,
      quality_flags = ARRAY(
        SELECT DISTINCT value
        FROM unnest(w.quality_flags || ARRAY['${flag}'::text]) AS value
        ORDER BY value
      ),
      metadata = w.metadata || jsonb_build_object(
        'duplicateKind', '${duplicateKind}',
        'duplicateKey', ranked.duplicate_key,
        'duplicateGroupSize', ranked.group_size,
        'canonicalFoodItemId', ranked.canonical_id
      )
    FROM ranked
    WHERE w.food_item_id = ranked.food_item_id
      AND ranked.group_size > 1
      AND ranked.food_item_id <> ranked.canonical_id
  `);
}

async function applyQualityRows(sql: Sql): Promise<void> {
  await sql.unsafe(`
    INSERT INTO food_item_quality (
      food_item_id,
      quality_status,
      is_search_eligible,
      canonical_food_item_id,
      quality_score,
      quality_flags,
      quality_version,
      metadata,
      created_at,
      updated_at
    )
    SELECT
      food_item_id,
      quality_status,
      is_search_eligible,
      canonical_food_item_id,
      quality_score,
      quality_flags,
      quality_version,
      metadata,
      now(),
      now()
    FROM tmp_food_item_quality_work
    ON CONFLICT (food_item_id) DO UPDATE SET
      quality_status = EXCLUDED.quality_status,
      is_search_eligible = EXCLUDED.is_search_eligible,
      canonical_food_item_id = EXCLUDED.canonical_food_item_id,
      quality_score = EXCLUDED.quality_score,
      quality_flags = EXCLUDED.quality_flags,
      quality_version = EXCLUDED.quality_version,
      metadata = EXCLUDED.metadata,
      updated_at = now()
  `);
}

async function buildReport(sql: Sql, command: Command): Promise<Report> {
  const [
    sourceTotals,
    statusCounts,
    flagCounts,
    topDuplicateGroups,
    quarantinedSamples,
    badRiceRows,
    eligibility,
  ] = await Promise.all([
    sql.unsafe(`
      SELECT
        coalesce(source, '') AS source,
        coalesce(external_source, '') AS external_source,
        coalesce(data_type, '') AS data_type,
        count(*)::int AS rows
      FROM food_items
      GROUP BY source, external_source, data_type
      ORDER BY rows DESC
    `),
    sql.unsafe(`
      SELECT quality_status, count(*)::int AS rows
      FROM tmp_food_item_quality_work
      GROUP BY quality_status
      ORDER BY rows DESC
    `),
    sql.unsafe(`
      SELECT flag, count(*)::int AS rows
      FROM tmp_food_item_quality_work, unnest(quality_flags) AS flag
      GROUP BY flag
      ORDER BY rows DESC, flag
    `),
    sql.unsafe(`
      SELECT
        metadata->>'duplicateKind' AS duplicate_kind,
        metadata->>'duplicateKey' AS duplicate_key,
        count(*)::int AS duplicate_rows,
        min(metadata->>'canonicalFoodItemId') AS canonical_food_item_id
      FROM tmp_food_item_quality_work
      WHERE quality_status = 'duplicate'
      GROUP BY duplicate_kind, duplicate_key
      ORDER BY duplicate_rows DESC, duplicate_key
      LIMIT 25
    `),
    sql.unsafe(`
      SELECT flag, jsonb_agg(sample ORDER BY sample->>'name') AS samples
      FROM (
        SELECT
          flag,
          jsonb_build_object(
            'id', f.id,
            'name', f.name,
            'source', f.source,
            'externalSource', f.external_source,
            'dataType', f.data_type,
            'calories', f.calories,
            'proteinGrams', f.protein_grams,
            'carbsGrams', f.carbs_grams,
            'fatGrams', f.fat_grams
          ) AS sample,
          row_number() OVER (PARTITION BY flag ORDER BY f.name, f.id) AS rn
        FROM tmp_food_item_quality_work w
        JOIN food_items f ON f.id = w.food_item_id
        CROSS JOIN LATERAL unnest(w.quality_flags) AS flag
        WHERE w.quality_status = 'quarantined'
      ) ranked
      WHERE rn <= 5
      GROUP BY flag
      ORDER BY flag
    `),
    sql.unsafe(`
      SELECT
        f.id,
        f.name,
        f.brand,
        f.barcode,
        f.source,
        f.external_source,
        f.food_key,
        f.calories,
        f.protein_grams,
        f.carbs_grams,
        f.fat_grams,
        w.quality_status,
        w.quality_flags
      FROM tmp_food_item_quality_work w
      JOIN food_items f ON f.id = w.food_item_id
      WHERE (f.external_source = 'openfoodfacts' OR f.source = 'openfoodfacts')
        AND f.calories = 0
        AND (
          f.normalized_name ILIKE '%rice%'
          OR f.name ILIKE '%rice%'
          OR f.normalized_name ILIKE '%arroz%'
          OR f.name ILIKE '%arroz%'
        )
      ORDER BY f.name, f.id
      LIMIT 25
    `),
    sql.unsafe(`
      SELECT
        count(*)::int AS total_rows,
        count(*) FILTER (WHERE is_search_eligible)::int AS search_eligible_rows,
        count(*) FILTER (WHERE NOT is_search_eligible)::int AS excluded_rows
      FROM tmp_food_item_quality_work
    `),
  ]);

  return {
    command,
    qualityVersion: FOOD_QUALITY_VERSION,
    generatedAt: new Date().toISOString(),
    sourceTotals,
    statusCounts,
    flagCounts,
    topDuplicateGroups,
    quarantinedSamples,
    badRiceRows,
    eligibility,
  };
}

async function writeReport(report: Report): Promise<string> {
  const directory = resolve(process.cwd(), "../../data/food-quality");
  await mkdir(directory, { recursive: true });
  const safeTime = report.generatedAt.replaceAll(":", "-");
  const path = resolve(directory, `${report.command}-${safeTime}.json`);
  await writeFile(path, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return path;
}

function printReportSummary(report: Report, path: string): void {
  console.log(`Food data quality ${report.command} report written to ${path}`);
  console.table(report.statusCounts);
  console.table(report.flagCounts);
  console.table(report.eligibility);
  if (report.badRiceRows.length > 0) {
    console.log("Bad OFF rice rows detected:");
    console.table(report.badRiceRows.slice(0, 10));
  }
}
