import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
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
  type NormalizedFoodSearchDocumentInput,
} from "../src/foodData/normalization.js";
import {
  longNameInputSignature,
  parseLongNameDecision,
  type LongNameDecision,
} from "../src/foodData/longNameDecisions.js";
import {
  evaluateNormalizationReview,
  normalizationMetrics,
  percentileThresholdsFromMetrics,
  type NormalizationReviewThresholds,
} from "../src/foodData/normalizationReview.js";
import type { FoodItemRecord } from "../src/repository/types.js";
import { normalizeText } from "../src/utils/normalize.js";

type Mode = "candidates" | "decisions" | "suggest";
type Scope = "sample" | "full";

type Args = {
  mode: Mode;
  scope: Scope;
  sampleSetName: string;
  auditReportPath?: string;
  candidatesPath?: string;
  outPath?: string;
  limit?: number;
  batchSize: number;
  requiredDbName?: string;
  requiredSchema?: string;
};

type CandidateRow = Record<string, unknown> & {
  issue_codes?: string[];
  metrics?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
};

type LongNameCandidate = {
  foodItemId: string;
  normalizationVersion: string;
  inputSignature: string;
  issueCodes: string[];
  rawName: string;
  rawBrand?: string;
  rawExternalSource?: string;
  rawDataType?: string;
  displayName?: string;
  baseName?: string;
  variantName?: string;
  brandDisplay?: string;
  resultType?: string;
  foodCategory?: string;
  ingredientsPreview?: string;
  metrics: Record<string, unknown>;
};

type FoodRow = Record<string, unknown> & {
  quality_flags?: string[];
};

const guardArgs = consumeRequireDbNameArg(process.argv.slice(2));
const args = parseArgs(guardArgs.argv, guardArgs.requiredDbName, guardArgs.requiredSchema);

if (args.mode === "candidates") {
  await runCandidates(args);
} else if (args.mode === "decisions") {
  await runDecisions(args);
} else {
  await runSuggest(args);
}

async function runCandidates(args: Args): Promise<void> {
  if (args.auditReportPath) {
    await readFile(resolve(process.cwd(), args.auditReportPath), "utf8");
  }
  const config = loadConfig();
  const client = createDbClient(config.DATABASE_URL, { max: 1 });
  try {
    await assertRequiredDatabaseName(client.sql, args.requiredDbName);
    await assertRequiredSchema(client.sql, args.requiredSchema);
    const candidates = await buildCandidatesFromPreviews(client.sql, args);
    const outPath = args.outPath ?? defaultOutputPath("long-name-candidates");
    await writeJsonl(outPath, candidates);
    console.log(`Wrote ${candidates.length} long-name candidates to ${outPath}`);
  } finally {
    await client.close();
  }
}

async function runDecisions(args: Args): Promise<void> {
  if (!args.candidatesPath) throw new Error("--candidates is required for --mode decisions.");
  const candidates = await readJsonl<LongNameCandidate>(args.candidatesPath);
  const decisions = candidates.map((candidate) => compactDecisionForCandidate(candidate));
  const approved = decisions.filter((decision) => decision.status === "approved").length;
  const rejected = decisions.length - approved;
  const outPath = args.outPath ?? defaultOutputPath("long-name-decisions");
  await writeJsonl(outPath, decisions);
  console.log(`Wrote ${decisions.length} Codex compact-identity decisions to ${outPath}`);
  console.log(`Approved: ${approved}; rejected: ${rejected}`);
}

async function runSuggest(args: Args): Promise<void> {
  if (!args.candidatesPath) throw new Error("--candidates is required for --mode suggest.");
  const config = loadConfig();
  const candidates = await readJsonl<LongNameCandidate>(args.candidatesPath);
  const decisions: LongNameDecision[] = [];
  for (const candidate of candidates) {
    const decision = await suggestDecision(config.OPENROUTER_API_KEY, config.OPENROUTER_MODEL, candidate);
    decisions.push(decision);
    console.log(`suggested ${decision.status} decision for ${candidate.foodItemId}`);
  }
  const outPath = args.outPath ?? defaultOutputPath("long-name-decisions");
  await writeJsonl(outPath, decisions);
  console.log(`Wrote ${decisions.length} long-name decisions to ${outPath}`);
}

async function loadCandidateRows(sql: Sql, args: Args): Promise<CandidateRow[]> {
  const samplePredicate = args.scope === "sample"
    ? `
      AND EXISTS (
        SELECT 1
        FROM food_normalization_sample_items si
        JOIN food_normalization_sample_sets ss ON ss.id = si.sample_set_id
        WHERE si.food_item_id = r.food_item_id
          AND ss.name = '${args.sampleSetName.replaceAll("'", "''")}'
      )
    `
    : "";
  const limitClause = args.limit ? `LIMIT ${args.limit}` : "";
  return await sql.unsafe(`
    SELECT
      r.food_item_id,
      r.normalization_version,
      r.issue_codes,
      r.raw_name,
      r.raw_brand,
      r.raw_source,
      r.raw_external_source,
      r.raw_data_type,
      r.display_name,
      r.base_name,
      r.variant_name,
      r.brand_display,
      r.metrics,
      r.metadata,
      f.user_id,
      f.source,
      f.external_source,
      f.data_type,
      f.food_key,
      f.name,
      f.normalized_name,
      f.canonical_name,
      f.brand,
      f.food_category,
      f.market_country,
      f.ingredients
    FROM food_normalization_review r
    JOIN food_items f ON f.id = r.food_item_id
    WHERE r.normalization_version = $1
      AND (
        'display_too_long' = ANY(r.issue_codes)
        OR 'search_text_too_long' = ANY(r.issue_codes)
      )
      ${samplePredicate}
    ORDER BY r.raw_name, r.food_item_id
    ${limitClause}
  `, [FOOD_NORMALIZATION_VERSION]) as CandidateRow[];
}

async function buildCandidatesFromPreviews(sql: Sql, args: Args): Promise<LongNameCandidate[]> {
  const sampleSetId = await sampleSetIdForName(sql, args.sampleSetName);
  const thresholds = await computeSampleThresholds(sql, sampleSetId);
  const candidates: LongNameCandidate[] = [];
  let lastId: string | undefined;
  for (;;) {
    const rows = await loadRows(sql, args, sampleSetId, lastId);
    if (rows.length === 0) break;
    for (const row of rows) {
      const food = mapFood(row);
      const doc = buildNormalizedFoodSearchDocument(food, normalizeQualityFlags(row.quality_flags));
      const review = evaluateNormalizationReview({
        foodId: food.id,
        rawName: food.name,
        rawBrand: food.brand,
        rawSource: food.source,
        rawExternalSource: food.externalSource,
        rawDataType: food.dataType,
        doc,
      }, thresholds);
      const exceedsLongNameGate =
        review.metrics.displayTokenCount > 18 ||
        review.metrics.searchTextTokenCount > 80;
      if (
        doc?.resultType === "product" &&
        (
          exceedsLongNameGate ||
          review.issueCodes.includes("display_too_long") ||
          review.issueCodes.includes("search_text_too_long")
        )
      ) {
        candidates.push(candidateFromPreview(row, doc, review.issueCodes, review.metrics));
        if (args.limit && candidates.length >= args.limit) return candidates;
      }
    }
    lastId = String(rows[rows.length - 1]?.id);
    console.log(`scanned ${lastId}; candidates=${candidates.length}`);
  }
  return candidates;
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
  const rows = await loadRows(sql, {
    ...args,
    scope: "sample",
    limit: undefined,
    batchSize: 100000,
  }, sampleSetId, undefined);
  const metrics = rows.map((row) => {
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

function candidateFromRow(row: CandidateRow): LongNameCandidate {
  return {
    foodItemId: String(row.food_item_id),
    normalizationVersion: String(row.normalization_version ?? FOOD_NORMALIZATION_VERSION),
    inputSignature: longNameInputSignature({
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
    }),
    issueCodes: Array.isArray(row.issue_codes) ? row.issue_codes.map(String) : [],
    rawName: String(row.raw_name ?? ""),
    rawBrand: optionalString(row.raw_brand),
    rawExternalSource: optionalString(row.raw_external_source),
    rawDataType: optionalString(row.raw_data_type),
    displayName: optionalString(row.display_name),
    baseName: optionalString(row.base_name),
    variantName: optionalString(row.variant_name),
    brandDisplay: optionalString(row.brand_display),
    resultType: optionalString(row.result_type),
    foodCategory: optionalString(row.food_category),
    ingredientsPreview: optionalString(row.ingredients)?.slice(0, 1200),
    metrics: row.metrics ?? {},
  };
}

function candidateFromPreview(
  row: FoodRow,
  doc: NormalizedFoodSearchDocumentInput | undefined,
  issueCodes: string[],
  metrics: Record<string, unknown>,
): LongNameCandidate {
  return {
    foodItemId: String(row.id),
    normalizationVersion: doc?.normalizationVersion ?? FOOD_NORMALIZATION_VERSION,
    inputSignature: longNameInputSignature({
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
    }),
    issueCodes,
    rawName: String(row.name ?? ""),
    rawBrand: optionalString(row.brand),
    rawExternalSource: optionalString(row.external_source),
    rawDataType: optionalString(row.data_type),
    displayName: doc?.displayName,
    baseName: doc?.baseName,
    variantName: doc?.variantName,
    brandDisplay: doc?.brandDisplay,
    resultType: doc?.resultType,
    foodCategory: optionalString(row.food_category),
    ingredientsPreview: optionalString(row.ingredients)?.slice(0, 1200),
    metrics,
  };
}

function compactDecisionForCandidate(candidate: LongNameCandidate): LongNameDecision {
  const brand = compactBrandDisplay(candidate);
  const base = compactProductIdentity(candidate, brand);
  if (!base) {
    return {
      foodItemId: candidate.foodItemId,
      normalizationVersion: candidate.normalizationVersion,
      inputSignature: candidate.inputSignature,
      status: "rejected",
      retainedDescriptors: [],
      supplementalDescriptors: [],
      aliases: [],
      confidence: 0,
      decisionSource: "codex_compact_identity_review",
    };
  }

  const variantDescriptors = compactVariantDescriptors(candidate, base, brand);
  const boundedDisplay = boundedDecisionDisplay(base, brand);
  const variantName = joinBoundedDescriptors(variantDescriptors, 36);
  const aliases = dedupeText([
    boundedDisplay.baseName,
    base,
    candidate.baseName,
    candidate.displayName,
    variantName,
    ...variantDescriptors,
  ])
    .filter((value) => tokenCount(value) <= 12)
    .slice(0, 8);

  return {
    foodItemId: candidate.foodItemId,
    normalizationVersion: candidate.normalizationVersion,
    inputSignature: candidate.inputSignature,
    status: "approved",
    displayName: boundedDisplay.displayName,
    baseName: boundedDisplay.baseName,
    variantName,
    fullNormalizedDescription: cleanDisplayText(candidate.rawName),
    retainedDescriptors: variantDescriptors.slice(0, 6),
    supplementalDescriptors: compactSupplementalDescriptors(candidate, [...variantDescriptors, boundedDisplay.baseName, brand]).slice(0, 8),
    aliases,
    confidence: 0.86,
    decisionSource: "codex_compact_identity_review",
    reviewedAt: new Date().toISOString(),
  };
}

function compactProductIdentity(candidate: LongNameCandidate, brand: string | undefined): string | undefined {
  const minIdentityTokens = tokenCount(candidate.rawName) >= 4 ? 2 : 1;
  const sourceTexts = [
    candidate.rawName,
    candidate.baseName,
    candidate.displayName,
  ].filter((value): value is string => Boolean(value));
  const candidateSegments = dedupeText(sourceTexts.flatMap(splitIdentitySegments))
    .map((segment) => stripBrandFromEdges(segment, brand))
    .map(cleanDisplayText)
    .map(removeTrailingQuantityDetails)
    .filter((segment): segment is string => Boolean(segment));

  const direct = candidateSegments
    .filter((segment) => tokenCount(segment) >= minIdentityTokens && tokenCount(segment) <= 14)
    .filter((segment) => !isBrandOnlySegment(segment, candidate, brand))
    .filter((segment) => numericTokenRatio(segment) < 0.45)
    .sort((a, b) => identityScore(a, candidate, brand) - identityScore(b, candidate, brand))[0];
  if (direct) return direct;

  const rawSegments = splitIdentitySegments(candidate.rawName)
    .map((segment) => stripBrandFromEdges(segment, brand))
    .map(cleanDisplayText)
    .map(removeTrailingQuantityDetails)
    .filter((segment): segment is string => Boolean(segment))
    .filter((segment) => !isBrandOnlySegment(segment, candidate, brand));
  const combinedLeadingSegments = rawSegments.length >= 2 &&
    tokenCount(rawSegments[0]) < minIdentityTokens &&
    tokenCount(rawSegments[1]) >= minIdentityTokens
    ? cleanDisplayText(`${rawSegments[0]} ${rawSegments[1]}`)
    : undefined;
  if (combinedLeadingSegments) return clampNormalizedTokenCount(combinedLeadingSegments, 14);

  const leadingRawSegment = rawSegments
    .filter((segment) => tokenCount(segment) >= minIdentityTokens)[0];
  if (leadingRawSegment) return clampNormalizedTokenCount(leadingRawSegment, 14);

  const shortest = candidateSegments
    .filter((segment) => tokenCount(segment) >= minIdentityTokens)
    .filter((segment) => !isBrandOnlySegment(segment, candidate, brand))
    .sort((a, b) => tokenCount(a) - tokenCount(b) || a.length - b.length)[0];
  if (shortest) return clampNormalizedTokenCount(shortest, 14);

  return clampNormalizedTokenCount(cleanDisplayText(candidate.rawName), 14);
}

function compactVariantDescriptors(
  candidate: LongNameCandidate,
  base: string,
  brand: string | undefined,
): string[] {
  const rawSegments = splitIdentitySegments(candidate.rawName)
    .map((segment) => stripBrandFromEdges(segment, brand))
    .map(cleanDisplayText)
    .map(removeTrailingQuantityDetails)
    .filter((segment): segment is string => Boolean(segment))
    .filter((segment) => normalizeText(segment) !== normalizeText(base))
    .filter((segment) => !isBrandOnlySegment(segment, candidate, brand));
  const descriptorSegments = rawSegments.flatMap((segment) => descriptorVariantsFromSegment(segment, base));
  return dedupeText([
    ...descriptorSegments,
    ...rawSegments.filter((segment) => tokenCount(segment) <= 12),
  ])
    .filter((segment) => normalizeText(segment) !== normalizeText(base))
    .filter((segment) => !isBrandOnlySegment(segment, candidate, brand))
    .filter((segment) => tokenCount(segment) <= 12);
}

function removeTrailingQuantityDetails(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const tokens = value.split(/\s+/).filter(Boolean);
  const cutIndex = tokens.findIndex((token, index) => index >= 3 && /\d/.test(token));
  if (cutIndex < 0) return value;
  const retained = tokens.slice(0, cutIndex).join(" ");
  return retained.length >= 4 ? retained : value;
}

function descriptorVariantsFromSegment(segment: string, base: string): string[] {
  const edgeStripped = stripPhraseFromTokenEdges(segment, base);
  const descriptor = cleanDisplayText(removeTrailingQuantityDetails(edgeStripped) ?? edgeStripped);
  if (!descriptor) return [];
  if (normalizeText(descriptor) === normalizeText(base)) return [];
  const bounded = clampNormalizedTokenCount(descriptor, 12);
  return tokenCount(bounded) >= 2 ? [bounded] : [];
}

function stripPhraseFromTokenEdges(value: string, phrase: string): string {
  const phraseTokens = phrase.split(/\s+/).filter(Boolean);
  if (phraseTokens.length === 0) return value;
  let tokens = value.split(/\s+/).filter(Boolean);
  for (let index = 0; index < 2; index += 1) {
    if (tokens.length <= phraseTokens.length) break;
    if (tokenSliceEquals(tokens, 0, phraseTokens)) {
      tokens = tokens.slice(phraseTokens.length);
      continue;
    }
    const suffixStart = tokens.length - phraseTokens.length;
    if (tokenSliceEquals(tokens, suffixStart, phraseTokens)) {
      tokens = tokens.slice(0, suffixStart);
      continue;
    }
    break;
  }
  return tokens.join(" ");
}

function joinBoundedDescriptors(descriptors: string[], maxTokens: number): string | undefined {
  const retained: string[] = [];
  let totalTokens = 0;
  for (const descriptor of dedupeText(descriptors)) {
    const count = tokenCount(descriptor);
    if (count === 0) continue;
    if (totalTokens === 0 && count > maxTokens) {
      return clampNormalizedTokenCount(descriptor, maxTokens);
    }
    if (totalTokens + count > maxTokens) break;
    retained.push(descriptor);
    totalTokens += count;
  }
  return retained.join(", ") || undefined;
}

function compactSupplementalDescriptors(candidate: LongNameCandidate, visible: Array<string | undefined>): string[] {
  const visibleText = normalizeText(visible.filter(Boolean).join(" "));
  return dedupeText([
    candidate.foodCategory,
    ...splitIdentitySegments(candidate.ingredientsPreview ?? ""),
  ])
    .map(cleanDisplayText)
    .filter((value): value is string => Boolean(value))
    .filter((value) => tokenCount(value) <= 8)
    .filter((value) => !visibleText.includes(normalizeText(value)));
}

function splitIdentitySegments(value: string | undefined): string[] {
  if (!value) return [];
  return value
    .split(/[,;|]+|\s+-\s+|\s+[–—]\s+|\s{2,}/u)
    .flatMap((segment) => segment.split(/\s+(?:\/|\+)\s+/u))
    .map((segment) => segment.trim())
    .filter(Boolean);
}

function identityScore(segment: string, candidate: LongNameCandidate, brand: string | undefined): number {
  const count = tokenCount(segment);
  const normalized = normalizeText(segment);
  const raw = normalizeText(candidate.rawName);
  const brandKey = normalizeText(brand ?? "");
  const rawBrandKey = normalizeText(candidate.rawBrand ?? "");
  const isRepeated = raw.indexOf(normalized) !== raw.lastIndexOf(normalized);
  const startsRawName = raw.startsWith(normalized);
  const numericRatio = normalized
    ? numericTokenRatio(segment)
    : 0;
  const brandOnlyPenalty = brandKey && (normalized === brandKey || rawBrandKey.includes(normalized))
    ? 120
    : 0;
  return (
    Math.abs(count - 5) * 4 +
    (isRepeated ? -10 : 0) +
    (startsRawName ? -14 : 0) +
    numericRatio * 45 +
    brandOnlyPenalty +
    segment.length * 0.02
  );
}

function isBrandOnlySegment(
  segment: string,
  candidate: LongNameCandidate,
  brand: string | undefined,
): boolean {
  const segmentKey = normalizeText(segment);
  const brandKeys = [
    brand,
    candidate.rawBrand,
    candidate.brandDisplay,
  ].map((value) => normalizeText(value ?? "")).filter(Boolean);
  if (!segmentKey) return true;
  return brandKeys.some((brandKey) => {
    if (segmentKey === brandKey) return true;
    const brandTokens = new Set(brandKey.split(/\s+/).filter(Boolean));
    const segmentTokens = segmentKey.split(/\s+/).filter(Boolean);
    return segmentTokens.length > 0 && segmentTokens.every((token) => brandTokens.has(token));
  });
}

function numericTokenRatio(value: string): number {
  const tokens = normalizeText(value).split(/\s+/).filter(Boolean);
  return tokens.filter((token) => /\d/.test(token)).length / Math.max(1, tokens.length);
}

function compactBrandDisplay(candidate: LongNameCandidate): string | undefined {
  const rawSegments = splitIdentitySegments(candidate.rawBrand);
  const segments = dedupeText([
    ...rawSegments,
    candidate.brandDisplay,
  ])
    .filter((segment) => tokenCount(segment) <= 8)
    .map((segment, index) => ({ segment, index }));
  if (segments.length === 0) {
    return clampNormalizedTokenCount(cleanDisplayText(rawSegments[0] ?? candidate.rawBrand), 4) || undefined;
  }
  const selectableSegments = segments.filter((segment) => {
    const compactKey = normalizeText(segment.segment).replace(/\s+/g, "");
    return compactKey.length > 3 || segments.length === 1;
  });
  return (selectableSegments.length > 0 ? selectableSegments : segments)
    .sort((a, b) => brandScore(a.segment, a.index) - brandScore(b.segment, b.index))[0]
    ?.segment;
}

function brandScore(value: string, index: number): number {
  const count = tokenCount(value);
  return index * 20 + Math.max(0, count - 4) * 8 + value.length * 0.03;
}

function stripBrandFromEdges(value: string, brand: string | undefined): string {
  if (!brand) return value;
  const brandKey = normalizeText(brand);
  if (!brandKey) return value;
  let result = value.trim();
  for (let index = 0; index < 2; index += 1) {
    const tokens = result.split(/\s+/).filter(Boolean);
    const brandTokens = brand.split(/\s+/).filter(Boolean);
    if (brandTokens.length === 0 || tokens.length <= brandTokens.length) break;
    if (tokenSliceEquals(tokens, 0, brandTokens)) {
      result = tokens.slice(brandTokens.length).join(" ");
      continue;
    }
    const suffixStart = tokens.length - brandTokens.length;
    if (tokenSliceEquals(tokens, suffixStart, brandTokens)) {
      result = tokens.slice(0, suffixStart).join(" ");
    }
  }
  return result;
}

function tokenSliceEquals(tokens: string[], start: number, expectedTokens: string[]): boolean {
  if (start < 0 || start + expectedTokens.length > tokens.length) return false;
  return expectedTokens.every((expected, offset) => normalizeText(tokens[start + offset] ?? "") === normalizeText(expected));
}

function containsNormalizedPhrase(value: string, phrase: string): boolean {
  return normalizeText(value).includes(normalizeText(phrase));
}

function boundedDecisionDisplay(base: string, brand: string | undefined, maxTokens = 18): {
  displayName: string;
  baseName: string;
} {
  const cleanedBase = cleanDisplayText(base) ?? "";
  const cleanedBrand = cleanDisplayText(brand);
  if (!cleanedBrand || containsNormalizedPhrase(cleanedBase, cleanedBrand)) {
    const baseName = clampNormalizedTokenCount(cleanedBase, maxTokens);
    return { displayName: baseName, baseName };
  }

  let brandDisplay = cleanedBrand;
  if (tokenCount(brandDisplay) > maxTokens - 2) {
    brandDisplay = clampNormalizedTokenCount(brandDisplay, Math.max(1, maxTokens - 2));
  }

  let baseName = clampNormalizedTokenCount(cleanedBase, Math.max(2, maxTokens - tokenCount(brandDisplay)));
  if (tokenCount(`${baseName} ${brandDisplay}`) > maxTokens) {
    brandDisplay = clampNormalizedTokenCount(brandDisplay, Math.max(1, maxTokens - tokenCount(baseName)));
  }

  return {
    displayName: `${baseName} - ${brandDisplay}`,
    baseName,
  };
}

function tokenCount(value: string | undefined): number {
  return normalizeText(value ?? "").split(/\s+/).filter(Boolean).length;
}

function clampNormalizedTokenCount(value: string | undefined, maxTokens: number): string {
  const cleaned = cleanDisplayText(value);
  if (!cleaned) return "";
  const tokens = cleaned.split(/\s+/).filter(Boolean);
  const retained: string[] = [];
  for (const token of tokens) {
    const next = [...retained, token].join(" ");
    if (tokenCount(next) > maxTokens) break;
    retained.push(token);
  }
  return retained.join(" ") || (tokens[0] ?? "");
}

function cleanDisplayText(value: string | undefined): string | undefined {
  const cleaned = value
    ?.replace(/[^\p{L}\p{N}&%'.+\- ]+/gu, " ")
    .replace(/\s+/g, " ")
    .replace(/^[\s,;:&+\-.]+|[\s,;:&+\-.]+$/g, "")
    .trim();
  if (!cleaned) return undefined;
  return cleaned.toLowerCase().replace(/\b[\p{L}\p{N}][\p{L}\p{N}'%-]*/gu, (word) => {
    if (/^\d/.test(word)) return word;
    return `${word[0]?.toUpperCase() ?? ""}${word.slice(1)}`;
  });
}

function dedupeText(values: Array<string | undefined>): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const cleaned = cleanDisplayText(value);
    if (!cleaned) continue;
    const key = normalizeText(cleaned);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(cleaned);
  }
  return result;
}

async function suggestDecision(
  apiKey: string,
  model: string,
  candidate: LongNameCandidate,
): Promise<LongNameDecision> {
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: [
            "You normalize long food product names for search indexing.",
            "Return only JSON.",
            "Do not invent brands, flavors, product forms, or nutrition details.",
            "Keep product identity descriptors that affect what a user would choose.",
            "Do not add ingredient-specific rules or translations.",
          ].join(" "),
        },
        {
          role: "user",
          content: JSON.stringify({
            task: "Create an approved long-name normalization decision or reject if the product identity cannot be preserved.",
            requiredSchema: {
              foodItemId: "string",
              normalizationVersion: "string",
              inputSignature: "string",
              status: "approved|rejected",
              displayName: "short user-facing product name, required when approved",
              baseName: "short searchable product identity, required when approved",
              variantName: "optional meaningful variant descriptors",
              fullNormalizedDescription: "full cleaned product meaning",
              retainedDescriptors: ["descriptors preserved in display/base/variant"],
              supplementalDescriptors: ["important descriptors not visible in display"],
              aliases: ["compact search aliases only"],
              confidence: "number from 0 to 1",
              decisionSource: "offline_llm_review",
            },
            candidate,
          }),
        },
      ],
    }),
  });
  if (!response.ok) {
    throw new Error(`OpenRouter long-name review failed: ${response.status} ${await response.text()}`);
  }
  const payload = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
  const content = payload.choices?.[0]?.message?.content;
  if (!content) throw new Error("OpenRouter long-name review returned no content.");
  const decision = parseLongNameDecision(JSON.parse(content));
  if (
    decision.foodItemId !== candidate.foodItemId ||
    decision.normalizationVersion !== candidate.normalizationVersion ||
    decision.inputSignature !== candidate.inputSignature
  ) {
    throw new Error(`OpenRouter long-name review returned mismatched identity for ${candidate.foodItemId}.`);
  }
  return decision;
}

function parseArgs(argv: string[], requiredDbName?: string, requiredSchema?: string): Args {
  const parsed: Args = {
    mode: "candidates",
    scope: "full",
    sampleSetName: NORMALIZED_SEARCH_SAMPLE_SET,
    batchSize: 5000,
    requiredDbName,
    requiredSchema,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--mode") parsed.mode = parseMode(requiredValue(argv, ++index, arg));
    else if (arg === "--scope") parsed.scope = parseScope(requiredValue(argv, ++index, arg));
    else if (arg === "--sample-set") parsed.sampleSetName = requiredValue(argv, ++index, arg);
    else if (arg === "--audit-report") parsed.auditReportPath = requiredValue(argv, ++index, arg);
    else if (arg === "--candidates") parsed.candidatesPath = requiredValue(argv, ++index, arg);
    else if (arg === "--out") parsed.outPath = requiredValue(argv, ++index, arg);
    else if (arg === "--limit") parsed.limit = parsePositiveInteger(requiredValue(argv, ++index, arg), arg);
    else if (arg === "--batch-size") parsed.batchSize = parsePositiveInteger(requiredValue(argv, ++index, arg), arg);
    else throw new Error(`Unknown argument "${arg}".`);
  }
  return parsed;
}

function parseMode(value: string): Mode {
  if (value === "candidates" || value === "decisions" || value === "suggest") return value;
  throw new Error(`Invalid --mode "${value}". Use candidates, decisions, or suggest.`);
}

function parseScope(value: string): Scope {
  if (value === "sample" || value === "full") return value;
  throw new Error(`Invalid --scope "${value}". Use sample or full.`);
}

function parsePositiveInteger(value: string, name: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${name} must be a positive integer.`);
  return parsed;
}

async function readJsonl<T>(path: string): Promise<T[]> {
  const content = await readFile(resolve(process.cwd(), path), "utf8");
  return content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => JSON.parse(line) as T);
}

async function writeJsonl(path: string, rows: unknown[]): Promise<void> {
  const resolvedPath = resolve(process.cwd(), path);
  await mkdir(dirname(resolvedPath), { recursive: true });
  await writeFile(resolvedPath, `${rows.map((row) => JSON.stringify(row)).join("\n")}\n`, "utf8");
}

function defaultOutputPath(prefix: string): string {
  return resolve(process.cwd(), "../../data/food-normalization", `${prefix}-${new Date().toISOString().replaceAll(":", "-")}.jsonl`);
}

function requiredValue(argv: string[], index: number, flag: string): string {
  const value = argv[index];
  if (!value) throw new Error(`${flag} requires a value.`);
  return value;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function mapFood(row: FoodRow): FoodItemRecord {
  return {
    id: String(row.id),
    userId: optionalString(row.user_id),
    name: String(row.name ?? ""),
    normalizedName: String(row.normalized_name ?? row.name ?? ""),
    canonicalName: optionalString(row.canonical_name),
    brand: optionalString(row.brand),
    barcode: optionalString(row.barcode),
    source: String(row.source ?? ""),
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

function toIso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : new Date(value as string).toISOString();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
