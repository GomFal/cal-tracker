import type { FoodHybridSearchInput, FoodSearchCandidate } from "./types.js";
import type { FoodSearchBackend } from "./foodSearchBackend.js";
import {
  DEFAULT_TYPESENSE_FOOD_COLLECTION,
  foodRecordFromTypesenseDocument,
  type TypesenseFoodDocument,
} from "./typesenseFoodDocument.js";
import { lexicalFoodScore } from "./foodSearchScoring.js";
import { normalizeText } from "../utils/normalize.js";

const DEFAULT_FOOD_SEARCH_LIMIT = 50;
const MAX_FOOD_SEARCH_LIMIT = 100;
const LEXICAL_ONLY_SCORE_WEIGHT = 0.95;
const TYPESENSE_SCORE_WEIGHT = 0.05;
const FOOD_SEARCH_CACHE_TTL_MS = 5 * 60 * 1000;
const FOOD_SEARCH_CACHE_MAX_ENTRIES = 500;
const TYPESENSE_FOOD_INCLUDE_FIELDS = [
  "id",
  "userId",
  "isGlobal",
  "name",
  "normalizedName",
  "canonicalName",
  "brand",
  "barcode",
  "scope",
  "locale",
  "source",
  "externalSource",
  "externalId",
  "sourceUrl",
  "license",
  "dataType",
  "foodCategory",
  "publicationDate",
  "ndbNumber",
  "foodKey",
  "ingredients",
  "marketCountry",
  "householdServingFulltext",
  "rankBucket",
  "servingGrams",
  "calories",
  "proteinGrams",
  "carbsGrams",
  "fatGrams",
  "portions",
].join(",");

export type TypesenseFoodSearchOptions = {
  protocol?: "http" | "https";
  host?: string;
  port?: number;
  apiKey?: string;
  collection?: string;
  timeoutMs?: number;
};

type TypesenseSearchHit = {
  document?: TypesenseFoodDocument;
  text_match?: number;
  text_match_info?: { score?: string | number };
};

type TypesenseSearchResponse = {
  hits?: TypesenseSearchHit[];
};

export class TypesenseFoodSearch implements FoodSearchBackend {
  private readonly protocol: "http" | "https";
  private readonly host: string;
  private readonly port: number;
  private readonly apiKey: string;
  private readonly collection: string;
  private readonly timeoutMs: number;
  private readonly cache = new Map<string, { expiresAt: number; value: FoodSearchCandidate[] }>();

  constructor(options: TypesenseFoodSearchOptions = {}) {
    this.protocol = options.protocol ?? "http";
    this.host = options.host ?? "localhost";
    this.port = options.port ?? 8108;
    this.apiKey = options.apiKey ?? "xyz";
    this.collection = options.collection ?? DEFAULT_TYPESENSE_FOOD_COLLECTION;
    this.timeoutMs = options.timeoutMs ?? 10000;
  }

  async searchFoodsHybrid(
    userId: string,
    input: FoodHybridSearchInput,
  ): Promise<FoodSearchCandidate[]> {
    const limit = sanitizeLimit(input.limit);
    const normalized = normalizeText(input.query);
    const cacheKey = JSON.stringify({
      userId,
      query: normalized,
      barcode: input.barcode,
      locale: normalizeSearchLocale(input.locale),
      scope: input.scope,
      excludeBranded: input.excludeBranded,
      limit,
    });
    const cached = this.getCached(cacheKey);
    if (cached) return cached.map(cloneFoodSearchCandidate);

    if (!input.barcode && normalized.length === 0) {
      this.setCached(cacheKey, []);
      return [];
    }

    const hits = await this.search(userId, input, normalized, limit);
    const maxTextMatch = Math.max(
      ...hits.map((hit) => textMatchScore(hit)).filter((score) => score > 0),
      1,
    );
    const candidates = hits
      .map((hit, index) => {
        if (!hit.document) return undefined;
        const food = foodRecordFromTypesenseDocument(hit.document);
        const lexicalScore = input.barcode
          ? (food.barcode === input.barcode ? 1 : 0)
          : lexicalFoodScore(food, normalized);
        const typesenseScore = clampScore(textMatchScore(hit) / maxTextMatch);
        const rankScore = clampScore(1 - index / Math.max(hits.length, 1));
        const finalScore = clampScore(
          lexicalScore * LEXICAL_ONLY_SCORE_WEIGHT +
          Math.max(typesenseScore, rankScore * 0.5) * TYPESENSE_SCORE_WEIGHT,
        );
        return {
          ...food,
          lexicalScore,
          preferenceScore: 0,
          finalScore,
        } satisfies FoodSearchCandidate;
      })
      .filter((candidate): candidate is FoodSearchCandidate => Boolean(candidate))
      .sort((a, b) =>
        b.finalScore - a.finalScore ||
        b.lexicalScore - a.lexicalScore ||
        a.name.localeCompare(b.name)
      )
      .slice(0, limit);

    this.setCached(cacheKey, candidates);
    return candidates.map(cloneFoodSearchCandidate);
  }

  private async search(
    userId: string,
    input: FoodHybridSearchInput,
    normalized: string,
    limit: number,
  ): Promise<TypesenseSearchHit[]> {
    const queries = input.barcode
      ? ["*"]
      : uniqueStrings([normalized, simplifyFoodQuery(normalized)].filter(Boolean));
    const seen = new Set<string>();
    const hits: TypesenseSearchHit[] = [];
    for (const query of queries) {
      const queryHits = await this.searchOnce(userId, input, query, limit, true);
      for (const hit of queryHits) {
        const id = hit.document?.id;
        if (!id || seen.has(id)) continue;
        seen.add(id);
        hits.push(hit);
      }
      if (hits.length >= limit) return hits;
    }
    if (!input.barcode && hits.length === 0) {
      return this.searchOnce(userId, input, normalized, limit, false);
    }
    return hits;
  }

  private async searchOnce(
    userId: string,
    input: FoodHybridSearchInput,
    query: string,
    limit: number,
    requireAllTokens: boolean,
  ): Promise<TypesenseSearchHit[]> {
    const searchLimit = Math.max(limit, DEFAULT_FOOD_SEARCH_LIMIT);
    const searchParams = new URLSearchParams({
      q: query,
      query_by: "searchText",
      include_fields: TYPESENSE_FOOD_INCLUDE_FIELDS,
      per_page: String(searchLimit),
      page: "1",
      prioritize_exact_match: "true",
      typo_tokens_threshold: "1",
      num_typos: input.barcode ? "0" : "2",
      sort_by: "_text_match:desc,rankBucket:asc",
      filter_by: filterBy(userId, input),
    });
    if (requireAllTokens) searchParams.set("drop_tokens_threshold", "0");
    const response = await this.request<TypesenseSearchResponse>(
      `/collections/${encodeURIComponent(this.collection)}/documents/search?${searchParams}`,
      { method: "GET" },
    );
    return response.hits ?? [];
  }

  private async request<T>(path: string, init: RequestInit): Promise<T> {
    const response = await fetch(`${this.protocol}://${this.host}:${this.port}${path}`, {
      ...init,
      signal: AbortSignal.timeout(this.timeoutMs),
      headers: {
        "X-TYPESENSE-API-KEY": this.apiKey,
        ...(init.headers ?? {}),
      },
    });
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`typesense_food_search_failed ${response.status} ${body}`);
    }
    return await response.json() as T;
  }

  private getCached(key: string): FoodSearchCandidate[] | undefined {
    const cached = this.cache.get(key);
    if (!cached) return undefined;
    if (cached.expiresAt < Date.now()) {
      this.cache.delete(key);
      return undefined;
    }
    this.cache.delete(key);
    this.cache.set(key, cached);
    return cached.value;
  }

  private setCached(key: string, value: FoodSearchCandidate[]): void {
    if (this.cache.size >= FOOD_SEARCH_CACHE_MAX_ENTRIES) {
      const oldest = this.cache.keys().next().value;
      if (oldest) this.cache.delete(oldest);
    }
    this.cache.set(key, {
      expiresAt: Date.now() + FOOD_SEARCH_CACHE_TTL_MS,
      value: value.map(cloneFoodSearchCandidate),
    });
  }
}

function filterBy(userId: string, input: FoodHybridSearchInput): string {
  const filters = [
    `(isGlobal:=true || userId:=${filterValue(userId)})`,
  ];
  if (input.barcode) filters.push(`barcode:=${filterValue(input.barcode)}`);
  const scope = input.scope ?? (input.excludeBranded ? "generic" : "market");
  if (scope === "generic") {
    filters.push("scope:=generic");
  } else if (scope === "market") {
    filters.push("scope:=[market,generic]");
  }
  if (input.excludeBranded) {
    filters.push("dataType:!=Branded");
    filters.push("source:!=usda_branded");
  }
  return filters.join(" && ");
}

function filterValue(value: string): string {
  return `\`${value.replace(/`/g, "\\`")}\``;
}

function normalizeSearchLocale(locale?: string): "es" | "en" | undefined {
  const normalized = locale?.toLowerCase();
  if (!normalized) return undefined;
  if (normalized.startsWith("es")) return "es";
  if (normalized.startsWith("en")) return "en";
  return undefined;
}

function simplifyFoodQuery(query: string): string {
  const stopwords = new Set([
    "a",
    "al",
    "and",
    "con",
    "de",
    "del",
    "el",
    "en",
    "extra",
    "for",
    "la",
    "las",
    "los",
    "of",
    "sin",
    "the",
    "virgen",
    "with",
  ]);
  return query
    .split(/\s+/)
    .filter((token) => token.length > 1 && !stopwords.has(token))
    .join(" ");
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}

function textMatchScore(hit: TypesenseSearchHit): number {
  const direct = typeof hit.text_match === "number" ? hit.text_match : undefined;
  const info = hit.text_match_info?.score;
  const fromInfo = typeof info === "number" ? info : typeof info === "string" ? Number(info) : undefined;
  return Number.isFinite(direct) ? direct! : Number.isFinite(fromInfo) ? fromInfo! : 0;
}

function sanitizeLimit(limit: number | undefined): number {
  if (!limit || !Number.isFinite(limit)) return DEFAULT_FOOD_SEARCH_LIMIT;
  return Math.max(1, Math.min(MAX_FOOD_SEARCH_LIMIT, Math.floor(limit)));
}

function clampScore(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function cloneFoodSearchCandidate(candidate: FoodSearchCandidate): FoodSearchCandidate {
  return {
    ...candidate,
    portions: candidate.portions?.map((portion) => ({ ...portion })),
  };
}
