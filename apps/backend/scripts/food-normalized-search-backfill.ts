import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { Sql } from "postgres";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { assertRequiredDatabaseName, assertRequiredSchema, consumeRequireDbNameArg } from "../src/db/scriptGuards.js";
import {
  FOOD_NORMALIZATION_VERSION,
  NORMALIZED_SEARCH_SAMPLE_SET,
} from "../src/foodData/constants.js";
import {
  buildNormalizedFoodSearchDocument,
  normalizeFoodNameParts,
  type NormalizedFoodNameParts,
  type NormalizedFoodSearchDocumentInput,
} from "../src/foodData/normalization.js";
import {
  applyLongNameDecision,
  longNameInputSignature,
  parseLongNameDecision,
  type LongNameDecision,
  type LongNameDecisionApplication,
} from "../src/foodData/longNameDecisions.js";
import {
  evaluateNormalizationReview,
  normalizationMetrics,
  nutritionDiverges,
  percentileThresholdsFromMetrics,
  type NormalizationReviewResult,
  type NormalizationReviewThresholds,
} from "../src/foodData/normalizationReview.js";
import type { FoodItemRecord } from "../src/repository/types.js";
import { normalizeText } from "../src/utils/normalize.js";

type BackfillScope = "sample" | "full";
type BackfillMode = "audit" | "apply";

type Args = {
  scope: BackfillScope;
  mode: BackfillMode;
  batchSize: number;
  resumeAfter?: string;
  sampleSetName: string;
  reportDir?: string;
  longNameDecisionsPath?: string;
  excludeAmbiguousProductCollisions: boolean;
  requiredDbName?: string;
  requiredSchema?: string;
};

type FoodRow = Record<string, unknown> & {
  quality_flags?: string[];
};

type ReviewRecord = {
  foodItemId: string;
  normalizationVersion: string;
  reviewStatus: string;
  severity: string;
  issueCodes: string[];
  rawName: string;
  rawBrand?: string;
  rawSource?: string;
  rawExternalSource?: string;
  rawDataType?: string;
  displayName?: string;
  baseName?: string;
  variantName?: string;
  brandDisplay?: string;
  primaryEntityName?: string;
  locale?: string;
  resultType?: string;
  normalizationConfidence?: number;
  metrics: Record<string, unknown>;
  metadata: Record<string, unknown>;
};

type LongNameDecisionCounts = {
  loaded: number;
  applied: number;
  stale: number;
  rejected: number;
};

type BackfillReport = {
  scope: BackfillScope;
  mode: BackfillMode;
  sampleSetName: string;
  normalizationVersion: string;
  generatedAt: string;
  selectedRows: number;
  normalizedRows: number;
  reviewRows: number;
  runtimeDocWriteRows: number;
  runtimeDocDeleteRows: number;
  runtimeDocDeleteSkipped: boolean;
  collisionIssueRows: number;
  normalizationSignatureCacheHits: number;
  normalizationSignatureCacheMisses: number;
  thresholds: NormalizationReviewThresholds;
  statusCounts: unknown[];
  issueCounts: unknown[];
  reviewByResultType: unknown[];
  reviewBySource: unknown[];
  docsByResultType: unknown[];
  docsBySource: unknown[];
  samplesByIssue: unknown[];
  topDisplayCollisionGroups: unknown[];
  topProductCollisionGroups: unknown[];
  topOutlierGroups: unknown[];
  collisionRootCauseCounts: unknown[];
  targetCollisionSamples: unknown[];
  excludedCollisionSamples: unknown[];
  observabilityIssueCounts: unknown[];
  samplesByObservabilityIssue: unknown[];
  longNameDecisionCounts: LongNameDecisionCounts;
  staleLongNameDecisionSamples: unknown[];
  ambiguousProductCollisionRows: number;
};

const DEFAULT_BATCH_SIZE = 5000;

const guardArgs = consumeRequireDbNameArg(process.argv.slice(2));
const args = parseArgs(guardArgs.argv, guardArgs.requiredDbName, guardArgs.requiredSchema);
const config = loadConfig();
const client = createDbClient(config.DATABASE_URL, { max: 1 });

try {
  await assertRequiredDatabaseName(client.sql, args.requiredDbName);
  await assertRequiredSchema(client.sql, args.requiredSchema);
  await client.sql`SET statement_timeout = '60min'`;
  await client.sql`SET lock_timeout = '30s'`;
  const sampleSetId = await sampleSetIdForName(client.sql, args.sampleSetName);
  const thresholds = await computeSampleThresholds(client.sql, sampleSetId);
  const genericDocs = await loadAdjustedGenericDocs(client.sql);
  const longNameDecisions = args.longNameDecisionsPath
    ? await loadLongNameDecisions(args.longNameDecisionsPath)
    : new Map<string, LongNameDecision>();
  const result = await runBackfill(client.sql, args, sampleSetId, thresholds, genericDocs, longNameDecisions);
  const report = await buildReport(client.sql, args, result, thresholds);
  const path = await writeReport(report, args);
  printReportSummary(report, path);
} finally {
  await client.close();
}

async function runBackfill(
  sql: Sql,
  args: Args,
  sampleSetId: string,
  thresholds: NormalizationReviewThresholds,
  genericDocs: Map<string, NormalizedFoodSearchDocumentInput>,
  longNameDecisions: Map<string, LongNameDecision>,
): Promise<{
  selectedRows: number;
  normalizedRows: number;
  reviewRows: number;
  runtimeDocWriteRows: number;
  runtimeDocDeleteRows: number;
  runtimeDocDeleteSkipped: boolean;
  collisionIssueRows: number;
  normalizationSignatureCacheHits: number;
  normalizationSignatureCacheMisses: number;
  longNameDecisionCounts: LongNameDecisionCounts;
  ambiguousProductCollisionRows: number;
}> {
  let selectedRows = 0;
  let normalizedRows = 0;
  let reviewRows = 0;
  let runtimeDocWriteRows = 0;
  let lastId = args.resumeAfter;
  let normalizationSignatureCacheHits = 0;
  let normalizationSignatureCacheMisses = 0;
  let ambiguousProductCollisionRows = 0;
  const longNameDecisionCounts: LongNameDecisionCounts = {
    loaded: longNameDecisions.size,
    applied: 0,
    stale: 0,
    rejected: 0,
  };
  const normalizationSignatureCache = new Map<string, NormalizedFoodNameParts>();

  for (;;) {
    const rows = await loadRows(sql, args, sampleSetId, lastId);
    if (rows.length === 0) break;
    const reviews: ReviewRecord[] = [];
    const docs: NormalizedFoodSearchDocumentInput[] = [];

    for (const row of rows) {
      const food = mapFood(row);
      let doc = genericDocs.get(food.id);
      if (!doc) {
        const signature = normalizationSignature(row);
        let normalizedParts: NormalizedFoodNameParts;
        if (normalizationSignatureCache.has(signature)) {
          normalizationSignatureCacheHits += 1;
          normalizedParts = normalizationSignatureCache.get(signature)!;
        } else {
          normalizationSignatureCacheMisses += 1;
          normalizedParts = normalizeFoodNameParts(food);
          normalizationSignatureCache.set(signature, normalizedParts);
        }
        doc = buildNormalizedFoodSearchDocument(food, normalizeQualityFlags(row.quality_flags), normalizedParts);
      }
      const longNameDecision = applyRowLongNameDecision(row, doc, longNameDecisions.get(food.id));
      if (longNameDecision.status === "applied") {
        doc = longNameDecision.doc;
        longNameDecisionCounts.applied += 1;
      } else if (longNameDecision.status === "stale") {
        longNameDecisionCounts.stale += 1;
      } else if (longNameDecision.status === "rejected") {
        longNameDecisionCounts.rejected += 1;
      }
      const review = evaluateNormalizationReview({
        foodId: food.id,
        rawName: food.name,
        rawBrand: food.brand,
        rawSource: food.source,
        rawExternalSource: food.externalSource,
        rawDataType: food.dataType,
        doc,
      }, thresholds);
      reviews.push(reviewRecord(row, doc, review, longNameDecision));
      if (doc) normalizedRows += 1;
      if (args.mode === "apply" && doc && review.reviewStatus === "valid") docs.push(doc);
    }

    await upsertReviewBatch(sql, reviews);
    if (args.mode === "apply") {
      await upsertDocumentBatch(sql, docs);
      runtimeDocWriteRows += docs.length;
    }

    selectedRows += rows.length;
    reviewRows += reviews.length;
    lastId = String(rows[rows.length - 1]?.id);
    console.log(`processed ${selectedRows} ${args.scope} rows, lastId=${lastId}`);
  }

  const collisionIssueRows = await applyCollisionIssueCodes(sql, args, sampleSetId);
  if (args.mode === "apply" && args.excludeAmbiguousProductCollisions) {
    ambiguousProductCollisionRows = await excludeAmbiguousProductCollisionRows(sql, args, sampleSetId);
  }
  const runtimeDocDeleteSkipped = args.mode === "apply" && Boolean(args.resumeAfter);
  const runtimeDocDeleteRows = args.mode === "apply" && !runtimeDocDeleteSkipped
    ? await deleteNonValidRuntimeDocs(sql, args, sampleSetId)
    : 0;

  return {
    selectedRows,
    normalizedRows,
    reviewRows,
    runtimeDocWriteRows,
    runtimeDocDeleteRows,
    runtimeDocDeleteSkipped,
    collisionIssueRows,
    normalizationSignatureCacheHits,
    normalizationSignatureCacheMisses,
    longNameDecisionCounts,
    ambiguousProductCollisionRows,
  };
}

async function sampleSetIdForName(sql: Sql, sampleSetName: string): Promise<string> {
  const [row] = await sql`
    SELECT id
    FROM food_normalization_sample_sets
    WHERE name = ${sampleSetName}
    LIMIT 1
  `;
  if (!row) throw new Error(`Sample set ${sampleSetName} does not exist. Run food-normalization:sample first.`);
  return row.id as string;
}

async function computeSampleThresholds(sql: Sql, sampleSetId: string): Promise<NormalizationReviewThresholds> {
  const rows = await loadSampleRows(sql, sampleSetId);
  const metrics = rows
    .map((row) => {
      const food = mapFood(row);
      const doc = buildNormalizedFoodSearchDocument(food, normalizeQualityFlags(row.quality_flags));
      return normalizationMetrics({
        foodId: food.id,
        rawName: food.name,
        rawBrand: food.brand,
        rawSource: food.source,
        rawExternalSource: food.externalSource,
        rawDataType: food.dataType,
        doc,
      });
    });
  return percentileThresholdsFromMetrics(metrics);
}

async function loadAdjustedGenericDocs(sql: Sql): Promise<Map<string, NormalizedFoodSearchDocumentInput>> {
  const rows = await sql`
    SELECT f.*, q.quality_flags
    FROM food_items f
    JOIN food_item_quality q ON q.food_item_id = f.id
    WHERE q.is_search_eligible
      AND f.external_source = 'usda_fdc'
      AND f.data_type IN ('SR Legacy', 'Foundation')
    ORDER BY f.id
  ` as FoodRow[];
  const rawDocs = rows
    .map((row) => buildNormalizedFoodSearchDocument(mapFood(row), normalizeQualityFlags(row.quality_flags)))
    .filter((doc): doc is NormalizedFoodSearchDocumentInput => Boolean(doc));
  const docs = applyPrimaryEntityCategoryCoherence(disambiguateGenericDisplayCollisions(rows, rawDocs));
  return new Map(docs.map((doc) => [doc.foodItemId, doc]));
}

async function loadLongNameDecisions(path: string): Promise<Map<string, LongNameDecision>> {
  const content = await readFile(resolve(process.cwd(), path), "utf8");
  const decisions = new Map<string, LongNameDecision>();
  for (const [index, line] of content.split(/\r?\n/).entries()) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const decision = parseLongNameDecision(JSON.parse(trimmed));
      decisions.set(decision.foodItemId, decision);
    } catch (error) {
      throw new Error(`Invalid long-name decision at ${path}:${index + 1}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return decisions;
}

function applyRowLongNameDecision(
  row: FoodRow,
  doc: NormalizedFoodSearchDocumentInput | undefined,
  decision: LongNameDecision | undefined,
): LongNameDecisionApplication {
  if (!doc) return { status: "none" };
  const expectedInputSignature = longNameInputSignature({
    userId: optionalString(row.user_id),
    source: optionalString(row.source),
    externalSource: optionalString(row.external_source),
    dataType: optionalString(row.data_type),
    foodKey: optionalString(row.food_key),
    name: optionalString(row.name),
    normalizedName: optionalString(row.normalized_name),
    canonicalName: optionalString(row.canonical_name),
    brand: optionalString(row.brand),
    foodCategory: optionalString(row.food_category),
    marketCountry: optionalString(row.market_country),
    normalizationVersion: FOOD_NORMALIZATION_VERSION,
  });
  return applyLongNameDecision(doc, decision, expectedInputSignature);
}

async function loadRows(
  sql: Sql,
  args: Args,
  sampleSetId: string,
  lastId: string | undefined,
): Promise<FoodRow[]> {
  if (args.scope === "sample") {
    if (lastId) {
      return await sql`
        SELECT f.*, q.quality_flags
        FROM food_normalization_sample_items si
        JOIN food_items f ON f.id = si.food_item_id
        JOIN food_item_quality q ON q.food_item_id = f.id
        WHERE si.sample_set_id = ${sampleSetId}
          AND q.is_search_eligible
          AND f.id > ${lastId}
        ORDER BY f.id
        LIMIT ${args.batchSize}
      ` as FoodRow[];
    }
    return await sql`
      SELECT f.*, q.quality_flags
      FROM food_normalization_sample_items si
      JOIN food_items f ON f.id = si.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      WHERE si.sample_set_id = ${sampleSetId}
        AND q.is_search_eligible
      ORDER BY f.id
      LIMIT ${args.batchSize}
    ` as FoodRow[];
  }

  if (lastId) {
    return await sql`
      SELECT f.*, q.quality_flags
      FROM food_items f
      JOIN food_item_quality q ON q.food_item_id = f.id
      WHERE q.is_search_eligible
        AND f.id > ${lastId}
      ORDER BY f.id
      LIMIT ${args.batchSize}
    ` as FoodRow[];
  }
  return await sql`
    SELECT f.*, q.quality_flags
    FROM food_items f
    JOIN food_item_quality q ON q.food_item_id = f.id
    WHERE q.is_search_eligible
    ORDER BY f.id
    LIMIT ${args.batchSize}
  ` as FoodRow[];
}

async function loadSampleRows(sql: Sql, sampleSetId: string): Promise<FoodRow[]> {
  return await sql`
    SELECT f.*, q.quality_flags
    FROM food_normalization_sample_items si
    JOIN food_items f ON f.id = si.food_item_id
    JOIN food_item_quality q ON q.food_item_id = f.id
    WHERE si.sample_set_id = ${sampleSetId}
      AND q.is_search_eligible
    ORDER BY f.id
  ` as FoodRow[];
}

async function upsertReviewBatch(sql: Sql, reviews: ReviewRecord[]): Promise<void> {
  if (reviews.length === 0) return;
  const payload = JSON.stringify(reviews.map((review) => ({
    foodItemId: review.foodItemId,
    normalizationVersion: review.normalizationVersion,
    reviewStatus: review.reviewStatus,
    severity: review.severity,
    issueCodesText: review.issueCodes.join("\n"),
    rawName: review.rawName,
    rawBrand: review.rawBrand ?? null,
    rawSource: review.rawSource ?? null,
    rawExternalSource: review.rawExternalSource ?? null,
    rawDataType: review.rawDataType ?? null,
    displayName: review.displayName ?? null,
    baseName: review.baseName ?? null,
    variantName: review.variantName ?? null,
    brandDisplay: review.brandDisplay ?? null,
    primaryEntityName: review.primaryEntityName ?? null,
    locale: review.locale ?? null,
    resultType: review.resultType ?? null,
    normalizationConfidence: review.normalizationConfidence ?? null,
    metrics: review.metrics,
    metadata: review.metadata,
  })));

  await sql.unsafe(`
    WITH input AS (
      SELECT *
      FROM jsonb_to_recordset($1::jsonb) AS x(
        "foodItemId" uuid,
        "normalizationVersion" text,
        "reviewStatus" text,
        "severity" text,
        "issueCodesText" text,
        "rawName" text,
        "rawBrand" text,
        "rawSource" text,
        "rawExternalSource" text,
        "rawDataType" text,
        "displayName" text,
        "baseName" text,
        "variantName" text,
        "brandDisplay" text,
        "primaryEntityName" text,
        "locale" text,
        "resultType" text,
        "normalizationConfidence" numeric,
        "metrics" jsonb,
        "metadata" jsonb
      )
    )
    INSERT INTO food_normalization_review (
      food_item_id,
      normalization_version,
      review_status,
      severity,
      issue_codes,
      raw_name,
      raw_brand,
      raw_source,
      raw_external_source,
      raw_data_type,
      display_name,
      base_name,
      variant_name,
      brand_display,
      primary_entity_name,
      locale,
      result_type,
      normalization_confidence,
      metrics,
      metadata,
      created_at,
      updated_at
    )
    SELECT
      "foodItemId",
      "normalizationVersion",
      "reviewStatus",
      "severity",
      coalesce(string_to_array(nullif("issueCodesText", ''), E'\\n'), '{}'::text[]),
      "rawName",
      "rawBrand",
      "rawSource",
      "rawExternalSource",
      "rawDataType",
      "displayName",
      "baseName",
      "variantName",
      "brandDisplay",
      "primaryEntityName",
      "locale",
      "resultType",
      "normalizationConfidence",
      "metrics",
      "metadata",
      now(),
      now()
    FROM input
    ON CONFLICT (food_item_id) DO UPDATE SET
      normalization_version = EXCLUDED.normalization_version,
      review_status = EXCLUDED.review_status,
      severity = EXCLUDED.severity,
      issue_codes = EXCLUDED.issue_codes,
      raw_name = EXCLUDED.raw_name,
      raw_brand = EXCLUDED.raw_brand,
      raw_source = EXCLUDED.raw_source,
      raw_external_source = EXCLUDED.raw_external_source,
      raw_data_type = EXCLUDED.raw_data_type,
      display_name = EXCLUDED.display_name,
      base_name = EXCLUDED.base_name,
      variant_name = EXCLUDED.variant_name,
      brand_display = EXCLUDED.brand_display,
      primary_entity_name = EXCLUDED.primary_entity_name,
      locale = EXCLUDED.locale,
      result_type = EXCLUDED.result_type,
      normalization_confidence = EXCLUDED.normalization_confidence,
      metrics = EXCLUDED.metrics,
      metadata = EXCLUDED.metadata,
      updated_at = now()
  `, [payload]);
}

async function upsertDocumentBatch(sql: Sql, docs: NormalizedFoodSearchDocumentInput[]): Promise<void> {
  if (docs.length === 0) return;
  const payload = JSON.stringify(docs.map((doc) => ({
    foodItemId: doc.foodItemId,
    userId: doc.userId ?? null,
    locale: doc.locale,
    resultType: doc.resultType,
    displayName: doc.displayName,
    baseName: doc.baseName,
    variantName: doc.variantName ?? null,
    brandDisplay: doc.brandDisplay ?? null,
    primaryEntityName: doc.primaryEntityName,
    primaryEntityAliasesText: doc.primaryEntityAliases.join("\n"),
    secondaryEntityAliasesText: doc.secondaryEntityAliases.join("\n"),
    identityTokenKeysText: doc.identityTokenKeys.join("\n"),
    primaryEntityCategory: doc.primaryEntityCategory ?? null,
    primaryEntityCategoryCoherence: doc.primaryEntityCategoryCoherence,
    primaryEntityRepresentativeness: doc.primaryEntityRepresentativeness,
    searchText: doc.searchText,
    searchAliasesText: doc.searchAliases.join("\n"),
    rankBucket: doc.rankBucket,
    normalizationVersion: doc.normalizationVersion,
    normalizationSource: doc.normalizationSource,
    normalizationConfidence: doc.normalizationConfidence,
    qualityFlagsText: doc.qualityFlags.join("\n"),
    metadata: doc.metadata,
  })));

  await sql.unsafe(`
    WITH input AS (
      SELECT *
      FROM jsonb_to_recordset($1::jsonb) AS x(
        "foodItemId" uuid,
        "userId" uuid,
        "locale" text,
        "resultType" text,
        "displayName" text,
        "baseName" text,
        "variantName" text,
        "brandDisplay" text,
        "primaryEntityName" text,
        "primaryEntityAliasesText" text,
        "secondaryEntityAliasesText" text,
        "identityTokenKeysText" text,
        "primaryEntityCategory" text,
        "primaryEntityCategoryCoherence" numeric,
        "primaryEntityRepresentativeness" numeric,
        "searchText" text,
        "searchAliasesText" text,
        "rankBucket" integer,
        "normalizationVersion" text,
        "normalizationSource" text,
        "normalizationConfidence" numeric,
        "qualityFlagsText" text,
        "metadata" jsonb
      )
    )
    INSERT INTO food_normalized_search_documents (
      food_item_id,
      user_id,
      locale,
      result_type,
      display_name,
      base_name,
      variant_name,
      brand_display,
      primary_entity_name,
      primary_entity_aliases,
      secondary_entity_aliases,
      identity_token_keys,
      primary_entity_category,
      primary_entity_category_coherence,
      primary_entity_representativeness,
      search_text,
      search_aliases,
      search_vector,
      rank_bucket,
      normalization_version,
      normalization_source,
      normalization_confidence,
      quality_flags,
      metadata,
      updated_at
    )
    SELECT
      "foodItemId",
      "userId",
      "locale",
      "resultType",
      "displayName",
      "baseName",
      "variantName",
      "brandDisplay",
      "primaryEntityName",
      coalesce(string_to_array(nullif("primaryEntityAliasesText", ''), E'\\n'), '{}'::text[]),
      coalesce(string_to_array(nullif("secondaryEntityAliasesText", ''), E'\\n'), '{}'::text[]),
      coalesce(string_to_array(nullif("identityTokenKeysText", ''), E'\\n'), '{}'::text[]),
      "primaryEntityCategory",
      "primaryEntityCategoryCoherence",
      "primaryEntityRepresentativeness",
      "searchText",
      coalesce(string_to_array(nullif("searchAliasesText", ''), E'\\n'), '{}'::text[]),
      to_tsvector('simple', "searchText"),
      "rankBucket",
      "normalizationVersion",
      "normalizationSource",
      "normalizationConfidence",
      coalesce(string_to_array(nullif("qualityFlagsText", ''), E'\\n'), '{}'::text[]),
      "metadata",
      now()
    FROM input
    ON CONFLICT (food_item_id) DO UPDATE SET
      user_id = EXCLUDED.user_id,
      locale = EXCLUDED.locale,
      result_type = EXCLUDED.result_type,
      display_name = EXCLUDED.display_name,
      base_name = EXCLUDED.base_name,
      variant_name = EXCLUDED.variant_name,
      brand_display = EXCLUDED.brand_display,
      primary_entity_name = EXCLUDED.primary_entity_name,
      primary_entity_aliases = EXCLUDED.primary_entity_aliases,
      secondary_entity_aliases = EXCLUDED.secondary_entity_aliases,
      identity_token_keys = EXCLUDED.identity_token_keys,
      primary_entity_category = EXCLUDED.primary_entity_category,
      primary_entity_category_coherence = EXCLUDED.primary_entity_category_coherence,
      primary_entity_representativeness = EXCLUDED.primary_entity_representativeness,
      search_text = EXCLUDED.search_text,
      search_aliases = EXCLUDED.search_aliases,
      search_vector = EXCLUDED.search_vector,
      rank_bucket = EXCLUDED.rank_bucket,
      normalization_version = EXCLUDED.normalization_version,
      normalization_source = EXCLUDED.normalization_source,
      normalization_confidence = EXCLUDED.normalization_confidence,
      quality_flags = EXCLUDED.quality_flags,
      metadata = EXCLUDED.metadata,
      updated_at = now()
  `, [payload]);
}

async function applyCollisionIssueCodes(sql: Sql, args: Args, sampleSetId: string): Promise<number> {
  const displayRows = await applyDisplayCollisionIssue(sql, args, sampleSetId);
  const productRows = await applyProductCollisionIssue(sql, args, sampleSetId);
  return displayRows + productRows;
}

async function applyDisplayCollisionIssue(sql: Sql, args: Args, sampleSetId: string): Promise<number> {
  const rows = await sql.unsafe(`
    WITH scoped AS (
      SELECT
        r.food_item_id,
        r.locale,
        r.result_type,
        lower(concat_ws('|', r.display_name, coalesce(r.variant_name, ''), coalesce(r.brand_display, ''))) AS display_key,
        f.calories::numeric AS calories,
        f.protein_grams::numeric AS protein_grams,
        f.carbs_grams::numeric AS carbs_grams,
        f.fat_grams::numeric AS fat_grams
      FROM food_normalization_review r
      JOIN food_items f ON f.id = r.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      ${args.scope === "sample" ? `
      JOIN food_normalization_sample_items si ON si.food_item_id = f.id
      ` : ""}
      WHERE r.normalization_version = $1
        AND r.review_status <> 'failed'
        AND q.is_search_eligible
        AND r.display_name IS NOT NULL
        AND r.locale IS NOT NULL
        AND r.result_type IS NOT NULL
        ${args.scope === "sample" ? "AND si.sample_set_id = $2" : ""}
    ),
    stats AS (
      SELECT
        locale,
        result_type,
        display_key,
        count(*)::int AS rows,
        max(calories) - min(calories) AS calories_delta,
        max(protein_grams) - min(protein_grams) AS protein_delta,
        max(carbs_grams) - min(carbs_grams) AS carbs_delta,
        max(fat_grams) - min(fat_grams) AS fat_delta,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY calories)::numeric AS calories_median,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY protein_grams)::numeric AS protein_median,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY carbs_grams)::numeric AS carbs_median,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY fat_grams)::numeric AS fat_median
      FROM scoped
      GROUP BY locale, result_type, display_key
    ),
    divergent AS (
      SELECT locale, result_type, display_key
      FROM stats
      WHERE rows > 1
        AND (
          calories_delta > greatest(50::numeric, abs(calories_median) * 0.2)
          OR protein_delta > greatest(5::numeric, abs(protein_median) * 0.2)
          OR carbs_delta > greatest(5::numeric, abs(carbs_median) * 0.2)
          OR fat_delta > greatest(5::numeric, abs(fat_median) * 0.2)
        )
    ),
    affected AS (
      SELECT scoped.food_item_id
      FROM scoped
      JOIN divergent USING (locale, result_type, display_key)
    )
    UPDATE food_normalization_review r
    SET
      review_status = 'needs_review',
      severity = 'warning',
      issue_codes = ARRAY(
        SELECT DISTINCT value
        FROM unnest(r.issue_codes || ARRAY['display_name_collision_nutrition_divergent'::text]) AS value
        ORDER BY value
      ),
      updated_at = now()
    FROM affected
    WHERE r.food_item_id = affected.food_item_id
      AND r.normalization_version = $1
      AND r.review_status <> 'failed'
    RETURNING r.food_item_id
  `, args.scope === "sample" ? [FOOD_NORMALIZATION_VERSION, sampleSetId] : [FOOD_NORMALIZATION_VERSION]);
  return rows.length;
}

async function applyProductCollisionIssue(sql: Sql, args: Args, sampleSetId: string): Promise<number> {
  const rows = await sql.unsafe(`
    WITH scoped AS (
      SELECT
        r.food_item_id,
        r.locale,
        lower(r.base_name) AS base_key,
        lower(coalesce(r.variant_name, '')) AS variant_key,
        lower(coalesce(r.brand_display, '')) AS brand_key,
        coalesce(nullif(btrim(f.barcode), ''), nullif(btrim(f.external_id), ''), f.id::text) AS identity_key,
        f.calories::numeric AS calories,
        f.protein_grams::numeric AS protein_grams,
        f.carbs_grams::numeric AS carbs_grams,
        f.fat_grams::numeric AS fat_grams
      FROM food_normalization_review r
      JOIN food_items f ON f.id = r.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      ${args.scope === "sample" ? `
      JOIN food_normalization_sample_items si ON si.food_item_id = f.id
      ` : ""}
      WHERE r.normalization_version = $1
        AND r.review_status <> 'failed'
        AND q.is_search_eligible
        AND r.result_type = 'product'
        AND r.base_name IS NOT NULL
        AND r.locale IS NOT NULL
        ${args.scope === "sample" ? "AND si.sample_set_id = $2" : ""}
    ),
    stats AS (
      SELECT
        locale,
        base_key,
        variant_key,
        brand_key,
        count(DISTINCT identity_key)::int AS identities,
        max(calories) - min(calories) AS calories_delta,
        max(protein_grams) - min(protein_grams) AS protein_delta,
        max(carbs_grams) - min(carbs_grams) AS carbs_delta,
        max(fat_grams) - min(fat_grams) AS fat_delta,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY calories)::numeric AS calories_median,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY protein_grams)::numeric AS protein_median,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY carbs_grams)::numeric AS carbs_median,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY fat_grams)::numeric AS fat_median
      FROM scoped
      GROUP BY locale, base_key, variant_key, brand_key
    ),
    divergent AS (
      SELECT locale, base_key, variant_key, brand_key
      FROM stats
      WHERE identities > 1
        AND (
          calories_delta > greatest(50::numeric, abs(calories_median) * 0.2)
          OR protein_delta > greatest(5::numeric, abs(protein_median) * 0.2)
          OR carbs_delta > greatest(5::numeric, abs(carbs_median) * 0.2)
          OR fat_delta > greatest(5::numeric, abs(fat_median) * 0.2)
        )
    ),
    affected AS (
      SELECT scoped.food_item_id
      FROM scoped
      JOIN divergent USING (locale, base_key, variant_key, brand_key)
    )
    UPDATE food_normalization_review r
    SET
      review_status = 'needs_review',
      severity = 'warning',
      issue_codes = ARRAY(
        SELECT DISTINCT value
        FROM unnest(r.issue_codes || ARRAY['product_identity_collision'::text]) AS value
        ORDER BY value
      ),
      updated_at = now()
    FROM affected
    WHERE r.food_item_id = affected.food_item_id
      AND r.normalization_version = $1
      AND r.review_status <> 'failed'
    RETURNING r.food_item_id
  `, args.scope === "sample" ? [FOOD_NORMALIZATION_VERSION, sampleSetId] : [FOOD_NORMALIZATION_VERSION]);
  return rows.length;
}

async function excludeAmbiguousProductCollisionRows(
  sql: Sql,
  args: Args,
  sampleSetId: string,
): Promise<number> {
  await sql.unsafe("DROP TABLE IF EXISTS tmp_ambiguous_product_collision_exclusions");
  await sql.unsafe(`
    CREATE TEMP TABLE tmp_ambiguous_product_collision_exclusions AS
    WITH collision_rows AS (
      SELECT
        r.food_item_id,
        r.locale,
        lower(r.base_name) AS base_key,
        lower(coalesce(r.variant_name, '')) AS variant_key,
        lower(coalesce(r.brand_display, '')) AS brand_key,
        coalesce(nullif(r.metadata->>'rawNameTokenKey', ''), '') AS raw_name_token_key,
        coalesce(nullif(r.metadata->>'rawBrandTokenKey', ''), '') AS raw_brand_token_key,
        coalesce(nullif(r.metadata->>'rawFullTokenKey', ''), '') AS raw_full_token_key,
        coalesce(nullif(r.metadata->>'rawFullUniqueTokenKey', ''), '') AS raw_full_unique_token_key
      FROM food_normalization_review r
      JOIN food_items f ON f.id = r.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      ${args.scope === "sample" ? `
      JOIN food_normalization_sample_items si ON si.food_item_id = f.id
      ` : ""}
      WHERE r.normalization_version = $1
        AND q.is_search_eligible
        AND r.result_type = 'product'
        AND 'product_identity_collision' = ANY(r.issue_codes)
        ${args.scope === "sample" ? "AND si.sample_set_id = $2" : ""}
    ),
    grouped AS (
      SELECT
        locale,
        base_key,
        variant_key,
        brand_key,
        count(DISTINCT raw_name_token_key)::int AS raw_name_token_identities,
        count(DISTINCT raw_brand_token_key)::int AS raw_brand_token_identities,
        count(DISTINCT raw_full_token_key)::int AS raw_full_token_identities,
        count(DISTINCT raw_full_unique_token_key)::int AS raw_full_unique_token_identities,
        count(*)::int AS group_rows
      FROM collision_rows
      GROUP BY locale, base_key, variant_key, brand_key
    ),
    classified AS (
      SELECT
        *,
        CASE
          WHEN raw_full_token_identities = 1 THEN 'pre_normalization_token_identity_collision'
          WHEN raw_full_unique_token_identities = 1 THEN 'product_brand_format_or_cross_source_conflict'
          WHEN raw_name_token_identities = 1 AND raw_brand_token_identities > 1 THEN 'product_brand_format_or_cross_source_conflict'
          ELSE 'unresolved_product_identity_collision'
        END AS root_cause_class
      FROM grouped
    )
    SELECT
      cr.food_item_id,
      c.root_cause_class,
      c.group_rows,
      c.raw_name_token_identities,
      c.raw_brand_token_identities,
      c.raw_full_token_identities,
      c.raw_full_unique_token_identities
    FROM collision_rows cr
    JOIN classified c USING (locale, base_key, variant_key, brand_key)
    WHERE c.root_cause_class IN (
      'pre_normalization_token_identity_collision',
      'product_brand_format_or_cross_source_conflict',
      'unresolved_product_identity_collision'
    )
  `, args.scope === "sample" ? [FOOD_NORMALIZATION_VERSION, sampleSetId] : [FOOD_NORMALIZATION_VERSION]);

  const rows = await sql`
    UPDATE food_item_quality q
    SET
      quality_status = 'suspicious',
      is_search_eligible = false,
      canonical_food_item_id = NULL,
      quality_score = 0,
      quality_flags = ARRAY(
        SELECT DISTINCT value
        FROM unnest(q.quality_flags || ARRAY['ambiguous_product_collision'::text]) AS value
        ORDER BY value
      ),
      metadata = q.metadata || jsonb_build_object(
        'ambiguousProductCollisionRootCause', e.root_cause_class,
        'ambiguousProductCollisionGroupRows', e.group_rows,
        'ambiguousProductCollisionRawNameTokenIdentities', e.raw_name_token_identities,
        'ambiguousProductCollisionRawBrandTokenIdentities', e.raw_brand_token_identities,
        'ambiguousProductCollisionRawFullTokenIdentities', e.raw_full_token_identities,
        'ambiguousProductCollisionRawFullUniqueTokenIdentities', e.raw_full_unique_token_identities
      ),
      updated_at = now()
    FROM tmp_ambiguous_product_collision_exclusions e
    WHERE q.food_item_id = e.food_item_id
    RETURNING q.food_item_id
  `;

  await sql`
    DELETE FROM food_normalized_search_documents d
    USING tmp_ambiguous_product_collision_exclusions e
    WHERE d.food_item_id = e.food_item_id
      AND d.normalization_version = ${FOOD_NORMALIZATION_VERSION}
  `;
  await sql`
    DELETE FROM food_normalization_review r
    USING tmp_ambiguous_product_collision_exclusions e
    WHERE r.food_item_id = e.food_item_id
      AND r.normalization_version = ${FOOD_NORMALIZATION_VERSION}
  `;

  return rows.length;
}

async function deleteNonValidRuntimeDocs(sql: Sql, args: Args, sampleSetId: string): Promise<number> {
  const rows = await sql.unsafe(`
    DELETE FROM food_normalized_search_documents d
    USING food_items f
    JOIN food_item_quality q ON q.food_item_id = f.id
    ${args.scope === "sample" ? `
    JOIN food_normalization_sample_items si ON si.food_item_id = f.id
    ` : ""}
    WHERE d.food_item_id = f.id
      AND d.normalization_version = $1
      ${args.scope === "sample" ? "AND si.sample_set_id = $2" : ""}
      AND (
        NOT q.is_search_eligible
        OR NOT EXISTS (
          SELECT 1
          FROM food_normalization_review r
          WHERE r.food_item_id = d.food_item_id
            AND r.normalization_version = d.normalization_version
            AND r.review_status = 'valid'
        )
      )
    RETURNING d.food_item_id
  `, args.scope === "sample" ? [FOOD_NORMALIZATION_VERSION, sampleSetId] : [FOOD_NORMALIZATION_VERSION]);
  return rows.length;
}

async function buildReport(
  sql: Sql,
  args: Args,
  result: {
    selectedRows: number;
    normalizedRows: number;
    reviewRows: number;
    runtimeDocWriteRows: number;
    runtimeDocDeleteRows: number;
    runtimeDocDeleteSkipped: boolean;
    collisionIssueRows: number;
    normalizationSignatureCacheHits: number;
    normalizationSignatureCacheMisses: number;
    longNameDecisionCounts: LongNameDecisionCounts;
    ambiguousProductCollisionRows: number;
  },
  thresholds: NormalizationReviewThresholds,
): Promise<BackfillReport> {
  const scopeReviewPredicate = args.scope === "sample"
    ? `AND EXISTS (
        SELECT 1
        FROM food_normalization_sample_items si
        JOIN food_normalization_sample_sets ss ON ss.id = si.sample_set_id
        WHERE si.food_item_id = r.food_item_id
          AND ss.name = '${args.sampleSetName.replaceAll("'", "''")}'
      )`
    : "";
  const scopeDocPredicate = args.scope === "sample"
    ? `AND EXISTS (
        SELECT 1
        FROM food_normalization_sample_items si
        JOIN food_normalization_sample_sets ss ON ss.id = si.sample_set_id
        WHERE si.food_item_id = d.food_item_id
          AND ss.name = '${args.sampleSetName.replaceAll("'", "''")}'
      )`
    : "";

  const [
    statusCounts,
    issueCounts,
    reviewByResultType,
    reviewBySource,
    docsByResultType,
    docsBySource,
    samplesByIssue,
    topDisplayCollisionGroups,
    topProductCollisionGroups,
    topOutlierGroups,
    collisionRootCauseCounts,
    targetCollisionSamples,
    excludedCollisionSamples,
    observabilityIssueCounts,
    samplesByObservabilityIssue,
    staleLongNameDecisionSamples,
  ] = await Promise.all([
    sql.unsafe(`
      SELECT review_status, severity, count(*)::int AS rows
      FROM food_normalization_review r
      WHERE normalization_version = $1
      ${scopeReviewPredicate}
      GROUP BY review_status, severity
      ORDER BY rows DESC
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT issue_code, count(*)::int AS rows
      FROM food_normalization_review r
      CROSS JOIN LATERAL unnest(r.issue_codes) AS issue_code
      WHERE normalization_version = $1
      ${scopeReviewPredicate}
      GROUP BY issue_code
      ORDER BY rows DESC, issue_code
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT
        coalesce(result_type, '') AS result_type,
        review_status,
        severity,
        count(*)::int AS rows
      FROM food_normalization_review r
      WHERE normalization_version = $1
      ${scopeReviewPredicate}
      GROUP BY result_type, review_status, severity
      ORDER BY rows DESC, result_type, review_status, severity
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT
        coalesce(raw_external_source, '') AS external_source,
        coalesce(raw_data_type, '') AS data_type,
        coalesce(result_type, '') AS result_type,
        review_status,
        count(*)::int AS rows
      FROM food_normalization_review r
      WHERE normalization_version = $1
      ${scopeReviewPredicate}
      GROUP BY raw_external_source, raw_data_type, result_type, review_status
      ORDER BY rows DESC, external_source, data_type, result_type, review_status
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT result_type, count(*)::int AS rows
      FROM food_normalized_search_documents d
      WHERE normalization_version = $1
      ${scopeDocPredicate}
      GROUP BY result_type
      ORDER BY rows DESC
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT
        coalesce(f.external_source, '') AS external_source,
        coalesce(f.data_type, '') AS data_type,
        d.result_type,
        count(*)::int AS rows
      FROM food_normalized_search_documents d
      JOIN food_items f ON f.id = d.food_item_id
      WHERE d.normalization_version = $1
      ${scopeDocPredicate}
      GROUP BY f.external_source, f.data_type, d.result_type
      ORDER BY rows DESC
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT issue_code, jsonb_agg(sample ORDER BY sample->>'rawName') AS samples
      FROM (
        SELECT
          issue_code,
          jsonb_build_object(
            'foodItemId', r.food_item_id,
            'rawName', r.raw_name,
            'rawBrand', r.raw_brand,
            'displayName', r.display_name,
            'resultType', r.result_type,
            'source', r.raw_external_source,
            'dataType', r.raw_data_type,
            'metrics', r.metrics
          ) AS sample,
          row_number() OVER (PARTITION BY issue_code ORDER BY r.raw_name, r.food_item_id) AS rn
        FROM food_normalization_review r
        CROSS JOIN LATERAL unnest(r.issue_codes) AS issue_code
        WHERE r.normalization_version = $1
        ${scopeReviewPredicate}
      ) ranked
      WHERE rn <= 10
      GROUP BY issue_code
      ORDER BY issue_code
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT
        r.locale,
        r.result_type,
        r.display_name,
        r.variant_name,
        r.brand_display,
        count(*)::int AS rows,
        jsonb_agg(
          jsonb_build_object(
            'foodItemId', r.food_item_id,
            'rawName', r.raw_name,
            'calories', f.calories,
            'proteinGrams', f.protein_grams,
            'carbsGrams', f.carbs_grams,
            'fatGrams', f.fat_grams
          )
          ORDER BY r.raw_name, r.food_item_id
        ) FILTER (WHERE row_number_sample <= 10) AS samples
      FROM (
        SELECT
          r.*,
          row_number() OVER (
            PARTITION BY r.locale, r.result_type, lower(concat_ws('|', r.display_name, coalesce(r.variant_name, ''), coalesce(r.brand_display, '')))
            ORDER BY r.raw_name, r.food_item_id
          ) AS row_number_sample
        FROM food_normalization_review r
        WHERE r.normalization_version = $1
          AND 'display_name_collision_nutrition_divergent' = ANY(r.issue_codes)
          ${scopeReviewPredicate}
      ) r
      JOIN food_items f ON f.id = r.food_item_id
      GROUP BY r.locale, r.result_type, r.display_name, r.variant_name, r.brand_display
      ORDER BY rows DESC, r.display_name, r.variant_name, r.brand_display
      LIMIT 50
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT
        r.locale,
        r.base_name,
        r.variant_name,
        r.brand_display,
        count(*)::int AS rows,
        count(DISTINCT coalesce(nullif(btrim(f.barcode), ''), nullif(btrim(f.external_id), ''), f.id::text))::int AS identities,
        jsonb_agg(
          jsonb_build_object(
            'foodItemId', r.food_item_id,
            'rawName', r.raw_name,
            'rawBrand', r.raw_brand,
            'barcode', f.barcode,
            'externalId', f.external_id,
            'calories', f.calories
          )
          ORDER BY r.raw_name, r.food_item_id
        ) FILTER (WHERE row_number_sample <= 10) AS samples
      FROM (
        SELECT
          r.*,
          row_number() OVER (
            PARTITION BY r.locale, lower(r.base_name), lower(coalesce(r.variant_name, '')), lower(coalesce(r.brand_display, ''))
            ORDER BY r.raw_name, r.food_item_id
          ) AS row_number_sample
        FROM food_normalization_review r
        WHERE r.normalization_version = $1
          AND 'product_identity_collision' = ANY(r.issue_codes)
          ${scopeReviewPredicate}
      ) r
      JOIN food_items f ON f.id = r.food_item_id
      GROUP BY r.locale, r.base_name, r.variant_name, r.brand_display
      ORDER BY rows DESC, r.base_name, r.variant_name, r.brand_display
      LIMIT 50
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT
        issue_code,
        coalesce(raw_external_source, '') AS external_source,
        coalesce(raw_data_type, '') AS data_type,
        count(*)::int AS rows
      FROM food_normalization_review r
      CROSS JOIN LATERAL unnest(r.issue_codes) AS issue_code
      WHERE r.normalization_version = $1
        AND issue_code NOT IN (
          'normalizer_returned_no_doc',
          'empty_display_name',
          'empty_base_name',
          'empty_primary_entity',
          'empty_search_text',
          'invalid_result_type',
          'invalid_locale',
          'product_empty_name',
          'generic_empty_name',
          'display_name_collision_nutrition_divergent',
          'product_identity_collision',
          'primary_secondary_token_collision'
        )
        ${scopeReviewPredicate}
      GROUP BY issue_code, raw_external_source, raw_data_type
      ORDER BY rows DESC, issue_code, external_source, data_type
      LIMIT 100
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      WITH collision_rows AS (
        SELECT
          r.food_item_id,
          r.locale,
          r.result_type,
          lower(concat_ws('|', r.display_name, coalesce(r.variant_name, ''), coalesce(r.brand_display, ''))) AS display_key,
          coalesce(nullif(r.metadata->>'rawNameTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_name, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_name_token_key,
          coalesce(nullif(r.metadata->>'rawBrandTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_brand_token_key,
          coalesce(nullif(r.metadata->>'rawFullTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_name, '') || ' ' || coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_full_token_key,
          coalesce(nullif(r.metadata->>'rawFullUniqueTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM (
              SELECT DISTINCT token
              FROM regexp_split_to_table(lower(coalesce(r.raw_name, '') || ' ' || coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
              WHERE token <> ''
            ) unique_tokens
          ), '') AS raw_full_unique_token_key,
          f.calories::numeric AS calories
        FROM food_normalization_review r
        JOIN food_items f ON f.id = r.food_item_id
        WHERE r.normalization_version = $1
          AND 'display_name_collision_nutrition_divergent' = ANY(r.issue_codes)
          ${scopeReviewPredicate}
      ),
      grouped AS (
        SELECT
          locale,
          result_type,
          display_key,
          count(*)::int AS rows,
          count(DISTINCT raw_name_token_key)::int AS raw_name_token_identities,
          count(DISTINCT raw_brand_token_key)::int AS raw_brand_token_identities,
          count(DISTINCT raw_full_token_key)::int AS raw_full_token_identities,
          count(DISTINCT raw_full_unique_token_key)::int AS raw_full_unique_token_identities,
          max(calories) - min(calories) AS calories_delta
        FROM collision_rows
        GROUP BY locale, result_type, display_key
      ),
      classified AS (
        SELECT
          *,
          CASE
            WHEN result_type = 'generic_food' AND raw_name_token_identities > 1 THEN 'generic_descriptor_token_loss'
            WHEN raw_full_token_identities = 1 THEN 'pre_normalization_token_identity_collision'
            WHEN result_type = 'product' AND raw_full_unique_token_identities = 1 THEN 'product_brand_format_or_cross_source_conflict'
            WHEN result_type = 'product' AND raw_name_token_identities > 1 THEN 'product_raw_name_token_difference'
            WHEN result_type = 'product' AND raw_name_token_identities = 1 AND raw_brand_token_identities > 1 THEN 'product_brand_format_or_cross_source_conflict'
            ELSE 'other_display_collision'
          END AS root_cause_class,
          CASE
            WHEN result_type = 'generic_food' AND raw_name_token_identities > 1 THEN 'requires_normalization_fix'
            WHEN raw_full_token_identities = 1 THEN 'pre_existing_data_collision'
            WHEN result_type = 'product' AND raw_full_unique_token_identities = 1 THEN 'data_ambiguity_excluded'
            WHEN result_type = 'product' AND raw_name_token_identities > 1 THEN 'requires_normalization_fix'
            WHEN result_type = 'product' AND raw_name_token_identities = 1 AND raw_brand_token_identities > 1 THEN 'data_ambiguity_excluded'
            ELSE 'needs_manual_review'
          END AS validation_status
        FROM grouped
      )
      SELECT
        result_type,
        root_cause_class,
        validation_status,
        count(*)::int AS groups,
        sum(rows)::int AS rows,
        max(rows)::int AS max_group_rows,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY rows)::numeric AS median_group_rows,
        max(calories_delta) AS max_calories_delta
      FROM classified
      GROUP BY result_type, root_cause_class, validation_status
      ORDER BY rows DESC, result_type, root_cause_class
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      WITH collision_rows AS (
        SELECT
          r.food_item_id,
          r.locale,
          r.result_type,
          r.display_name,
          lower(concat_ws('|', r.display_name, coalesce(r.variant_name, ''), coalesce(r.brand_display, ''))) AS display_key,
          r.raw_name,
          r.raw_brand,
          r.base_name,
          r.brand_display,
          coalesce(nullif(r.metadata->>'rawNameTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_name, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_name_token_key,
          coalesce(nullif(r.metadata->>'rawBrandTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_brand_token_key,
          coalesce(nullif(r.metadata->>'rawFullTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_name, '') || ' ' || coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_full_token_key,
          coalesce(nullif(r.metadata->>'rawFullUniqueTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM (
              SELECT DISTINCT token
              FROM regexp_split_to_table(lower(coalesce(r.raw_name, '') || ' ' || coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
              WHERE token <> ''
            ) unique_tokens
          ), '') AS raw_full_unique_token_key,
          f.calories::numeric AS calories,
          f.protein_grams::numeric AS protein_grams,
          f.carbs_grams::numeric AS carbs_grams,
          f.fat_grams::numeric AS fat_grams
        FROM food_normalization_review r
        JOIN food_items f ON f.id = r.food_item_id
        WHERE r.normalization_version = $1
          AND 'display_name_collision_nutrition_divergent' = ANY(r.issue_codes)
          ${scopeReviewPredicate}
      ),
      grouped AS (
        SELECT
          locale,
          result_type,
          display_key,
          min(display_name) AS display_name,
          count(*)::int AS rows,
          count(DISTINCT raw_name_token_key)::int AS raw_name_token_identities,
          count(DISTINCT raw_brand_token_key)::int AS raw_brand_token_identities,
          count(DISTINCT raw_full_token_key)::int AS raw_full_token_identities,
          count(DISTINCT raw_full_unique_token_key)::int AS raw_full_unique_token_identities,
          max(calories) - min(calories) AS calories_delta
        FROM collision_rows
        GROUP BY locale, result_type, display_key
      ),
      classified AS (
        SELECT
          *,
          CASE
            WHEN result_type = 'generic_food' AND raw_name_token_identities > 1 THEN 'generic_descriptor_token_loss'
            WHEN raw_full_token_identities = 1 THEN 'pre_normalization_token_identity_collision'
            WHEN result_type = 'product' AND raw_full_unique_token_identities = 1 THEN 'product_brand_format_or_cross_source_conflict'
            WHEN result_type = 'product' AND raw_name_token_identities > 1 THEN 'product_raw_name_token_difference'
            WHEN result_type = 'product' AND raw_name_token_identities = 1 AND raw_brand_token_identities > 1 THEN 'product_brand_format_or_cross_source_conflict'
            ELSE 'other_display_collision'
          END AS root_cause_class
        FROM grouped
      ),
      sampled AS (
        SELECT
          c.root_cause_class,
          c.result_type,
          c.display_name,
          c.rows,
          c.raw_name_token_identities,
          c.raw_brand_token_identities,
          c.calories_delta,
          cr.raw_name,
          cr.raw_brand,
          cr.base_name,
          cr.brand_display,
          cr.calories,
          cr.protein_grams,
          cr.carbs_grams,
          cr.fat_grams,
          row_number() OVER (
            PARTITION BY c.root_cause_class, c.result_type, c.display_key
            ORDER BY cr.calories, cr.raw_name, cr.food_item_id
          ) AS sample_rank,
          dense_rank() OVER (
            PARTITION BY c.root_cause_class
            ORDER BY c.rows DESC, c.calories_delta DESC, c.display_name
          ) AS group_rank
        FROM classified c
        JOIN collision_rows cr USING (locale, result_type, display_key)
        WHERE c.root_cause_class IN (
          'generic_descriptor_token_loss',
          'product_raw_name_token_difference',
          'other_display_collision'
        )
      )
      SELECT
        root_cause_class,
        result_type,
        display_name,
        rows,
        raw_name_token_identities,
        raw_brand_token_identities,
        calories_delta,
        jsonb_agg(
          jsonb_build_object(
            'rawName', raw_name,
            'rawBrand', raw_brand,
            'baseName', base_name,
            'brandDisplay', brand_display,
            'calories', calories,
            'proteinGrams', protein_grams,
            'carbsGrams', carbs_grams,
            'fatGrams', fat_grams
          )
          ORDER BY calories, raw_name
        ) FILTER (WHERE sample_rank <= 8) AS samples
      FROM sampled
      WHERE group_rank <= 50
      GROUP BY root_cause_class, result_type, display_name, rows, raw_name_token_identities, raw_brand_token_identities, calories_delta
      ORDER BY root_cause_class, rows DESC, calories_delta DESC, display_name
      LIMIT 100
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      WITH collision_rows AS (
        SELECT
          r.food_item_id,
          r.locale,
          r.result_type,
          r.display_name,
          lower(concat_ws('|', r.display_name, coalesce(r.variant_name, ''), coalesce(r.brand_display, ''))) AS display_key,
          r.raw_name,
          r.raw_brand,
          r.base_name,
          r.brand_display,
          coalesce(nullif(r.metadata->>'rawNameTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_name, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_name_token_key,
          coalesce(nullif(r.metadata->>'rawBrandTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_brand_token_key,
          coalesce(nullif(r.metadata->>'rawFullTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM regexp_split_to_table(lower(coalesce(r.raw_name, '') || ' ' || coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
            WHERE token <> ''
          ), '') AS raw_full_token_key,
          coalesce(nullif(r.metadata->>'rawFullUniqueTokenKey', ''), (
            SELECT string_agg(token, ' ' ORDER BY token)
            FROM (
              SELECT DISTINCT token
              FROM regexp_split_to_table(lower(coalesce(r.raw_name, '') || ' ' || coalesce(r.raw_brand, '')), '[^[:alnum:]]+') AS token
              WHERE token <> ''
            ) unique_tokens
          ), '') AS raw_full_unique_token_key,
          f.calories::numeric AS calories,
          f.protein_grams::numeric AS protein_grams,
          f.carbs_grams::numeric AS carbs_grams,
          f.fat_grams::numeric AS fat_grams
        FROM food_normalization_review r
        JOIN food_items f ON f.id = r.food_item_id
        WHERE r.normalization_version = $1
          AND 'display_name_collision_nutrition_divergent' = ANY(r.issue_codes)
          ${scopeReviewPredicate}
      ),
      grouped AS (
        SELECT
          locale,
          result_type,
          display_key,
          min(display_name) AS display_name,
          count(*)::int AS rows,
          count(DISTINCT raw_name_token_key)::int AS raw_name_token_identities,
          count(DISTINCT raw_brand_token_key)::int AS raw_brand_token_identities,
          count(DISTINCT raw_full_token_key)::int AS raw_full_token_identities,
          count(DISTINCT raw_full_unique_token_key)::int AS raw_full_unique_token_identities,
          max(calories) - min(calories) AS calories_delta
        FROM collision_rows
        GROUP BY locale, result_type, display_key
      ),
      classified AS (
        SELECT
          *,
          CASE
            WHEN result_type = 'generic_food' AND raw_name_token_identities > 1 THEN 'generic_descriptor_token_loss'
            WHEN raw_full_token_identities = 1 THEN 'pre_normalization_token_identity_collision'
            WHEN result_type = 'product' AND raw_full_unique_token_identities = 1 THEN 'product_brand_format_or_cross_source_conflict'
            WHEN result_type = 'product' AND raw_name_token_identities > 1 THEN 'product_raw_name_token_difference'
            WHEN result_type = 'product' AND raw_name_token_identities = 1 AND raw_brand_token_identities > 1 THEN 'product_brand_format_or_cross_source_conflict'
            ELSE 'other_display_collision'
          END AS root_cause_class
        FROM grouped
      ),
      sampled AS (
        SELECT
          c.root_cause_class,
          c.result_type,
          c.display_name,
          c.rows,
          c.raw_name_token_identities,
          c.raw_brand_token_identities,
          c.raw_full_token_identities,
          c.raw_full_unique_token_identities,
          c.calories_delta,
          cr.raw_name,
          cr.raw_brand,
          cr.base_name,
          cr.brand_display,
          cr.calories,
          cr.protein_grams,
          cr.carbs_grams,
          cr.fat_grams,
          row_number() OVER (
            PARTITION BY c.root_cause_class, c.result_type, c.display_key
            ORDER BY cr.calories, cr.raw_name, cr.food_item_id
          ) AS sample_rank,
          dense_rank() OVER (
            PARTITION BY c.root_cause_class
            ORDER BY c.rows DESC, c.calories_delta DESC, c.display_name
          ) AS group_rank
        FROM classified c
        JOIN collision_rows cr USING (locale, result_type, display_key)
        WHERE c.root_cause_class IN (
          'product_brand_format_or_cross_source_conflict',
          'pre_normalization_token_identity_collision'
        )
      )
      SELECT
        root_cause_class,
        result_type,
        display_name,
        rows,
        raw_name_token_identities,
        raw_brand_token_identities,
        raw_full_token_identities,
        raw_full_unique_token_identities,
        calories_delta,
        jsonb_agg(
          jsonb_build_object(
            'rawName', raw_name,
            'rawBrand', raw_brand,
            'baseName', base_name,
            'brandDisplay', brand_display,
            'calories', calories,
            'proteinGrams', protein_grams,
            'carbsGrams', carbs_grams,
            'fatGrams', fat_grams
          )
          ORDER BY calories, raw_name
        ) FILTER (WHERE sample_rank <= 8) AS samples
      FROM sampled
      WHERE group_rank <= 50
      GROUP BY root_cause_class, result_type, display_name, rows, raw_name_token_identities, raw_brand_token_identities, raw_full_token_identities, raw_full_unique_token_identities, calories_delta
      ORDER BY root_cause_class, rows DESC, calories_delta DESC, display_name
      LIMIT 100
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT issue_code, count(*)::int AS rows
      FROM food_normalization_review r
      CROSS JOIN LATERAL jsonb_array_elements_text(
        CASE
          WHEN jsonb_typeof(r.metadata->'observabilityIssueCodes') = 'array'
            THEN r.metadata->'observabilityIssueCodes'
          ELSE '[]'::jsonb
        END
      ) AS issue_code
      WHERE r.normalization_version = $1
      ${scopeReviewPredicate}
      GROUP BY issue_code
      ORDER BY rows DESC, issue_code
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT issue_code, jsonb_agg(sample ORDER BY sample->>'rawName') AS samples
      FROM (
        SELECT
          issue_code,
          jsonb_build_object(
            'foodItemId', r.food_item_id,
            'rawName', r.raw_name,
            'rawBrand', r.raw_brand,
            'displayName', r.display_name,
            'resultType', r.result_type,
            'source', r.raw_external_source,
            'dataType', r.raw_data_type,
            'metrics', r.metrics
          ) AS sample,
          row_number() OVER (PARTITION BY issue_code ORDER BY r.raw_name, r.food_item_id) AS rn
        FROM food_normalization_review r
        CROSS JOIN LATERAL jsonb_array_elements_text(
          CASE
            WHEN jsonb_typeof(r.metadata->'observabilityIssueCodes') = 'array'
              THEN r.metadata->'observabilityIssueCodes'
            ELSE '[]'::jsonb
          END
        ) AS issue_code
        WHERE r.normalization_version = $1
        ${scopeReviewPredicate}
      ) ranked
      WHERE rn <= 10
      GROUP BY issue_code
      ORDER BY issue_code
    `, [FOOD_NORMALIZATION_VERSION]),
    sql.unsafe(`
      SELECT
        r.food_item_id AS "foodItemId",
        r.raw_name AS "rawName",
        r.raw_brand AS "rawBrand",
        r.display_name AS "displayName",
        r.metadata->>'longNameDecisionInputSignature' AS "decisionInputSignature",
        r.metadata->>'expectedLongNameDecisionInputSignature' AS "expectedInputSignature"
      FROM food_normalization_review r
      WHERE r.normalization_version = $1
        AND r.metadata->>'longNameDecisionStatus' = 'stale'
        ${scopeReviewPredicate}
      ORDER BY r.raw_name, r.food_item_id
      LIMIT 25
    `, [FOOD_NORMALIZATION_VERSION]),
  ]);

  return {
    scope: args.scope,
    mode: args.mode,
    sampleSetName: args.sampleSetName,
    normalizationVersion: FOOD_NORMALIZATION_VERSION,
    generatedAt: new Date().toISOString(),
    selectedRows: result.selectedRows,
    normalizedRows: result.normalizedRows,
    reviewRows: result.reviewRows,
    runtimeDocWriteRows: result.runtimeDocWriteRows,
    runtimeDocDeleteRows: result.runtimeDocDeleteRows,
    runtimeDocDeleteSkipped: result.runtimeDocDeleteSkipped,
    collisionIssueRows: result.collisionIssueRows,
    normalizationSignatureCacheHits: result.normalizationSignatureCacheHits,
    normalizationSignatureCacheMisses: result.normalizationSignatureCacheMisses,
    longNameDecisionCounts: result.longNameDecisionCounts,
    ambiguousProductCollisionRows: result.ambiguousProductCollisionRows,
    thresholds,
    statusCounts,
    issueCounts,
    reviewByResultType,
    reviewBySource,
    docsByResultType,
    docsBySource,
    samplesByIssue,
    topDisplayCollisionGroups,
    topProductCollisionGroups,
    topOutlierGroups,
    collisionRootCauseCounts,
    targetCollisionSamples,
    excludedCollisionSamples,
    observabilityIssueCounts,
    samplesByObservabilityIssue,
    staleLongNameDecisionSamples,
  };
}

async function writeReport(report: BackfillReport, args: Args): Promise<string> {
  const directory = resolve(process.cwd(), args.reportDir ?? "../../data/food-normalization");
  await mkdir(directory, { recursive: true });
  const safeTime = report.generatedAt.replaceAll(":", "-");
  const path = resolve(directory, `review-${report.scope}-${report.mode}-${safeTime}.json`);
  await writeFile(path, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return path;
}

function printReportSummary(report: BackfillReport, path: string): void {
  console.log(`Food normalization ${report.scope}/${report.mode} report written to ${path}`);
  console.log(`Selected rows: ${report.selectedRows}`);
  console.log(`Normalized rows: ${report.normalizedRows}`);
  console.log(`Review rows: ${report.reviewRows}`);
  console.log(`Runtime doc write rows: ${report.runtimeDocWriteRows}`);
  console.log(`Runtime doc delete rows: ${report.runtimeDocDeleteRows}`);
  console.log(`Runtime doc delete skipped: ${report.runtimeDocDeleteSkipped}`);
  console.log(`Collision issue rows: ${report.collisionIssueRows}`);
  console.log(`Ambiguous product collision rows excluded: ${report.ambiguousProductCollisionRows}`);
  console.log(`Normalization signature cache hits: ${report.normalizationSignatureCacheHits}`);
  console.log(`Normalization signature cache misses: ${report.normalizationSignatureCacheMisses}`);
  console.log(`Long-name decision counts: ${JSON.stringify(report.longNameDecisionCounts)}`);
  console.log(`Collision root cause counts: ${JSON.stringify(report.collisionRootCauseCounts)}`);
  console.log(`Blocking collision sample groups: ${report.targetCollisionSamples.length}`);
  console.log(`Excluded collision sample groups: ${report.excludedCollisionSamples.length}`);
  console.table(report.statusCounts);
  console.table(report.issueCounts);
  console.table(report.reviewByResultType);
  console.table(report.reviewBySource);
  console.table(report.docsByResultType);
  console.table(report.docsBySource);
  console.table(report.topOutlierGroups);
  console.table(report.observabilityIssueCounts);
}

function reviewRecord(
  row: FoodRow,
  doc: NormalizedFoodSearchDocumentInput | undefined,
  review: NormalizationReviewResult,
  longNameDecision: LongNameDecisionApplication,
): ReviewRecord {
  const longNameDecisionMetadata = longNameDecisionReviewMetadata(longNameDecision);
  return {
    foodItemId: String(row.id),
    normalizationVersion: doc?.normalizationVersion ?? FOOD_NORMALIZATION_VERSION,
    reviewStatus: review.reviewStatus,
    severity: review.severity,
    issueCodes: review.issueCodes,
    rawName: String(row.name ?? ""),
    rawBrand: optionalString(row.brand),
    rawSource: optionalString(row.source),
    rawExternalSource: optionalString(row.external_source),
    rawDataType: optionalString(row.data_type),
    displayName: doc?.displayName,
    baseName: doc?.baseName,
    variantName: doc?.variantName,
    brandDisplay: doc?.brandDisplay,
    primaryEntityName: doc?.primaryEntityName,
    locale: doc?.locale,
    resultType: doc?.resultType,
    normalizationConfidence: doc?.normalizationConfidence,
    metrics: review.metrics,
    metadata: {
      ...doc?.metadata,
      observabilityIssueCodes: review.observabilityIssueCodes,
      ...longNameDecisionMetadata,
      sourceUrl: optionalString(row.source_url),
      externalId: optionalString(row.external_id),
      rawNameTokenKey: normalizedTokenKey(optionalString(row.name)),
      rawBrandTokenKey: normalizedTokenKey(optionalString(row.brand)),
      rawFullTokenKey: normalizedTokenKey(optionalString(row.name), optionalString(row.brand)),
      rawFullUniqueTokenKey: normalizedUniqueTokenKey(optionalString(row.name), optionalString(row.brand)),
    },
  };
}

function longNameDecisionReviewMetadata(
  longNameDecision: LongNameDecisionApplication,
): Record<string, unknown> {
  if (longNameDecision.status === "none") return {};
  if (longNameDecision.status === "applied") {
    return {
      longNameDecisionStatus: "applied",
      longNameDecisionInputSignature: longNameDecision.decision.inputSignature,
      longNameDecisionSource: longNameDecision.decision.decisionSource,
    };
  }
  if (longNameDecision.status === "stale") {
    return {
      longNameDecisionStatus: "stale",
      longNameDecisionInputSignature: longNameDecision.decision.inputSignature,
      expectedLongNameDecisionInputSignature: longNameDecision.expectedInputSignature,
      longNameDecisionSource: longNameDecision.decision.decisionSource,
    };
  }
  return {
    longNameDecisionStatus: "rejected",
    longNameDecisionInputSignature: longNameDecision.decision.inputSignature,
    longNameDecisionSource: longNameDecision.decision.decisionSource,
  };
}

function parseArgs(argv: string[], requiredDbName?: string, requiredSchema?: string): Args {
  const parsed: Args = {
    scope: "sample",
    mode: "apply",
    batchSize: DEFAULT_BATCH_SIZE,
    sampleSetName: NORMALIZED_SEARCH_SAMPLE_SET,
    excludeAmbiguousProductCollisions: false,
    requiredDbName,
    requiredSchema,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--scope") parsed.scope = parseScope(requiredValue(argv, ++index, arg));
    else if (arg === "--mode") parsed.mode = parseMode(requiredValue(argv, ++index, arg));
    else if (arg === "--batch-size") parsed.batchSize = parsePositiveInteger(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--resume-after") parsed.resumeAfter = requiredValue(argv, ++index, arg);
    else if (arg === "--sample-set") parsed.sampleSetName = requiredValue(argv, ++index, arg);
    else if (arg === "--report-dir") parsed.reportDir = requiredValue(argv, ++index, arg);
    else if (arg === "--long-name-decisions") parsed.longNameDecisionsPath = requiredValue(argv, ++index, arg);
    else if (arg === "--exclude-ambiguous-product-collisions") parsed.excludeAmbiguousProductCollisions = true;
    else throw new Error(`Unknown argument "${arg}".`);
  }

  return parsed;
}

function parseScope(value: string): BackfillScope {
  if (value === "sample" || value === "full") return value;
  throw new Error(`Invalid --scope "${value}". Use sample or full.`);
}

function parseMode(value: string): BackfillMode {
  if (value === "audit" || value === "apply") return value;
  throw new Error(`Invalid --mode "${value}". Use audit or apply.`);
}

function parsePositiveInteger(value: string, name: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer.`);
  return parsed;
}

function normalizedTokenKey(...values: Array<string | undefined>): string {
  return normalizedTokenList(values).sort().join(" ");
}

function normalizedUniqueTokenKey(...values: Array<string | undefined>): string {
  return [...new Set(normalizedTokenList(values))].sort().join(" ");
}

function normalizedTokenList(values: Array<string | undefined>): string[] {
  return normalizeText(values.filter((value): value is string => Boolean(value)).join(" "))
    .split(/\s+/)
    .filter(Boolean);
}

function requiredValue(argv: string[], index: number, flag: string): string {
  const value = argv[index];
  if (!value) throw new Error(`${flag} requires a value.`);
  return value;
}

function normalizationSignature(row: FoodRow): string {
  return JSON.stringify({
    userId: optionalString(row.user_id),
    source: optionalString(row.source),
    externalSource: optionalString(row.external_source),
    dataType: optionalString(row.data_type),
    foodKey: optionalString(row.food_key),
    name: optionalString(row.name),
    normalizedName: optionalString(row.normalized_name),
    canonicalName: optionalString(row.canonical_name),
    brand: optionalString(row.brand),
    foodCategory: optionalString(row.food_category),
    marketCountry: optionalString(row.market_country),
    normalizationVersion: FOOD_NORMALIZATION_VERSION,
  });
}

function disambiguateGenericDisplayCollisions(
  rows: FoodRow[],
  docs: NormalizedFoodSearchDocumentInput[],
): NormalizedFoodSearchDocumentInput[] {
  const rowByFoodId = new Map(rows.map((row) => [String(row.id), row]));
  const groups = new Map<string, NormalizedFoodSearchDocumentInput[]>();
  for (const doc of docs) {
    if (doc.resultType !== "generic_food") continue;
    const displayKey = normalizeText(doc.displayName);
    if (!displayKey) continue;
    const key = [doc.locale, doc.resultType, displayKey].join("|");
    const group = groups.get(key) ?? [];
    group.push(doc);
    groups.set(key, group);
  }

  const replacements = new Map<string, NormalizedFoodSearchDocumentInput>();
  for (const group of groups.values()) {
    if (group.length <= 1) continue;
    const nutrition = group
      .map((doc) => rowByFoodId.get(doc.foodItemId))
      .filter((row): row is FoodRow => Boolean(row))
      .map((row) => ({
        calories: Number(row.calories),
        proteinGrams: Number(row.protein_grams),
        carbsGrams: Number(row.carbs_grams),
        fatGrams: Number(row.fat_grams),
      }));
    if (!nutritionDiverges(nutrition)) continue;

    const descriptorsByFoodId = new Map<string, string[]>();
    const descriptorFrequency = new Map<string, number>();
    for (const doc of group) {
      const descriptors = hiddenDisambiguationDescriptors(doc);
      descriptorsByFoodId.set(doc.foodItemId, descriptors);
      for (const descriptorKey of new Set(descriptors.map(normalizeText))) {
        descriptorFrequency.set(descriptorKey, (descriptorFrequency.get(descriptorKey) ?? 0) + 1);
      }
    }

    for (const doc of group) {
      const descriptors = descriptorsByFoodId.get(doc.foodItemId) ?? [];
      const differentiatingDescriptors = descriptors
        .filter((descriptor) => (descriptorFrequency.get(normalizeText(descriptor)) ?? 0) < group.length)
        .sort((left, right) => (
          normalizedTokenCount(left) - normalizedTokenCount(right)
        ));
      if (differentiatingDescriptors.length === 0) continue;
      replacements.set(doc.foodItemId, appendVariantDescriptors(doc, differentiatingDescriptors));
    }
  }

  return docs.map((doc) => replacements.get(doc.foodItemId) ?? doc);
}

function hiddenDisambiguationDescriptors(doc: NormalizedFoodSearchDocumentInput): string[] {
  const visible = normalizeText([doc.displayName, doc.baseName, doc.variantName].filter(Boolean).join(" "));
  return stringArray(doc.metadata.hiddenDescriptors)
    .filter(isDisambiguatingHiddenDescriptor)
    .filter((descriptor) => !visible.includes(normalizeText(descriptor)))
    .map(displayDescriptor)
    .filter(Boolean);
}

function isDisambiguatingHiddenDescriptor(descriptor: string): boolean {
  const normalized = normalizeText(descriptor);
  if (!normalized) return false;
  return !(
    normalized.includes("food distribution program") ||
    normalized.includes("includes foods for") ||
    normalized === "usda" ||
    normalized === "usdas" ||
    normalized === "commodity" ||
    normalized === "commercial" ||
    normalized === "commercially prepared" ||
    normalized === "retail" ||
    normalized === "store"
  );
}

function appendVariantDescriptors(
  doc: NormalizedFoodSearchDocumentInput,
  descriptors: string[],
): NormalizedFoodSearchDocumentInput {
  const existingVariantDescriptors = doc.variantName
    ? doc.variantName.split(",").map((value) => value.trim()).filter(Boolean)
    : [];
  const additionalDescriptors = descriptors
    .map(displayDescriptor)
    .filter((descriptor) => !normalizeText(doc.displayName).includes(normalizeText(descriptor)));
  const boundedVariant = descriptorsWithinTokenLimit(
    dedupeByNormalizedText([...additionalDescriptors, ...existingVariantDescriptors]),
    Math.max(0, 18 - normalizedTokenCount(doc.baseName)),
  );
  const variantDescriptors = boundedVariant.retained;
  const variantName = variantDescriptors.join(", ") || undefined;
  const displayName = [doc.baseName, variantName].filter(Boolean).join(", ");
  const appendedKeys = new Set(boundedVariant.retained.map(normalizeText));
  const retainedDescriptors = dedupeByNormalizedText([
    ...stringArray(doc.metadata.retainedDescriptors),
    ...boundedVariant.retained,
  ]);
  const hiddenDescriptors = stringArray(doc.metadata.hiddenDescriptors)
    .filter((descriptor) => !appendedKeys.has(normalizeText(descriptor)));
  const secondaryEntityAliases = dedupeByNormalizedText([
    ...doc.secondaryEntityAliases,
    ...boundedVariant.retained.map(normalizeText),
  ]);
  const metadata = {
    ...doc.metadata,
    retainedDescriptors,
    hiddenDescriptors: dedupeByNormalizedText([...hiddenDescriptors, ...boundedVariant.overflow]),
    collisionDisambiguationDescriptors: boundedVariant.retained,
  };

  return {
    ...doc,
    displayName,
    variantName,
    secondaryEntityAliases,
    searchText: rebuildSearchText(doc, displayName, variantName, secondaryEntityAliases, metadata),
    metadata,
  };
}

function rebuildSearchText(
  doc: NormalizedFoodSearchDocumentInput,
  displayName: string,
  variantName: string | undefined,
  secondaryEntityAliases: string[],
  metadata: Record<string, unknown>,
): string {
  return buildBoundedSearchText([
    displayName,
    doc.baseName,
    variantName,
    doc.brandDisplay,
    doc.primaryEntityName,
    ...doc.primaryEntityAliases,
    ...secondaryEntityAliases,
    optionalString(metadata.barcode),
    optionalString(metadata.foodCategory),
  ]);
}

function buildBoundedSearchText(values: Array<string | undefined>, maxTokens = 80): string {
  const fields = dedupeByNormalizedText(values.filter((value): value is string => Boolean(value)))
    .map(normalizeText)
    .filter(Boolean);
  const retainedFields: string[] = [];
  let tokenTotal = 0;
  for (const field of fields) {
    const tokens = field.split(/\s+/).filter(Boolean);
    if (tokens.length === 0) continue;
    if (tokenTotal + tokens.length > maxTokens) {
      const remaining = maxTokens - tokenTotal;
      if (remaining > 0) retainedFields.push(tokens.slice(0, remaining).join(" "));
      break;
    }
    retainedFields.push(field);
    tokenTotal += tokens.length;
  }
  return retainedFields.join(" ");
}

function descriptorsWithinTokenLimit(descriptors: string[], maxTokens: number): {
  retained: string[];
  overflow: string[];
} {
  const retained: string[] = [];
  const overflow: string[] = [];
  let tokenTotal = 0;
  for (const descriptor of descriptors) {
    const count = normalizedTokenCount(descriptor);
    if (count === 0) continue;
    if (tokenTotal + count <= maxTokens) {
      retained.push(descriptor);
      tokenTotal += count;
    } else {
      overflow.push(descriptor);
    }
  }
  return { retained, overflow };
}

function normalizedTokenCount(value: string): number {
  return normalizeText(value).split(/\s+/).filter(Boolean).length;
}

function displayDescriptor(value: string): string {
  return value
    .toLowerCase()
    .replace(/\b[\p{L}\p{N}][\p{L}\p{N}'%-]*/gu, (word) => {
      if (/^\d/.test(word)) return word;
      return `${word[0]?.toUpperCase() ?? ""}${word.slice(1)}`;
    })
    .trim();
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0)
    : [];
}

function dedupeByNormalizedText(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const key = normalizeText(value);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(value);
  }
  return result;
}

function applyPrimaryEntityCategoryCoherence(
  docs: NormalizedFoodSearchDocumentInput[],
): NormalizedFoodSearchDocumentInput[] {
  const categoryCounts = new Map<string, Map<string, number>>();
  for (const doc of docs) {
    if (doc.resultType !== "generic_food") continue;
    const entityKey = doc.primaryEntityName.trim().toLowerCase();
    const category = optionalString(doc.metadata.foodCategory);
    if (!entityKey || !category) continue;
    const counts = categoryCounts.get(entityKey) ?? new Map<string, number>();
    counts.set(category, (counts.get(category) ?? 0) + 1);
    categoryCounts.set(entityKey, counts);
  }

  const categoryStats = new Map<string, { dominantCategory: string; counts: Map<string, number>; total: number }>();
  for (const [entityKey, counts] of categoryCounts.entries()) {
    const entries = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
    const total = entries.reduce((sum, [, count]) => sum + count, 0);
    const dominantCategory = entries[0]?.[0];
    if (!dominantCategory || total === 0) continue;
    categoryStats.set(entityKey, { dominantCategory, counts, total });
  }

  const docsWithCategory = docs.map((doc) => {
    if (doc.resultType !== "generic_food") {
      return {
        ...doc,
        primaryEntityCategory: optionalString(doc.metadata.foodCategory),
        primaryEntityCategoryCoherence: 0,
      };
    }
    const entityKey = doc.primaryEntityName.trim().toLowerCase();
    const category = optionalString(doc.metadata.foodCategory);
    const stats = categoryStats.get(entityKey);
    if (!entityKey || !category || !stats) {
      return {
        ...doc,
        primaryEntityCategory: stats?.dominantCategory ?? category,
        primaryEntityCategoryCoherence: 0,
      };
    }
    return {
      ...doc,
      primaryEntityCategory: stats.dominantCategory,
      primaryEntityCategoryCoherence: roundFour((stats.counts.get(category) ?? 0) / stats.total),
    };
  });

  return applyPrimaryEntityRepresentativeness(docsWithCategory);
}

function applyPrimaryEntityRepresentativeness(
  docs: NormalizedFoodSearchDocumentInput[],
): NormalizedFoodSearchDocumentInput[] {
  const entityStats = new Map<string, { total: number; tokenCounts: Map<string, number> }>();

  for (const doc of docs) {
    if (doc.resultType !== "generic_food") continue;
    const entityKey = normalizeText(doc.primaryEntityName);
    if (!entityKey) continue;
    const stats = entityStats.get(entityKey) ?? { total: 0, tokenCounts: new Map<string, number>() };
    stats.total += 1;
    for (const token of primaryEntityNormalizedTokens(doc)) {
      stats.tokenCounts.set(token, (stats.tokenCounts.get(token) ?? 0) + 1);
    }
    entityStats.set(entityKey, stats);
  }

  return docs.map((doc) => {
    if (doc.resultType !== "generic_food") {
      return { ...doc, primaryEntityRepresentativeness: 0 };
    }
    const entityKey = normalizeText(doc.primaryEntityName);
    const stats = entityStats.get(entityKey);
    if (!entityKey || !stats) {
      return { ...doc, primaryEntityRepresentativeness: 0 };
    }
    return {
      ...doc,
      primaryEntityRepresentativeness: roundFour(primaryEntityRepresentativeness(doc, stats)),
    };
  });
}

function primaryEntityRepresentativeness(
  doc: NormalizedFoodSearchDocumentInput,
  stats: { total: number; tokenCounts: Map<string, number> },
): number {
  const tokens = primaryEntityNormalizedTokens(doc);
  if (tokens.length === 0) return 1;
  if (stats.total <= 1) return 0.5;

  const averageTokenFrequency = tokens.reduce((total, token) =>
    total + ((stats.tokenCounts.get(token) ?? 0) / stats.total), 0) / tokens.length;
  const rareTokenPenalty = 1 - averageTokenFrequency;
  const tokenCountPenalty = Math.min(0.25, Math.log1p(tokens.length) * 0.08);
  return clamp(1 - rareTokenPenalty * 0.65 - tokenCountPenalty, 0, 1);
}

function primaryEntityNormalizedTokens(doc: NormalizedFoodSearchDocumentInput): string[] {
  return normalizeText([doc.baseName, doc.variantName].filter(Boolean).join(" "))
    .split(/\s+/)
    .filter(Boolean);
}

function mapFood(row: FoodRow): FoodItemRecord {
  return {
    id: row.id as string,
    userId: optionalString(row.user_id),
    name: row.name as string,
    normalizedName: row.normalized_name as string,
    canonicalName: optionalString(row.canonical_name),
    brand: optionalString(row.brand),
    barcode: optionalString(row.barcode),
    source: row.source as string,
    externalSource: optionalString(row.external_source),
    externalId: optionalString(row.external_id),
    sourceUrl: optionalString(row.source_url),
    license: optionalString(row.license),
    fetchedAt: row.fetched_at ? toIso(row.fetched_at) : undefined,
    dataType: optionalString(row.data_type),
    foodCategory: optionalString(row.food_category),
    publicationDate: row.publication_date ? String(row.publication_date).slice(0, 10) : undefined,
    ndbNumber: optionalString(row.ndb_number),
    foodKey: optionalString(row.food_key),
    ingredients: optionalString(row.ingredients),
    marketCountry: optionalString(row.market_country),
    householdServingFulltext: optionalString(row.household_serving_fulltext),
    nutrients: isRecord(row.nutrients_json) ? row.nutrients_json : undefined,
    portions: [],
    servingGrams: Number(row.serving_grams),
    calories: Number(row.calories),
    proteinGrams: Number(row.protein_grams),
    carbsGrams: Number(row.carbs_grams),
    fatGrams: Number(row.fat_grams),
  };
}

function normalizeQualityFlags(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function roundFour(value: number): number {
  return Math.round(value * 10000) / 10000;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function toIso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : new Date(value as string).toISOString();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
