import { createHash } from "node:crypto";
import { z } from "zod";
import { FOOD_NORMALIZATION_VERSION } from "./constants.js";
import {
  normalizedIdentityTokenKeys,
  type NormalizedFoodSearchDocumentInput,
} from "./normalization.js";
import { normalizeText } from "../utils/normalize.js";

export type LongNameInputSignatureFields = {
  userId?: string;
  source?: string;
  externalSource?: string;
  dataType?: string;
  foodKey?: string;
  name?: string;
  normalizedName?: string;
  canonicalName?: string;
  brand?: string;
  foodCategory?: string;
  marketCountry?: string;
  normalizationVersion?: string;
};

export const longNameDecisionSchema = z.object({
  foodItemId: z.string().min(1),
  normalizationVersion: z.string().min(1).default(FOOD_NORMALIZATION_VERSION),
  inputSignature: z.string().min(1),
  status: z.enum(["approved", "rejected"]),
  displayName: z.string().min(1).optional(),
  baseName: z.string().min(1).optional(),
  variantName: z.string().min(1).optional(),
  fullNormalizedDescription: z.string().min(1).optional(),
  retainedDescriptors: z.array(z.string()).default([]),
  supplementalDescriptors: z.array(z.string()).default([]),
  aliases: z.array(z.string()).default([]),
  confidence: z.number().min(0).max(1).default(0.9),
  decisionSource: z.string().min(1).default("offline_llm_review"),
  reviewedAt: z.string().min(1).optional(),
});

export type LongNameDecision = z.infer<typeof longNameDecisionSchema>;

export type LongNameDecisionApplication =
  | { status: "none" }
  | { status: "rejected"; decision: LongNameDecision }
  | { status: "stale"; decision: LongNameDecision; expectedInputSignature: string }
  | { status: "applied"; decision: LongNameDecision; doc: NormalizedFoodSearchDocumentInput };

export function longNameInputSignature(fields: LongNameInputSignatureFields): string {
  const payload = JSON.stringify({
    userId: fields.userId ?? "",
    source: fields.source ?? "",
    externalSource: fields.externalSource ?? "",
    dataType: fields.dataType ?? "",
    foodKey: fields.foodKey ?? "",
    name: fields.name ?? "",
    normalizedName: fields.normalizedName ?? "",
    canonicalName: fields.canonicalName ?? "",
    brand: fields.brand ?? "",
    foodCategory: fields.foodCategory ?? "",
    marketCountry: fields.marketCountry ?? "",
    normalizationVersion: fields.normalizationVersion ?? FOOD_NORMALIZATION_VERSION,
  });
  return createHash("sha256").update(payload).digest("hex");
}

export function applyLongNameDecision(
  doc: NormalizedFoodSearchDocumentInput,
  decision: LongNameDecision | undefined,
  expectedInputSignature: string,
): LongNameDecisionApplication {
  if (!decision) return { status: "none" };
  if (decision.status === "rejected") return { status: "rejected", decision };
  if (
    decision.normalizationVersion !== doc.normalizationVersion ||
    decision.inputSignature !== expectedInputSignature
  ) {
    return { status: "stale", decision, expectedInputSignature };
  }

  const requestedDisplayName = cleanDecisionText(decision.displayName);
  const requestedBaseName = cleanDecisionText(decision.baseName);
  if (!requestedDisplayName || !requestedBaseName) return { status: "rejected", decision };

  const variantName = cleanDecisionText(decision.variantName);
  const brandDisplay = compactDecisionBrandDisplay(requestedDisplayName, doc.brandDisplay);
  const boundedDisplay = boundedDecisionDisplay(requestedBaseName, brandDisplay);
  const displayName = boundedDisplay.displayName;
  const baseName = boundedDisplay.baseName;
  const retainedDescriptors = dedupeStrings([
    ...stringArray(doc.metadata.retainedDescriptors),
    ...decision.retainedDescriptors,
    ...decision.supplementalDescriptors,
  ]);
  const longNameAliases = dedupeStrings([
    ...decision.aliases,
    ...decision.retainedDescriptors,
    ...decision.supplementalDescriptors,
  ]);
  const indexedLongNameAliases = boundedSearchValues(longNameAliases, 8, 8);
  const secondaryEntityAliases = dedupeStrings([
    normalizeText(brandDisplay ?? ""),
    ...indexedLongNameAliases.map(normalizeText),
  ]).slice(0, 12);
  const metadata = {
    ...doc.metadata,
    retainedDescriptors,
    longNameDisplayDetails: {
      displayName,
      baseName,
      variantName,
      brandDisplay,
      aliases: longNameAliases,
      retainedDescriptors: decision.retainedDescriptors,
      supplementalDescriptors: decision.supplementalDescriptors,
      confidence: decision.confidence,
      reviewedAt: decision.reviewedAt,
    },
    fullNormalizedDescription: cleanDecisionText(decision.fullNormalizedDescription),
    longNameDecisionSource: decision.decisionSource,
    longNameDecisionInputSignature: decision.inputSignature,
  };

  const updatedDoc: NormalizedFoodSearchDocumentInput = {
    ...doc,
    displayName,
    baseName,
    variantName,
    brandDisplay,
    primaryEntityName: baseName,
    primaryEntityAliases: dedupeStrings([normalizeText(baseName), normalizeText(displayName)]),
    secondaryEntityAliases,
    identityTokenKeys: normalizedIdentityTokenKeys([
      baseName,
      displayName,
      variantName,
      ...indexedLongNameAliases,
      ...secondaryEntityAliases,
    ]),
    searchText: boundedLongNameSearchText(doc, displayName, baseName, variantName, brandDisplay, secondaryEntityAliases, indexedLongNameAliases, metadata),
    searchAliases: dedupeStrings([displayName, baseName, variantName, ...indexedLongNameAliases]).slice(0, 12),
    normalizationConfidence: Math.max(doc.normalizationConfidence, decision.confidence),
    metadata,
  };

  return { status: "applied", decision, doc: updatedDoc };
}

export function parseLongNameDecision(value: unknown): LongNameDecision {
  return longNameDecisionSchema.parse(value);
}

function boundedLongNameSearchText(
  doc: NormalizedFoodSearchDocumentInput,
  displayName: string,
  baseName: string,
  variantName: string | undefined,
  brandDisplay: string | undefined,
  secondaryEntityAliases: string[],
  longNameAliases: string[],
  metadata: Record<string, unknown>,
): string {
  return boundedNormalizedFieldText([
    displayName,
    baseName,
    variantName,
    brandDisplay,
    ...longNameAliases,
    ...secondaryEntityAliases,
    optionalString(metadata.barcode),
    optionalString(metadata.foodCategory),
  ], 80);
}

function cleanDecisionText(value: string | undefined): string | undefined {
  const cleaned = value?.replace(/\s+/g, " ").trim();
  return cleaned || undefined;
}

function boundedSearchValues(values: Array<string | undefined>, maxValues: number, maxTokens: number): string[] {
  return dedupeStrings(values)
    .filter((value) => normalizedTokenCount(value) <= maxTokens)
    .slice(0, maxValues);
}

function boundedNormalizedFieldText(values: Array<string | undefined>, maxTokens: number): string {
  const fields = dedupeStrings(values)
    .map(normalizeText)
    .filter(Boolean);
  const retainedFields: string[] = [];
  let retainedTokenCount = 0;
  for (const field of fields) {
    const tokens = field.split(/\s+/).filter(Boolean);
    if (tokens.length === 0) continue;
    if (retainedTokenCount + tokens.length > maxTokens) {
      const remaining = maxTokens - retainedTokenCount;
      if (remaining > 0) retainedFields.push(tokens.slice(0, remaining).join(" "));
      break;
    }
    retainedFields.push(field);
    retainedTokenCount += tokens.length;
  }
  return retainedFields.join(" ");
}

function compactDecisionBrandDisplay(displayName: string, fallback: string | undefined): string | undefined {
  const parts = displayName.split(/\s+-\s+/).map(cleanDecisionText).filter(Boolean);
  const suffix = parts.length > 1 ? parts.at(-1) : undefined;
  if (!suffix) return fallback;
  if (!fallback) return suffix;
  return normalizeText(fallback).includes(normalizeText(suffix)) ? suffix : fallback;
}

function boundedDecisionDisplay(base: string, brand: string | undefined, maxTokens = 18): {
  displayName: string;
  baseName: string;
} {
  if (!brand || normalizeText(base).includes(normalizeText(brand))) {
    const baseName = clampNormalizedTokenCount(base, maxTokens);
    return { displayName: baseName, baseName };
  }

  let brandDisplay = brand;
  if (normalizedTokenCount(brandDisplay) > maxTokens - 2) {
    brandDisplay = clampNormalizedTokenCount(brandDisplay, Math.max(1, maxTokens - 2));
  }

  let baseName = clampNormalizedTokenCount(base, Math.max(2, maxTokens - normalizedTokenCount(brandDisplay)));
  if (normalizedTokenCount(`${baseName} ${brandDisplay}`) > maxTokens) {
    brandDisplay = clampNormalizedTokenCount(brandDisplay, Math.max(1, maxTokens - normalizedTokenCount(baseName)));
  }

  return {
    displayName: `${baseName} - ${brandDisplay}`,
    baseName,
  };
}

function clampNormalizedTokenCount(value: string, maxTokens: number): string {
  const tokens = value.split(/\s+/).filter(Boolean);
  const retained: string[] = [];
  for (const token of tokens) {
    const next = [...retained, token].join(" ");
    if (normalizedTokenCount(next) > maxTokens) break;
    retained.push(token);
  }
  return retained.join(" ") || (tokens[0] ?? "");
}

function normalizedTokenCount(value: string): number {
  return normalizeText(value).split(/\s+/).filter(Boolean).length;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string" && item.trim().length > 0)
    : [];
}

function dedupeStrings(values: Array<string | undefined>): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const cleaned = cleanDecisionText(value);
    if (!cleaned) continue;
    const key = normalizeText(cleaned);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(cleaned);
  }
  return result;
}
