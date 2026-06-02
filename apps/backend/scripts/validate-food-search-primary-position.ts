import { mkdir, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { Sql } from "postgres";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { FOOD_NORMALIZATION_VERSION, NORMALIZED_SEARCH_SAMPLE_SET } from "../src/foodData/constants.js";
import { PostgresRepository } from "../src/repository/postgres.js";
import type { FoodSearchCandidate } from "../src/repository/types.js";
import { normalizeText } from "../src/utils/normalize.js";

type ResultType = "generic_food" | "product" | "custom_food";
type ValidationScope = "sample" | "full";
type QueryReason = "generic_primary" | "product_collision" | "conflict_token";
type ReviewStatus = "pass" | "fail";
type FailureReason = "top_not_primary" | "no_primary_match" | "secondary_above_primary";

export type NormalizedSearchDoc = {
  foodId: string;
  locale: string;
  resultType: ResultType;
  displayName: string;
  baseName: string;
  variantName?: string;
  primaryEntityName: string;
  primaryEntityAliases: string[];
  secondaryEntityAliases: string[];
  externalSource?: string;
  dataType?: string;
};

export type ConflictCandidate = {
  token: string;
  locale: string;
  foodId: string;
  displayName: string;
  primaryEntityName: string;
  baseName: string;
  variantName?: string;
  resultType: ResultType;
  externalSource?: string;
  dataType?: string;
};

export type ValidationQuery = {
  query: string;
  locale: string;
  reasons: QueryReason[];
  candidateCount: number;
};

export type SearchResultRow = {
  rank: number;
  foodId: string;
  name: string;
  normalizedDisplayName?: string;
  normalizedBaseName?: string;
  primaryEntityName?: string;
  primaryEntityAliases: string[];
  resultType?: string;
  finalScore: number;
};

export type CandidateReview = {
  query: string;
  locale: string;
  token: string;
  candidateFoodId: string;
  candidateDisplayName: string;
  candidatePrimaryEntity: string;
  candidateBaseName: string;
  candidateVariantName?: string;
  candidateRank?: number;
  bestPrimaryRank?: number;
  topResultName?: string;
  topResultPrimaryEntity?: string;
  status: ReviewStatus;
  failureReason?: FailureReason;
};

type QueryRun = {
  query: string;
  locale: string;
  reasons: QueryReason[];
  latencyMs: number;
  topResult?: SearchResultRow;
  bestPrimaryRank?: number;
  topResultPrimaryMatch: boolean;
  resultCount: number;
  results: SearchResultRow[];
  candidateReviews: CandidateReview[];
};

type ValidationReport = {
  runId: string;
  generatedAt: string;
  scope: ValidationScope;
  sampleSetName: string;
  topK: number;
  docs: {
    total: number;
    generic: number;
    product: number;
    custom: number;
  };
  queries: ValidationQuery[];
  candidates: ConflictCandidate[];
  candidateCount: number;
  candidateTokenCount: number;
  candidateRowCount: number;
  runs: QueryRun[];
  failedQueries: number;
  failedCandidateReviews: number;
  markedReviewIssueRows: number;
  ok: boolean;
};

type Args = {
  scope: ValidationScope;
  sampleSetName: string;
  topK: number;
  outputDir?: string;
  query?: string;
  maxQueries?: number;
  includeAllProducts: boolean;
  markReviewIssues: boolean;
  reportOnly: boolean;
};

const DEFAULT_TOP_K = 100;
const PROGRESS_INTERVAL = 50;

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const report = await runValidation(args);
  const outputDir = await writeReports(report, args);
  printSummary(report, outputDir);
  if (!report.ok && !args.reportOnly) process.exitCode = 1;
}

async function runValidation(args: Args): Promise<ValidationReport> {
  const config = loadConfig();
  const client = createDbClient(config.DATABASE_URL, { max: 1 });
  const repository = new PostgresRepository(config.DATABASE_URL, {
    normalizedSearchEnabled: true,
    normalizedSearchScope: args.scope,
    normalizedSearchSampleSet: args.sampleSetName,
  });
  const runId = new Date().toISOString().replace(/[:.]/g, "-");

  try {
    const docs = await loadNormalizedSampleDocs(client.sql, args);
    const candidates = extractConflictCandidates(docs);
    const queries = selectQueries(
      extractValidationQueries(docs, candidates, { includeAllProducts: args.includeAllProducts }),
      args,
    );
    const candidatesByQuery = groupCandidatesByQuery(candidates);
    const runs: QueryRun[] = [];

    for (const [index, query] of queries.entries()) {
      const startedAt = performance.now();
      const results = await repository.searchFoodsHybrid(
        validationUserId(index),
        { query: query.query, locale: query.locale, limit: args.topK },
      );
      const rows = results.slice(0, args.topK).map(toSearchResultRow);
      const candidateReviews = evaluateQuery(
        query,
        rows,
        candidatesByQuery.get(queryKey(query.query, query.locale)) ?? [],
      );
      runs.push({
        query: query.query,
        locale: query.locale,
        reasons: query.reasons,
        latencyMs: roundMs(performance.now() - startedAt),
        topResult: rows[0],
        bestPrimaryRank: bestPrimaryRank(query.query, rows),
        topResultPrimaryMatch: rows[0] ? isPrimaryPositionMatch(query.query, rows[0]) : false,
        resultCount: rows.length,
        results: rows,
        candidateReviews,
      });

      if ((index + 1) % PROGRESS_INTERVAL === 0 || index + 1 === queries.length) {
        console.log(`validated ${index + 1}/${queries.length} queries`);
      }
    }

    const failedQueries = runs.filter((run) => !run.topResultPrimaryMatch || run.bestPrimaryRank == null).length;
    const failedCandidateReviews = runs
      .flatMap((run) => run.candidateReviews)
      .filter((review) => review.status === "fail").length;
    const summary = summarizeDocs(docs);
    const report: ValidationReport = {
      runId,
      generatedAt: new Date().toISOString(),
      scope: args.scope,
      sampleSetName: args.sampleSetName,
      topK: args.topK,
      docs: summary,
      queries,
      candidates,
      candidateCount: candidates.length,
      candidateTokenCount: new Set(candidates.map((candidate) => candidate.token)).size,
      candidateRowCount: new Set(candidates.map((candidate) => candidate.foodId)).size,
      runs,
      failedQueries,
      failedCandidateReviews,
      markedReviewIssueRows: 0,
      ok: failedQueries === 0 && failedCandidateReviews === 0,
    };
    report.markedReviewIssueRows = args.markReviewIssues
      ? await markPrimarySecondaryReviewIssues(client.sql, report)
      : 0;
    return report;
  } finally {
    await repository.close();
    await client.close();
  }
}

async function markPrimarySecondaryReviewIssues(sql: Sql, report: ValidationReport): Promise<number> {
  const affectedIds = new Set<string>();
  for (const run of report.runs) {
    if (!run.topResultPrimaryMatch && run.topResult) affectedIds.add(run.topResult.foodId);
    for (const review of run.candidateReviews) {
      if (review.status === "fail") affectedIds.add(review.candidateFoodId);
    }
  }
  if (affectedIds.size === 0) return 0;
  const rows = await sql`
    UPDATE food_normalization_review
    SET
      review_status = CASE WHEN review_status = 'failed' THEN review_status ELSE 'needs_review' END,
      severity = CASE WHEN severity = 'error' THEN severity ELSE 'warning' END,
      issue_codes = ARRAY(
        SELECT DISTINCT value
        FROM unnest(issue_codes || ARRAY['primary_secondary_token_collision'::text]) AS value
        ORDER BY value
      ),
      updated_at = now()
    WHERE normalization_version = ${FOOD_NORMALIZATION_VERSION}
      AND food_item_id = ANY(${[...affectedIds]}::uuid[])
    RETURNING food_item_id
  `;
  return rows.length;
}

async function loadNormalizedSampleDocs(
  sql: Sql,
  args: Pick<Args, "scope" | "sampleSetName">,
): Promise<NormalizedSearchDoc[]> {
  const rows = args.scope === "sample"
    ? await sql`
      SELECT
        d.food_item_id::text AS food_id,
        d.locale,
        d.result_type,
        d.display_name,
        d.base_name,
        d.variant_name,
        d.primary_entity_name,
        d.primary_entity_aliases,
        d.secondary_entity_aliases,
        f.external_source,
        f.data_type
      FROM food_normalized_search_documents d
      JOIN food_items f ON f.id = d.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      JOIN food_normalization_review r ON r.food_item_id = d.food_item_id
        AND r.normalization_version = d.normalization_version
      JOIN food_normalization_sample_items si ON si.food_item_id = d.food_item_id
      JOIN food_normalization_sample_sets ss ON ss.id = si.sample_set_id
      WHERE ss.name = ${args.sampleSetName}
        AND q.is_search_eligible
        AND r.review_status = 'valid'
      ORDER BY d.result_type, d.display_name, d.food_item_id
    `
    : await sql`
      SELECT
        d.food_item_id::text AS food_id,
        d.locale,
        d.result_type,
        d.display_name,
        d.base_name,
        d.variant_name,
        d.primary_entity_name,
        d.primary_entity_aliases,
        d.secondary_entity_aliases,
        f.external_source,
        f.data_type
      FROM food_normalized_search_documents d
      JOIN food_items f ON f.id = d.food_item_id
      JOIN food_item_quality q ON q.food_item_id = f.id
      JOIN food_normalization_review r ON r.food_item_id = d.food_item_id
        AND r.normalization_version = d.normalization_version
      WHERE q.is_search_eligible
        AND r.review_status = 'valid'
      ORDER BY d.result_type, d.display_name, d.food_item_id
    `;

  return rows.map((row) => ({
    foodId: String(row.food_id),
    locale: normalizeDocLocale(row.locale),
    resultType: parseResultType(row.result_type),
    displayName: String(row.display_name),
    baseName: String(row.base_name),
    variantName: optionalString(row.variant_name),
    primaryEntityName: String(row.primary_entity_name ?? ""),
    primaryEntityAliases: normalizedAliases(row.primary_entity_aliases),
    secondaryEntityAliases: normalizedAliases(row.secondary_entity_aliases),
    externalSource: optionalString(row.external_source),
    dataType: optionalString(row.data_type),
  }));
}

export function extractConflictCandidates(docs: NormalizedSearchDoc[]): ConflictCandidate[] {
  const globalPrimaryTokens = new Set(docs.flatMap((doc) => primaryAliasLeadingTokens(doc)));
  const candidates: ConflictCandidate[] = [];
  const seen = new Set<string>();

  for (const doc of docs) {
    const ownPrimaryTokens = new Set(primaryAliasLeadingTokens(doc));
    for (const token of normalizedTokens([doc.baseName, doc.variantName].filter(Boolean).join(" "))) {
      if (ownPrimaryTokens.has(token) || !globalPrimaryTokens.has(token)) continue;
      const key = `${doc.foodId}:${doc.locale}:${token}`;
      if (seen.has(key)) continue;
      seen.add(key);
      candidates.push({
        token,
        locale: doc.locale,
        foodId: doc.foodId,
        displayName: doc.displayName,
        primaryEntityName: doc.primaryEntityName,
        baseName: doc.baseName,
        variantName: doc.variantName,
        resultType: doc.resultType,
        externalSource: doc.externalSource,
        dataType: doc.dataType,
      });
    }
  }

  return candidates.sort((a, b) =>
    a.token.localeCompare(b.token) ||
    a.displayName.localeCompare(b.displayName) ||
    a.foodId.localeCompare(b.foodId),
  );
}

export function extractValidationQueries(
  docs: NormalizedSearchDoc[],
  candidates: ConflictCandidate[],
  options: { includeAllProducts?: boolean } = {},
): ValidationQuery[] {
  const queryMap = new Map<string, ValidationQuery>();
  const conflictTokens = new Set(candidates.map((candidate) => candidate.token));

  for (const doc of docs) {
    for (const alias of doc.primaryEntityAliases) {
      const query = normalizeText(alias);
      if (!query) continue;
      if (doc.resultType === "generic_food") {
        upsertQuery(queryMap, query, doc.locale, "generic_primary");
      } else if (
        options.includeAllProducts ||
        conflictTokens.has(query) ||
        normalizedTokens(query).some((token) => conflictTokens.has(token))
      ) {
        upsertQuery(queryMap, query, doc.locale, "product_collision");
      }
    }
  }

  for (const candidate of candidates) {
    upsertQuery(queryMap, candidate.token, candidate.locale, "conflict_token");
  }

  const candidateCounts = new Map<string, number>();
  for (const candidate of candidates) {
    const key = queryKey(candidate.token, candidate.locale);
    candidateCounts.set(key, (candidateCounts.get(key) ?? 0) + 1);
  }
  for (const query of queryMap.values()) {
    query.candidateCount = candidateCounts.get(queryKey(query.query, query.locale)) ?? 0;
  }

  return [...queryMap.values()].sort((a, b) =>
    a.locale.localeCompare(b.locale) ||
    a.query.localeCompare(b.query),
  );
}

export function evaluateQuery(
  query: Pick<ValidationQuery, "query" | "locale">,
  rows: SearchResultRow[],
  candidates: ConflictCandidate[],
): CandidateReview[] {
  const bestRank = bestPrimaryRank(query.query, rows);
  const topResult = rows[0];
  const topResultPrimaryMatch = topResult ? isPrimaryPositionMatch(query.query, topResult) : false;
  const resultRanks = new Map(rows.map((row) => [row.foodId, row.rank]));

  return candidates.map((candidate) => {
    const candidateRank = resultRanks.get(candidate.foodId);
    const base = {
      query: query.query,
      locale: query.locale,
      token: candidate.token,
      candidateFoodId: candidate.foodId,
      candidateDisplayName: candidate.displayName,
      candidatePrimaryEntity: candidate.primaryEntityName,
      candidateBaseName: candidate.baseName,
      candidateVariantName: candidate.variantName,
      candidateRank,
      bestPrimaryRank: bestRank,
      topResultName: topResult?.name,
      topResultPrimaryEntity: topResult?.primaryEntityName,
    };
    if (bestRank == null) {
      return { ...base, status: "fail" as const, failureReason: "no_primary_match" as const };
    }
    if (!topResultPrimaryMatch) {
      return { ...base, status: "fail" as const, failureReason: "top_not_primary" as const };
    }
    if (candidateRank != null && candidateRank < bestRank) {
      return { ...base, status: "fail" as const, failureReason: "secondary_above_primary" as const };
    }
    return { ...base, status: "pass" as const };
  });
}

export function isPrimaryPositionMatch(
  query: string,
  row: Pick<SearchResultRow, "primaryEntityAliases"> &
    Partial<Pick<SearchResultRow, "name" | "normalizedDisplayName" | "normalizedBaseName" | "primaryEntityName" | "resultType">>,
): boolean {
  const normalizedQuery = normalizeText(query);
  if (!normalizedQuery) return false;
  const aliasesMatch = row.primaryEntityAliases.some((alias) =>
    alias === normalizedQuery ||
    alias.startsWith(`${normalizedQuery} `) ||
    normalizedQuery.startsWith(`${alias} `),
  );
  if (aliasesMatch) return true;

  const candidateNames = [row.name, row.normalizedDisplayName, row.normalizedBaseName];
  const nameMatches = candidateNames
    .map((value) => normalizeText(value ?? ""))
    .some((value) => value === normalizedQuery || value.startsWith(`${normalizedQuery} `));
  if (nameMatches) return true;

  if (
    row.resultType === "generic_food" &&
    normalizedTokens(normalizedQuery).length === 1 &&
    isSimpleCategoryLikeEntityName(row.primaryEntityName)
  ) {
    return candidateNames
      .map((value) => normalizedTokens(value ?? ""))
      .some((tokens) => tokens[1] === normalizedQuery);
  }

  return false;
}

export function normalizedTokens(value: string): string[] {
  return normalizeText(value).split(/\s+/).filter(Boolean);
}

function primaryAliasLeadingTokens(doc: Pick<NormalizedSearchDoc, "primaryEntityAliases">): string[] {
  return doc.primaryEntityAliases
    .map((alias) => normalizedTokens(alias)[0])
    .filter((token): token is string => Boolean(token));
}

function isSimpleCategoryLikeEntityName(value: string | undefined): boolean {
  return /^[\p{L}\p{M}]+(?: [\p{L}\p{M}]+)*$/u.test(value ?? "");
}

function upsertQuery(
  queryMap: Map<string, ValidationQuery>,
  query: string,
  locale: string,
  reason: QueryReason,
): void {
  const key = queryKey(query, locale);
  const current = queryMap.get(key);
  if (!current) {
    queryMap.set(key, { query, locale, reasons: [reason], candidateCount: 0 });
    return;
  }
  if (!current.reasons.includes(reason)) current.reasons.push(reason);
}

function groupCandidatesByQuery(candidates: ConflictCandidate[]): Map<string, ConflictCandidate[]> {
  const groups = new Map<string, ConflictCandidate[]>();
  for (const candidate of candidates) {
    const key = queryKey(candidate.token, candidate.locale);
    const current = groups.get(key) ?? [];
    current.push(candidate);
    groups.set(key, current);
  }
  return groups;
}

function queryKey(query: string, locale: string): string {
  return `${locale}:${normalizeText(query)}`;
}

function bestPrimaryRank(query: string, rows: SearchResultRow[]): number | undefined {
  return rows.find((row) => isPrimaryPositionMatch(query, row))?.rank;
}

function toSearchResultRow(result: FoodSearchCandidate, index: number): SearchResultRow {
  return {
    rank: index + 1,
    foodId: result.id,
    name: result.name,
    normalizedDisplayName: result.normalizedDisplayName,
    normalizedBaseName: result.normalizedBaseName,
    primaryEntityName: result.primaryEntityName,
    primaryEntityAliases: normalizedAliases(result.primaryEntityAliases),
    resultType: result.normalizedResultType,
    finalScore: Number(result.finalScore.toFixed(4)),
  };
}

function selectQueries(queries: ValidationQuery[], args: Args): ValidationQuery[] {
  let selected = queries;
  if (args.query) {
    const normalizedQuery = normalizeText(args.query);
    selected = selected.filter((query) => query.query === normalizedQuery);
  }
  if (args.maxQueries != null) selected = selected.slice(0, args.maxQueries);
  return selected;
}

function summarizeDocs(docs: NormalizedSearchDoc[]): ValidationReport["docs"] {
  return {
    total: docs.length,
    generic: docs.filter((doc) => doc.resultType === "generic_food").length,
    product: docs.filter((doc) => doc.resultType === "product").length,
    custom: docs.filter((doc) => doc.resultType === "custom_food").length,
  };
}

async function writeReports(report: ValidationReport, args: Args): Promise<string> {
  const outputRoot = resolve(process.cwd(), args.outputDir ?? "../../data/food-search-benchmarks/secondary-token-conflicts");
  const outputDir = resolve(outputRoot, report.runId);
  await mkdir(outputDir, { recursive: true });
  const selectedCandidateKeys = new Set(report.queries.map((query) => queryKey(query.query, query.locale)));
  const selectedCandidates = report.candidates.filter((candidate) =>
    selectedCandidateKeys.has(queryKey(candidate.token, candidate.locale)),
  );
  const compactReport = {
    ...report,
    candidates: selectedCandidates,
  };
  await writeFile(resolve(outputDir, "queries.json"), `${JSON.stringify(report.queries, null, 2)}\n`, "utf8");
  await writeFile(resolve(outputDir, "candidates.json"), `${JSON.stringify(selectedCandidates, null, 2)}\n`, "utf8");
  await writeFile(resolve(outputDir, "results.json"), `${JSON.stringify(compactReport, null, 2)}\n`, "utf8");
  await writeFile(resolve(outputDir, "summary.md"), renderMarkdownSummary(report), "utf8");
  return outputDir;
}

function renderMarkdownSummary(report: ValidationReport): string {
  const failedReviews = report.runs.flatMap((run) => run.candidateReviews).filter((review) => review.status === "fail");
  const failedQueries = report.runs.filter((run) => !run.topResultPrimaryMatch || run.bestPrimaryRank == null);
  return [
    "# Food Search Primary Position Validation",
    "",
    `Generated: ${report.generatedAt}`,
    `Scope: ${report.scope}`,
    `Sample set: ${report.sampleSetName}`,
    `Status: ${report.ok ? "PASS" : "FAIL"}`,
    `Top K: ${report.topK}`,
    "",
    "## Counts",
    "",
    `- Docs: ${report.docs.total}`,
    `- Generic docs: ${report.docs.generic}`,
    `- Product docs: ${report.docs.product}`,
    `- Queries: ${report.queries.length}`,
    `- Conflict candidates: ${report.candidateCount}`,
    `- Conflict rows: ${report.candidateRowCount}`,
    `- Conflict tokens: ${report.candidateTokenCount}`,
    `- Failed queries: ${report.failedQueries}`,
    `- Failed candidate reviews: ${report.failedCandidateReviews}`,
    `- Marked review issue rows: ${report.markedReviewIssueRows}`,
    "",
    "## Failed Queries",
    "",
    failedQueries.length === 0
      ? "None."
      : [
          "| Query | Locale | Top result | Best primary rank | Reasons |",
          "| --- | --- | --- | ---: | --- |",
          ...failedQueries.slice(0, 100).map((run) =>
            `| ${escapeMarkdown(run.query)} | ${run.locale} | ${escapeMarkdown(run.topResult?.name ?? "none")} | ${run.bestPrimaryRank ?? ""} | ${run.reasons.join(", ")} |`,
          ),
        ].join("\n"),
    "",
    "## Failed Candidate Reviews",
    "",
    failedReviews.length === 0
      ? "None."
      : [
          "| Query | Candidate | Candidate rank | Best primary rank | Reason |",
          "| --- | --- | ---: | ---: | --- |",
          ...failedReviews.slice(0, 100).map((review) =>
            `| ${escapeMarkdown(review.query)} | ${escapeMarkdown(review.candidateDisplayName)} | ${review.candidateRank ?? ""} | ${review.bestPrimaryRank ?? ""} | ${review.failureReason ?? ""} |`,
          ),
        ].join("\n"),
    "",
  ].join("\n");
}

function printSummary(report: ValidationReport, outputDir: string): void {
  console.log(`Food search primary position validation ${report.ok ? "PASS" : "FAIL"} (${report.runId})`);
  console.log(`Report directory: ${outputDir}`);
  console.table([{
    docs: report.docs.total,
    queries: report.queries.length,
    candidates: report.candidateCount,
    candidateRows: report.candidateRowCount,
    candidateTokens: report.candidateTokenCount,
    failedQueries: report.failedQueries,
    failedCandidateReviews: report.failedCandidateReviews,
    markedReviewIssueRows: report.markedReviewIssueRows,
  }]);
}

function parseArgs(argv: string[]): Args {
  const parsed: Args = {
    scope: "sample",
    sampleSetName: NORMALIZED_SEARCH_SAMPLE_SET,
    topK: DEFAULT_TOP_K,
    includeAllProducts: false,
    markReviewIssues: false,
    reportOnly: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--scope") parsed.scope = parseScope(requiredValue(argv, ++index, arg));
    else if (arg === "--sample-set") parsed.sampleSetName = requiredValue(argv, ++index, arg);
    else if (arg === "--top-k") parsed.topK = positiveInt(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--output-dir") parsed.outputDir = requiredValue(argv, ++index, arg);
    else if (arg === "--query") parsed.query = requiredValue(argv, ++index, arg);
    else if (arg === "--max-queries") parsed.maxQueries = positiveInt(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--include-all-products") parsed.includeAllProducts = true;
    else if (arg === "--mark-review-issues") parsed.markReviewIssues = true;
    else if (arg === "--report-only") parsed.reportOnly = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return parsed;
}

function parseScope(value: string): ValidationScope {
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

function normalizedAliases(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map((item) => typeof item === "string" ? normalizeText(item) : "").filter(Boolean)
    : [];
}

function parseResultType(value: unknown): ResultType {
  if (value === "generic_food" || value === "product" || value === "custom_food") return value;
  return "product";
}

function normalizeDocLocale(value: unknown): string {
  return value === "es" ? "es" : "en";
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function roundMs(value: number): number {
  return Number(value.toFixed(2));
}

function validationUserId(index: number): string {
  return `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`;
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
