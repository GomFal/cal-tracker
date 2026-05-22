import type {
  FoodCandidateGroup,
  FoodMention,
  FoodPortionChoice,
  MealItem,
} from "@cal-tracker/contracts";
import type { EmbeddingProvider } from "../embeddings/provider.js";
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

export interface FoodTextExtractor {
  extract(text: string): Promise<FoodMention[]>;
}

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
const localCandidateSymbol = Symbol("localCandidate");
type MealItemWithResolvedGrams = MealItem & { [resolvedGramsSymbol]?: number };
type MealItemWithLocalMarker = MealItem & { [localCandidateSymbol]?: boolean };

function canonicalNameForMention(mention: FoodMention): string {
  return normalizeFoodName(
    mention.canonicalName ??
      mention.canonicalEnglishName ??
      mention.originalText,
  );
}

function canonicalEnglishFallbackName(mention: FoodMention): string | undefined {
  if (!mention.canonicalEnglishName) return undefined;
  const fallback = normalizeFoodName(mention.canonicalEnglishName);
  return fallback && fallback !== canonicalNameForMention(mention)
    ? fallback
    : undefined;
}

function searchQueriesForMention(mention: FoodMention): string[] {
  const queries = [
    canonicalNameForMention(mention),
    canonicalEnglishFallbackName(mention),
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
    private readonly extractor: FoodTextExtractor,
    private readonly providers: FoodDataProvider[],
    private readonly repository: AppRepository,
    private readonly minConfidence: number,
  ) {}

  async resolveMealText(
    userId: string,
    text: string,
    locale?: string,
  ): Promise<FoodResolutionResult> {
    return withSpan(
      "FoodResolver.resolveMealText",
      { textChars: text.length, locale },
      async () => {
        const mentions = await withSpan(
          "FoodTextExtractor.extract",
          undefined,
          () => this.extractor.extract(text),
        );
        return this.resolveMealMentions(userId, mentions, locale);
      },
    );
  }

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
      await this.cacheExternalCandidate(selected);
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
      marketProduct: Boolean(barcode),
    };
    const { candidates, reason, portionOptions } = await this.resolveMention(
      userId,
      mention,
      {
        includeMarketSearch: true,
      },
    );
    for (const candidate of candidates.slice(0, 3)) {
      await this.cacheExternalCandidate(candidate);
    }
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
    options: { includeMarketSearch?: boolean } = {},
  ): Promise<{
    candidates: MealItem[];
    reason?: FoodCandidateGroup["reason"];
    portionOptions?: FoodPortionChoice[];
  }> {
    const candidates: MealItem[] = [];
    let reason: FoodCandidateGroup["reason"] | undefined;
    let portionOptions: FoodPortionChoice[] | undefined;
    for (const provider of this.providers) {
      if (
        provider.id === "openfoodfacts" &&
        !options.includeMarketSearch &&
        !mention.barcode &&
        !mention.brand &&
        !mention.marketProduct
      ) {
        continue;
      }
      let resolved: FoodProviderResolution;
      try {
        resolved = normalizeProviderResolution(
          await withSpan(
            "FoodDataProvider.resolve",
            { provider: provider.id },
            () => provider.resolve(userId, mention),
          ),
        );
      } catch {
        resolved = { items: [] };
      }
      if (resolved.items.length === 0 && resolved.reason) {
        if (
          !reason ||
          resolved.reason === "ambiguous_portion" ||
          resolved.portionOptions?.length
        ) {
          reason = resolved.reason;
          portionOptions = resolved.portionOptions ?? portionOptions;
        }
      }
      candidates.push(...resolved.items);
      if (
        resolved.items.some(
          (item) => (item.confidence ?? 0) >= this.minConfidence,
        )
      )
        break;
    }
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

  private async cacheExternalCandidate(item: MealItem): Promise<void> {
    if ((item as MealItemWithLocalMarker)[localCandidateSymbol]) return;
    if (!item.externalSource || !item.externalId) return;
    await withSpan(
      "Repository.upsertFoodItem.cacheExternalCandidate",
      { externalSource: item.externalSource },
      () => this.repository.upsertFoodItem({
        name: item.name,
        normalizedName: normalizeText(item.canonicalName ?? item.name),
        canonicalName: item.canonicalName ?? item.name,
        source: item.source,
        externalSource: item.externalSource,
        externalId: item.externalId,
        sourceUrl: item.sourceUrl,
        license: item.license,
        fetchedAt: new Date().toISOString(),
        servingGrams: servingGramsForMealItem(item),
        calories: item.calories,
        proteinGrams: item.proteinGrams,
        carbsGrams: item.carbsGrams,
        fatGrams: item.fatGrams,
      }),
    );
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

function servingGramsForMealItem(item: MealItem): number {
  const grams = item.resolvedGrams ?? resolvedGrams(item);
  if (grams) return grams;
  if (item.unit === "g") return item.quantity;
  const fallbackPortion = seededFallbackPortionForMention({
    originalText: item.originalText ?? item.name,
    canonicalName: item.canonicalName ?? item.name,
    canonicalEnglishName: item.canonicalName ?? item.name,
    quantity: item.quantity,
    unit: item.unit,
    confidence: item.confidence ?? 0.8,
    marketProduct: false,
  });
  return (fallbackPortion?.gramWeight ?? 100) * item.quantity;
}

export class DeterministicFoodTextExtractor implements FoodTextExtractor {
  async extract(text: string): Promise<FoodMention[]> {
    const normalized = normalizeText(text);
    const language = inferDeterministicFoodLanguage(normalized);
    const measuredMentions = extractQuantityMentions(normalized, language);
    const countedMentions = extractCountMentions(normalized, language);
    return mergeDuplicateMentions([...measuredMentions, ...countedMentions]);
  }
}

export class OpenRouterFoodTextExtractor implements FoodTextExtractor {
  constructor(
    private readonly apiKey: string,
    private readonly model: string,
    private readonly baseUrl = "https://openrouter.ai/api/v1",
    private readonly timeoutMs = 25000,
  ) {}

  async extract(text: string): Promise<FoodMention[]> {
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: "POST",
        signal: timeoutSignal(this.timeoutMs),
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: this.model,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: [
                "Extract foods from meal text as strict JSON.",
                "For every food, preserve the user's exact food phrase in originalText.",
                "Normalize each food name in the same language as the meal text in canonicalName.",
                "Include language as an ISO 639-1 code when clear.",
                "Optionally include canonicalEnglishName as an English fallback search term, but do not replace canonicalName with English unless the user wrote English.",
                "Use common generic food names, not brands, recipes, or nutrition estimates.",
                'Return {"mentions":[{"originalText":"...","canonicalName":"...","canonicalEnglishName":"...","language":"es","quantity":100,"unit":"g","rawUnitText":"grams","unitKind":"metric","portionDescriptorRaw":"extra large","portionDescriptor":"extra large","confidence":0.9,"marketProduct":false}]}',
                "Use the text only to parse quantity, raw unit, and food name; do not decide whether a non-metric unit is valid.",
                "Use grams when the user gives gram quantities.",
                "Use household for explicit measures like cup, tbsp, slice, breast, or egg.",
                "Use implicit_count when the user gives only a number and food name, for example one egg, 1 banana, or 1 rice.",
                "Preserve count-size descriptors such as small, medium, large, extra large, XL, and jumbo.",
                "Do not invent nutrition values or calories.",
              ].join(" "),
            },
            { role: "user", content: text },
          ],
        }),
      });
    } catch {
      return [];
    }
    if (!response.ok) return [];
    const json = (await response.json()) as {
      choices?: Array<{ message?: { content?: string | null } }>;
    };
    const content = json.choices?.[0]?.message?.content;
    if (!content) return [];
    try {
      const parsed = JSON.parse(content) as { mentions?: unknown[] };
      return (parsed.mentions ?? [])
        .map(parseMention)
        .filter((mention): mention is FoodMention => Boolean(mention));
    } catch {
      return [];
    }
  }
}

export class CompositeFoodTextExtractor implements FoodTextExtractor {
  constructor(private readonly extractors: FoodTextExtractor[]) {}

  async extract(text: string): Promise<FoodMention[]> {
    for (const extractor of this.extractors) {
      const mentions = await extractor.extract(text);
      if (mentions.length > 0) return mentions;
    }
    return [];
  }
}

export class LocalFoodDataProvider implements FoodDataProvider {
  readonly id = "local";
  private readonly searchCache = new Map<string, Array<FoodItemRecord & Partial<FoodSearchCandidate>>>();

  constructor(
    private readonly repository: AppRepository,
    private readonly options: {
      allowSeededPortionFallback?: boolean;
      embeddingProvider?: EmbeddingProvider;
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
    if (
      compatibleFoods.length === 0 &&
      this.options.embeddingProvider &&
      !hasMarketProductIntent(mention)
    ) {
      compatibleFoods = (await this.searchFoods(userId, mention, canonicalNameForMention(mention)))
        .filter((food) => cachedFoodIsCompatible(food, mention))
        .sort(
          (a, b) =>
            localFoodPriority(a, mention) - localFoodPriority(b, mention),
        );
      scoringMention = mention;
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
        item.matchReason = food.vectorScore ? "hybrid_search" : item.matchReason;
        items.push(markLocalCandidate(item));
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
        hasEmbeddingProvider: Boolean(this.options.embeddingProvider),
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

    if (this.options.embeddingProvider) {
      try {
        const model = await withSpan(
          "Repository.getActiveEmbeddingModel",
          undefined,
          () => this.repository.getActiveEmbeddingModel(),
        );
        if (model) {
          const embedding = (await withSpan(
            "EmbeddingProvider.embed",
            { inputCount: 1 },
            () => this.options.embeddingProvider!.embed([query]),
          )).data[0]?.embedding;
          if (embedding) {
            const vector = await withSpan(
              "Repository.searchFoodsHybrid",
              { query, mode: "hybrid" },
              () => this.repository.searchFoodsHybrid(userId, {
                query,
                barcode: mention.barcode,
                embedding,
                embeddingModelId: model.id,
                limit: 50,
                excludeBranded: !marketIntent,
                locale,
                scope: marketIntent ? "market" : "generic",
              }),
            );
            this.setSearchCache(cacheKey, vector);
            return vector.map(cloneLocalFoodCandidate);
          }
        }
      } catch {
        // Fall back to lexical search if embeddings are unavailable.
      }
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

function markLocalCandidate(item: MealItem): MealItem {
  Object.defineProperty(item, localCandidateSymbol, { value: true });
  return item;
}

export class OpenFoodFactsFoodDataProvider implements FoodDataProvider {
  readonly id = "openfoodfacts";

  constructor(
    private readonly baseUrl: string,
    private readonly userAgent: string,
    private readonly timeoutMs = 5000,
  ) {}

  async resolve(_userId: string, mention: FoodMention): Promise<MealItem[]> {
    return withSpan(
      "OpenFoodFactsFoodDataProvider.resolve",
      { hasBarcode: Boolean(mention.barcode), canonicalName: canonicalNameForMention(mention) },
      async () => {
        const product = mention.barcode
          ? await this.fetchBarcode(mention.barcode)
          : await this.searchFirst(mention);
        const item = product ? mapOpenFoodFactsProduct(product, mention) : null;
        return item ? [item] : [];
      },
    );
  }

  private async fetchBarcode(
    barcode: string,
  ): Promise<OpenFoodFactsProduct | null> {
    const response = await withSpan(
      "OpenFoodFacts.fetchBarcode",
      undefined,
      () => fetch(
        `${this.baseUrl}/api/v2/product/${encodeURIComponent(barcode)}.json`,
        {
          signal: timeoutSignal(this.timeoutMs),
          headers: { "User-Agent": this.userAgent },
        },
      ),
    );
    if (!response.ok) return null;
    const json = (await response.json()) as {
      status?: number;
      product?: OpenFoodFactsProduct;
    };
    return json.status === 1 ? (json.product ?? null) : null;
  }

  private async searchFirst(
    mention: FoodMention,
  ): Promise<OpenFoodFactsProduct | null> {
    for (const query of searchQueriesForMention(mention)) {
      const url = new URL(`${this.baseUrl}/cgi/search.pl`);
      url.searchParams.set(
        "search_terms",
        [mention.brand, query].filter(Boolean).join(" "),
      );
      url.searchParams.set("search_simple", "1");
      url.searchParams.set("action", "process");
      url.searchParams.set("json", "1");
      url.searchParams.set("page_size", "1");
      const response = await withSpan(
        "OpenFoodFacts.search",
        { query },
        () => fetch(url, {
          signal: timeoutSignal(this.timeoutMs),
          headers: { "User-Agent": this.userAgent },
        }),
      );
      if (!response.ok) continue;
      const json = (await response.json()) as {
        products?: OpenFoodFactsProduct[];
      };
      const product = json.products?.[0];
      if (product) return product;
    }
    return null;
  }
}

export class UsdaFoodDataProvider implements FoodDataProvider {
  readonly id = "usda_fdc";
  private readonly portionCache = new Map<number, PortionOption[]>();

  constructor(
    private readonly apiKey?: string,
    private readonly baseUrl = "https://api.nal.usda.gov/fdc/v1",
    private readonly timeoutMs = 5000,
  ) {}

  async resolve(
    _userId: string,
    mention: FoodMention,
  ): Promise<FoodProviderResolution> {
    return withSpan(
      "UsdaFoodDataProvider.resolve",
      { canonicalName: canonicalNameForMention(mention) },
      () => this.resolveInternal(mention),
    );
  }

  private async resolveInternal(
    mention: FoodMention,
  ): Promise<FoodProviderResolution> {
    if (!this.apiKey)
      return {
        items: [],
        reason: requiresPortionValidation(mention)
          ? "unsupported_unit"
          : undefined,
      };
    let reason: FoodCandidateGroup["reason"] | undefined;
    let portionChoices: FoodPortionChoice[] | undefined;
    for (const query of searchQueriesForMention(mention)) {
      const searchMention = mentionForSearchQuery(mention, query);
      const url = new URL(`${this.baseUrl}/foods/search`);
      url.searchParams.set("api_key", this.apiKey);
      url.searchParams.set("query", query);
      url.searchParams.set("pageSize", "25");
      url.searchParams.set("dataType", "Foundation,SR Legacy");
      const response = await withSpan(
        "USDA.foods.search",
        { query },
        () => fetch(url, {
          signal: timeoutSignal(this.timeoutMs),
        }),
      );
      if (!response.ok) continue;
      let json: { foods?: UsdaFood[] };
      try {
        json = (await response.json()) as { foods?: UsdaFood[] };
      } catch {
        continue;
      }
      const items: MealItem[] = [];
      const scoredFoods = (json.foods ?? [])
        .map((food) => ({
          food,
          score: scoreUsdaCandidate(food, searchMention),
        }))
        .filter(
          (entry): entry is { food: UsdaFood; score: UsdaCandidateScore } =>
            Boolean(entry.score),
        )
        .sort((a, b) => b.score.confidence - a.score.confidence);
      for (const { food, score } of scoredFoods) {
        const foodWithNutrition = hasUsdaNutrition(food)
          ? food
          : ((await this.fetchFoodDetail(food.fdcId)) ?? food);
        let portionOptions: PortionOption[] | undefined;
        let portionResolution: PortionResolution | undefined;
        if (requiresPortionValidation(mention)) {
          portionOptions = await this.fetchPortionOptions(food.fdcId);
          portionResolution = resolvePortionForMention(
            mention,
            portionOptions,
          );
          if (portionResolution.reason) {
            reason ??= portionResolution.reason;
            portionChoices ??= portionResolution.choices;
          }
        }
        const item = mapUsdaFood(
          foodWithNutrition,
          mention,
          portionOptions,
          portionResolution?.portion,
          score,
        );
        if (item) {
          items.push(item);
          continue;
        }
        if (
          requiresPortionValidation(mention) &&
          hasUsdaNutrition(foodWithNutrition)
        ) {
          reason ??= portionResolution?.reason ?? "unsupported_unit";
          portionChoices ??= portionResolution?.choices;
        }
      }
      items.sort((a, b) => (b.confidence ?? 0) - (a.confidence ?? 0));
      if (items.length > 0) {
        return {
          items,
          reason: undefined,
          portionOptions: undefined,
        };
      }
    }
    return {
      items: [],
      reason,
      portionOptions: portionChoices,
    };
  }

  private async fetchPortionOptions(fdcId: number): Promise<PortionOption[]> {
    const cached = this.portionCache.get(fdcId);
    if (cached) return cached;
    const detail = await withSpan(
      "USDA.fetchFoodDetail.forPortions",
      { fdcId },
      () => this.fetchFoodDetail(fdcId),
    );
    const options = detail ? normalizeUsdaPortions(detail, String(fdcId)) : [];
    this.portionCache.set(fdcId, options);
    return options;
  }

  private async fetchFoodDetail(fdcId: number): Promise<UsdaFood | null> {
    const url = new URL(`${this.baseUrl}/food/${fdcId}`);
    url.searchParams.set("api_key", this.apiKey!);
    try {
      const response = await withSpan(
        "USDA.food.detail",
        { fdcId },
        () => fetch(url, {
          signal: timeoutSignal(this.timeoutMs),
        }),
      );
      if (!response.ok) return null;
      return (await response.json()) as UsdaFood;
    } catch {
      return null;
    }
  }
}

function extractQuantityMentions(
  text: string,
  language?: string,
): FoodMention[] {
  const mentions: FoodMention[] = [];
  const metricUnitPattern =
    "g|gr|gramo|gramos|gram|grams|kg|kilogram|kilograms|kilo|kilos|oz|ounce|ounces";
  const unit = `(${metricUnitPattern})`;
  const followingMetricQuantity =
    `\\s+\\d+(?:[\\.,]\\d+)?\\s*(?:${metricUnitPattern})\\b`;
  const quantityBefore = new RegExp(
    `(\\d+(?:[\\.,]\\d+)?)\\s*${unit}\\b\\s*(?:de\\s+|of\\s+)?([a-z][a-z\\s]{0,40}?)(?=\\s+(?:y|and)\\s+|${followingMetricQuantity}|,|\\.|$)`,
    "g",
  );
  for (const match of text.matchAll(quantityBefore)) {
    const quantity = normalizeQuantity(
      Number(match[1]!.replace(",", ".")),
      match[2]!,
    );
    const unitValue = normalizeUnit(match[2]!);
    const originalText = match[3]!.trim();
    mentions.push(
      buildMention(
        originalText,
        quantity,
        unitValue,
        match[2],
        "metric",
        originalText,
        language,
      ),
    );
  }

  const householdUnit = householdUnitPattern();
  const countPattern = countTokenPattern();
  const householdBefore = new RegExp(
    `\\b(${countPattern})\\s+(${householdUnit})\\b\\s*(?:de\\s+|of\\s+)?([a-z][a-z\\s]{0,40}?)(?=\\s+(?:y|and)\\s+|,|\\.|$)`,
    "g",
  );
  for (const match of text.matchAll(householdBefore)) {
    const quantity = parseCountToken(match[1]!);
    if (!quantity) continue;
    const rawUnitText = match[2]!;
    const foodText = match[3]!.trim();
    mentions.push(
      buildMention(
        foodText,
        quantity,
        normalizeUnit(rawUnitText, normalizeFoodName(foodText)),
        rawUnitText,
        "household",
        `${match[1]} ${rawUnitText} ${foodText}`,
        language,
      ),
    );
  }
  return mergeDuplicateMentions(mentions);
}

function extractCountMentions(text: string, language?: string): FoodMention[] {
  const mentions: FoodMention[] = [];
  const countPattern = countTokenPattern();
  const descriptorPattern = portionDescriptorPattern();
  const pattern = new RegExp(
    `\\b(${countPattern})\\s+(?:(${descriptorPattern})\\s+)?(?:de\\s+|of\\s+)?([a-z][a-z\\s]{0,40}?)(?=\\s+(?:y|and)\\s+|,|\\.|$)`,
    "g",
  );
  for (const match of text.matchAll(pattern)) {
    const quantity = parseCountToken(match[1]!);
    if (!quantity) continue;
    const portionDescriptorRaw = match[2]?.trim();
    const portionDescriptor = normalizePortionDescriptor(portionDescriptorRaw);
    const foodText = match[3]!.trim();
    const firstFoodToken = normalizeText(foodText).split(" ")[0] ?? "";
    if (metricUnits.has(firstFoodToken) || countPrefixUnits.has(firstFoodToken))
      continue;
    const canonical = normalizeFoodName(foodText);
    mentions.push({
      originalText: [match[1], portionDescriptorRaw, foodText]
        .filter(Boolean)
        .join(" "),
      canonicalName: canonical,
      canonicalEnglishName: canonical,
      quantity,
      unit: normalizeUnit(foodText, canonical),
      rawUnitText: foodText,
      unitKind: "implicit_count",
      portionDescriptorRaw,
      portionDescriptor,
      confidence: 0.86,
      marketProduct: false,
      ...(language ? { language } : {}),
    });
  }
  return mergeDuplicateMentions(mentions);
}

function buildMention(
  foodText: string,
  quantity: number,
  unit: string,
  rawUnitText: string,
  unitKind: UnitKind,
  originalText = foodText,
  language?: string,
): FoodMention {
  const canonicalName = normalizeFoodName(foodText);
  return {
    originalText,
    canonicalName,
    canonicalEnglishName: canonicalName,
    quantity,
    unit,
    rawUnitText,
    unitKind,
    confidence: unitKind === "metric" || unitKind === "household" ? 0.86 : 0.78,
    marketProduct: false,
    ...(language ? { language } : {}),
  };
}

function inferDeterministicFoodLanguage(text: string): "es" | "en" | undefined {
  if (
    /\b(anade|anademe|agrega|agregame|gramo|gramos|kilo|kilos|taza|tazas|cucharada|cucharadas|cucharadita|cucharaditas|rebanada|rebanadas|pieza|piezas|desayuno|comida|cena|almuerzo|merienda|por favor)\b/.test(
      text,
    )
  )
    return "es";
  if (
    /\b(add|please|gram|grams|kilogram|kilograms|ounce|ounces|cup|cups|tablespoon|tablespoons|teaspoon|teaspoons|slice|slices|piece|pieces|breakfast|lunch|dinner|snack)\b/.test(
      text,
    )
  )
    return "en";
  return undefined;
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
    canonicalName: canonicalNameForMention(mention),
    externalSource: food.externalSource,
    externalId: food.externalId,
    sourceUrl: food.sourceUrl,
    license: food.license,
    confidence: Math.min(mention.confidence, options.confidence),
    needsReview: Math.min(mention.confidence, options.confidence) < 0.9,
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

function usdaFoodFromRecord(food: FoodItemRecord): UsdaFood {
  return {
    fdcId: Number(food.externalId ?? 0),
    description: food.name,
    dataType: food.dataType,
  };
}

function mapOpenFoodFactsProduct(
  product: OpenFoodFactsProduct,
  mention: FoodMention,
): MealItem | null {
  const nutriments = product.nutriments;
  const calories = nutriments?.["energy-kcal_100g"];
  const proteinGrams = nutriments?.["proteins_100g"];
  const carbsGrams = nutriments?.["carbohydrates_100g"];
  const fatGrams = nutriments?.["fat_100g"];
  if (
    !isNumber(calories) ||
    !isNumber(proteinGrams) ||
    !isNumber(carbsGrams) ||
    !isNumber(fatGrams)
  )
    return null;
  const canonicalName = canonicalNameForMention(mention);
  const base: FoodItemRecord = {
    id: product.code ?? canonicalName,
    name:
      product.product_name ||
      product.product_name_en ||
      product.brands ||
      canonicalName,
    normalizedName: normalizeText(canonicalName),
    canonicalName,
    brand: product.brands,
    barcode: product.code,
    source: "openfoodfacts",
    externalSource: "openfoodfacts",
    externalId: product.code,
    sourceUrl: product.url,
    license: "ODbL-1.0",
    servingGrams: 100,
    calories,
    proteinGrams,
    carbsGrams,
    fatGrams,
  };
  return itemFromFood(base, mention, {
    confidence: mention.barcode ? 0.98 : 0.86,
    source: "openfoodfacts",
  });
}

function mapUsdaFood(
  food: UsdaFood,
  mention: FoodMention,
  portionOptions?: PortionOption[],
  selectedPortion?: PortionOption,
  candidateScore?: UsdaCandidateScore,
): MealItem | null {
  const calories = findUsdaNutrient(food, 1008);
  const proteinGrams = findUsdaNutrient(food, 1003);
  const carbsGrams = findUsdaNutrient(food, 1005);
  const fatGrams = findUsdaNutrient(food, 1004);
  if (
    !isNumber(calories) ||
    !isNumber(proteinGrams) ||
    !isNumber(carbsGrams) ||
    !isNumber(fatGrams)
  )
    return null;
  const canonicalName = canonicalNameForMention(mention);
  const description = food.description ?? canonicalName;
  const base: FoodItemRecord = {
    id: String(food.fdcId),
    name: titleCase(description),
    normalizedName: normalizeText(canonicalName),
    canonicalName,
    source: "usda_fdc",
    externalSource: "usda_fdc",
    externalId: String(food.fdcId),
    dataType: food.dataType,
    sourceUrl: `https://fdc.nal.usda.gov/fdc-app.html#/food-details/${food.fdcId}/nutrients`,
    license: "CC0-1.0",
    servingGrams: 100,
    calories,
    proteinGrams,
    carbsGrams,
    fatGrams,
  };
  return itemFromFood(base, mention, {
    confidence:
      candidateScore?.confidence ??
      scoreUsdaCandidate(food, mention)?.confidence ??
      0.74,
    source: "usda_fdc",
    portionOptions,
    selectedPortion,
  });
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

function findUsdaNutrient(
  food: UsdaFood,
  nutrientNumber: number,
): number | undefined {
  const match = food.foodNutrients?.find((nutrient) => {
    const numbers = [
      nutrient.nutrientNumber,
      nutrient.nutrientId,
      nutrient.nutrient?.number,
      nutrient.nutrient?.id,
    ].map((value) => (typeof value === "string" ? Number(value) : value));
    return numbers.includes(nutrientNumber);
  });
  const value = match?.value ?? match?.amount;
  return isNumber(value) ? value : undefined;
}

function hasUsdaNutrition(food: UsdaFood): boolean {
  return [1008, 1003, 1005, 1004].every((nutrient) =>
    isNumber(findUsdaNutrient(food, nutrient)),
  );
}

function parseMention(input: unknown): FoodMention | null {
  if (!input || typeof input !== "object") return null;
  const value = input as Record<string, unknown>;
  const originalText =
    typeof value.originalText === "string" ? value.originalText : undefined;
  const canonicalName =
    typeof value.canonicalName === "string" ? value.canonicalName : undefined;
  const canonicalEnglishName =
    typeof value.canonicalEnglishName === "string"
      ? value.canonicalEnglishName
      : undefined;
  const quantity =
    typeof value.quantity === "number" ? value.quantity : undefined;
  const unit = typeof value.unit === "string" ? value.unit : undefined;
  if (
    !originalText ||
    (!canonicalName && !canonicalEnglishName) ||
    !quantity ||
    !unit
  )
    return null;
  const normalizedCanonical = normalizeFoodName(
    canonicalName ?? canonicalEnglishName!,
  );
  const normalizedCanonicalEnglish =
    canonicalEnglishName ? normalizeFoodName(canonicalEnglishName) : undefined;
  const rawUnitText =
    typeof value.rawUnitText === "string" ? value.rawUnitText : unit;
  const unitKind = parseUnitKind(
    value.unitKind,
    rawUnitText,
    unit,
    normalizedCanonical,
  );
  const portionDescriptorRaw =
    typeof value.portionDescriptorRaw === "string"
      ? value.portionDescriptorRaw
      : undefined;
  const portionDescriptor = normalizePortionDescriptor(
    typeof value.portionDescriptor === "string"
      ? value.portionDescriptor
      : portionDescriptorRaw,
  );
  return {
    originalText,
    canonicalName: normalizedCanonical,
    canonicalEnglishName: normalizedCanonicalEnglish,
    language: typeof value.language === "string" ? value.language : undefined,
    quantity:
      unitKind === "metric"
        ? normalizeQuantity(quantity, rawUnitText)
        : quantity,
    unit: normalizeUnit(unit, normalizedCanonical),
    rawUnitText,
    unitKind,
    portionDescriptorRaw,
    portionDescriptor,
    brand: typeof value.brand === "string" ? value.brand : undefined,
    barcode: typeof value.barcode === "string" ? value.barcode : undefined,
    confidence: typeof value.confidence === "number" ? value.confidence : 0.78,
    marketProduct: Boolean(value.marketProduct),
  };
}

function normalizeQuantity(quantity: number, unit: string): number {
  const normalized = normalizeText(unit);
  if (["kg", "kilogram", "kilograms", "kilo", "kilos"].includes(normalized))
    return quantity * 1000;
  if (["oz", "ounce", "ounces"].includes(normalized))
    return Math.round(quantity * 28.3495 * 10) / 10;
  return quantity;
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
        sourceDescription: "local seeded egg fallback",
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

function normalizeUsdaPortions(
  food: UsdaFood,
  externalFoodId: string,
): PortionOption[] {
  return (food.foodPortions ?? [])
    .map((portion) => normalizeUsdaPortion(portion, externalFoodId))
    .filter((portion): portion is PortionOption => Boolean(portion));
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

function normalizeUsdaPortion(
  portion: UsdaFoodPortion,
  externalFoodId: string,
): PortionOption | null {
  if (!isNumber(portion.gramWeight) || portion.gramWeight <= 0) return null;
  const amount =
    isNumber(portion.amount) && portion.amount > 0 ? portion.amount : 1;
  const gramWeight = roundOne(portion.gramWeight / amount);
  const sourceParts = [
    isNumber(portion.amount) ? String(portion.amount) : undefined,
    portion.measureUnit?.name,
    portion.measureUnit?.abbreviation,
    portion.modifier,
    portion.portionDescription,
  ].filter((part): part is string => Boolean(part && part.trim()));
  const sourceDescription = sourceParts.join(" ");
  const aliases = [
    ...aliasesFromPortionUnit(portion.measureUnit?.name),
    ...aliasesFromPortionUnit(portion.measureUnit?.abbreviation),
    ...aliasesFromPortionDescription(portion.modifier),
    ...aliasesFromPortionDescription(portion.portionDescription),
  ];
  const sourceText = normalizeText(sourceDescription);
  const size = normalizePortionDescriptor(sourceText);
  const kind = classifyPortionKind(sourceText, size);
  const shape = shapeFromPortionDescription(sourceText, kind);
  const unitName = unitNameForPortion(kind, size, shape, aliases, sourceText);
  if (aliases.length === 0) return null;
  return {
    unitName,
    aliases: [...new Set(aliases)],
    gramWeight,
    sourceDescription,
    externalFoodId,
    kind,
    size,
    shape,
  };
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

function titleCase(value: string): string {
  return value.toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function timeoutSignal(timeoutMs: number): AbortSignal | undefined {
  return (
    AbortSignal as typeof AbortSignal & {
      timeout?: (milliseconds: number) => AbortSignal;
    }
  ).timeout?.(timeoutMs);
}

type OpenFoodFactsProduct = {
  code?: string;
  url?: string;
  product_name?: string;
  product_name_en?: string;
  brands?: string;
  nutriments?: {
    "energy-kcal_100g"?: number;
    proteins_100g?: number;
    carbohydrates_100g?: number;
    fat_100g?: number;
  };
};

type UsdaFood = {
  fdcId: number;
  description?: string;
  dataType?: string;
  foodPortions?: UsdaFoodPortion[];
  foodNutrients?: Array<{
    nutrientId?: number;
    nutrientNumber?: number | string;
    value?: number;
    amount?: number;
    nutrient?: {
      id?: number;
      number?: string;
    };
  }>;
};

type UsdaFoodPortion = {
  amount?: number;
  gramWeight?: number;
  modifier?: string;
  portionDescription?: string;
  measureUnit?: {
    name?: string;
    abbreviation?: string;
  };
};
