import { mkdir, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { Sql } from "postgres";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { NORMALIZED_SEARCH_SAMPLE_SET } from "../src/foodData/constants.js";
import { normalizedIdentityTokenKeys } from "../src/foodData/normalization.js";
import { PostgresRepository } from "../src/repository/postgres.js";
import type { FoodSearchCandidate } from "../src/repository/types.js";
import { normalizeText } from "../src/utils/normalize.js";

type BenchmarkMode = "legacy" | "normalized";
type CliMode = BenchmarkMode | "compare";
type BenchmarkScope = "sample" | "full";
type BenchmarkComparisonKind = "single_database_modes" | "cross_database";
type BenchmarkTargetRole = "single" | "baseline" | "candidate";
type CaseKind = "broad_generic" | "brand_intent" | "barcode";
type ResultType = "generic_food" | "product" | "custom_food";

export type BenchmarkTarget = {
  label: string;
  role: BenchmarkTargetRole;
  mode: BenchmarkMode;
  scope: BenchmarkScope;
  sampleSetName: string;
  databaseUrl: string;
  databaseName: string;
};

export type BenchmarkCase = {
  id: string;
  query: string;
  locale: string;
  kind: CaseKind;
  barcode?: string;
  expectedTopName?: string;
  expectedTopBarcode?: string;
  relevant?: RelevanceJudgment[];
};

export type RelevanceJudgment = {
  name?: string;
  barcode?: string;
  grade: number;
};

export type LatencySummary = {
  min: number;
  p50: number;
  p90: number;
  p99: number;
  max: number;
  average: number;
};

export type DuplicateFlood = {
  maxDuplicateCount: number;
  uniqueDisplayRatio: number;
  floodedDisplayNames: Array<{ displayName: string; count: number }>;
};

export type SearchResultRow = {
  rank: number;
  foodId: string;
  returnedName: string;
  rawName?: string;
  normalizedDisplayName?: string;
  brand?: string;
  barcode?: string;
  source: string;
  externalSource?: string;
  dataType?: string;
  resultType: ResultType;
  qualityStatus?: string;
  isSearchEligible?: boolean;
  qualityFlags: string[];
  inNormalizedSample: boolean;
  lexicalScore: number;
  finalScore: number;
};

export type SearchRun = {
  targetLabel: string;
  targetRole: BenchmarkTargetRole;
  mode: BenchmarkMode;
  scope: BenchmarkScope;
  caseId: string;
  query: string;
  locale: string;
  kind: CaseKind;
  topK: number;
  latenciesMs: number[];
  latency: LatencySummary;
  topResult?: SearchResultRow;
  results: SearchResultRow[];
  sourceResultTypeMix: Array<{ source: string; resultType: ResultType; rows: number }>;
  duplicateFlood: DuplicateFlood;
  quarantinedRows: number;
  ineligibleRows: number;
  outsideSampleRows: number;
  knownBadRows: number;
  sampledGenericCoverage: boolean;
  sampledGenericCoverageCount: number;
  mrr: number | null;
  ndcgAt5: number | null;
  ndcgAt10: number | null;
  checks: AcceptanceCheck[];
};

export type AcceptanceCheck = {
  name: string;
  ok: boolean;
  detail?: string;
};

export type CaseComparison = {
  caseId: string;
  query: string;
  baselineTargetLabel: string;
  candidateTargetLabel: string;
  baselineP50Ms: number;
  candidateP50Ms: number;
  baselineP90Ms: number;
  candidateP90Ms: number;
  p50Ratio: number | null;
  p90Ratio: number | null;
  baselineTopResult?: string;
  candidateTopResult?: string;
  duplicateMaxDelta: number;
  uniqueDisplayRatioDelta: number;
  candidateQualityOk: boolean;
  latencyOk: boolean;
  ok: boolean;
};

export type SqlProfileSummary = {
  targetLabel: string;
  caseId: string;
  query: string;
  locale: string;
  rawPlanFile: string;
  planningTimeMs: number;
  executionTimeMs: number;
  actualRows: number;
  indexNames: string[];
  sequentialScans: string[];
  sharedHitBlocks: number;
  sharedReadBlocks: number;
  rawPlan?: unknown;
};

type BenchmarkReport = {
  runId: string;
  generatedAt: string;
  comparisonKind: BenchmarkComparisonKind;
  scope: BenchmarkScope;
  sampleSetName: string;
  topK: number;
  iterations: number;
  warmup: number;
  cases: BenchmarkCase[];
  modes: BenchmarkMode[];
  targets: Array<Omit<BenchmarkTarget, "databaseUrl">>;
  modeLatency: Record<BenchmarkMode, LatencySummary | undefined>;
  targetLatency: Record<string, LatencySummary | undefined>;
  caseComparisons: CaseComparison[];
  sqlProfiles: SqlProfileSummary[];
  globalChecks: AcceptanceCheck[];
  runs: SearchRun[];
  ok: boolean;
};

export type Args = {
  mode: CliMode;
  scope: BenchmarkScope;
  caseId?: string;
  topK: number;
  iterations: number;
  warmup: number;
  repeat: number;
  reportOnly: boolean;
  outputDir?: string;
  sampleSetName: string;
  baselineDbUrl?: string;
  candidateDbUrl?: string;
  baselineLabel: string;
  candidateLabel: string;
  profileSql: boolean;
  profileTopN: number;
};

type ResultMetadata = {
  foodId: string;
  rawName: string;
  normalizedDisplayName?: string;
  brand?: string;
  barcode?: string;
  source: string;
  externalSource?: string;
  dataType?: string;
  resultType: ResultType;
  qualityStatus?: string;
  isSearchEligible?: boolean;
  qualityFlags: string[];
  inNormalizedSample: boolean;
};

const DEFAULT_TOP_K = 10;
const DEFAULT_ITERATIONS = 5;
const DEFAULT_WARMUP = 1;
const DEFAULT_PROFILE_TOP_N = 5;
const DUPLICATE_MAX_COUNT = 2;
const DUPLICATE_MIN_UNIQUE_RATIO = 0.8;
const NORMALIZED_REQUIRED_SPEED_RATIO = 0.75;
const NORMALIZED_ALLOWED_CASE_SLOWDOWN = 1.1;
const NORMALIZED_ALLOWED_CASE_ABSOLUTE_MS = 10;
const KNOWN_BAD_ZERO_CALORIE_RICE_ID = "ffa54544-2a80-4fa0-adf0-9f7662a50ac6";

const BASE_CASES: BenchmarkCase[] = [
  { id: "rice", query: "rice", locale: "en", kind: "broad_generic" },
  { id: "arroz", query: "arroz", locale: "es", kind: "broad_generic" },
  {
    id: "arroz-goya",
    query: "arroz goya",
    locale: "es",
    kind: "brand_intent",
    expectedTopName: "Arroz - Goya",
    relevant: [{ name: "Arroz - Goya", grade: 3 }],
  },
  { id: "chicken-breast", query: "chicken breast", locale: "en", kind: "broad_generic" },
  { id: "ground-beef", query: "ground beef", locale: "en", kind: "broad_generic" },
  { id: "ground-turkey", query: "ground turkey", locale: "en", kind: "broad_generic" },
  { id: "ground-pork", query: "ground pork", locale: "en", kind: "broad_generic" },
  { id: "ground-lamb", query: "ground lamb", locale: "en", kind: "broad_generic" },
  { id: "ground-chicken", query: "ground chicken", locale: "en", kind: "broad_generic" },
  { id: "egg", query: "egg", locale: "en", kind: "broad_generic" },
  { id: "milk", query: "milk", locale: "en", kind: "broad_generic" },
  { id: "apple", query: "apple", locale: "en", kind: "broad_generic" },
  { id: "yogur-natural", query: "yogur natural", locale: "es", kind: "broad_generic" },
  { id: "oats", query: "oats", locale: "en", kind: "broad_generic" },
  { id: "lentils", query: "lentils", locale: "en", kind: "broad_generic" },
  { id: "lentejas", query: "lentejas", locale: "es", kind: "broad_generic" },
  { id: "beans", query: "beans", locale: "en", kind: "broad_generic" },
  { id: "frijoles", query: "frijoles", locale: "es", kind: "broad_generic" },
  { id: "potato", query: "potato", locale: "en", kind: "broad_generic" },
  { id: "patata", query: "patata", locale: "es", kind: "broad_generic" },
  { id: "tomato", query: "tomato", locale: "en", kind: "broad_generic" },
  { id: "tomate", query: "tomate", locale: "es", kind: "broad_generic" },
  { id: "banana", query: "banana", locale: "en", kind: "broad_generic" },
  { id: "platano", query: "platano", locale: "es", kind: "broad_generic" },
  { id: "olive-oil", query: "olive oil", locale: "en", kind: "broad_generic" },
  { id: "aceite-oliva", query: "aceite oliva", locale: "es", kind: "broad_generic" },
  { id: "bread", query: "bread", locale: "en", kind: "broad_generic" },
  { id: "pan", query: "pan", locale: "es", kind: "broad_generic" },
  { id: "salmon", query: "salmon", locale: "en", kind: "broad_generic" },
  { id: "tuna", query: "tuna", locale: "en", kind: "broad_generic" },
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const reports: BenchmarkReport[] = [];
  for (let runIndex = 0; runIndex < args.repeat; runIndex += 1) {
    const report = await runBenchmark(args);
    reports.push(report);
    await writeReports(report, args);
    printReportSummary(report);
    if (!report.ok && !args.reportOnly) {
      process.exitCode = 1;
      break;
    }
  }
  if (reports.length > 1) {
    console.log(`Completed ${reports.length} benchmark runs.`);
  }
}

async function runBenchmark(args: Args): Promise<BenchmarkReport> {
  const config = loadConfig();
  const targets = buildBenchmarkTargets(args, config.DATABASE_URL);
  const modes = uniqueStrings(targets.map((target) => target.mode)) as BenchmarkMode[];
  const comparisonKind: BenchmarkComparisonKind = targets.some((target) => target.role === "baseline" || target.role === "candidate")
    ? "cross_database"
    : "single_database_modes";
  const runId = new Date().toISOString().replace(/[:.]/g, "-");
  const contexts = targets.map((target) => ({
    target,
    client: createDbClient(target.databaseUrl, { max: 1 }),
    repository: new PostgresRepository(target.databaseUrl, {
      normalizedSearchEnabled: target.mode === "normalized",
      normalizedSearchScope: target.scope,
      normalizedSearchSampleSet: target.sampleSetName,
    }),
  }));
  const discoveryContext = contexts.find((context) => context.target.role === "candidate") ??
    contexts.find((context) => context.target.mode === "normalized") ??
    contexts[0];
  if (!discoveryContext) throw new Error("No benchmark targets configured.");

  try {
    const cases = await selectCases(discoveryContext.client.sql, args);
    const runs: SearchRun[] = [];
    for (const benchmarkCase of cases) {
      const sampledGenericCoverageCount = await countSampledGenericCoverage(discoveryContext.client.sql, benchmarkCase, args);
      for (const context of contexts) {
        runs.push(await runCase(context.repository, context.client.sql, benchmarkCase, context.target, args, sampledGenericCoverageCount));
      }
    }

    const modeLatency = summarizeModeLatency(runs, modes);
    const targetLatency = summarizeTargetLatency(runs, targets);
    const caseComparisons = buildCaseComparisons(runs);
    const globalChecks = evaluateGlobalChecks(runs, modeLatency, modes);
    const sqlProfiles = args.profileSql
      ? await profileSlowCandidateRuns(contexts, runs, args)
      : [];
    const ok = [...globalChecks, ...runs.flatMap((run) => run.checks)].every((check) => check.ok);
    return {
      runId,
      generatedAt: new Date().toISOString(),
      comparisonKind,
      scope: args.scope,
      sampleSetName: args.sampleSetName,
      topK: args.topK,
      iterations: args.iterations,
      warmup: args.warmup,
      cases,
      modes,
      targets: targets.map(({ databaseUrl: _databaseUrl, ...target }) => target),
      modeLatency,
      targetLatency,
      caseComparisons,
      sqlProfiles,
      globalChecks,
      runs,
      ok,
    };
  } finally {
    for (const context of contexts) {
      await context.repository.close();
      await context.client.close();
    }
  }
}

async function runCase(
  repository: PostgresRepository,
  sql: Sql,
  benchmarkCase: BenchmarkCase,
  target: BenchmarkTarget,
  args: Args,
  sampledGenericCoverageCount: number,
): Promise<SearchRun> {
  for (let index = 0; index < args.warmup; index += 1) {
    await repository.searchFoodsHybrid(benchmarkUserId(target, benchmarkCase.id, `warmup-${index}`), searchInput(benchmarkCase, args.topK));
  }

  const latenciesMs: number[] = [];
  let lastResults: FoodSearchCandidate[] = [];
  for (let index = 0; index < args.iterations; index += 1) {
    const start = performance.now();
    lastResults = await repository.searchFoodsHybrid(benchmarkUserId(target, benchmarkCase.id, `run-${index}`), searchInput(benchmarkCase, args.topK));
    latenciesMs.push(roundMs(performance.now() - start));
  }

  const metadata = await loadResultMetadata(sql, lastResults.map((result) => result.id), target);
  const rows = lastResults.slice(0, args.topK).map((result, index) => {
    const item = metadata.get(result.id);
    return toSearchResultRow(result, item, index + 1);
  });
  const duplicateFlood = detectDuplicateFlood(rows.map((row) => row.returnedName));
  const run: SearchRun = {
    targetLabel: target.label,
    targetRole: target.role,
    mode: target.mode,
    scope: target.scope,
    caseId: benchmarkCase.id,
    query: benchmarkCase.query,
    locale: benchmarkCase.locale,
    kind: benchmarkCase.kind,
    topK: args.topK,
    latenciesMs,
    latency: percentileSummary(latenciesMs),
    topResult: rows[0],
    results: rows,
    sourceResultTypeMix: aggregateSourceResultTypeMix(rows),
    duplicateFlood,
    quarantinedRows: rows.filter((row) => row.qualityStatus === "quarantined").length,
    ineligibleRows: rows.filter((row) => row.isSearchEligible === false).length,
    outsideSampleRows: target.mode === "normalized" ? rows.filter((row) => !row.inNormalizedSample).length : 0,
    knownBadRows: rows.filter((row) => row.foodId === KNOWN_BAD_ZERO_CALORIE_RICE_ID).length,
    sampledGenericCoverage: sampledGenericCoverageCount > 0,
    sampledGenericCoverageCount,
    mrr: benchmarkCase.relevant ? reciprocalRank(rows, benchmarkCase.relevant) : null,
    ndcgAt5: benchmarkCase.relevant ? ndcgAt(rows, benchmarkCase.relevant, 5) : null,
    ndcgAt10: benchmarkCase.relevant ? ndcgAt(rows, benchmarkCase.relevant, 10) : null,
    checks: [],
  };
  run.checks = evaluateRunChecks(run, benchmarkCase);
  return run;
}

function searchInput(benchmarkCase: BenchmarkCase, limit: number) {
  return {
    query: benchmarkCase.query,
    locale: benchmarkCase.locale,
    barcode: benchmarkCase.barcode,
    limit,
  };
}

function benchmarkUserId(target: Pick<BenchmarkTarget, "label" | "mode">, caseId: string, iteration: string): string {
  const hash = stableHash(`${target.label}:${target.mode}:${caseId}:${iteration}`).slice(0, 12);
  return `00000000-0000-4000-8000-${hash}`;
}

async function selectCases(sql: Sql, args: Args): Promise<BenchmarkCase[]> {
  const cases = [...BASE_CASES];
  const barcodeCase = await discoverBarcodeCase(sql, args);
  if (barcodeCase) cases.push(barcodeCase);
  const selected = args.caseId ? cases.filter((item) => item.id === args.caseId) : cases;
  if (selected.length === 0) throw new Error(`No benchmark case matched "${args.caseId}".`);
  return selected;
}

async function discoverBarcodeCase(sql: Sql, args: Args): Promise<BenchmarkCase | undefined> {
  const [row] = args.scope === "sample"
    ? await sql`
      SELECT f.barcode, d.display_name
      FROM food_normalized_search_documents d
      JOIN food_items f ON f.id = d.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      JOIN food_normalization_review r ON r.food_item_id = f.id
        AND r.normalization_version = d.normalization_version
      JOIN food_normalization_sample_items si ON si.food_item_id = f.id
      JOIN food_normalization_sample_sets ss ON ss.id = si.sample_set_id
      WHERE ss.name = ${args.sampleSetName}
        AND q.is_search_eligible
        AND r.review_status = 'valid'
        AND d.result_type = 'product'
        AND nullif(btrim(f.barcode), '') IS NOT NULL
      ORDER BY d.rank_bucket, md5(f.id::text || ':benchmark-barcode')
      LIMIT 1
    `
    : await sql`
      SELECT f.barcode, d.display_name
      FROM food_normalized_search_documents d
      JOIN food_items f ON f.id = d.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      JOIN food_normalization_review r ON r.food_item_id = f.id
        AND r.normalization_version = d.normalization_version
      WHERE q.is_search_eligible
        AND r.review_status = 'valid'
        AND d.result_type = 'product'
        AND nullif(btrim(f.barcode), '') IS NOT NULL
      ORDER BY d.rank_bucket, md5(f.id::text || ':benchmark-barcode')
      LIMIT 1
    `;
  const barcode = optionalString(row?.barcode);
  if (!barcode) return undefined;
  return {
    id: "representative-barcode",
    query: barcode,
    locale: "en",
    kind: "barcode",
    barcode,
    expectedTopBarcode: barcode,
    relevant: [{ barcode, grade: 3 }],
  };
}

async function countSampledGenericCoverage(sql: Sql, benchmarkCase: BenchmarkCase, args: Args): Promise<number> {
  if (benchmarkCase.kind !== "broad_generic") return 0;
  const normalized = normalizeText(benchmarkCase.query);
  if (!normalized) return 0;
  const identityTokenKey = normalizedIdentityTokenKeys([normalized])[0];
  const tokenPrefix = `${normalized} %`;
  const queryTokenCount = normalized.split(/\s+/).filter(Boolean).length;
  const isSingleTokenQuery = queryTokenCount === 1;
  const maxBaseTokens = queryTokenCount + 3;
  const [row] = args.scope === "sample"
    ? await sql`
      SELECT count(DISTINCT lower(d.display_name))::int AS rows
      FROM food_normalized_search_documents d
      JOIN food_normalization_review r ON r.food_item_id = d.food_item_id
        AND r.normalization_version = d.normalization_version
      JOIN food_normalization_sample_items si ON si.food_item_id = d.food_item_id
      JOIN food_normalization_sample_sets ss ON ss.id = si.sample_set_id
      WHERE ss.name = ${args.sampleSetName}
        AND r.review_status = 'valid'
        AND d.result_type = 'generic_food'
        AND (
          lower(d.base_name) = ${normalized}
          OR lower(d.base_name) LIKE ${tokenPrefix}
          OR (
            ${Boolean(identityTokenKey)}
            AND d.identity_token_keys @> ARRAY[${identityTokenKey ?? ""}]::text[]
          )
          OR (
            ${isSingleTokenQuery}
            AND split_part(lower(d.base_name), ' ', 2) = ${normalized}
          )
        )
        AND COALESCE(array_length(regexp_split_to_array(NULLIF(btrim(d.base_name), ''), '[[:space:]]+'), 1), 0) <= ${maxBaseTokens}
    `
    : await sql`
      SELECT count(DISTINCT lower(d.display_name))::int AS rows
      FROM food_normalized_search_documents d
      JOIN food_normalization_review r ON r.food_item_id = d.food_item_id
        AND r.normalization_version = d.normalization_version
      WHERE r.review_status = 'valid'
        AND d.result_type = 'generic_food'
        AND (
          lower(d.base_name) = ${normalized}
          OR lower(d.base_name) LIKE ${tokenPrefix}
          OR (
            ${Boolean(identityTokenKey)}
            AND d.identity_token_keys @> ARRAY[${identityTokenKey ?? ""}]::text[]
          )
          OR (
            ${isSingleTokenQuery}
            AND split_part(lower(d.base_name), ' ', 2) = ${normalized}
          )
        )
        AND COALESCE(array_length(regexp_split_to_array(NULLIF(btrim(d.base_name), ''), '[[:space:]]+'), 1), 0) <= ${maxBaseTokens}
    `;
  return Number(row?.rows ?? 0);
}

async function loadResultMetadata(sql: Sql, foodIds: string[], target: Pick<BenchmarkTarget, "scope" | "sampleSetName">): Promise<Map<string, ResultMetadata>> {
  if (foodIds.length === 0) return new Map();
  const rows = target.scope === "sample"
    ? await sql`
      SELECT
        f.id,
        f.name AS raw_name,
        f.brand,
        f.barcode,
        f.source,
        f.external_source,
        f.data_type,
        f.user_id,
        q.quality_status,
        q.is_search_eligible,
        q.quality_flags,
        d.display_name AS normalized_display_name,
        d.result_type AS normalized_result_type,
        EXISTS (
          SELECT 1
          FROM food_normalization_sample_items si
          JOIN food_normalization_sample_sets ss ON ss.id = si.sample_set_id
          WHERE ss.name = ${target.sampleSetName}
            AND si.food_item_id = f.id
        ) AS in_normalized_sample
      FROM food_items f
      LEFT JOIN food_item_quality q ON q.food_item_id = f.id
      LEFT JOIN food_normalized_search_documents d ON d.food_item_id = f.id
      WHERE f.id = ANY(${foodIds}::uuid[])
    `
    : await sql`
      SELECT
        f.id,
        f.name AS raw_name,
        f.brand,
        f.barcode,
        f.source,
        f.external_source,
        f.data_type,
        f.user_id,
        q.quality_status,
        q.is_search_eligible,
        q.quality_flags,
        d.display_name AS normalized_display_name,
        d.result_type AS normalized_result_type,
        EXISTS (
          SELECT 1
          FROM food_normalized_search_documents vd
          JOIN food_normalization_review r ON r.food_item_id = vd.food_item_id
            AND r.normalization_version = vd.normalization_version
          WHERE vd.food_item_id = f.id
            AND r.review_status = 'valid'
        ) AS in_normalized_sample
      FROM food_items f
      LEFT JOIN food_item_quality q ON q.food_item_id = f.id
      LEFT JOIN food_normalized_search_documents d ON d.food_item_id = f.id
      WHERE f.id = ANY(${foodIds}::uuid[])
    `;
  return new Map(rows.map((row) => {
    const resultType = parseResultType(row.normalized_result_type) ?? deriveResultType(row);
    return [row.id as string, {
      foodId: row.id as string,
      rawName: row.raw_name as string,
      normalizedDisplayName: optionalString(row.normalized_display_name),
      brand: optionalString(row.brand),
      barcode: optionalString(row.barcode),
      source: row.source as string,
      externalSource: optionalString(row.external_source),
      dataType: optionalString(row.data_type),
      resultType,
      qualityStatus: optionalString(row.quality_status),
      isSearchEligible: row.is_search_eligible == null ? undefined : Boolean(row.is_search_eligible),
      qualityFlags: arrayOfStrings(row.quality_flags),
      inNormalizedSample: Boolean(row.in_normalized_sample),
    }];
  }));
}

function toSearchResultRow(result: FoodSearchCandidate, metadata: ResultMetadata | undefined, rank: number): SearchResultRow {
  return {
    rank,
    foodId: result.id,
    returnedName: result.name,
    rawName: metadata?.rawName,
    normalizedDisplayName: metadata?.normalizedDisplayName,
    brand: result.brand ?? metadata?.brand,
    barcode: result.barcode ?? metadata?.barcode,
    source: result.source,
    externalSource: result.externalSource ?? metadata?.externalSource,
    dataType: result.dataType ?? metadata?.dataType,
    resultType: metadata?.resultType ?? deriveResultType(result),
    qualityStatus: metadata?.qualityStatus,
    isSearchEligible: metadata?.isSearchEligible,
    qualityFlags: metadata?.qualityFlags ?? [],
    inNormalizedSample: metadata?.inNormalizedSample ?? false,
    lexicalScore: Number(result.lexicalScore.toFixed(4)),
    finalScore: Number(result.finalScore.toFixed(4)),
  };
}

function parseResultType(value: unknown): ResultType | undefined {
  return value === "generic_food" || value === "product" || value === "custom_food" ? value : undefined;
}

function deriveResultType(row: { userId?: string; user_id?: unknown; externalSource?: string; external_source?: unknown; dataType?: string; data_type?: unknown }): ResultType {
  if (row.userId || optionalString(row.user_id)) return "custom_food";
  const externalSource = row.externalSource ?? optionalString(row.external_source);
  const dataType = row.dataType ?? optionalString(row.data_type);
  if (externalSource === "usda_fdc" && (dataType === "SR Legacy" || dataType === "Foundation")) return "generic_food";
  return "product";
}

export function percentileSummary(values: number[]): LatencySummary {
  if (values.length === 0) {
    return { min: 0, p50: 0, p90: 0, p99: 0, max: 0, average: 0 };
  }
  return {
    min: roundMs(Math.min(...values)),
    p50: percentile(values, 0.5),
    p90: percentile(values, 0.9),
    p99: percentile(values, 0.99),
    max: roundMs(Math.max(...values)),
    average: roundMs(values.reduce((total, value) => total + value, 0) / values.length),
  };
}

export function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * p));
  return roundMs(sorted[index] ?? 0);
}

export function detectDuplicateFlood(displayNames: string[]): DuplicateFlood {
  const counts = new Map<string, { displayName: string; count: number }>();
  for (const displayName of displayNames) {
    const key = normalizeText(displayName);
    if (!key) continue;
    const current = counts.get(key);
    counts.set(key, { displayName, count: (current?.count ?? 0) + 1 });
  }
  const floodedDisplayNames = [...counts.values()]
    .filter((item) => item.count > DUPLICATE_MAX_COUNT)
    .sort((a, b) => b.count - a.count || a.displayName.localeCompare(b.displayName));
  return {
    maxDuplicateCount: Math.max(0, ...[...counts.values()].map((item) => item.count)),
    uniqueDisplayRatio: displayNames.length === 0
      ? 1
      : Number((counts.size / displayNames.length).toFixed(4)),
    floodedDisplayNames,
  };
}

export function aggregateSourceResultTypeMix(rows: SearchResultRow[]): Array<{ source: string; resultType: ResultType; rows: number }> {
  const counts = new Map<string, { source: string; resultType: ResultType; rows: number }>();
  for (const row of rows) {
    const source = row.externalSource ?? row.source;
    const key = `${source}:${row.resultType}`;
    const current = counts.get(key) ?? { source, resultType: row.resultType, rows: 0 };
    current.rows += 1;
    counts.set(key, current);
  }
  return [...counts.values()].sort((a, b) => b.rows - a.rows || a.source.localeCompare(b.source));
}

export function reciprocalRank(rows: SearchResultRow[], judgments: RelevanceJudgment[]): number {
  for (const row of rows) {
    if (relevanceGrade(row, judgments) > 0) return Number((1 / row.rank).toFixed(4));
  }
  return 0;
}

export function ndcgAt(rows: SearchResultRow[], judgments: RelevanceJudgment[], k: number): number {
  const dcg = rows.slice(0, k).reduce((total, row, index) => {
    const grade = relevanceGrade(row, judgments);
    return total + ((2 ** grade - 1) / Math.log2(index + 2));
  }, 0);
  const idealGrades = judgments
    .map((judgment) => judgment.grade)
    .sort((a, b) => b - a)
    .slice(0, k);
  const idcg = idealGrades.reduce((total, grade, index) => total + ((2 ** grade - 1) / Math.log2(index + 2)), 0);
  return idcg === 0 ? 0 : Number((dcg / idcg).toFixed(4));
}

function relevanceGrade(row: SearchResultRow, judgments: RelevanceJudgment[]): number {
  const returnedName = normalizeText(row.returnedName);
  const rawName = normalizeText(row.rawName ?? "");
  const normalizedDisplayName = normalizeText(row.normalizedDisplayName ?? "");
  const barcode = row.barcode ?? "";
  return Math.max(0, ...judgments.map((judgment) => {
    if (judgment.barcode && judgment.barcode === barcode) return judgment.grade;
    if (!judgment.name) return 0;
    const expected = normalizeText(judgment.name);
    return returnedName === expected || rawName === expected || normalizedDisplayName === expected ? judgment.grade : 0;
  }));
}

export function evaluateRunChecks(run: SearchRun, benchmarkCase: BenchmarkCase): AcceptanceCheck[] {
  const checks: AcceptanceCheck[] = [];
  if (run.mode === "normalized") {
    checks.push({ name: "no_quarantined_rows", ok: run.quarantinedRows === 0, detail: `${run.quarantinedRows}` });
    checks.push({ name: "no_ineligible_rows", ok: run.ineligibleRows === 0, detail: `${run.ineligibleRows}` });
    checks.push({
      name: run.scope === "sample" ? "no_rows_outside_sample" : "no_rows_without_valid_normalized_doc",
      ok: run.outsideSampleRows === 0,
      detail: `${run.outsideSampleRows}`,
    });
    checks.push({ name: "known_bad_zero_calorie_rice_absent", ok: run.knownBadRows === 0, detail: `${run.knownBadRows}` });
    checks.push({
      name: "no_duplicate_display_flood",
      ok:
        run.duplicateFlood.maxDuplicateCount <= DUPLICATE_MAX_COUNT &&
        run.duplicateFlood.uniqueDisplayRatio >= DUPLICATE_MIN_UNIQUE_RATIO,
      detail: `max=${run.duplicateFlood.maxDuplicateCount}, uniqueRatio=${run.duplicateFlood.uniqueDisplayRatio}`,
    });

    if (benchmarkCase.kind === "broad_generic" && run.sampledGenericCoverage) {
      const topThreeHasGeneric = run.results.slice(0, 3).some((row) => row.resultType === "generic_food");
      const genericRows = run.results.filter((row) => row.resultType === "generic_food").length;
      const productRows = run.results.filter((row) => row.resultType === "product").length;
      checks.push({
        name: "broad_generic_top3_contains_generic",
        ok: topThreeHasGeneric,
        detail: `top3=${run.results.slice(0, 3).map((row) => row.resultType).join(",")}`,
      });
      checks.push({
        name: "broad_generic_top_result_is_generic",
        ok: run.topResult?.resultType === "generic_food",
        detail: `top=${run.topResult?.resultType ?? "none"}, generic=${genericRows}, product=${productRows}, sampledGenericCoverage=${run.sampledGenericCoverageCount}`,
      });
    }

    if (benchmarkCase.expectedTopName) {
      checks.push({
        name: "expected_top_name",
        ok: normalizeText(run.topResult?.returnedName ?? "") === normalizeText(benchmarkCase.expectedTopName),
        detail: `${run.topResult?.returnedName ?? "none"} != ${benchmarkCase.expectedTopName}`,
      });
    }
    if (benchmarkCase.expectedTopBarcode) {
      checks.push({
        name: "expected_top_barcode",
        ok: run.topResult?.barcode === benchmarkCase.expectedTopBarcode,
        detail: `${run.topResult?.barcode ?? "none"} != ${benchmarkCase.expectedTopBarcode}`,
      });
    }
  }
  return checks;
}

export function evaluateGlobalChecks(
  runs: SearchRun[],
  modeLatency: Record<BenchmarkMode, LatencySummary | undefined>,
  modes: BenchmarkMode[],
): AcceptanceCheck[] {
  if (!modes.includes("legacy") || !modes.includes("normalized")) return [];
  const legacy = modeLatency.legacy;
  const normalized = modeLatency.normalized;
  if (!legacy || !normalized) return [];
  const checks: AcceptanceCheck[] = [
    {
      name: "normalized_p50_at_least_25_percent_faster",
      ok: normalized.p50 <= legacy.p50 * NORMALIZED_REQUIRED_SPEED_RATIO,
      detail: `legacy=${legacy.p50}ms, normalized=${normalized.p50}ms`,
    },
    {
      name: "normalized_p90_at_least_25_percent_faster",
      ok: normalized.p90 <= legacy.p90 * NORMALIZED_REQUIRED_SPEED_RATIO,
      detail: `legacy=${legacy.p90}ms, normalized=${normalized.p90}ms`,
    },
  ];
  for (const normalizedRun of runs.filter((run) => run.mode === "normalized")) {
    const legacyRun = runs.find((run) => run.mode === "legacy" && run.caseId === normalizedRun.caseId);
    if (!legacyRun) continue;
    const duplicateImproved = normalizedImprovesDuplicateQuality(normalizedRun, legacyRun);
    checks.push({
      name: `case_not_materially_slower:${normalizedRun.caseId}`,
      ok: normalizedCaseSpeedAcceptable(normalizedRun, legacyRun) || duplicateImproved,
      detail: `legacy=${legacyRun.latency.p50}ms, normalized=${normalizedRun.latency.p50}ms, duplicateImproved=${duplicateImproved}`,
    });
  }
  return checks;
}

function normalizedCaseSpeedAcceptable(normalizedRun: SearchRun, legacyRun: SearchRun): boolean {
  return normalizedRun.latency.p50 <= NORMALIZED_ALLOWED_CASE_ABSOLUTE_MS ||
    normalizedRun.latency.p50 <= legacyRun.latency.p50 * NORMALIZED_ALLOWED_CASE_SLOWDOWN;
}

function normalizedImprovesDuplicateQuality(normalizedRun: SearchRun, legacyRun: SearchRun): boolean {
  const normalizedChecksPass = normalizedRun.checks.every((check) => check.ok);
  const maxDuplicateImproved =
    normalizedRun.duplicateFlood.maxDuplicateCount < legacyRun.duplicateFlood.maxDuplicateCount;
  const uniqueRatioImproved =
    normalizedRun.duplicateFlood.uniqueDisplayRatio > legacyRun.duplicateFlood.uniqueDisplayRatio;
  return normalizedChecksPass && (maxDuplicateImproved || uniqueRatioImproved);
}

export function buildCaseComparisons(runs: SearchRun[]): CaseComparison[] {
  const baselineRuns = runs.filter((run) => run.targetRole === "baseline");
  const candidateRuns = runs.filter((run) => run.targetRole === "candidate");
  const effectiveBaselineRuns = baselineRuns.length > 0 ? baselineRuns : runs.filter((run) => run.mode === "legacy");
  const effectiveCandidateRuns = candidateRuns.length > 0 ? candidateRuns : runs.filter((run) => run.mode === "normalized");
  return effectiveCandidateRuns.flatMap((candidateRun) => {
    const baselineRun = effectiveBaselineRuns.find((run) => run.caseId === candidateRun.caseId);
    if (!baselineRun) return [];
    const p50Ratio = ratioOrNull(candidateRun.latency.p50, baselineRun.latency.p50);
    const p90Ratio = ratioOrNull(candidateRun.latency.p90, baselineRun.latency.p90);
    const candidateQualityOk = candidateRun.checks.every((check) => check.ok);
    const duplicateImproved = normalizedImprovesDuplicateQuality(candidateRun, baselineRun);
    const latencyOk = normalizedCaseSpeedAcceptable(candidateRun, baselineRun) || duplicateImproved;
    return [{
      caseId: candidateRun.caseId,
      query: candidateRun.query,
      baselineTargetLabel: baselineRun.targetLabel,
      candidateTargetLabel: candidateRun.targetLabel,
      baselineP50Ms: baselineRun.latency.p50,
      candidateP50Ms: candidateRun.latency.p50,
      baselineP90Ms: baselineRun.latency.p90,
      candidateP90Ms: candidateRun.latency.p90,
      p50Ratio,
      p90Ratio,
      baselineTopResult: baselineRun.topResult?.returnedName,
      candidateTopResult: candidateRun.topResult?.returnedName,
      duplicateMaxDelta: candidateRun.duplicateFlood.maxDuplicateCount - baselineRun.duplicateFlood.maxDuplicateCount,
      uniqueDisplayRatioDelta: roundMs(candidateRun.duplicateFlood.uniqueDisplayRatio - baselineRun.duplicateFlood.uniqueDisplayRatio),
      candidateQualityOk,
      latencyOk,
      ok: candidateQualityOk && latencyOk,
    }];
  });
}

function ratioOrNull(value: number, baseline: number): number | null {
  return baseline > 0 ? roundMs(value / baseline) : null;
}

function summarizeModeLatency(
  runs: SearchRun[],
  modes: BenchmarkMode[],
): Record<BenchmarkMode, LatencySummary | undefined> {
  return {
    legacy: modes.includes("legacy")
      ? percentileSummary(runs.filter((run) => run.mode === "legacy").flatMap((run) => run.latenciesMs))
      : undefined,
    normalized: modes.includes("normalized")
      ? percentileSummary(runs.filter((run) => run.mode === "normalized").flatMap((run) => run.latenciesMs))
      : undefined,
  };
}

function summarizeTargetLatency(
  runs: SearchRun[],
  targets: BenchmarkTarget[],
): Record<string, LatencySummary | undefined> {
  return Object.fromEntries(targets.map((target) => [
    target.label,
    percentileSummary(runs.filter((run) => run.targetLabel === target.label).flatMap((run) => run.latenciesMs)),
  ]));
}

async function profileSlowCandidateRuns(
  contexts: Array<{ target: BenchmarkTarget; client: ReturnType<typeof createDbClient>; repository: PostgresRepository }>,
  runs: SearchRun[],
  args: Args,
): Promise<SqlProfileSummary[]> {
  const hasExplicitCandidate = runs.some((run) => run.targetRole === "candidate");
  const candidateRuns = runs
    .filter((run) => hasExplicitCandidate ? run.targetRole === "candidate" : run.mode === "normalized")
    .sort((a, b) => b.latency.p90 - a.latency.p90 || b.latency.p50 - a.latency.p50)
    .slice(0, args.profileTopN);
  const profiles: SqlProfileSummary[] = [];
  for (const run of candidateRuns) {
    const context = contexts.find((item) => item.target.label === run.targetLabel);
    if (!context || context.target.mode !== "normalized") continue;
    profiles.push(await profileNormalizedSearchSql(context.client.sql, run, args.topK));
  }
  return profiles;
}

async function profileNormalizedSearchSql(sql: Sql, run: SearchRun, topK: number): Promise<SqlProfileSummary> {
  const normalized = normalizeText(run.query);
  const locales = normalizedSearchLocales(run.locale);
  const identityTokenKey = normalizedIdentityTokenKeys([normalized])[0];
  const rows = identityTokenKey
    ? await sql`
      EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
      SELECT d.food_item_id
      FROM food_normalized_search_documents d
      JOIN food_items f ON f.id = d.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      JOIN food_normalization_review r ON r.food_item_id = d.food_item_id
        AND r.normalization_version = d.normalization_version
      WHERE (d.user_id IS NULL OR d.user_id = ${benchmarkUserId({ label: run.targetLabel, mode: run.mode }, run.caseId, "profile")})
        AND q.is_search_eligible
        AND r.review_status = 'valid'
        AND d.locale = ANY(${locales}::text[])
        AND d.identity_token_keys @> ARRAY[${identityTokenKey}]::text[]
      ORDER BY
        CASE d.result_type
          WHEN 'generic_food' THEN 0
          WHEN 'product' THEN 1
          ELSE 2
        END,
        d.rank_bucket,
        char_length(d.display_name),
        d.display_name
      LIMIT ${topK}
    `
    : await profileNormalizedFallbackSearchSql(sql, normalized, locales, topK);
  const rawPlan = planValueFromExplainRows(rows);
  return summarizeSqlProfilePlan(rawPlan, {
    targetLabel: run.targetLabel,
    caseId: run.caseId,
    query: run.query,
    locale: run.locale,
  });
}

async function profileNormalizedFallbackSearchSql(
  sql: Sql,
  normalized: string,
  locales: string[],
  topK: number,
): Promise<Array<Record<string, unknown>>> {
  const tokenPrefix = `${normalized} %`;
  const tokenContainsMiddle = `% ${normalized} %`;
  const tokenContainsEnd = `% ${normalized}`;
  return sql`
    EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
    SELECT d.food_item_id
    FROM food_normalized_search_documents d
    JOIN food_items f ON f.id = d.food_item_id
    JOIN food_item_quality q ON q.food_item_id = f.id
    JOIN food_normalization_review r ON r.food_item_id = d.food_item_id
      AND r.normalization_version = d.normalization_version
    WHERE q.is_search_eligible
      AND r.review_status = 'valid'
      AND d.locale = ANY(${locales}::text[])
      AND (
        (
          d.result_type <> 'product'
          AND d.search_vector @@ websearch_to_tsquery('simple', ${normalized})
        )
        OR (
          d.result_type = 'product'
          AND d.search_vector @@ websearch_to_tsquery('simple', ${normalized})
          AND (
            lower(coalesce(d.base_name, '')) = ${normalized}
            OR lower(coalesce(d.display_name, '')) = ${normalized}
            OR lower(coalesce(d.brand_display, '')) = ${normalized}
            OR lower(coalesce(d.base_name, '')) LIKE ${tokenPrefix}
            OR lower(coalesce(d.display_name, '')) LIKE ${tokenPrefix}
            OR lower(coalesce(d.brand_display, '')) LIKE ${tokenPrefix}
            OR lower(coalesce(d.base_name, '')) LIKE ${tokenContainsMiddle}
            OR lower(coalesce(d.base_name, '')) LIKE ${tokenContainsEnd}
            OR lower(coalesce(d.display_name, '')) LIKE ${tokenContainsMiddle}
            OR lower(coalesce(d.display_name, '')) LIKE ${tokenContainsEnd}
            OR d.primary_entity_aliases @> ARRAY[${normalized}]::text[]
            OR d.secondary_entity_aliases @> ARRAY[${normalized}]::text[]
          )
        )
      )
    ORDER BY d.rank_bucket, d.display_name
    LIMIT ${topK}
  `;
}

function planValueFromExplainRows(rows: Array<Record<string, unknown>>): unknown {
  const first = rows[0];
  return first?.["QUERY PLAN"] ?? first?.["query_plan"] ?? first;
}

export function summarizeSqlProfilePlan(
  rawPlan: unknown,
  fields: Pick<SqlProfileSummary, "targetLabel" | "caseId" | "query" | "locale">,
): SqlProfileSummary {
  const root = Array.isArray(rawPlan) ? asRecord(rawPlan[0]) : asRecord(rawPlan);
  const plan = asRecord(root.Plan);
  const indexNames = new Set<string>();
  const sequentialScans = new Set<string>();
  const blocks = { sharedHitBlocks: 0, sharedReadBlocks: 0 };
  collectPlanEvidence(plan, indexNames, sequentialScans, blocks);
  const rawPlanFile = `sql-profile-${safeFileSegment(fields.caseId)}-${safeFileSegment(fields.targetLabel)}.json`;
  return {
    ...fields,
    rawPlanFile,
    planningTimeMs: roundMs(numberField(root["Planning Time"])),
    executionTimeMs: roundMs(numberField(root["Execution Time"])),
    actualRows: numberField(plan["Actual Rows"]),
    indexNames: [...indexNames].sort(),
    sequentialScans: [...sequentialScans].sort(),
    sharedHitBlocks: blocks.sharedHitBlocks,
    sharedReadBlocks: blocks.sharedReadBlocks,
    rawPlan,
  };
}

function collectPlanEvidence(
  plan: Record<string, unknown>,
  indexNames: Set<string>,
  sequentialScans: Set<string>,
  blocks: { sharedHitBlocks: number; sharedReadBlocks: number },
): void {
  const nodeType = optionalString(plan["Node Type"]);
  const relationName = optionalString(plan["Relation Name"]);
  const indexName = optionalString(plan["Index Name"]);
  if (indexName) indexNames.add(indexName);
  if (nodeType?.includes("Seq Scan")) sequentialScans.add(relationName ?? "unknown");
  blocks.sharedHitBlocks += numberField(plan["Shared Hit Blocks"]);
  blocks.sharedReadBlocks += numberField(plan["Shared Read Blocks"]);
  const childPlans = Array.isArray(plan.Plans) ? plan.Plans : [];
  for (const child of childPlans) collectPlanEvidence(asRecord(child), indexNames, sequentialScans, blocks);
}

function normalizedSearchLocales(locale: string): string[] {
  const normalized = locale.toLowerCase();
  if (normalized.startsWith("es")) return ["es", "any", "en"];
  if (normalized.startsWith("en")) return ["en", "any", "es"];
  return ["en", "any", "es"];
}

async function writeReports(report: BenchmarkReport, args: Args): Promise<void> {
  const outputRoot = resolve(process.cwd(), args.outputDir ?? "../../data/food-search-benchmarks");
  const outputDir = resolve(outputRoot, report.runId);
  await mkdir(outputDir, { recursive: true });
  for (const profile of report.sqlProfiles) {
    await writeFile(resolve(outputDir, profile.rawPlanFile), `${JSON.stringify(profile.rawPlan, null, 2)}\n`, "utf8");
  }
  const reportForJson = {
    ...report,
    sqlProfiles: report.sqlProfiles.map(({ rawPlan: _rawPlan, ...profile }) => profile),
  };
  await writeFile(resolve(outputDir, "report.json"), `${JSON.stringify(reportForJson, null, 2)}\n`, "utf8");
  await writeFile(resolve(outputDir, "summary.md"), renderMarkdownReport(report), "utf8");
}

function renderMarkdownReport(report: BenchmarkReport): string {
  const failedChecks = [
    ...report.globalChecks.map((check) => ({ scope: "global", caseId: "", target: "", mode: "", ...check })),
    ...report.runs.flatMap((run) => run.checks.map((check) => ({ scope: "case", caseId: run.caseId, target: run.targetLabel, mode: run.mode, ...check }))),
  ].filter((check) => !check.ok);

  return [
    "# Food Search Benchmark",
    "",
    `Generated: ${report.generatedAt}`,
    `Comparison: ${report.comparisonKind}`,
    `Scope: ${report.scope}`,
    `Sample set: ${report.sampleSetName}`,
    `Status: ${report.ok ? "PASS" : "FAIL"}`,
    "",
    "## Targets",
    "",
    "| Target | Role | Mode | Scope | DB | p50 ms | p90 ms | p99 ms | avg ms |",
    "| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: |",
    ...report.targets.map((target) => {
      const latency = report.targetLatency[target.label];
      return `| ${escapeMarkdown(target.label)} | ${target.role} | ${target.mode} | ${target.scope} | ${escapeMarkdown(target.databaseName)} | ${latency?.p50 ?? 0} | ${latency?.p90 ?? 0} | ${latency?.p99 ?? 0} | ${latency?.average ?? 0} |`;
    }),
    "",
    "## Mode Latency",
    "",
    "| Mode | p50 ms | p90 ms | p99 ms | avg ms |",
    "| --- | ---: | ---: | ---: | ---: |",
    ...report.modes.map((mode) => {
      const latency = report.modeLatency[mode];
      return `| ${mode} | ${latency?.p50 ?? 0} | ${latency?.p90 ?? 0} | ${latency?.p99 ?? 0} | ${latency?.average ?? 0} |`;
    }),
    "",
    "## Case Comparisons",
    "",
    report.caseComparisons.length === 0
      ? "None."
      : [
          "| Case | Query | Baseline p50 | Candidate p50 | p50 ratio | Baseline top | Candidate top | Duplicate max delta | Unique ratio delta | Quality | Latency |",
          "| --- | --- | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- |",
          ...report.caseComparisons.map((item) => `| ${item.caseId} | ${escapeMarkdown(item.query)} | ${item.baselineP50Ms} | ${item.candidateP50Ms} | ${item.p50Ratio ?? "n/a"} | ${escapeMarkdown(item.baselineTopResult ?? "none")} | ${escapeMarkdown(item.candidateTopResult ?? "none")} | ${item.duplicateMaxDelta} | ${item.uniqueDisplayRatioDelta} | ${item.candidateQualityOk ? "PASS" : "FAIL"} | ${item.latencyOk ? "PASS" : "FAIL"} |`),
        ].join("\n"),
    "",
    "## Cases",
    "",
    "| Case | Target | Mode | Query | p50 ms | Top result | Mix | Duplicate max | Unique ratio | Checks |",
    "| --- | --- | --- | --- | ---: | --- | --- | ---: | ---: | --- |",
    ...report.runs.map((run) => {
      const checks = run.checks.length === 0
        ? "n/a"
        : run.checks.every((check) => check.ok)
          ? "PASS"
          : `FAIL: ${run.checks.filter((check) => !check.ok).map((check) => check.name).join(", ")}`;
      return `| ${run.caseId} | ${escapeMarkdown(run.targetLabel)} | ${run.mode} | ${escapeMarkdown(run.query)} | ${run.latency.p50} | ${escapeMarkdown(run.topResult?.returnedName ?? "none")} | ${escapeMarkdown(formatMix(run.sourceResultTypeMix))} | ${run.duplicateFlood.maxDuplicateCount} | ${run.duplicateFlood.uniqueDisplayRatio} | ${escapeMarkdown(checks)} |`;
    }),
    "",
    "## SQL Profiles",
    "",
    report.sqlProfiles.length === 0
      ? "None."
      : [
          "| Case | Target | Execution ms | Planning ms | Rows | Indexes | Seq scans | Buffers hit/read | Raw plan |",
          "| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |",
          ...report.sqlProfiles.map((profile) => `| ${profile.caseId} | ${escapeMarkdown(profile.targetLabel)} | ${profile.executionTimeMs} | ${profile.planningTimeMs} | ${profile.actualRows} | ${escapeMarkdown(profile.indexNames.join(", ") || "none")} | ${escapeMarkdown(profile.sequentialScans.join(", ") || "none")} | ${profile.sharedHitBlocks}/${profile.sharedReadBlocks} | ${profile.rawPlanFile} |`),
        ].join("\n"),
    "",
    "## Failed Checks",
    "",
    failedChecks.length === 0
      ? "None."
      : [
          "| Scope | Case | Target | Mode | Check | Detail |",
          "| --- | --- | --- | --- | --- | --- |",
          ...failedChecks.map((check) => `| ${check.scope} | ${check.caseId} | ${escapeMarkdown(check.target)} | ${check.mode} | ${check.name} | ${escapeMarkdown(check.detail ?? "")} |`),
        ].join("\n"),
    "",
  ].join("\n");
}

function printReportSummary(report: BenchmarkReport): void {
  console.log(`Food search benchmark ${report.ok ? "PASS" : "FAIL"} (${report.runId})`);
  console.table(report.targets.map((target) => ({
    target: target.label,
    role: target.role,
    mode: target.mode,
    scope: target.scope,
    db: target.databaseName,
    ...report.targetLatency[target.label],
  })));
  const failedChecks = [
    ...report.globalChecks.map((check) => ({ scope: "global", caseId: "", target: "", mode: "", ...check })),
    ...report.runs.flatMap((run) => run.checks.map((check) => ({ scope: "case", caseId: run.caseId, target: run.targetLabel, mode: run.mode, ...check }))),
  ].filter((check) => !check.ok);
  if (failedChecks.length > 0) console.table(failedChecks);
}

function parseArgs(argv: string[]): Args {
  const parsed: Args = {
    mode: "compare",
    scope: "sample",
    topK: DEFAULT_TOP_K,
    iterations: DEFAULT_ITERATIONS,
    warmup: DEFAULT_WARMUP,
    repeat: 1,
    reportOnly: false,
    sampleSetName: NORMALIZED_SEARCH_SAMPLE_SET,
    baselineLabel: "baseline-legacy",
    candidateLabel: "normalized-full",
    profileSql: false,
    profileTopN: DEFAULT_PROFILE_TOP_N,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--mode") parsed.mode = parseMode(requiredValue(argv, ++index, arg));
    else if (arg === "--scope") parsed.scope = parseScope(requiredValue(argv, ++index, arg));
    else if (arg === "--case") parsed.caseId = requiredValue(argv, ++index, arg);
    else if (arg === "--top-k") parsed.topK = positiveInt(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--iterations") parsed.iterations = positiveInt(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--warmup") parsed.warmup = nonNegativeInt(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--repeat") parsed.repeat = positiveInt(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--output-dir") parsed.outputDir = requiredValue(argv, ++index, arg);
    else if (arg === "--sample-set") parsed.sampleSetName = requiredValue(argv, ++index, arg);
    else if (arg === "--baseline-db-url") parsed.baselineDbUrl = requiredValue(argv, ++index, arg);
    else if (arg === "--candidate-db-url") parsed.candidateDbUrl = requiredValue(argv, ++index, arg);
    else if (arg === "--baseline-label") parsed.baselineLabel = requiredValue(argv, ++index, arg);
    else if (arg === "--candidate-label") parsed.candidateLabel = requiredValue(argv, ++index, arg);
    else if (arg === "--profile-sql") parsed.profileSql = true;
    else if (arg === "--profile-top-n") parsed.profileTopN = positiveInt(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--report-only") parsed.reportOnly = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return parsed;
}

export function buildBenchmarkTargets(args: Args, defaultDatabaseUrl: string): BenchmarkTarget[] {
  if (args.baselineDbUrl || args.candidateDbUrl) {
    const baselineUrl = targetDatabaseUrl(args.baselineDbUrl, defaultDatabaseUrl);
    const candidateUrl = targetDatabaseUrl(args.candidateDbUrl, defaultDatabaseUrl);
    return [
      {
        label: args.baselineLabel,
        role: "baseline",
        mode: "legacy",
        scope: args.scope,
        sampleSetName: args.sampleSetName,
        databaseUrl: baselineUrl,
        databaseName: databaseNameFromUrl(baselineUrl),
      },
      {
        label: args.candidateLabel,
        role: "candidate",
        mode: "normalized",
        scope: args.scope,
        sampleSetName: args.sampleSetName,
        databaseUrl: candidateUrl,
        databaseName: databaseNameFromUrl(candidateUrl),
      },
    ];
  }

  return selectedModes(args.mode).map((mode) => ({
    label: mode,
    role: "single",
    mode,
    scope: args.scope,
    sampleSetName: args.sampleSetName,
    databaseUrl: defaultDatabaseUrl,
    databaseName: databaseNameFromUrl(defaultDatabaseUrl),
  }));
}

function targetDatabaseUrl(databaseUrl: string | undefined, defaultDatabaseUrl: string): string {
  if (!databaseUrl) return defaultDatabaseUrl;
  return withDefaultConnectionOptions(databaseUrl, defaultDatabaseUrl);
}

function withDefaultConnectionOptions(databaseUrl: string, defaultDatabaseUrl: string): string {
  try {
    const url = new URL(databaseUrl);
    const defaults = new URL(defaultDatabaseUrl);
    if (!url.searchParams.has("options") && defaults.searchParams.has("options")) {
      url.searchParams.set("options", defaults.searchParams.get("options") ?? "");
    }
    return url.toString();
  } catch {
    return databaseUrl;
  }
}

function selectedModes(mode: CliMode): BenchmarkMode[] {
  if (mode === "compare") return ["legacy", "normalized"];
  return [mode];
}

function parseMode(value: string): CliMode {
  if (value === "legacy" || value === "normalized" || value === "compare") return value;
  throw new Error(`Invalid --mode value: ${value}`);
}

function parseScope(value: string): BenchmarkScope {
  if (value === "sample" || value === "full") return value;
  throw new Error(`Invalid --scope value: ${value}`);
}

function requiredValue(argv: string[], index: number, flag: string): string {
  const value = argv[index];
  if (!value) throw new Error(`Missing value for ${flag}`);
  return value;
}

function positiveInt(value: string, flag: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${flag} must be a positive integer.`);
  return parsed;
}

function nonNegativeInt(value: string, flag: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) throw new Error(`${flag} must be a non-negative integer.`);
  return parsed;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function arrayOfStrings(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function numberField(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function roundMs(value: number): number {
  return Number(value.toFixed(2));
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}

function databaseNameFromUrl(databaseUrl: string): string {
  try {
    const parsed = new URL(databaseUrl);
    return parsed.pathname.replace(/^\//, "") || "unknown";
  } catch {
    return "unknown";
  }
}

function safeFileSegment(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]+/g, "-").replace(/^-+|-+$/g, "") || "unknown";
}

function stableHash(value: string): string {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  const first = (hash >>> 0).toString(16).padStart(8, "0");
  const second = Math.imul(hash ^ value.length, 2246822507) >>> 0;
  return `${first}${second.toString(16).padStart(8, "0")}`;
}

function formatMix(mix: Array<{ source: string; resultType: ResultType; rows: number }>): string {
  return mix.map((item) => `${item.source}/${item.resultType}:${item.rows}`).join(", ");
}

function escapeMarkdown(value: string): string {
  return value.replaceAll("|", "\\|").replaceAll("\n", " ");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack ?? error.message : error);
    process.exitCode = 1;
  });
}
