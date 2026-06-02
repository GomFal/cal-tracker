import type { NormalizedFoodSearchDocumentInput } from "./normalization.js";
import { normalizeText } from "../utils/normalize.js";

export type NormalizationReviewStatus = "valid" | "needs_review" | "failed";
export type NormalizationReviewSeverity = "info" | "warning" | "error";

export type NormalizationReviewIssueCode =
  | "normalizer_returned_no_doc"
  | "empty_display_name"
  | "empty_base_name"
  | "empty_primary_entity"
  | "empty_search_text"
  | "invalid_result_type"
  | "invalid_locale"
  | "product_empty_name"
  | "generic_empty_name"
  | "low_confidence"
  | "display_too_short"
  | "display_too_long"
  | "search_text_too_long"
  | "overcollapsed_display"
  | "no_effect_generic_compaction"
  | "excessive_descriptor_loss"
  | "product_brand_only_display"
  | "product_brand_duplicated"
  | "display_name_collision_nutrition_divergent"
  | "product_identity_collision"
  | "primary_secondary_token_collision";

export type NormalizationReviewMetrics = {
  rawTokenCount: number;
  displayTokenCount: number;
  rawCharLength: number;
  displayCharLength: number;
  searchTextTokenCount: number;
  hiddenDescriptorCount: number;
  retainedDescriptorCount: number;
  compressionRatio: number;
  charCompressionRatio: number;
  descriptorLossRatio: number;
  normalizationConfidence: number;
};

export type NormalizationReviewThresholds = {
  p99DisplayTokenCount: number;
  p99SearchTextTokenCount: number;
};

export type NormalizationReviewInput = {
  foodId: string;
  rawName: string;
  rawBrand?: string;
  rawSource?: string;
  rawExternalSource?: string;
  rawDataType?: string;
  doc?: NormalizedFoodSearchDocumentInput;
};

export type NormalizationReviewResult = {
  foodItemId: string;
  normalizationVersion: string;
  reviewStatus: NormalizationReviewStatus;
  severity: NormalizationReviewSeverity;
  issueCodes: NormalizationReviewIssueCode[];
  observabilityIssueCodes: NormalizationReviewIssueCode[];
  metrics: NormalizationReviewMetrics;
};

const VALID_RESULT_TYPES = new Set(["generic_food", "product", "custom_food"]);
const VALID_LOCALES = new Set(["en", "es", "any"]);
const DEFAULT_THRESHOLDS: NormalizationReviewThresholds = {
  p99DisplayTokenCount: 18,
  p99SearchTextTokenCount: 80,
};

const FAILURE_ISSUES = new Set<NormalizationReviewIssueCode>([
  "normalizer_returned_no_doc",
  "empty_display_name",
  "empty_base_name",
  "empty_primary_entity",
  "empty_search_text",
  "invalid_result_type",
  "invalid_locale",
  "product_empty_name",
  "generic_empty_name",
]);

export function evaluateNormalizationReview(
  input: NormalizationReviewInput,
  thresholds: NormalizationReviewThresholds = DEFAULT_THRESHOLDS,
): NormalizationReviewResult {
  const metrics = normalizationMetrics(input);
  const issueCodes: NormalizationReviewIssueCode[] = [];
  const observabilityIssueCodes: NormalizationReviewIssueCode[] = [];
  const doc = input.doc;

  if (!doc) {
    issueCodes.push("normalizer_returned_no_doc");
    return reviewResult(input.foodId, "", issueCodes, observabilityIssueCodes, metrics);
  }

  if (!normalizeText(doc.displayName)) issueCodes.push("empty_display_name");
  if (!normalizeText(doc.baseName)) issueCodes.push("empty_base_name");
  if (!normalizeText(doc.primaryEntityName)) issueCodes.push("empty_primary_entity");
  if (!normalizeText(doc.searchText)) issueCodes.push("empty_search_text");
  if (!VALID_RESULT_TYPES.has(doc.resultType)) issueCodes.push("invalid_result_type");
  if (!VALID_LOCALES.has(doc.locale)) issueCodes.push("invalid_locale");
  if (doc.resultType === "product" && !normalizeText(doc.baseName)) issueCodes.push("product_empty_name");
  if (doc.resultType === "generic_food" && !normalizeText(doc.baseName)) issueCodes.push("generic_empty_name");

  const rawNameTokenCount = normalizedTokens(input.rawName).length;
  const compactionRawTokenCount = doc.resultType === "product" ? rawNameTokenCount : metrics.rawTokenCount;
  const compactionRatio = doc.resultType === "product"
    ? ratio(metrics.displayTokenCount, compactionRawTokenCount)
    : metrics.compressionRatio;

  if (doc.normalizationConfidence < 0.68) issueCodes.push("low_confidence");
  if (compactionRawTokenCount >= 4 && metrics.displayTokenCount === 1) issueCodes.push("display_too_short");
  if (metrics.displayTokenCount > Math.max(18, thresholds.p99DisplayTokenCount)) issueCodes.push("display_too_long");
  if (metrics.searchTextTokenCount > Math.max(80, thresholds.p99SearchTextTokenCount)) issueCodes.push("search_text_too_long");
  const overcollapsedDisplay = compactionRawTokenCount >= 6 && compactionRatio < 0.25;
  if (
    doc.resultType === "generic_food" &&
    input.rawName.includes(",") &&
    normalizeText(doc.displayName) === normalizeText(input.rawName)
  ) {
    observabilityIssueCodes.push("no_effect_generic_compaction");
  }
  if (metrics.hiddenDescriptorCount >= 4 && metrics.descriptorLossRatio > 0.75) {
    issueCodes.push("excessive_descriptor_loss");
  }
  if (overcollapsedDisplay) {
    if (
      issueCodes.includes("display_too_short") ||
      issueCodes.includes("excessive_descriptor_loss")
    ) {
      issueCodes.push("overcollapsed_display");
    } else {
      observabilityIssueCodes.push("overcollapsed_display");
    }
  }
  if (
    doc.resultType === "product" &&
    doc.brandDisplay &&
    normalizeText(doc.displayName) === normalizeText(doc.brandDisplay)
  ) {
    observabilityIssueCodes.push("product_brand_only_display");
  }
  if (
    doc.resultType === "product" &&
    doc.brandDisplay &&
    normalizedPhraseOccurrences(doc.displayName, doc.brandDisplay) > 1
  ) {
    observabilityIssueCodes.push("product_brand_duplicated");
  }

  return reviewResult(
    input.foodId,
    doc.normalizationVersion,
    dedupeIssues(issueCodes),
    dedupeIssues(observabilityIssueCodes),
    metrics,
  );
}

export function normalizationMetrics(input: NormalizationReviewInput): NormalizationReviewMetrics {
  const doc = input.doc;
  const rawText = rawMetricText(input);
  const rawTokens = normalizedTokens(rawText);
  const displayTokens = normalizedTokens(doc?.displayName ?? "");
  const searchTokens = normalizedTokens(doc?.searchText ?? "");
  const hiddenDescriptorCount = stringArray(doc?.metadata.hiddenDescriptors).length;
  const retainedDescriptorCount = stringArray(doc?.metadata.retainedDescriptors).length;
  const descriptorTotal = hiddenDescriptorCount + retainedDescriptorCount;
  const rawCharLength = normalizeText(rawText).replaceAll(" ", "").length;
  const displayCharLength = normalizeText(doc?.displayName ?? "").replaceAll(" ", "").length;

  return {
    rawTokenCount: rawTokens.length,
    displayTokenCount: displayTokens.length,
    rawCharLength,
    displayCharLength,
    searchTextTokenCount: searchTokens.length,
    hiddenDescriptorCount,
    retainedDescriptorCount,
    compressionRatio: roundFour(ratio(displayTokens.length, rawTokens.length)),
    charCompressionRatio: roundFour(ratio(displayCharLength, rawCharLength)),
    descriptorLossRatio: roundFour(ratio(hiddenDescriptorCount, Math.max(1, descriptorTotal))),
    normalizationConfidence: doc?.normalizationConfidence ?? 0,
  };
}

export function percentileThresholdsFromMetrics(
  metrics: NormalizationReviewMetrics[],
): NormalizationReviewThresholds {
  return {
    p99DisplayTokenCount: percentile(metrics.map((item) => item.displayTokenCount), 0.99),
    p99SearchTextTokenCount: percentile(metrics.map((item) => item.searchTextTokenCount), 0.99),
  };
}

export function nutritionDiverges(values: Array<{
  calories: number;
  proteinGrams: number;
  carbsGrams: number;
  fatGrams: number;
}>): boolean {
  if (values.length <= 1) return false;
  return diverges(values.map((value) => value.calories), 50) ||
    diverges(values.map((value) => value.proteinGrams), 5) ||
    diverges(values.map((value) => value.carbsGrams), 5) ||
    diverges(values.map((value) => value.fatGrams), 5);
}

export function normalizedTokens(value: string): string[] {
  return normalizeText(value).split(/\s+/).filter(Boolean);
}

export function dedupeIssues(issueCodes: NormalizationReviewIssueCode[]): NormalizationReviewIssueCode[] {
  return [...new Set(issueCodes)].sort();
}

function reviewResult(
  foodItemId: string,
  normalizationVersion: string,
  issueCodes: NormalizationReviewIssueCode[],
  observabilityIssueCodes: NormalizationReviewIssueCode[],
  metrics: NormalizationReviewMetrics,
): NormalizationReviewResult {
  const hasFailure = issueCodes.some((issue) => FAILURE_ISSUES.has(issue));
  return {
    foodItemId,
    normalizationVersion,
    reviewStatus: hasFailure ? "failed" : issueCodes.length > 0 ? "needs_review" : "valid",
    severity: hasFailure ? "error" : issueCodes.length > 0 ? "warning" : "info",
    issueCodes,
    observabilityIssueCodes,
    metrics,
  };
}

function rawMetricText(input: NormalizationReviewInput): string {
  if (input.doc?.resultType === "product") return [input.rawName, input.rawBrand].filter(Boolean).join(" ");
  return input.rawName;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function normalizedPhraseOccurrences(value: string, phrase: string): number {
  const haystack = normalizedTokens(value);
  const needle = normalizedTokens(phrase);
  if (needle.length === 0 || haystack.length < needle.length) return 0;
  let count = 0;
  for (let index = 0; index <= haystack.length - needle.length; index += 1) {
    if (needle.every((token, offset) => haystack[index + offset] === token)) count += 1;
  }
  return count;
}

function ratio(numerator: number, denominator: number): number {
  if (denominator <= 0) return 0;
  return numerator / denominator;
}

function diverges(values: number[], absoluteThreshold: number): boolean {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (sorted.length <= 1) return false;
  const min = sorted[0]!;
  const max = sorted[sorted.length - 1]!;
  const medianValue = median(sorted);
  return max - min > Math.max(absoluteThreshold, Math.abs(medianValue) * 0.2);
}

function median(sorted: number[]): number {
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle]!;
  return ((sorted[middle - 1] ?? 0) + (sorted[middle] ?? 0)) / 2;
}

function percentile(values: number[], p: number): number {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (sorted.length === 0) return 0;
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * p) - 1));
  return sorted[index]!;
}

function roundFour(value: number): number {
  return Math.round(value * 10000) / 10000;
}
