import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { Sql } from "postgres";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { assertRequiredDatabaseName, assertRequiredSchema, consumeRequireDbNameArg } from "../src/db/scriptGuards.js";
import {
  FOOD_NORMALIZATION_VERSION,
  FOOD_QUALITY_VERSION,
  NORMALIZED_SEARCH_SAMPLE_SEED,
  NORMALIZED_SEARCH_SAMPLE_SET,
} from "../src/foodData/constants.js";

type SampleReport = {
  sampleSetName: string;
  generatedAt: string;
  totalsByReason: unknown[];
  totalsBySource: unknown[];
  usdaGenericCoverage: unknown[];
  offCoverage: unknown[];
  targetedCoverage: unknown[];
};

// QA coverage only. Runtime normalization and search ranking must not branch on these families.
const TARGETED_QUERY_FAMILIES = [
  { reason: "targeted_query_rice_arroz", patterns: ["%rice%", "%arroz%"] },
  { reason: "targeted_query_arroz_goya", patterns: ["%arroz%", "%goya%"], match: "all" },
  { reason: "targeted_query_chicken_breast", patterns: ["%chicken breast%", "%pechuga pollo%"] },
  { reason: "targeted_query_egg", patterns: ["%egg%", "%huevo%"] },
  { reason: "targeted_query_milk", patterns: ["%milk%", "%leche%"] },
  { reason: "targeted_query_apple", patterns: ["%apple%", "%manzana%"] },
  { reason: "targeted_query_yogurt", patterns: ["%yogurt%", "%yogur%"] },
  { reason: "targeted_query_olive_oil", patterns: ["%olive oil%", "%aceite oliva%"] },
  { reason: "targeted_query_bread", patterns: ["%bread%", "%pan%"] },
];

const guardArgs = consumeRequireDbNameArg(process.argv.slice(2));
if (guardArgs.argv.length > 0) {
  throw new Error(`Unknown argument "${guardArgs.argv[0]}".`);
}
const config = loadConfig();
const client = createDbClient(config.DATABASE_URL, { max: 1 });

try {
  await assertRequiredDatabaseName(client.sql, guardArgs.requiredDbName);
  await assertRequiredSchema(client.sql, guardArgs.requiredSchema);
  await client.sql`SET statement_timeout = '30min'`;
  await client.sql`SET lock_timeout = '30s'`;
  const sampleSetId = await recreateSampleSet(client.sql);
  await insertUsdaGenericSample(client.sql, sampleSetId);
  await insertUsdaBrandedSample(client.sql, sampleSetId);
  await insertOpenFoodFactsSample(client.sql, sampleSetId);
  await insertTargetedCoverage(client.sql, sampleSetId);
  const report = await buildReport(client.sql, sampleSetId);
  const path = await writeReport(report);
  printReportSummary(report, path);
} finally {
  await client.close();
}

async function recreateSampleSet(sql: Sql): Promise<string> {
  await sql`
    DELETE FROM food_normalization_sample_sets
    WHERE name = ${NORMALIZED_SEARCH_SAMPLE_SET}
  `;
  const [row] = await sql`
    INSERT INTO food_normalization_sample_sets (
      name,
      description,
      seed,
      quality_version,
      normalization_version,
      criteria_json
    )
    VALUES (
      ${NORMALIZED_SEARCH_SAMPLE_SET},
      'Representative sample for validating cleaned normalized PostgreSQL food search.',
      ${NORMALIZED_SEARCH_SAMPLE_SEED},
      ${FOOD_QUALITY_VERSION},
      ${FOOD_NORMALIZATION_VERSION},
      ${JSON.stringify({
        usdaGeneric: "100% of quality-eligible SR Legacy and Foundation rows",
        usdaBrandedTarget: 10000,
        openFoodFactsTarget: 25000,
        targetedFamilies: TARGETED_QUERY_FAMILIES.map((family) => family.reason),
      })}::jsonb
    )
    RETURNING id
  `;
  return row.id as string;
}

async function insertUsdaGenericSample(sql: Sql, sampleSetId: string): Promise<void> {
  await sql`
    INSERT INTO food_normalization_sample_items (sample_set_id, food_item_id, sample_reason)
    SELECT ${sampleSetId}, f.id, 'usda_generic_all_eligible'
    FROM food_items f
    JOIN food_item_quality q ON q.food_item_id = f.id
    WHERE f.external_source = 'usda_fdc'
      AND f.data_type IN ('SR Legacy', 'Foundation')
      AND q.is_search_eligible
    ON CONFLICT DO NOTHING
  `;
}

async function insertUsdaBrandedSample(sql: Sql, sampleSetId: string): Promise<void> {
  await insertQuota(sql, sampleSetId, "usda_branded_suspicious_review", 2000, `
    f.external_source = 'usda_fdc'
    AND f.data_type = 'Branded'
    AND q.quality_status = 'suspicious'
  `);
  await insertQuota(sql, sampleSetId, "usda_branded_duplicate_review", 2500, `
    f.external_source = 'usda_fdc'
    AND f.data_type = 'Branded'
    AND q.quality_status = 'duplicate'
  `);
  await insertQuota(sql, sampleSetId, "usda_branded_strong_metadata", 2500, `
    f.external_source = 'usda_fdc'
    AND f.data_type = 'Branded'
    AND q.quality_status = 'valid'
    AND nullif(btrim(f.brand), '') IS NOT NULL
    AND nullif(btrim(f.barcode), '') IS NOT NULL
  `);
  await fillToTarget(sql, sampleSetId, "usda_branded_general", 10000, `
    f.external_source = 'usda_fdc'
    AND f.data_type = 'Branded'
    AND q.quality_status <> 'quarantined'
  `, `
    f.external_source = 'usda_fdc'
    AND f.data_type = 'Branded'
  `);
}

async function insertOpenFoodFactsSample(sql: Sql, sampleSetId: string): Promise<void> {
  await insertQuota(sql, sampleSetId, "off_suspicious_review", 3000, `
    f.external_source = 'openfoodfacts'
    AND q.quality_status = 'suspicious'
  `);
  await insertQuota(sql, sampleSetId, "off_duplicate_review", 4000, `
    f.external_source = 'openfoodfacts'
    AND q.quality_status = 'duplicate'
  `);
  await insertQuota(sql, sampleSetId, "off_branded_products", 8000, `
    f.external_source = 'openfoodfacts'
    AND q.quality_status = 'valid'
    AND nullif(btrim(f.brand), '') IS NOT NULL
  `);
  await insertQuota(sql, sampleSetId, "off_no_brand_products", 5000, `
    f.external_source = 'openfoodfacts'
    AND q.quality_status = 'valid'
    AND nullif(btrim(f.brand), '') IS NULL
  `);
  await insertQuota(sql, sampleSetId, "off_spanish_products", 3000, `
    f.external_source = 'openfoodfacts'
    AND q.quality_status <> 'quarantined'
    AND f.food_key = 'es'
  `);
  await fillToTarget(sql, sampleSetId, "off_general", 25000, `
    f.external_source = 'openfoodfacts'
    AND q.quality_status <> 'quarantined'
  `, `
    f.external_source = 'openfoodfacts'
  `);
}

async function insertTargetedCoverage(sql: Sql, sampleSetId: string): Promise<void> {
  for (const family of TARGETED_QUERY_FAMILIES) {
    const predicate = family.patterns
      .map((pattern) => `search_blob LIKE '${escapeSqlLiteral(pattern)}'`)
      .join(family.match === "all" ? " AND " : " OR ");
    await sql.unsafe(`
      WITH candidates AS (
        SELECT
          f.id,
          lower(concat_ws(' ', f.normalized_name, f.canonical_name, f.name, f.brand, f.food_category)) AS search_blob
        FROM food_items f
        JOIN food_item_quality q ON q.food_item_id = f.id
        WHERE q.quality_status <> 'quarantined'
      ),
      ranked AS (
        SELECT id
        FROM candidates
        WHERE ${predicate}
        ORDER BY md5(id::text || ':${NORMALIZED_SEARCH_SAMPLE_SEED}:${family.reason}')
        LIMIT 300
      )
      INSERT INTO food_normalization_sample_items (sample_set_id, food_item_id, sample_reason)
      SELECT '${sampleSetId}'::uuid, id, '${family.reason}'
      FROM ranked
      ON CONFLICT DO NOTHING
    `);
  }
}

async function insertQuota(sql: Sql, sampleSetId: string, reason: string, limit: number, predicate: string): Promise<void> {
  await sql.unsafe(`
    WITH ranked AS (
      SELECT f.id
      FROM food_items f
      JOIN food_item_quality q ON q.food_item_id = f.id
      WHERE ${predicate}
      ORDER BY md5(f.id::text || ':${NORMALIZED_SEARCH_SAMPLE_SEED}:${reason}')
      LIMIT ${limit}
    )
    INSERT INTO food_normalization_sample_items (sample_set_id, food_item_id, sample_reason)
    SELECT '${sampleSetId}'::uuid, id, '${reason}'
    FROM ranked
    ON CONFLICT DO NOTHING
  `);
}

async function fillToTarget(
  sql: Sql,
  sampleSetId: string,
  reason: string,
  target: number,
  predicate: string,
  groupPredicate: string,
): Promise<void> {
  const [countRow] = await sql.unsafe<{ rows: number }[]>(`
    SELECT count(*)::int AS rows
    FROM food_normalization_sample_items si
    JOIN food_items f ON f.id = si.food_item_id
    WHERE si.sample_set_id = '${sampleSetId}'::uuid
      AND ${groupPredicate}
  `);
  const fillCount = Math.max(0, target - Number(countRow?.rows ?? 0));
  if (fillCount === 0) return;

  await sql.unsafe(`
    WITH eligible_candidates AS MATERIALIZED (
      SELECT f.id
      FROM food_items f
      JOIN food_item_quality q ON q.food_item_id = f.id
      LEFT JOIN food_normalization_sample_items existing
        ON existing.sample_set_id = '${sampleSetId}'::uuid
       AND existing.food_item_id = f.id
      WHERE ${predicate}
        AND existing.food_item_id IS NULL
    ),
    ranked AS (
      SELECT id
      FROM eligible_candidates
      ORDER BY md5(id::text || ':${NORMALIZED_SEARCH_SAMPLE_SEED}:${reason}')
      LIMIT ${fillCount}
    )
    INSERT INTO food_normalization_sample_items (sample_set_id, food_item_id, sample_reason)
    SELECT '${sampleSetId}'::uuid, id, '${reason}'
    FROM ranked
    ON CONFLICT DO NOTHING
  `);
}

async function buildReport(sql: Sql, sampleSetId: string): Promise<SampleReport> {
  const [
    totalsByReason,
    totalsBySource,
    usdaGenericCoverage,
    offCoverage,
    targetedCoverage,
  ] = await Promise.all([
    sql`
      SELECT sample_reason, count(*)::int AS rows
      FROM food_normalization_sample_items
      WHERE sample_set_id = ${sampleSetId}
      GROUP BY sample_reason
      ORDER BY rows DESC, sample_reason
    `,
    sql`
      SELECT
        coalesce(f.external_source, '') AS external_source,
        coalesce(f.data_type, '') AS data_type,
        q.quality_status,
        count(*)::int AS rows
      FROM food_normalization_sample_items si
      JOIN food_items f ON f.id = si.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      WHERE si.sample_set_id = ${sampleSetId}
      GROUP BY f.external_source, f.data_type, q.quality_status
      ORDER BY rows DESC
    `,
    sql`
      SELECT
        (SELECT count(*)::int
         FROM food_items f
         JOIN food_item_quality q ON q.food_item_id = f.id
         WHERE f.external_source = 'usda_fdc'
           AND f.data_type IN ('SR Legacy', 'Foundation')
           AND q.is_search_eligible) AS eligible_usda_generic,
        count(*)::int AS sampled_usda_generic
      FROM food_normalization_sample_items si
      JOIN food_items f ON f.id = si.food_item_id
      WHERE si.sample_set_id = ${sampleSetId}
        AND f.external_source = 'usda_fdc'
        AND f.data_type IN ('SR Legacy', 'Foundation')
    `,
    sql`
      SELECT
        count(*)::int AS off_rows,
        count(*) FILTER (WHERE nullif(btrim(f.brand), '') IS NOT NULL)::int AS with_brand,
        count(*) FILTER (WHERE nullif(btrim(f.brand), '') IS NULL)::int AS without_brand,
        count(*) FILTER (WHERE f.food_key = 'es')::int AS spanish_rows,
        count(*) FILTER (WHERE q.quality_status = 'suspicious')::int AS suspicious_rows,
        count(*) FILTER (WHERE q.quality_status = 'duplicate')::int AS duplicate_rows
      FROM food_normalization_sample_items si
      JOIN food_items f ON f.id = si.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      WHERE si.sample_set_id = ${sampleSetId}
        AND f.external_source = 'openfoodfacts'
    `,
    sql`
      SELECT sample_reason, count(*)::int AS rows
      FROM food_normalization_sample_items
      WHERE sample_set_id = ${sampleSetId}
        AND sample_reason LIKE 'targeted_query_%'
      GROUP BY sample_reason
      ORDER BY sample_reason
    `,
  ]);

  return {
    sampleSetName: NORMALIZED_SEARCH_SAMPLE_SET,
    generatedAt: new Date().toISOString(),
    totalsByReason,
    totalsBySource,
    usdaGenericCoverage,
    offCoverage,
    targetedCoverage,
  };
}

async function writeReport(report: SampleReport): Promise<string> {
  const directory = resolve(process.cwd(), "../../data/food-normalization");
  await mkdir(directory, { recursive: true });
  const safeTime = report.generatedAt.replaceAll(":", "-");
  const path = resolve(directory, `sample-${safeTime}.json`);
  await writeFile(path, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return path;
}

function printReportSummary(report: SampleReport, path: string): void {
  console.log(`Food normalization sample report written to ${path}`);
  console.table(report.totalsByReason);
  console.table(report.totalsBySource);
  console.table(report.usdaGenericCoverage);
  console.table(report.offCoverage);
  console.table(report.targetedCoverage);
}

function escapeSqlLiteral(value: string): string {
  return value.replaceAll("'", "''");
}
