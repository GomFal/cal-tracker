import { pathToFileURL } from "node:url";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import {
  DEFAULT_TYPESENSE_FOOD_COLLECTION,
  typesenseFoodCollectionSchema,
  typesenseFoodDocumentForFood,
  type TypesenseFoodDocument,
} from "../src/repository/typesenseFoodDocument.js";
import type { FoodItemRecord, FoodPortionRecord } from "../src/repository/types.js";

type SyncArgs = {
  dryRun: boolean;
  drop: boolean;
  limit?: number;
  pageSize: number;
  batchSize: number;
};

type FoodRow = {
  id: string;
  user_id: string | null;
  name: string;
  normalized_name: string;
  canonical_name: string | null;
  brand: string | null;
  barcode: string | null;
  source: string;
  external_source: string | null;
  external_id: string | null;
  source_url: string | null;
  license: string | null;
  fetched_at: Date | string | null;
  data_type: string | null;
  food_category: string | null;
  publication_date: Date | string | null;
  ndb_number: string | null;
  food_key: string | null;
  ingredients: string | null;
  market_country: string | null;
  household_serving_fulltext: string | null;
  serving_grams: string | number;
  calories: string | number;
  protein_grams: string | number;
  carbs_grams: string | number;
  fat_grams: string | number;
  search_text: string | null;
  document_scope: string | null;
  document_locale: string | null;
  document_rank_bucket: string | number | null;
};

type PortionRow = {
  id: string;
  food_item_id: string;
  usda_portion_id: string | null;
  amount: string | number | null;
  unit: string | null;
  modifier: string | null;
  description: string | null;
  gram_weight: string | number;
  normalized_aliases: string[];
  kind: string | null;
  source_description: string;
};

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const config = loadConfig();
  const typesense = typesenseClient({
    protocol: config.TYPESENSE_PROTOCOL,
    host: config.TYPESENSE_HOST,
    port: config.TYPESENSE_PORT,
    apiKey: config.TYPESENSE_API_KEY,
    collection: config.TYPESENSE_COLLECTION,
  });
  const client = createDbClient(config.DATABASE_URL);

  let imported = 0;
  let processed = 0;
  let skipped = 0;
  let cursor: string | undefined;

  try {
    if (!args.dryRun) {
      if (args.drop) await typesense.dropCollection();
      await typesense.ensureCollection();
    }

    while (args.limit === undefined || processed < args.limit) {
      const remaining = args.limit === undefined
        ? args.pageSize
        : Math.min(args.pageSize, args.limit - processed);
      if (remaining <= 0) break;
      const foods = await fetchFoodPage(client.sql, cursor, remaining);
      if (foods.length === 0) break;
      cursor = foods.at(-1)!.id;
      processed += foods.length;

      const portions = await fetchPortions(client.sql, foods.map((food) => food.id));
      const documents = foods
        .map((food) => typesenseFoodDocumentForFood(
          foodFromRow(food),
          portions.get(food.id) ?? [],
          searchDocumentFromRow(food),
        ))
        .filter((document): document is TypesenseFoodDocument => Boolean(document));
      skipped += foods.length - documents.length;

      if (!args.dryRun) {
        for (const batch of chunks(documents, args.batchSize)) {
          imported += await typesense.importDocuments(batch);
        }
      }

      console.log(JSON.stringify({
        processed,
        imported: args.dryRun ? documents.length : imported,
        skipped,
        cursor,
      }));
    }

    console.log(JSON.stringify({
      ok: true,
      dryRun: args.dryRun,
      collection: config.TYPESENSE_COLLECTION,
      processed,
      imported: args.dryRun ? processed - skipped : imported,
      skipped,
    }, null, 2));
  } finally {
    await client.close();
  }
}

async function fetchFoodPage(
  sql: ReturnType<typeof createDbClient>["sql"],
  cursor: string | undefined,
  limit: number,
): Promise<FoodRow[]> {
  const cursorClause = cursor
    ? sql`WHERE food_items.id > ${cursor}`
    : sql``;
  return await sql<FoodRow[]>`
    SELECT food_items.*,
           food_search_documents.search_text,
           food_search_documents.scope AS document_scope,
           food_search_documents.locale AS document_locale,
           food_search_documents.rank_bucket AS document_rank_bucket
    FROM food_items
    LEFT JOIN food_search_documents
      ON food_search_documents.food_item_id = food_items.id
    ${cursorClause}
    ORDER BY food_items.id
    LIMIT ${limit}
  `;
}

async function fetchPortions(
  sql: ReturnType<typeof createDbClient>["sql"],
  foodIds: string[],
): Promise<Map<string, FoodPortionRecord[]>> {
  if (foodIds.length === 0) return new Map();
  const rows = await sql<PortionRow[]>`
    SELECT *
    FROM food_portions
    WHERE food_item_id IN ${sql(foodIds)}
    ORDER BY food_item_id, gram_weight, source_description
  `;
  const byFood = new Map<string, FoodPortionRecord[]>();
  for (const row of rows) {
    const portion = portionFromRow(row);
    const list = byFood.get(portion.foodItemId) ?? [];
    list.push(portion);
    byFood.set(portion.foodItemId, list);
  }
  return byFood;
}

function foodFromRow(row: FoodRow): FoodItemRecord {
  return {
    id: row.id,
    userId: optionalString(row.user_id),
    name: row.name,
    normalizedName: row.normalized_name,
    canonicalName: optionalString(row.canonical_name),
    brand: optionalString(row.brand),
    barcode: optionalString(row.barcode),
    source: row.source,
    externalSource: optionalString(row.external_source),
    externalId: optionalString(row.external_id),
    sourceUrl: optionalString(row.source_url),
    license: optionalString(row.license),
    fetchedAt: row.fetched_at ? toIso(row.fetched_at) : undefined,
    dataType: optionalString(row.data_type),
    foodCategory: optionalString(row.food_category),
    publicationDate: row.publication_date ? toDateOnly(row.publication_date) : undefined,
    ndbNumber: optionalString(row.ndb_number),
    foodKey: optionalString(row.food_key),
    ingredients: optionalString(row.ingredients),
    marketCountry: optionalString(row.market_country),
    householdServingFulltext: optionalString(row.household_serving_fulltext),
    portions: [],
    servingGrams: Number(row.serving_grams),
    calories: Number(row.calories),
    proteinGrams: Number(row.protein_grams),
    carbsGrams: Number(row.carbs_grams),
    fatGrams: Number(row.fat_grams),
  };
}

function searchDocumentFromRow(row: FoodRow):
  | { searchText?: string; scope?: "generic" | "market"; locale?: "es" | "en" | "any"; rankBucket?: number }
  | undefined {
  if (!row.search_text) return undefined;
  const scope = row.document_scope === "generic" || row.document_scope === "market"
    ? row.document_scope
    : undefined;
  const locale =
    row.document_locale === "es" || row.document_locale === "en" || row.document_locale === "any"
      ? row.document_locale
      : undefined;
  return {
    searchText: row.search_text,
    scope,
    locale,
    rankBucket: row.document_rank_bucket == null ? undefined : Number(row.document_rank_bucket),
  };
}

function portionFromRow(row: PortionRow): FoodPortionRecord {
  return {
    id: row.id,
    foodItemId: row.food_item_id,
    usdaPortionId: optionalString(row.usda_portion_id),
    amount: row.amount == null ? undefined : Number(row.amount),
    unit: optionalString(row.unit),
    modifier: optionalString(row.modifier),
    description: optionalString(row.description),
    gramWeight: Number(row.gram_weight),
    normalizedAliases: Array.isArray(row.normalized_aliases) ? row.normalized_aliases.map(String) : [],
    kind: row.kind ?? "serving",
    sourceDescription: row.source_description,
  };
}

function typesenseClient(input: {
  protocol: "http" | "https";
  host: string;
  port: number;
  apiKey: string;
  collection: string;
}) {
  const baseUrl = `${input.protocol}://${input.host}:${input.port}`;
  const headers = {
    "X-TYPESENSE-API-KEY": input.apiKey,
  };

  async function request(path: string, init: RequestInit = {}) {
    const response = await fetch(`${baseUrl}${path}`, {
      ...init,
      headers: {
        ...headers,
        ...(init.headers ?? {}),
      },
    });
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw Object.assign(new Error(`typesense_request_failed ${response.status} ${body}`), {
        status: response.status,
      });
    }
    return response;
  }

  return {
    async ensureCollection() {
      const path = `/collections/${encodeURIComponent(input.collection)}`;
      try {
        await request(path);
        return;
      } catch (error) {
        if (!isHttpStatus(error, 404)) throw error;
      }
      await request("/collections", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(typesenseFoodCollectionSchema(input.collection)),
      });
    },
    async dropCollection() {
      try {
        await request(`/collections/${encodeURIComponent(input.collection)}`, {
          method: "DELETE",
        });
      } catch (error) {
        if (!isHttpStatus(error, 404)) throw error;
      }
    },
    async importDocuments(documents: TypesenseFoodDocument[]): Promise<number> {
      if (documents.length === 0) return 0;
      const body = documents.map((document) => JSON.stringify(document)).join("\n");
      const response = await request(
        `/collections/${encodeURIComponent(input.collection)}/documents/import?action=upsert`,
        {
          method: "POST",
          headers: { "content-type": "text/plain" },
          body,
        },
      );
      const text = await response.text();
      const results = text
        .split(/\r?\n/)
        .filter(Boolean)
        .map((line) => JSON.parse(line) as { success?: boolean; error?: string; document?: string });
      const failures = results.filter((result) => !result.success);
      if (failures.length > 0) {
        throw new Error(`typesense_import_failed ${JSON.stringify(failures.slice(0, 5))}`);
      }
      return results.length;
    },
  };
}

function parseArgs(args: string[]): SyncArgs {
  const parsed: SyncArgs = {
    dryRun: false,
    drop: false,
    pageSize: 1000,
    batchSize: 1000,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--dry-run") parsed.dryRun = true;
    else if (arg === "--drop") parsed.drop = true;
    else if (arg === "--limit") parsed.limit = Number(args[++index]);
    else if (arg === "--page-size") parsed.pageSize = Number(args[++index]);
    else if (arg === "--batch-size") parsed.batchSize = Number(args[++index]);
    else throw new Error(`Unknown argument: ${arg}`);
  }
  parsed.pageSize = sanitizePositiveInt(parsed.pageSize, "page-size");
  parsed.batchSize = sanitizePositiveInt(parsed.batchSize, "batch-size");
  if (parsed.limit !== undefined) parsed.limit = sanitizePositiveInt(parsed.limit, "limit");
  return parsed;
}

function sanitizePositiveInt(value: number, name: string): number {
  if (!Number.isInteger(value) || value <= 0) throw new Error(`${name} must be a positive integer`);
  return value;
}

function chunks<T>(items: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

function isHttpStatus(error: unknown, status: number): boolean {
  return typeof error === "object" &&
    error !== null &&
    "status" in error &&
    (error as { status?: unknown }).status === status;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function toIso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : new Date(value as string).toISOString();
}

function toDateOnly(value: unknown): string {
  return value instanceof Date ? value.toISOString().slice(0, 10) : String(value).slice(0, 10);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
