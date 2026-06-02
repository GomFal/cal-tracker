import { normalizeText } from "../utils/normalize.js";
import { FOOD_NORMALIZATION_VERSION } from "./constants.js";
import type { FoodItemRecord } from "../repository/types.js";

export type NormalizedFoodSearchDocumentInput = {
  foodItemId: string;
  userId?: string;
  locale: string;
  resultType: "generic_food" | "product" | "custom_food";
  displayName: string;
  baseName: string;
  variantName?: string;
  brandDisplay?: string;
  primaryEntityName: string;
  primaryEntityAliases: string[];
  secondaryEntityAliases: string[];
  identityTokenKeys: string[];
  primaryEntityCategory?: string;
  primaryEntityCategoryCoherence: number;
  primaryEntityRepresentativeness: number;
  searchText: string;
  searchAliases: string[];
  rankBucket: number;
  normalizationVersion: string;
  normalizationSource: string;
  normalizationConfidence: number;
  qualityFlags: string[];
  metadata: Record<string, unknown>;
};

type NormalizationFood = Pick<
  FoodItemRecord,
  | "id"
  | "userId"
  | "name"
  | "normalizedName"
  | "canonicalName"
  | "brand"
  | "barcode"
  | "source"
  | "externalSource"
  | "dataType"
  | "foodKey"
  | "foodCategory"
  | "ingredients"
  | "marketCountry"
  | "sourceUrl"
  | "license"
>;

type GenericNameParts = {
  displayName: string;
  baseName: string;
  variantName?: string;
  primaryEntityName: string;
  primaryEntityAliases: string[];
  secondaryEntityAliases: string[];
  aliases: string[];
  hiddenDescriptors: string[];
  retainedDescriptors: string[];
  confidence: number;
};

export type NormalizedFoodNameParts = GenericNameParts & {
  brandDisplay?: string;
  normalizationSource: string;
};

const LOW_VALUE_DESCRIPTOR_PATTERNS = [
  /\bincludes?\s+foods?\s+for\s+usda'?s?\s+food\s+distribution\s+program\b/g,
  /\bfood distribution program\b/g,
  /\b(un)?enriched\b/g,
  /\bregular\b/g,
  /\bwithout salt added\b/g,
  /\bwith salt added\b/g,
  /\bno salt added\b/g,
  /\bwithout salt\b/g,
  /\bwith salt\b/g,
  /\bsalt added\b/g,
  /\bnot further specified\b/g,
  /\bns as to\b/g,
  /\busda'?s?\b/g,
  /\bcommodity\b/g,
  /\bcommercially prepared\b/g,
  /\bcommercial\b/g,
  /\bretail\b/g,
  /\bstore\b/g,
  /\blong-grain\b/g,
  /\bmedium-grain\b/g,
  /\bshort-grain\b/g,
];

const STATE_DESCRIPTOR_PATTERNS = [
  /\buncooked\b/,
  /\bunprepared\b/,
  /\braw\b/,
  /\bcooked\b/,
  /\bdry\b/,
  /\bdried\b/,
  /\bboiled\b/,
  /\bfried\b/,
  /\bbaked\b/,
  /\broasted\b/,
  /\bgrilled\b/,
  /\bsteamed\b/,
  /\btoasted\b/,
  /\bsmoked\b/,
  /\bcured\b/,
  /\bparboiled\b/,
  /\bprepared\b/,
  /\bcanned\b/,
  /\bfrozen\b/,
  /\bscrambled\b/,
  /\bhard-boiled\b/,
  /\bsoft-boiled\b/,
  /\bdehydrated\b/,
  /\binstant\b/,
];

const PREFIX_DESCRIPTOR_PATTERNS = [
  /\bwhite\b/,
  /\bbrown\b/,
  /\bred\b/,
  /\bblack\b/,
  /\bgreen\b/,
  /\byellow\b/,
  /\bpurple\b/,
  /\bwild\b/,
  /\blowfat\b/,
  /\bnonfat\b/,
  /\bwhole\b/,
  /\bskim\b/,
];

export function buildNormalizedFoodSearchDocument(
  food: NormalizationFood,
  qualityFlags: string[] = [],
  normalizedParts?: NormalizedFoodNameParts,
): NormalizedFoodSearchDocumentInput | undefined {
  const locale = localeForFood(food);
  const resultType = resultTypeForFood(food);
  const normalized = normalizedParts ?? normalizeFoodNameParts(food, resultType);
  if (!normalized.displayName || !normalizeText(normalized.displayName)) return undefined;

  const searchText = buildSearchText(food, resultType, normalized);
  const identityTokenKeys = normalizedIdentityTokenKeys([
    normalized.baseName,
    normalized.displayName,
    normalized.primaryEntityName,
    ...normalized.primaryEntityAliases,
    ...normalized.secondaryEntityAliases,
  ]);

  if (!searchText) return undefined;

  return {
    foodItemId: food.id,
    userId: food.userId,
    locale,
    resultType,
    displayName: normalized.displayName,
    baseName: normalized.baseName,
    variantName: normalized.variantName,
    brandDisplay: normalized.brandDisplay,
    primaryEntityName: normalized.primaryEntityName,
    primaryEntityAliases: normalized.primaryEntityAliases,
    secondaryEntityAliases: normalized.secondaryEntityAliases,
    identityTokenKeys,
    primaryEntityCategory: food.foodCategory,
    primaryEntityCategoryCoherence: 0,
    primaryEntityRepresentativeness: 0,
    searchText,
    searchAliases: normalized.aliases,
    rankBucket: rankBucketForFood(food, resultType, normalized),
    normalizationVersion: FOOD_NORMALIZATION_VERSION,
    normalizationSource: normalized.normalizationSource,
    normalizationConfidence: normalized.confidence,
    qualityFlags,
    metadata: {
      rawName: food.name,
      rawNormalizedName: food.normalizedName,
      rawCanonicalName: food.canonicalName,
      rawBrand: food.brand,
      barcode: food.barcode,
      source: food.source,
      externalSource: food.externalSource,
      dataType: food.dataType,
      foodKey: food.foodKey,
      foodCategory: food.foodCategory,
      ingredients: food.ingredients,
      marketCountry: food.marketCountry,
      sourceUrl: food.sourceUrl,
      license: food.license,
      retainedDescriptors: normalized.retainedDescriptors,
      hiddenDescriptors: normalized.hiddenDescriptors,
      primaryEntityName: normalized.primaryEntityName,
      primaryEntityAliases: normalized.primaryEntityAliases,
      secondaryEntityAliases: normalized.secondaryEntityAliases,
      identityTokenKeys,
      primaryEntityRepresentativeness: 0,
    },
  };
}

function buildSearchText(
  food: NormalizationFood,
  resultType: "generic_food" | "product" | "custom_food",
  normalized: NormalizedFoodNameParts,
): string {
  const sharedSearchFields = [
    normalized.displayName,
    normalized.baseName,
    normalized.variantName,
    normalized.brandDisplay,
    normalized.primaryEntityName,
    ...normalized.primaryEntityAliases,
    ...normalized.secondaryEntityAliases,
  ];

  if (resultType !== "generic_food") {
    return buildBoundedSearchText([
      ...sharedSearchFields,
      food.barcode,
      food.foodCategory,
      food.brand,
    ]);
  }

  return buildBoundedSearchText([
    ...sharedSearchFields,
    food.barcode,
    food.foodCategory,
  ]);
}

export function normalizeFoodNameParts(
  food: NormalizationFood,
  resultType: "generic_food" | "product" | "custom_food" = resultTypeForFood(food),
): NormalizedFoodNameParts {
  return resultType === "generic_food"
    ? normalizeGenericFoodName(food.name)
    : normalizeProductFoodName(food.name, food.brand);
}

export function normalizeGenericFoodName(name: string): GenericNameParts & {
  brandDisplay?: undefined;
  normalizationSource: string;
} {
  const segments = name
    .split(",")
    .map((segment) => cleanDisplayText(segment))
    .filter(Boolean);
  if (segments.length === 0) {
    return {
      displayName: "",
      baseName: "",
      primaryEntityName: "",
      primaryEntityAliases: [],
      secondaryEntityAliases: [],
      aliases: [],
      retainedDescriptors: [],
      hiddenDescriptors: [],
      confidence: 0,
      normalizationSource: "deterministic",
    };
  }

  const base = titleCase(segments[0]);
  const descriptorParts = extractDescriptorParts(segments.slice(1));
  const hiddenDescriptors = descriptorParts.hiddenDescriptors;
  let retained = descriptorParts.retainedDescriptors;
  if (retained.includes("raw") && retained.includes("dry")) {
    retained = retained.filter((descriptor) => descriptor !== "dry");
    hiddenDescriptors.push("dry");
  }

  const stateDescriptors = retained.filter(isStateDescriptor);
  const nonStateDescriptors = retained.filter((descriptor) => !isStateDescriptor(descriptor));
  const prefixDescriptors = nonStateDescriptors.filter(isPrefixDescriptor);
  const suffixDescriptors = nonStateDescriptors.filter((descriptor) => !isPrefixDescriptor(descriptor));
  const displayBase = compactDisplayBase(base, prefixDescriptors, suffixDescriptors);
  const compactedSuffixCount = prefixDescriptors.length === 0 && suffixDescriptors.length > 0 ? 1 : 0;
  const rawVariantDescriptors = [
    ...prefixDescriptors.slice(1),
    ...suffixDescriptors.slice(compactedSuffixCount),
    ...stateDescriptors,
  ]
    .map(titleCase)
    .filter((descriptor) => descriptor.toLowerCase() !== displayBase.toLowerCase());
  const boundedVariant = descriptorsWithinTokenLimit(
    dedupeStrings(rawVariantDescriptors),
    Math.max(0, 18 - normalizedTokenCount(displayBase)),
  );
  const variantDescriptors = boundedVariant.retained;
  const variantName = dedupeStrings(variantDescriptors).join(", ") || undefined;
  const displayName = [displayBase, variantName].filter(Boolean).join(", ");
  const primaryEntityName = base;
  const primaryEntityAliases = normalizedAliasList([
    primaryEntityName,
    singularizeLastToken(primaryEntityName),
  ]);
  const secondaryEntityAliases = normalizedAliasList([
    displayBase,
    variantName,
    ...retained,
    ...segments.slice(1),
  ]).filter((alias) => !primaryEntityAliases.includes(alias));
  const hiddenOverflowDescriptors = boundedVariant.overflow.map((descriptor) => descriptor.toLowerCase());

  return {
    displayName,
    baseName: displayBase,
    variantName,
    primaryEntityName,
    primaryEntityAliases,
    secondaryEntityAliases,
    aliases: dedupeStrings([name, segments.join(" "), base]).filter((alias) => alias !== displayName),
    hiddenDescriptors: dedupeStrings([...hiddenDescriptors, ...hiddenOverflowDescriptors]),
    retainedDescriptors: retained,
    confidence: segments.length > 1 ? 0.82 : 0.68,
    normalizationSource: "deterministic",
  };
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

export function normalizeProductFoodName(name: string, brand?: string): GenericNameParts & {
  brandDisplay?: string;
  normalizationSource: string;
} {
  const rawProductName = cleanDisplayText(name);
  const brandDisplay = compactBrandDisplay(brand);
  const debrandedName = brandDisplay
    ? debrandedProductName(rawProductName, brandDisplay)
    : rawProductName;
  const productName = normalizeText(debrandedName) ? debrandedName : rawProductName;
  const productIncludesBrand =
    brandDisplay != null &&
    normalizeText(productName).includes(normalizeText(brandDisplay));
  const displayName = brandDisplay && !productIncludesBrand
    ? `${productName} - ${brandDisplay}`
    : productName;
  const primaryEntityAliases = normalizedAliasList([
    productName,
    singularizeLastToken(productName),
  ]);
  const secondaryEntityAliases = normalizedAliasList([brandDisplay])
    .filter((alias) => !primaryEntityAliases.includes(alias));

  return {
    displayName,
    baseName: productName,
    brandDisplay,
    primaryEntityName: productName,
    primaryEntityAliases,
    secondaryEntityAliases,
    aliases: dedupeStrings([name, rawProductName, productName, brandDisplay].filter((value): value is string => Boolean(value))),
    hiddenDescriptors: [],
    retainedDescriptors: [],
    confidence: brandDisplay ? 0.9 : 0.75,
    normalizationSource: "deterministic",
  };
}

function buildBoundedSearchText(values: Array<string | undefined>, maxTokens = 80): string {
  const fields = dedupeStrings(values.filter((value): value is string => Boolean(value)))
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

function compactBrandDisplay(brand: string | undefined): string | undefined {
  if (!brand) return undefined;
  const rawSegments = splitBrandSegments(brand);
  const segments = dedupeStrings(rawSegments.map(cleanDisplayText).filter(Boolean))
    .filter((segment) => normalizedTokenCount(segment) <= 8)
    .map((segment, index) => ({ segment, index }));
  if (segments.length === 0) return clampDisplayTokens(cleanDisplayText(rawSegments[0] ?? brand), 4);
  const selectableSegments = segments.filter((segment) => {
    const compactKey = normalizeText(segment.segment).replace(/\s+/g, "");
    return compactKey.length > 3 || segments.length === 1;
  });
  return (selectableSegments.length > 0 ? selectableSegments : segments)
    .sort((a, b) => brandScore(a.segment, a.index) - brandScore(b.segment, b.index))[0]
    ?.segment;
}

function splitBrandSegments(value: string): string[] {
  return value
    .split(/[,;|]+|\s+-\s+|\s+[–—]\s+|\s*\/\s*/u)
    .map((segment) => segment.trim())
    .filter(Boolean);
}

function brandScore(value: string, index: number): number {
  const count = normalizedTokenCount(value);
  return index * 20 + Math.max(0, count - 4) * 8 + value.length * 0.03;
}

function clampDisplayTokens(value: string, maxTokens: number): string {
  const tokens = value.split(/\s+/).filter(Boolean);
  return tokens.length > maxTokens ? tokens.slice(0, maxTokens).join(" ") : value;
}

function debrandedProductName(productName: string, brandDisplay: string): string {
  const brandKey = normalizeText(brandDisplay);
  if (!productName || !brandKey) return productName;

  const delimiterParts = productName
    .split(/\s+-\s+/)
    .map((part) => cleanDisplayText(part))
    .filter(Boolean);
  if (delimiterParts.length > 1) {
    const brandPartIndexes = delimiterParts
      .map((part, index) => normalizeText(part) === brandKey ? index : -1)
      .filter((index) => index >= 0);
    if (brandPartIndexes.length > 0) {
      const retainedParts = delimiterParts.filter((_, index) => !brandPartIndexes.includes(index));
      const retainedName = retainedParts.join(" - ");
      const firstPartIsBrand = brandPartIndexes.includes(0);
      if (retainedName && (!firstPartIsBrand || shouldStripEdgeBrand(retainedName, brandDisplay))) {
        return retainedName;
      }
    }
  }

  const tokens = productName.split(/\s+/).filter(Boolean);
  const brandTokens = brandDisplay.split(/\s+/).filter(Boolean);
  if (tokens.length <= brandTokens.length || brandTokens.length === 0) return productName;

  const startsWithBrand = normalizedTokenSliceEquals(tokens, 0, brandTokens);
  if (startsWithBrand) {
    const retainedName = tokens.slice(brandTokens.length).join(" ");
    if (shouldStripEdgeBrand(retainedName, brandDisplay)) return cleanDisplayText(retainedName);
  }

  const suffixStart = tokens.length - brandTokens.length;
  const endsWithBrand = normalizedTokenSliceEquals(tokens, suffixStart, brandTokens);
  if (endsWithBrand) {
    const retainedName = tokens.slice(0, suffixStart).join(" ");
    if (shouldStripEdgeBrand(retainedName, brandDisplay)) return cleanDisplayText(retainedName);
  }

  return productName;
}

function shouldStripEdgeBrand(retainedName: string, brandDisplay: string): boolean {
  const retainedTokens = normalizeText(retainedName).split(/\s+/).filter(Boolean);
  const brandTokens = normalizeText(brandDisplay).split(/\s+/).filter(Boolean);
  return retainedTokens.length >= 2 || brandTokens.length >= 2;
}

function normalizedTokenSliceEquals(tokens: string[], start: number, expectedTokens: string[]): boolean {
  if (start < 0 || start + expectedTokens.length > tokens.length) return false;
  return expectedTokens.every((expectedToken, offset) =>
    normalizeText(tokens[start + offset] ?? "") === normalizeText(expectedToken)
  );
}

function compactDisplayBase(base: string, prefixDescriptors: string[], suffixDescriptors: string[]): string {
  const prefix = prefixDescriptors[0];
  const suffix = suffixDescriptors[0];
  if (prefix) return titleCase(`${prefix} ${base.toLowerCase()}`);
  if (suffix) return titleCase(`${base} ${suffix}`);
  return base;
}

function extractDescriptorParts(segments: string[]): {
  retainedDescriptors: string[];
  hiddenDescriptors: string[];
} {
  const retainedDescriptors: string[] = [];
  const hiddenDescriptors: string[] = [];

  for (const segment of segments) {
    const descriptor = cleanDescriptorText(segment);
    if (!descriptor) continue;

    let retainedText = descriptor;
    const segmentHiddenDescriptors: string[] = [];
    for (const pattern of LOW_VALUE_DESCRIPTOR_PATTERNS) {
      pattern.lastIndex = 0;
      const matches = [...retainedText.matchAll(pattern)];
      for (const match of matches) {
        const hidden = cleanDescriptorText(match[0]);
        if (hidden) segmentHiddenDescriptors.push(hidden);
      }
      retainedText = retainedText.replace(pattern, " ");
    }

    const segmentRetainedDescriptors = splitRetainedDescriptorText(retainedText);
    retainedDescriptors.push(...segmentRetainedDescriptors);
    hiddenDescriptors.push(...segmentHiddenDescriptors);

    if (segmentRetainedDescriptors.length === 0 && segmentHiddenDescriptors.length === 0) {
      hiddenDescriptors.push(descriptor);
    }
  }

  return {
    retainedDescriptors: dedupeStrings(retainedDescriptors),
    hiddenDescriptors: dedupeStrings(hiddenDescriptors),
  };
}

function splitRetainedDescriptorText(value: string): string[] {
  return value
    .split(/[;|]+/)
    .map(cleanDescriptorText)
    .filter(Boolean);
}

function cleanDescriptorText(value: string): string {
  return value
    .toLowerCase()
    .replace(/[()]/g, " ")
    .replace(/[^\p{L}\p{N}&%'.+\- ]+/gu, " ")
    .replace(/\s+/g, " ")
    .replace(/^[\s,;:&+\-.]+|[\s,;:&+\-.]+$/g, "")
    .trim();
}

function localeForFood(food: NormalizationFood): string {
  if (food.foodKey === "es" || food.foodKey === "en") return food.foodKey;
  if (food.externalSource === "usda_fdc") return "en";
  return "any";
}

function resultTypeForFood(food: NormalizationFood): "generic_food" | "product" | "custom_food" {
  if (food.userId) return "custom_food";
  if (
    food.externalSource === "usda_fdc" &&
    (food.dataType === "SR Legacy" || food.dataType === "Foundation")
  ) {
    return "generic_food";
  }
  return "product";
}

function rankBucketForFood(
  food: NormalizationFood,
  resultType: "generic_food" | "product" | "custom_food",
  normalized: GenericNameParts & { brandDisplay?: string },
): number {
  if (resultType === "custom_food") return 0;
  if (resultType === "generic_food" && food.dataType === "SR Legacy") return 1;
  if (resultType === "generic_food") return 2;
  if (normalized.brandDisplay && food.barcode) return 6;
  if (normalized.brandDisplay) return 7;
  return 8;
}

function cleanDisplayText(value: string): string {
  const cleaned = value
    .replace(/[^\p{L}\p{N}&%'.+\- ]+/gu, " ")
    .replace(/\s+/g, " ")
    .replace(/^[\s,;:&+\-.]+|[\s,;:&+\-.]+$/g, "")
    .trim();
  if (!cleaned) return "";
  return titleCase(cleaned);
}

function titleCase(value: string): string {
  const lower = value.toLowerCase();
  return lower.replace(/\b[\p{L}\p{N}][\p{L}\p{N}'%-]*/gu, (word) => {
    if (/^\d/.test(word)) return word;
    if (word.length <= 2 && word === word.toUpperCase()) return word;
    return `${word[0]?.toUpperCase() ?? ""}${word.slice(1)}`;
  });
}

function normalizedAliasList(values: Array<string | undefined>): string[] {
  return dedupeStrings(
    values
      .flatMap((value) => aliasVariants(value))
      .map(normalizeText)
      .filter(Boolean),
  );
}

function normalizedTokenCount(value: string): number {
  return normalizeText(value).split(/\s+/).filter(Boolean).length;
}

export function normalizedIdentityTokenKeys(
  values: Array<string | undefined>,
  options: { minTokens?: number; maxTokens?: number } = {},
): string[] {
  const minTokens = options.minTokens ?? 2;
  const maxTokens = options.maxTokens ?? 4;
  return dedupeStrings(
    values
      .map((value) => normalizedIdentityTokenKey(value, minTokens, maxTokens))
      .filter((value): value is string => Boolean(value)),
  );
}

function normalizedIdentityTokenKey(
  value: string | undefined,
  minTokens: number,
  maxTokens: number,
): string | undefined {
  const tokens = normalizeText(value ?? "").split(/\s+/).filter(Boolean);
  if (tokens.length < minTokens || tokens.length > maxTokens) return undefined;
  return tokens.sort().join(" ");
}

function aliasVariants(value: string | undefined): string[] {
  if (!value) return [];
  const normalized = normalizeText(value);
  if (!normalized) return [];
  return dedupeStrings([
    normalized,
    singularizeLastToken(normalized),
  ]);
}

function singularizeLastToken(value: string): string {
  const tokens = normalizeText(value).split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return "";
  const last = tokens[tokens.length - 1]!;
  if (last.length > 3 && last.endsWith("ies")) tokens[tokens.length - 1] = `${last.slice(0, -3)}y`;
  else if (last.length > 4 && last.endsWith("oes")) tokens[tokens.length - 1] = last.slice(0, -2);
  else if (last.length > 3 && last.endsWith("s") && !last.endsWith("ss")) tokens[tokens.length - 1] = last.slice(0, -1);
  return tokens.join(" ");
}

function isStateDescriptor(descriptor: string): boolean {
  return STATE_DESCRIPTOR_PATTERNS.some((pattern) => pattern.test(descriptor));
}

function isPrefixDescriptor(descriptor: string): boolean {
  return PREFIX_DESCRIPTOR_PATTERNS.some((pattern) => pattern.test(descriptor));
}

function dedupeStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const trimmed = value.trim();
    if (!trimmed) continue;
    const key = trimmed.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(trimmed);
  }
  return result;
}
