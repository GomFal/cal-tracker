import type {
  FoodCandidateGroup,
  FoodMention,
  FoodPortionChoice,
  MealItem,
} from "@cal-tracker/contracts";
import { withSpan } from "../observability/profiler.js";
import type { AppRepository, FoodItemRecord, FoodPortionRecord, FoodSearchCandidate } from "../repository/types.js";
import { normalizeText } from "../utils/normalize.js";
import { scaleFood } from "../utils/nutrition.js";

export type FoodResolutionResult = {
  items: MealItem[];
  unresolvedMentions: FoodMention[];
  candidateGroups: FoodCandidateGroup[];
  clarificationRequired: boolean;
};

export type FoodSearchResult = {
  items: MealItem[];
  candidateGroups: FoodCandidateGroup[];
};

export interface FoodDataProvider {
  readonly id: string;
  resolve(
    userId: string,
    mention: FoodMention,
  ): Promise<MealItem[] | FoodProviderResolution>;
}

type UnitKind = NonNullable<FoodMention["unitKind"]>;

export type FoodProviderResolution = {
  items: MealItem[];
  reason?: FoodCandidateGroup["reason"];
  portionOptions?: FoodPortionChoice[];
};

type PortionKind = NonNullable<FoodPortionChoice["kind"]>;
type PortionSize =
  | "extra small"
  | "small"
  | "medium"
  | "large"
  | "extra large"
  | "jumbo";

type PortionOption = {
  unitName: string;
  aliases: string[];
  gramWeight: number;
  sourceDescription: string;
  externalFoodId?: string;
  kind: PortionKind;
  size?: PortionSize;
  shape?: string;
};

const resolvedGramsSymbol = Symbol("resolvedGrams");
type MealItemWithResolvedGrams = MealItem & { [resolvedGramsSymbol]?: number };

function canonicalNameForMention(mention: FoodMention): string {
  return normalizeFoodName(
    mention.canonicalName ??
      mention.canonicalEnglishName ??
      mention.originalText,
  );
}

function canonicalEnglishSearchName(mention: FoodMention): string | undefined {
  if (!mention.canonicalEnglishName) return undefined;
  const searchName = normalizeFoodName(mention.canonicalEnglishName);
  return searchName && searchName !== canonicalNameForMention(mention)
    ? searchName
    : undefined;
}

function searchQueriesForMention(mention: FoodMention): string[] {
  const queries = [
    canonicalNameForMention(mention),
    canonicalEnglishSearchName(mention),
  ].filter((query): query is string => Boolean(query));
  return [...new Set(queries)];
}

function mentionForSearchQuery(
  mention: FoodMention,
  query: string,
): FoodMention {
  if (query === canonicalNameForMention(mention)) return mention;
  return {
    ...mention,
    canonicalName: query,
    canonicalEnglishName: query,
  };
}

export class FoodResolver {
  constructor(
    private readonly provider: FoodDataProvider,
    private readonly minConfidence: number,
  ) {}

  async resolveMealMentions(
    userId: string,
    mentions: FoodMention[],
    locale?: string,
  ): Promise<FoodResolutionResult> {
    return withSpan(
      "FoodResolver.resolveMealMentions",
      { mentionCount: mentions.length, locale },
      () => this.resolveMealMentionsInternal(userId, mentions, locale),
    );
  }

  private async resolveMealMentionsInternal(
    userId: string,
    mentions: FoodMention[],
    locale?: string,
  ): Promise<FoodResolutionResult> {
    const items: MealItem[] = [];
    const unresolvedMentions: FoodMention[] = [];
    const candidateGroups: FoodCandidateGroup[] = [];
    const localizedMentions = mentions.map((mention) =>
      mentionWithLocale(mention, locale),
    );

    const resolved = await mapWithConcurrency(localizedMentions, 4, async (mention) =>
      ({
        mention,
        resolution: await withSpan(
          "FoodResolver.resolveMention",
          {
            originalText: mention.originalText,
            canonicalName: canonicalNameForMention(mention),
            unitKind: mention.unitKind,
            marketProduct: Boolean(mention.marketProduct || mention.brand || mention.barcode),
          },
          () => this.resolveMention(userId, mention),
        ),
      }),
    );

    for (const { mention, resolution } of resolved) {
      const candidates = resolution.candidates;
      candidateGroups.push({
        mention,
        candidates,
        reason: candidates.length === 0 ? resolution.reason : undefined,
        portionOptions:
          candidates.length === 0 ? resolution.portionOptions : undefined,
      });
      const selected = candidates[0];
      if (
        !selected ||
        (selected.confidence ?? mention.confidence) < this.minConfidence
      ) {
        unresolvedMentions.push(mention);
        continue;
      }
      items.push(selected);
    }

    return {
      items,
      unresolvedMentions,
      candidateGroups,
      clarificationRequired:
        localizedMentions.length === 0 || unresolvedMentions.length > 0,
    };
  }

  async search(
    userId: string,
    query: string,
    barcode?: string,
    locale?: string,
  ): Promise<FoodSearchResult> {
    return withSpan(
      "FoodResolver.search",
      { query, hasBarcode: Boolean(barcode), locale },
      () => this.searchInternal(userId, query, barcode, locale),
    );
  }

  private async searchInternal(
    userId: string,
    query: string,
    barcode?: string,
    locale?: string,
  ): Promise<FoodSearchResult> {
    const canonicalName = normalizeFoodName(query);
    const mention: FoodMention = {
      originalText: query,
      canonicalName,
      canonicalEnglishName: canonicalName,
      quantity: 100,
      unit: "g",
      rawUnitText: "g",
      unitKind: "metric",
      language: languageFromLocale(locale),
      barcode,
      confidence: 0.95,
      marketProduct: true,
    };
    const { candidates, reason, portionOptions } = await this.resolveMention(
      userId,
      mention,
    );
    return {
      items: candidates,
      candidateGroups: [
        {
          mention,
          candidates,
          reason: candidates.length === 0 ? reason : undefined,
          portionOptions: candidates.length === 0 ? portionOptions : undefined,
        },
      ],
    };
  }

  private async resolveMention(
    userId: string,
    mention: FoodMention,
  ): Promise<{
    candidates: MealItem[];
    reason?: FoodCandidateGroup["reason"];
    portionOptions?: FoodPortionChoice[];
  }> {
    const candidates: MealItem[] = [];
    let reason: FoodCandidateGroup["reason"] | undefined;
    let portionOptions: FoodPortionChoice[] | undefined;
    let resolved: FoodProviderResolution;
    try {
      resolved = normalizeProviderResolution(
        await withSpan(
          "FoodDataProvider.resolve",
          { provider: this.provider.id },
          () => this.provider.resolve(userId, mention),
        ),
      );
    } catch {
      resolved = { items: [] };
    }
    if (resolved.items.length === 0 && resolved.reason) {
      reason = resolved.reason;
      portionOptions = resolved.portionOptions;
    }
    candidates.push(...resolved.items);
    candidates.sort(compareFoodCandidates);
    if (
      candidates.length === 0 &&
      !reason &&
      requiresPortionValidation(mention)
    )
      reason = "unsupported_unit";
    return {
      candidates: annotateCandidateMetadata(candidates),
      reason,
      portionOptions,
    };
  }

}

function mentionWithLocale(mention: FoodMention, locale?: string): FoodMention {
  if (mention.language) return mention;
  const language = languageFromLocale(locale);
  return language ? { ...mention, language } : mention;
}

function languageFromLocale(locale?: string): string | undefined {
  const normalized = locale?.toLowerCase();
  if (!normalized) return undefined;
  if (normalized.startsWith("es")) return "es";
  if (normalized.startsWith("en")) return "en";
  return undefined;
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  mapper: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let nextIndex = 0;
  const workers = Array.from(
    { length: Math.min(concurrency, Math.max(items.length, 1)) },
    async () => {
      while (nextIndex < items.length) {
        const index = nextIndex;
        nextIndex += 1;
        results[index] = await mapper(items[index]!, index);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

export class LocalFoodDataProvider implements FoodDataProvider {
  readonly id = "local";
  private readonly searchCache = new Map<string, Array<FoodItemRecord & Partial<FoodSearchCandidate>>>();

  constructor(
    private readonly repository: AppRepository,
    private readonly options: {
      allowSeededPortionFallback?: boolean;
    } = {},
  ) {}

  async resolve(
    userId: string,
    mention: FoodMention,
  ): Promise<FoodProviderResolution> {
    return withSpan(
      "LocalFoodDataProvider.resolve",
      {
        canonicalName: canonicalNameForMention(mention),
        marketProduct: hasMarketProductIntent(mention),
      },
      () => this.resolveInternal(userId, mention),
    );
  }

  private async resolveInternal(
    userId: string,
    mention: FoodMention,
  ): Promise<FoodProviderResolution> {
    let foods: Array<FoodItemRecord & Partial<FoodSearchCandidate>> = [];
    let compatibleFoods: Array<FoodItemRecord & Partial<FoodSearchCandidate>> =
      [];
    let scoringMention = mention;
    for (const query of searchQueriesForMention(mention)) {
      const searchMention = mentionForSearchQuery(mention, query);
      const queryFoods = await this.searchFoods(userId, mention, query);
      const queryCompatibleFoods = queryFoods
        .filter((food) => cachedFoodIsCompatible(food, searchMention))
        .sort((a, b) =>
          (b.finalScore ?? 0) - (a.finalScore ?? 0) ||
          localFoodPriority(a, searchMention) -
            localFoodPriority(b, searchMention),
        );
      foods = queryFoods;
      compatibleFoods = queryCompatibleFoods;
      scoringMention = searchMention;
      if (compatibleFoods.length > 0) break;
    }
    const items: MealItem[] = [];
    let reason: FoodCandidateGroup["reason"] | undefined;
    let portionOptions: FoodPortionChoice[] | undefined;

    for (const food of compatibleFoods) {
      const localPortionOptions = portionOptionsFromFoodPortions(
        food.portions ?? [],
        food.externalId,
      );
      const item = itemFromFood(food, mention, {
        confidence: localConfidence(food, scoringMention),
        source: food.source,
        portionOptions: localPortionOptions,
        allowSeededPortionFallback: this.options.allowSeededPortionFallback,
      });
      if (item) {
        item.lexicalScore = food.lexicalScore ?? item.lexicalScore;
        item.vectorScore = food.vectorScore ?? item.vectorScore;
        item.preferenceScore = food.preferenceScore ?? item.preferenceScore;
        item.matchScore = food.finalScore ?? item.matchScore;
        item.matchReason = isNormalizedSearchFood(food)
          ? "normalized_search"
          : food.vectorScore
            ? "hybrid_search"
            : item.matchReason;
        items.push(item);
        continue;
      }
      if (requiresPortionValidation(mention) && localPortionOptions.length > 0) {
        const portionResolution = resolvePortionForMention(
          mention,
          localPortionOptions,
        );
        reason ??= portionResolution.reason;
        portionOptions ??= portionResolution.choices;
      }
    }

    return {
      items,
      reason:
        foods.length > 0 &&
        items.length === 0 &&
        requiresPortionValidation(mention)
          ? (reason ?? "unsupported_unit")
          : undefined,
      portionOptions,
    };
  }

  private async searchFoods(
    userId: string,
    mention: FoodMention,
    query = canonicalNameForMention(mention),
  ): Promise<Array<FoodItemRecord & Partial<FoodSearchCandidate>>> {
    return withSpan(
      "LocalFoodDataProvider.searchFoods",
      {
        query,
        excludeBranded: !hasMarketProductIntent(mention),
      },
      () => this.searchFoodsInternal(userId, mention, query),
    );
  }

  private async searchFoodsInternal(
    userId: string,
    mention: FoodMention,
    query: string,
  ): Promise<Array<FoodItemRecord & Partial<FoodSearchCandidate>>> {
    const locale = mention.language;
    const marketIntent = hasMarketProductIntent(mention);
    const cacheKey = JSON.stringify({ userId, query, barcode: mention.barcode, locale, marketIntent });
    const cached = this.searchCache.get(cacheKey);
    if (cached) return cached.map(cloneLocalFoodCandidate);

    const lexical = await withSpan(
      "Repository.searchFoodsHybrid",
      { query, mode: "lexical", locale, marketIntent },
      () => this.repository.searchFoodsHybrid(userId, {
        query,
        barcode: mention.barcode,
        excludeBranded: !marketIntent,
        limit: 50,
        locale,
        scope: marketIntent ? "market" : "generic",
      }),
    );
    if (lexical.length > 0 || mention.barcode) {
      this.setSearchCache(cacheKey, lexical);
      return lexical.map(cloneLocalFoodCandidate);
    }

    this.setSearchCache(cacheKey, []);
    return [];
  }

  private setSearchCache(
    key: string,
    value: Array<FoodItemRecord & Partial<FoodSearchCandidate>>,
  ): void {
    if (this.searchCache.size >= 250) {
      const oldest = this.searchCache.keys().next().value;
      if (oldest) this.searchCache.delete(oldest);
    }
    this.searchCache.set(key, value.map(cloneLocalFoodCandidate));
  }
}

function cachedFoodIsCompatible(
  food: FoodItemRecord,
  mention: FoodMention,
): boolean {
  if (isNormalizedSearchFood(food))
    return normalizedFoodFit(food, mention).compatible;
  if (isBrandedFood(food) && !hasMarketProductIntent(mention)) return false;
  if (food.externalSource !== "usda_fdc") return true;
  return Boolean(scoreUsdaCandidate(usdaFoodFromRecord(food), mention));
}

function cloneLocalFoodCandidate<T extends FoodItemRecord & Partial<FoodSearchCandidate>>(food: T): T {
  return {
    ...food,
    portions: food.portions?.map((portion) => ({ ...portion })),
  };
}

function hasMarketProductIntent(mention: FoodMention): boolean {
  return Boolean(mention.barcode || mention.brand || mention.marketProduct);
}

function isBrandedFood(food: FoodItemRecord): boolean {
  return food.dataType === "Branded" || food.source === "usda_branded";
}

function localFoodPriority(food: FoodItemRecord, mention: FoodMention): number {
  if (food.userId) return 0;
  if (hasMarketProductIntent(mention) && isBrandedFood(food)) return 1;
  if (food.dataType === "SR Legacy") return 2;
  if (food.dataType === "Foundation") return 3;
  if (isBrandedFood(food)) return 6;
  return 4;
}

function normalizeFoodName(value: string): string {
  const normalized = normalizeText(value)
    .replace(/\b(por favor|please)\b/g, " ")
    .replace(/\b(de|del|of|a|mi|my|the|fresh|cooked|raw|sliced)\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return singularizeLastToken(normalized);
}

function singularizeLastToken(value: string): string {
  const parts = value.split(" ").filter(Boolean);
  if (parts.length === 0) return value;
  const last = parts[parts.length - 1]!;
  if (last.length > 3 && last.endsWith("ies")) {
    parts[parts.length - 1] = `${last.slice(0, -3)}y`;
  } else if (last.length > 4 && last.endsWith("oes")) {
    parts[parts.length - 1] = last.slice(0, -2);
  } else if (last.length > 3 && last.endsWith("s") && !last.endsWith("ss")) {
    parts[parts.length - 1] = last.slice(0, -1);
  }
  return parts.join(" ");
}

function itemFromFood(
  food: FoodItemRecord,
  mention: FoodMention,
  options: {
    confidence: number;
    source: string;
    portionOptions?: PortionOption[];
    selectedPortion?: PortionOption;
    allowSeededPortionFallback?: boolean;
  },
): MealItem | null {
  const item = scaleMentionFood(food, mention, options);
  if (!item) return null;
  return {
    ...item,
    source: options.source,
    originalText: mention.originalText,
    canonicalName: food.userId ? food.canonicalName ?? food.name : canonicalNameForMention(mention),
    language: mention.language,
    externalSource: food.userId && food.source === "user_custom" ? "user_custom" : food.externalSource,
    externalId: food.userId && food.source === "user_custom" ? food.id : food.externalId,
    sourceUrl: food.sourceUrl,
    license: food.license,
    confidence: Math.min(mention.confidence, options.confidence),
    needsReview: Math.min(mention.confidence, options.confidence) < 0.9,
    displayDetails: food.displayDetails,
  };
}

function scaleMentionFood(
  food: FoodItemRecord,
  mention: FoodMention,
  options: {
    portionOptions?: PortionOption[];
    selectedPortion?: PortionOption;
    allowSeededPortionFallback?: boolean;
  },
): MealItem | null {
  if (!requiresPortionValidation(mention))
    return scaleFood(food, mention.quantity, "g");

  const portion =
    options.selectedPortion ??
    resolvePortionForMention(mention, options.portionOptions ?? []).portion ??
    (options.allowSeededPortionFallback
      ? seededFallbackPortionForMention(mention)
      : undefined);
  if (!portion) return null;

  const grams = roundOne(mention.quantity * portion.gramWeight);
  const item: MealItemWithResolvedGrams = {
    ...scaleFood(food, grams, portionDisplayUnit(mention, portion)),
    quantity: mention.quantity,
    unit: portionDisplayUnit(mention, portion),
    resolvedGrams: grams,
    portionDescription: portion.sourceDescription,
  };
  Object.defineProperty(item, resolvedGramsSymbol, { value: grams });
  return item;
}

function localConfidence(food: FoodItemRecord, mention: FoodMention): number {
  if (isNormalizedSearchFood(food)) {
    return normalizedFoodFit(food, mention).confidence;
  }
  if (food.externalSource === "usda_fdc") {
    const score = scoreUsdaCandidate(usdaFoodFromRecord(food), mention);
    if (!score) return 0.2;
    const localCorpusBoost =
      food.dataType === "SR Legacy" ? 0.04 :
        food.dataType === "Foundation" ? 0.01 :
          0;
    return Math.min(0.99, roundTwo(score.confidence + localCorpusBoost));
  }
  const canonical = normalizeText(food.canonicalName ?? food.normalizedName);
  const mentionCanonical = canonicalNameForMention(mention);
  if (canonical === mentionCanonical) return 0.96;
  if (food.normalizedName === mentionCanonical)
    return 0.94;
  return 0.78;
}

type NormalizedFoodFit = {
  compatible: boolean;
  confidence: number;
};

function isNormalizedSearchFood(food: FoodItemRecord): boolean {
  return Boolean(
    food.normalizedBaseName ||
      food.normalizedDisplayName ||
      food.normalizedResultType,
  );
}

function normalizedFoodFit(food: FoodItemRecord, mention: FoodMention): NormalizedFoodFit {
  const queryTokens = uniqueTokens(meaningfulFoodTokens(canonicalNameForMention(mention)));
  if (queryTokens.length === 0) return { compatible: false, confidence: 0.1 };

  const candidateText = normalizeText([
    food.normalizedBaseName,
    food.normalizedDisplayName,
    food.normalizedVariantName,
    food.normalizedBrandDisplay ?? food.brand,
  ].filter((value): value is string => Boolean(value)).join(" "));
  const candidateTokens = uniqueTokens(meaningfulFoodTokens(candidateText));
  if (candidateTokens.length === 0) return { compatible: false, confidence: 0.1 };

  const candidateTokenSet = new Set(candidateTokens);
  const missingTokens = queryTokens.filter((token) => !candidateTokenSet.has(token));
  if (missingTokens.length > 0) return { compatible: false, confidence: 0.2 };

  const queryTokenSet = new Set(queryTokens);
  const extraTokenCount = candidateTokens.filter((token) => !queryTokenSet.has(token)).length;
  const queryText = queryTokens.join(" ");
  const compactCandidateText = candidateTokens.join(" ");
  const exactBaseMatch =
    normalizeText(food.normalizedBaseName ?? "") === queryText ||
    normalizeText(food.normalizedDisplayName ?? "") === queryText;
  const contiguousPhrase = tokenPhraseIndex(candidateTokens, queryTokens);
  const phraseBonus =
    exactBaseMatch ? 0.13 :
      contiguousPhrase === 0 ? 0.06 :
        contiguousPhrase > 0 ? 0.03 :
          0;
  const compactnessPenalty = Math.min(
    0.34,
    extraTokenCount * 0.04 +
      Math.max(compactCandidateText.length - queryText.length, 0) * 0.002,
  );
  const confidence = Math.max(
    0.1,
    Math.min(0.98, roundTwo(0.84 + phraseBonus - compactnessPenalty)),
  );
  return { compatible: confidence >= 0.55, confidence };
}

function uniqueTokens(tokens: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const token of tokens) {
    if (seen.has(token)) continue;
    seen.add(token);
    result.push(token);
  }
  return result;
}

function tokenPhraseIndex(tokens: string[], phraseTokens: string[]): number {
  if (phraseTokens.length === 0 || phraseTokens.length > tokens.length) return -1;
  for (let index = 0; index <= tokens.length - phraseTokens.length; index += 1) {
    if (phraseTokens.every((token, phraseIndex) => tokens[index + phraseIndex] === token)) {
      return index;
    }
  }
  return -1;
}

function usdaFoodFromRecord(food: FoodItemRecord): UsdaFood {
  return {
    fdcId: Number(food.externalId ?? 0),
    description: food.name,
    dataType: food.dataType,
  };
}

type UsdaCandidateScore = {
  confidence: number;
  matchedTokenCount: number;
  extraPenalty: number;
};

export function scoreUsdaCandidate(
  food: Pick<UsdaFood, "description" | "dataType">,
  mention: FoodMention,
): UsdaCandidateScore | null {
  const canonicalName = canonicalNameForMention(mention);
  const canonicalTokens = meaningfulFoodTokens(canonicalName);
  if (canonicalTokens.length === 0) return null;

  const description = food.description ?? "";
  const descriptionTokens = tokenizeFoodText(description);
  if (descriptionTokens.length === 0) return null;

  const descriptionTokenSet = new Set(descriptionTokens);
  const matchedTokenCount = canonicalTokens.filter((token) =>
    descriptionTokenSet.has(token),
  ).length;
  if (matchedTokenCount !== canonicalTokens.length) return null;

  const normalizedDescription = normalizeText(description);
  const normalizedCanonical = normalizeText(canonicalName);
  const inputTokenSet = new Set([
    ...meaningfulFoodTokens(canonicalName),
    ...meaningfulFoodTokens(mention.originalText),
  ]);
  const segments = description
    .split(",")
    .map((segment) => tokenizeFoodText(segment))
    .filter((segment) => segment.length > 0);
  const firstSegment = segments[0] ?? [];
  const firstSegmentIsCanonical =
    firstSegment.length === canonicalTokens.length &&
    canonicalTokens.every((token, index) => firstSegment[index] === token);
  const firstToken = descriptionTokens[0];
  const canonicalTokenSet = new Set(canonicalTokens);
  const canonicalIndexes = canonicalTokens
    .map((token) => descriptionTokens.indexOf(token))
    .filter((index) => index >= 0);
  const firstCanonicalIndex = Math.min(...canonicalIndexes);

  let confidence = 0.55 + 0.2 * (matchedTokenCount / canonicalTokens.length);
  if (food.dataType === "Foundation") confidence += 0.04;
  if (food.dataType === "SR Legacy") confidence += 0.03;

  if (normalizedDescription === normalizedCanonical) {
    confidence += 0.18;
  } else if (
    canonicalTokens.length > 1 &&
    (normalizedDescription.startsWith(`${normalizedCanonical} `) ||
      descriptionContainsTokenPhrase(descriptionTokens, canonicalTokens))
  ) {
    confidence += 0.13;
  }

  if (canonicalTokens.length === 1) {
    const token = canonicalTokens[0]!;
    if (firstSegmentIsCanonical) confidence += 0.22;
    else if (firstToken === token) confidence += 0.08;
    else if (firstSegment.includes(token)) confidence += 0.1;
    else if (firstToken && usdaCategoryWords.has(firstToken))
      confidence += 0.04;
    else confidence -= 0.08;
  } else {
    const sameSegment = segments.some((segment) =>
      canonicalTokens.every((token) => segment.includes(token)),
    );
    if (sameSegment) confidence += 0.1;
    if (firstSegment.some((token) => canonicalTokenSet.has(token)))
      confidence += 0.04;
    if (firstCanonicalIndex > 2) confidence -= 0.05;
  }

  const extraPenalty = usdaExtraDescriptionPenalty(
    descriptionTokens,
    canonicalTokenSet,
    inputTokenSet,
    firstCanonicalIndex,
    firstSegmentIsCanonical,
  );
  confidence -= extraPenalty;

  if (descriptionHasUnrequestedConnector(normalizedDescription, inputTokenSet)) {
    confidence -= 0.08;
  }

  confidence = Math.max(0.1, Math.min(0.97, roundTwo(confidence)));
  if (confidence < 0.55) return null;
  return { confidence, matchedTokenCount, extraPenalty: roundTwo(extraPenalty) };
}

function descriptionContainsTokenPhrase(
  descriptionTokens: string[],
  phraseTokens: string[],
): boolean {
  if (
    phraseTokens.length === 0 ||
    phraseTokens.length > descriptionTokens.length
  )
    return false;
  for (
    let index = 0;
    index <= descriptionTokens.length - phraseTokens.length;
    index++
  ) {
    if (
      phraseTokens.every(
        (token, phraseIndex) => descriptionTokens[index + phraseIndex] === token,
      )
    ) {
      return true;
    }
  }
  return false;
}

function usdaExtraDescriptionPenalty(
  descriptionTokens: string[],
  canonicalTokenSet: Set<string>,
  inputTokenSet: Set<string>,
  firstCanonicalIndex: number,
  firstSegmentIsCanonical: boolean,
): number {
  let penalty = 0;
  const canonicalStartsDescription = firstCanonicalIndex === 0;
  const hasLeadingCategory = descriptionTokens
    .slice(0, firstCanonicalIndex)
    .some((token) => usdaCategoryWords.has(token));
  for (const [index, token] of descriptionTokens.entries()) {
    if (
      canonicalTokenSet.has(token) ||
      inputTokenSet.has(token) ||
      usdaScoringStopWords.has(token) ||
      usdaNeutralDescriptorWords.has(token) ||
      usdaCategoryWords.has(token)
    ) {
      continue;
    }
    if (usdaStrongFormWords.has(token)) {
      penalty += index < firstCanonicalIndex ? 0.28 : 0.25;
      continue;
    }
    if (usdaPartDescriptorWords.has(token)) {
      penalty += 0.12;
      continue;
    }
    penalty +=
      index < firstCanonicalIndex
        ? hasLeadingCategory
          ? 0.035
          : 0.16
        : firstSegmentIsCanonical
          ? 0.025
          : canonicalStartsDescription
          ? 0.14
          : 0.025;
  }
  return Math.min(0.45, penalty);
}

function descriptionHasUnrequestedConnector(
  description: string,
  inputTokenSet: Set<string>,
): boolean {
  if (inputTokenSet.has("with") || inputTokenSet.has("and")) return false;
  if (/\bwith\s+(skin|salt)\b/.test(description)) return false;
  return /\b(with|and|blend|mixed|mixture)\b/.test(description);
}

function meaningfulFoodTokens(value: string): string[] {
  return tokenizeFoodText(value).filter(
    (token) => !usdaScoringStopWords.has(token) && token.length > 1,
  );
}

function tokenizeFoodText(value: string): string[] {
  return normalizeText(value)
    .split(/\s+/)
    .filter(Boolean)
    .map(singularizeToken);
}

function singularizeToken(token: string): string {
  if (token.length > 3 && token.endsWith("ies")) return `${token.slice(0, -3)}y`;
  if (token.length > 4 && token.endsWith("oes")) return token.slice(0, -2);
  if (token.length > 3 && token.endsWith("s") && !token.endsWith("ss"))
    return token.slice(0, -1);
  return token;
}

function roundTwo(value: number): number {
  return Math.round(value * 100) / 100;
}

function normalizeUnit(unit: string, canonicalName?: string): string {
  const normalized = normalizeText(unit);
  if (
    [
      "kg",
      "kilogram",
      "kilograms",
      "kilo",
      "kilos",
      "oz",
      "ounce",
      "ounces",
    ].includes(normalized)
  )
    return "g";
  if (["g", "gr", "gramo", "gramos", "gram", "grams"].includes(normalized))
    return "g";

  const householdUnit = householdUnitAliases.get(normalized);
  if (householdUnit) return householdUnit;

  return normalized || "g";
}

function parseUnitKind(
  value: unknown,
  rawUnitText: string,
  unit: string,
  canonicalName: string,
): UnitKind {
  if (
    value === "metric" ||
    value === "household" ||
    value === "implicit_count" ||
    value === "unknown"
  )
    return value;
  return inferUnitKind(rawUnitText || unit, unit, canonicalName);
}

function inferUnitKind(
  rawUnitText: string,
  unit: string,
  canonicalName?: string,
): UnitKind {
  const raw = normalizeText(rawUnitText);
  const normalizedUnit = normalizeUnit(unit, canonicalName);
  if (normalizedUnit === "g" || metricUnits.has(raw)) return "metric";
  if (
    householdUnitAliases.has(raw) ||
    householdCanonicalUnits.has(normalizedUnit)
  )
    return "household";
  if (
    canonicalName &&
    (raw === normalizeText(canonicalName) ||
      normalizedUnit === normalizeText(canonicalName))
  ) {
    return "implicit_count";
  }
  return "unknown";
}

function requiresPortionValidation(mention: FoodMention): boolean {
  return unitKindForMention(mention) !== "metric";
}

function unitKindForMention(mention: FoodMention): UnitKind {
  return (
    mention.unitKind ??
    inferUnitKind(
      mention.rawUnitText ?? mention.unit,
      mention.unit,
      canonicalNameForMention(mention),
    )
  );
}

function normalizeProviderResolution(
  result: MealItem[] | FoodProviderResolution,
): FoodProviderResolution {
  return Array.isArray(result) ? { items: result } : result;
}

function annotateCandidateMetadata(candidates: MealItem[]): MealItem[] {
  return candidates.slice(0, 10).map((candidate, index) => {
    candidate.rank = index + 1;
    candidate.matchScore ??= candidate.confidence;
    candidate.lexicalScore ??= candidate.confidence;
    candidate.matchReason ??= candidate.externalSource ?? candidate.source;
    return candidate;
  });
}

function compareFoodCandidates(a: MealItem, b: MealItem): number {
  if (a.matchReason === "normalized_search" && b.matchReason === "normalized_search") {
    return (
      (b.matchScore ?? 0) - (a.matchScore ?? 0) ||
      (b.confidence ?? 0) - (a.confidence ?? 0) ||
      (b.preferenceScore ?? 0) - (a.preferenceScore ?? 0) ||
      (b.vectorScore ?? 0) - (a.vectorScore ?? 0) ||
      (b.lexicalScore ?? 0) - (a.lexicalScore ?? 0) ||
      a.name.localeCompare(b.name)
    );
  }
  return (
    recommendationScore(b) - recommendationScore(a) ||
    (b.confidence ?? 0) - (a.confidence ?? 0) ||
    (b.matchScore ?? 0) - (a.matchScore ?? 0) ||
    (b.preferenceScore ?? 0) - (a.preferenceScore ?? 0) ||
    (b.vectorScore ?? 0) - (a.vectorScore ?? 0) ||
    (b.lexicalScore ?? 0) - (a.lexicalScore ?? 0) ||
    a.name.localeCompare(b.name)
  );
}

function recommendationScore(item: MealItem): number {
  const confidence = item.confidence ?? item.matchScore ?? 0;
  const matchScore = item.matchScore ?? confidence;
  const preferenceScore = Math.max(-1, Math.min(1, item.preferenceScore ?? 0));
  const vectorScore = item.vectorScore ?? 0;
  const lexicalScore = item.lexicalScore ?? 0;
  return (
    confidence * 0.72 +
    matchScore * 0.18 +
    preferenceScore * 0.07 +
    vectorScore * 0.02 +
    lexicalScore * 0.01
  );
}

function resolvedGrams(item: MealItem): number | undefined {
  const value = (item as MealItemWithResolvedGrams)[resolvedGramsSymbol];
  return isNumber(value) ? value : undefined;
}

function mergeDuplicateMentions(mentions: FoodMention[]): FoodMention[] {
  const deduped = new Map<string, FoodMention>();
  for (const mention of mentions) {
    const key = `${canonicalNameForMention(mention)}:${mention.quantity}:${
      mention.unit
    }:${mention.portionDescriptor ?? ""}`;
    if (!deduped.has(key)) deduped.set(key, mention);
  }
  return [...deduped.values()];
}

const portionDescriptorAliases = new Map<string, PortionSize>([
  ["extra small", "extra small"],
  ["extrasmall", "extra small"],
  ["xs", "extra small"],
  ["small", "small"],
  ["sm", "small"],
  ["medium", "medium"],
  ["med", "medium"],
  ["large", "large"],
  ["lg", "large"],
  ["extra large", "extra large"],
  ["extralarge", "extra large"],
  ["xl", "extra large"],
  ["x large", "extra large"],
  ["jumbo", "jumbo"],
]);

const countWords = new Map<string, number>([
  ["a", 1],
  ["an", 1],
  ["one", 1],
  ["two", 2],
  ["three", 3],
  ["four", 4],
  ["five", 5],
  ["six", 6],
  ["seven", 7],
  ["eight", 8],
  ["nine", 9],
  ["ten", 10],
  ["un", 1],
  ["una", 1],
  ["uno", 1],
  ["dos", 2],
  ["tres", 3],
  ["cuatro", 4],
  ["cinco", 5],
  ["seis", 6],
  ["siete", 7],
  ["ocho", 8],
  ["nueve", 9],
  ["diez", 10],
]);

const metricUnits = new Set([
  "g",
  "gr",
  "gram",
  "grams",
  "gramo",
  "gramos",
  "kg",
  "kilogram",
  "kilograms",
  "kilo",
  "kilos",
  "oz",
  "ounce",
  "ounces",
]);

const householdUnitAliases = new Map<string, string>([
  ["cup", "cup"],
  ["cups", "cup"],
  ["taza", "cup"],
  ["tazas", "cup"],
  ["tbsp", "tablespoon"],
  ["tablespoon", "tablespoon"],
  ["tablespoons", "tablespoon"],
  ["cucharada", "tablespoon"],
  ["cucharadas", "tablespoon"],
  ["tsp", "teaspoon"],
  ["teaspoon", "teaspoon"],
  ["teaspoons", "teaspoon"],
  ["cucharadita", "teaspoon"],
  ["cucharaditas", "teaspoon"],
  ["slice", "slice"],
  ["slices", "slice"],
  ["rebanada", "slice"],
  ["rebanadas", "slice"],
  ["piece", "piece"],
  ["pieces", "piece"],
  ["pieza", "piece"],
  ["piezas", "piece"],
  ["serving", "serving"],
  ["servings", "serving"],
  ["portion", "serving"],
  ["portions", "serving"],
  ["breast", "breast"],
  ["breasts", "breast"],
  ["leg", "leg"],
  ["legs", "leg"],
  ["fruit", "fruit"],
  ["fruits", "fruit"],
  ["item", "item"],
  ["items", "item"],
  ["unit", "unit"],
  ["units", "unit"],
  ["egg", "egg"],
  ["eggs", "egg"],
  ["huevo", "egg"],
  ["huevos", "egg"],
]);

const householdCanonicalUnits = new Set(householdUnitAliases.values());

// These vocabularies only score USDA result descriptions after a provider
// search. They are not ingredient aliases and must not trigger local nutrition
// estimates.
const usdaScoringStopWords = new Set([
  "a",
  "an",
  "and",
  "de",
  "del",
  "for",
  "in",
  "of",
  "or",
  "the",
  "to",
  "with",
  "only",
]);

const usdaNeutralDescriptorWords = new Set([
  "boneless",
  "broiler",
  "chopped",
  "clarified",
  "commercial",
  "commercially",
  "cooked",
  "delicious",
  "diced",
  "drained",
  "dry",
  "extra",
  "fresh",
  "fryer",
  "frozen",
  "golden",
  "green",
  "large",
  "light",
  "medium",
  "plain",
  "prepared",
  "raw",
  "red",
  "ripe",
  "salted",
  "skin",
  "skinless",
  "sliced",
  "small",
  "toasted",
  "unsalted",
  "unsweetened",
  "virgin",
  "whole",
]);

const usdaCategoryWords = new Set([
  "cereal",
  "dairy",
  "fish",
  "food",
  "fruit",
  "grain",
  "meat",
  "poultry",
  "seed",
  "vegetable",
]);

// Product-form descriptors that make a USDA hit less likely to be the requested
// generic ingredient unless the user asked for that form.
const usdaStrongFormWords = new Set([
  "bar",
  "battered",
  "beverage",
  "blend",
  "breaded",
  "cake",
  "candy",
  "capsule",
  "concentrate",
  "cookie",
  "cracker",
  "deli",
  "dessert",
  "dressing",
  "drink",
  "extract",
  "flour",
  "fried",
  "gravy",
  "glazed",
  "honey",
  "juice",
  "lunchmeat",
  "luncheon",
  "mayonnaise",
  "mix",
  "nugget",
  "oil",
  "oven",
  "patty",
  "powder",
  "prepackaged",
  "roll",
  "rotisserie",
  "sauce",
  "sausage",
  "seasoned",
  "smoked",
  "soup",
  "spread",
  "supplement",
  "syrup",
  "tablet",
  "tender",
]);

const usdaPartDescriptorWords = new Set([
  "breast",
  "kernel",
  "leg",
  "peel",
  "seed",
  "shell",
  "thigh",
  "white",
  "wing",
  "yolk",
]);

const countPrefixUnits = new Set([
  "cup",
  "cups",
  "taza",
  "tazas",
  "tbsp",
  "tablespoon",
  "tablespoons",
  "cucharada",
  "cucharadas",
  "tsp",
  "teaspoon",
  "teaspoons",
  "cucharadita",
  "cucharaditas",
  "slice",
  "slices",
  "rebanada",
  "rebanadas",
  "piece",
  "pieces",
  "pieza",
  "piezas",
  "serving",
  "servings",
  "portion",
  "portions",
  "breast",
  "breasts",
  "leg",
  "legs",
]);

const seededPortionFallbacks = new Map<string, PortionOption[]>([
  [
    "egg",
    [
      {
        unitName: "egg",
        aliases: ["egg", "eggs", "huevo", "huevos"],
        gramWeight: 50,
        sourceDescription: "local seeded egg portion",
        kind: "whole_item",
      },
    ],
  ],
]);

function countTokenPattern(): string {
  return `\\d+(?:[\\.,]\\d+)?|${[...countWords.keys()].map(escapeRegExp).join("|")}`;
}

function portionDescriptorPattern(): string {
  return [...portionDescriptorAliases.keys()]
    .sort((a, b) => b.length - a.length)
    .map(escapeRegExp)
    .join("|");
}

function normalizePortionDescriptor(value?: string): PortionSize | undefined {
  const normalized = normalizeText(value ?? "");
  if (!normalized) return undefined;
  const exact = portionDescriptorAliases.get(normalized);
  if (exact) return exact;
  if (/\bextra\s+small\b|\bxs\b/.test(normalized)) return "extra small";
  if (/\bextra\s+large\b|\bxl\b|\bx\s+large\b/.test(normalized))
    return "extra large";
  if (/\bjumbo\b/.test(normalized)) return "jumbo";
  if (/\bmedium\b|\bmed\b/.test(normalized)) return "medium";
  if (/\blarge\b|\blg\b/.test(normalized)) return "large";
  if (/\bsmall\b|\bsm\b/.test(normalized)) return "small";
  return undefined;
}

function parseCountToken(token: string): number | null {
  const normalized = normalizeText(token);
  if (/^\d+(?:[\.,]\d+)?$/.test(normalized))
    return Number(normalized.replace(",", "."));
  return countWords.get(normalized) ?? null;
}

function householdUnitPattern(): string {
  return [...householdUnitAliases.keys()]
    .sort((a, b) => b.length - a.length)
    .map(escapeRegExp)
    .join("|");
}

function seededFallbackPortionForMention(
  mention: FoodMention,
): PortionOption | undefined {
  return findMatchingPortion(
    mention,
    seededPortionFallbacks.get(canonicalNameForMention(mention)) ??
      [],
  );
}

type PortionResolution = {
  portion?: PortionOption;
  reason?: FoodCandidateGroup["reason"];
  choices?: FoodPortionChoice[];
};

function resolvePortionForMention(
  mention: FoodMention,
  portions: PortionOption[],
): PortionResolution {
  if (!requiresPortionValidation(mention)) return {};
  const descriptor = mention.portionDescriptor;
  const unitKind = unitKindForMention(mention);

  if (descriptor) {
    const portion = portions.find(
      (option) =>
        (option.kind === "count_size" || option.kind === "whole_item") &&
        (option.size === descriptor ||
          option.aliases.map(normalizeText).includes(descriptor)),
    );
    if (portion) return { portion };
    return {
      reason: "unsupported_unit",
      choices: portionChoicesForMention(mention, portions),
    };
  }

  if (unitKind === "household") {
    const portion = findExplicitUnitPortion(mention, portions);
    if (portion) return { portion };
    return {
      reason: "unsupported_unit",
      choices: portionChoicesForMention(mention, portions),
    };
  }

  if (unitKind === "implicit_count") {
    const countOptions = implicitCountPortions(portions);
    if (countOptions.length === 1) return { portion: countOptions[0] };
    if (countOptions.length > 1) {
      return {
        reason: "ambiguous_portion",
        choices: portionChoicesForMention(mention, countOptions),
      };
    }
    return {
      reason: "unsupported_unit",
      choices: portionChoicesForMention(mention, portions),
    };
  }

  return {
    reason: "unsupported_unit",
    choices: portionChoicesForMention(mention, portions),
  };
}

function findMatchingPortion(
  mention: FoodMention,
  portions: PortionOption[],
): PortionOption | undefined {
  return resolvePortionForMention(mention, portions).portion;
}

function findExplicitUnitPortion(
  mention: FoodMention,
  portions: PortionOption[],
): PortionOption | undefined {
  if (!requiresPortionValidation(mention)) return undefined;
  const unitKind = unitKindForMention(mention);
  const desired = normalizeText(mention.unit);
  const raw = normalizeText(mention.rawUnitText ?? mention.unit);
  const canonical = canonicalNameForMention(mention);
  const foodAliases = aliasesForCanonical(canonical);

  return portions.find((portion) => {
    const aliases = new Set(portion.aliases.map(normalizeText));
    if (unitKind === "household") {
      return aliases.has(desired) || aliases.has(raw);
    }
    if (unitKind === "implicit_count") {
      if (aliases.has(raw) || aliases.has(desired)) return true;
      if (foodAliases.some((alias) => aliases.has(alias))) return true;
      return ["whole", "piece", "item", "each", "fruit", "unit"].some((alias) =>
        aliases.has(alias),
      );
    }
    return false;
  });
}

function implicitCountPortions(portions: PortionOption[]): PortionOption[] {
  return portions.filter(
    (portion) => portion.kind === "count_size" || portion.kind === "whole_item",
  );
}

function portionChoicesForMention(
  mention: FoodMention,
  portions: PortionOption[],
): FoodPortionChoice[] {
  const seen = new Set<string>();
  const choices: FoodPortionChoice[] = [];
  for (const portion of portions) {
    if (portion.kind === "serving") continue;
    const unit = portionDisplayUnit(mention, portion);
    const key = `${unit}:${portion.gramWeight}:${portion.sourceDescription}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const totalGrams = roundOne(mention.quantity * portion.gramWeight);
    const canonicalName = canonicalNameForMention(mention);
    const label =
      portion.kind === "household" || portion.kind === "piece_shape"
        ? `${formatQuantity(mention.quantity)} ${unit} ${canonicalName}`
        : `${formatQuantity(mention.quantity)} ${unit}`;
    choices.push({
      label,
      quantity: mention.quantity,
      unit,
      gramWeight: portion.gramWeight,
      totalGrams,
      kind: portion.kind,
      portionDescriptor: portion.size ?? portion.shape,
      canonicalFoodName: canonicalName,
      sourceDescription: portion.sourceDescription,
      externalSource: "usda_fdc",
      externalFoodId: portion.externalFoodId,
      actionText: `Add ${label}`,
    });
  }
  if (!seen.has("g:1:metric")) {
    choices.push({
      label: "Use grams",
      quantity: 1,
      unit: "g",
      gramWeight: 1,
      kind: "metric",
      canonicalFoodName: canonicalNameForMention(mention),
    });
  }
  return choices;
}

function portionDisplayUnit(
  mention: FoodMention,
  portion: PortionOption,
): string {
  if (portion.kind === "count_size" && portion.size) {
    return pluralizeUnit(
      `${portion.size} ${baseCountUnit(mention)}`,
      mention.quantity,
    );
  }
  if (portion.kind === "whole_item") {
    return pluralizeUnit(
      portion.unitName || baseCountUnit(mention),
      mention.quantity,
    );
  }
  return pluralizeUnit(portion.unitName, mention.quantity);
}

function baseCountUnit(mention: FoodMention): string {
  const normalized = normalizeText(mention.unit);
  if (normalized && normalized !== "g") return normalized;
  return canonicalNameForMention(mention);
}

function pluralizeUnit(unit: string, quantity: number): string {
  if (quantity === 1) return unit;
  const parts = unit.split(" ");
  const last = parts.pop() ?? unit;
  const plural = last.endsWith("s")
    ? last
    : last.endsWith("y")
      ? `${last.slice(0, -1)}ies`
      : `${last}s`;
  return [...parts, plural].join(" ");
}

function formatQuantity(value: number): string {
  return Number.isInteger(value) ? String(value) : String(value);
}

function aliasesForCanonical(canonicalName: string): string[] {
  const normalized = normalizeText(canonicalName);
  return [...new Set([normalized, ...normalized.split(" ").filter(Boolean)])];
}

function portionOptionsFromFoodPortions(
  portions: FoodPortionRecord[],
  externalFoodId?: string,
): PortionOption[] {
  return portions
    .map((portion) => portionOptionFromFoodPortion(portion, externalFoodId))
    .filter((portion): portion is PortionOption => Boolean(portion));
}

function portionOptionFromFoodPortion(
  portion: FoodPortionRecord,
  externalFoodId?: string,
): PortionOption | null {
  if (!isNumber(portion.gramWeight) || portion.gramWeight <= 0) return null;
  const sourceDescription =
    portion.sourceDescription ||
    [portion.amount, portion.unit, portion.modifier, portion.description]
      .filter((part) => part !== undefined && part !== null && String(part).trim())
      .join(" ");
  const aliases = [
    ...(portion.normalizedAliases ?? []),
    ...aliasesFromPortionUnit(portion.unit),
    ...aliasesFromPortionDescription(portion.modifier),
    ...aliasesFromPortionDescription(portion.description),
    ...aliasesFromPortionDescription(sourceDescription),
  ].map(normalizeText).filter(Boolean);
  const sourceText = normalizeText(sourceDescription);
  const size = normalizePortionDescriptor(sourceText);
  const kind = isKnownPortionKind(portion.kind)
    ? portion.kind
    : classifyPortionKind(sourceText, size);
  const shape = shapeFromPortionDescription(sourceText, kind);
  const unitName = unitNameForPortion(kind, size, shape, aliases, sourceText);
  if (aliases.length === 0) return null;
  return {
    unitName,
    aliases: [...new Set(aliases)],
    gramWeight: roundOne(portion.gramWeight),
    sourceDescription,
    externalFoodId,
    kind,
    size,
    shape,
  };
}

function isKnownPortionKind(value: string): value is PortionKind {
  return ["count_size", "whole_item", "household", "piece_shape", "serving"].includes(value);
}

function classifyPortionKind(
  sourceText: string,
  size?: PortionSize,
): PortionKind {
  if (
    /\b(cup|cups|tbsp|tablespoon|tablespoons|tsp|teaspoon|teaspoons)\b/.test(
      sourceText,
    )
  )
    return "household";
  if (
    /\b(slice|slices|wedge|wedges|piece|pieces|clove|cloves|head|heads|stalk|stalks|bunch|bunches|breast|breasts|leg|legs|fillet|fillets)\b/.test(
      sourceText,
    )
  )
    return "piece_shape";
  if (size) return "count_size";
  if (/\b(whole|fruit|item|each)\b/.test(sourceText)) return "whole_item";
  if (/\b(racc|nlea|serving|servings)\b/.test(sourceText)) return "serving";
  return "serving";
}

function shapeFromPortionDescription(
  sourceText: string,
  kind: PortionKind,
): string | undefined {
  if (kind === "household") {
    for (const shape of ["cup", "tablespoon", "teaspoon"]) {
      if (sourceText.includes(shape) || sourceText.includes(`${shape}s`))
        return shape;
    }
    if (/\btbsp\b/.test(sourceText)) return "tablespoon";
    if (/\btsp\b/.test(sourceText)) return "teaspoon";
  }
  if (kind === "piece_shape") {
    for (const shape of [
      "slice",
      "wedge",
      "piece",
      "clove",
      "head",
      "stalk",
      "bunch",
      "breast",
      "leg",
      "fillet",
    ]) {
      if (sourceText.includes(shape) || sourceText.includes(`${shape}s`))
        return shape;
    }
  }
  if (kind === "whole_item") {
    for (const shape of ["fruit", "whole", "item", "each"]) {
      if (sourceText.includes(shape)) return shape;
    }
  }
  return undefined;
}

function unitNameForPortion(
  kind: PortionKind,
  size: PortionSize | undefined,
  shape: string | undefined,
  aliases: string[],
  sourceText: string,
): string {
  if (kind === "count_size" && size) return size;
  if (shape) return shape;
  const usefulAlias = aliases.find(
    (alias) => !["undetermined", "unit"].includes(alias),
  );
  if (usefulAlias) return usefulAlias;
  return sourceText || "serving";
}

function aliasesFromPortionUnit(value?: string): string[] {
  const normalized = normalizeText(value ?? "");
  if (!normalized) return [];
  const aliases = new Set<string>(aliasesFromPortionDescription(normalized));
  for (const token of normalized.split(" ")) {
    if (token.length > 1) aliases.add(token);
  }
  return [...aliases];
}

function aliasesFromPortionDescription(value?: string): string[] {
  const normalized = normalizeText(value ?? "");
  if (!normalized) return [];
  const aliases = new Set<string>();
  for (const [alias, canonical] of householdUnitAliases) {
    if ((alias === "egg" || alias === "eggs") && /\bcups?\b/.test(normalized))
      continue;
    if (new RegExp(`\\b${escapeRegExp(alias)}\\b`).test(normalized)) {
      aliases.add(alias);
      aliases.add(canonical);
    }
  }
  const hasExtraSmall = /\bextra\s+small\b/.test(normalized);
  if (hasExtraSmall) aliases.add("extra small");
  if (/\bextra\s+large\b/.test(normalized)) aliases.add("extra large");
  else if (/\blarge\b/.test(normalized)) aliases.add("large");
  for (const size of ["medium", "jumbo"]) {
    if (new RegExp(`\\b${escapeRegExp(size)}\\b`).test(normalized))
      aliases.add(size);
  }
  if (!hasExtraSmall && /\bsmall\b/.test(normalized)) aliases.add("small");
  if (/\bwhole\b/.test(normalized)) aliases.add("whole");
  if (/\beach\b/.test(normalized)) aliases.add("each");
  return [...aliases];
}

function roundOne(value: number): number {
  return Math.round(value * 10) / 10;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

type UsdaFood = {
  fdcId?: number;
  description?: string;
  dataType?: string;
};
