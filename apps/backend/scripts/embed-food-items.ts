import { createHash } from "node:crypto";
import { and, eq, inArray, isNull, sql } from "drizzle-orm";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { foodItemEmbeddings, foodItems } from "../src/db/schema.js";
import { OpenRouterEmbeddingProvider } from "../src/embeddings/provider.js";
import { PostgresRepository } from "../src/repository/postgres.js";

const config = loadConfig();
if (!config.EMBEDDINGS_ENABLED) {
  throw new Error("embeddings_disabled_set_EMBEDDINGS_ENABLED_true_to_backfill");
}

const client = createDbClient(config.DATABASE_URL, { max: 1 });
const repository = new PostgresRepository(config.DATABASE_URL);
const embeddingProvider = new OpenRouterEmbeddingProvider(
  config.OPENROUTER_API_KEY,
  config.EMBEDDING_MODEL,
  config.EMBEDDING_DIMENSIONS,
);

const batchSize = Number(process.env.FOOD_EMBEDDING_BATCH_SIZE ?? 64);
const limit = process.env.FOOD_EMBEDDING_LIMIT
  ? Number(process.env.FOOD_EMBEDDING_LIMIT)
  : undefined;

const foodQuery = client.db
  .select()
  .from(foodItems)
  .where(and(
    isNull(foodItems.userId),
    eq(foodItems.externalSource, "usda_fdc"),
    inArray(foodItems.dataType, ["SR Legacy", "Foundation"]),
  ))
  .orderBy(
    sql`CASE ${foodItems.dataType} WHEN 'SR Legacy' THEN 0 WHEN 'Foundation' THEN 1 ELSE 2 END`,
    foodItems.name,
  );
const rows = limit ? await foodQuery.limit(limit) : await foodQuery;

let embedded = 0;
let skipped = 0;

for (let offset = 0; offset < rows.length; offset += batchSize) {
  const batch = rows.slice(offset, offset + batchSize).map((row) => {
    const text = embeddedFoodText(row);
    return {
      foodItemId: row.id as string,
      text,
      hash: sha256(text),
    };
  });
  const existing = await client.db
    .select({
      foodItemId: foodItemEmbeddings.foodItemId,
      embeddedTextHash: foodItemEmbeddings.embeddedTextHash,
    })
    .from(foodItemEmbeddings)
    .where(inArray(foodItemEmbeddings.foodItemId, batch.map((item) => item.foodItemId)));
  const hashes = new Map(
    existing.map((row) => [
      row.foodItemId,
      row.embeddedTextHash,
    ]),
  );
  const pending = batch.filter((item) => hashes.get(item.foodItemId) !== item.hash);
  skipped += batch.length - pending.length;
  if (pending.length === 0) continue;

  const result = await embeddingProvider.embed(pending.map((item) => item.text));
  for (const [index, item] of pending.entries()) {
    const embedding = result.data[index]?.embedding;
    if (!embedding) throw new Error("missing_embedding_result");
    await repository.upsertFoodItemEmbedding({
      foodItemId: item.foodItemId,
      embeddedText: item.text,
      embeddedTextHash: item.hash,
      embedding,
    });
    embedded += 1;
  }
  console.log(`Embedded ${embedded} foods, skipped ${skipped}`);
}

await client.close();
await repository.close();
console.log(`Food embeddings complete. Embedded ${embedded}, skipped ${skipped}.`);

function embeddedFoodText(row: Record<string, unknown>): string {
  return [
    `name: ${row.name ?? ""}`,
    `canonical: ${row.canonicalName ?? row.canonical_name ?? row.normalizedName ?? row.normalized_name ?? ""}`,
    `category: ${row.foodCategory ?? row.food_category ?? ""}`,
    `data type: ${row.dataType ?? row.data_type ?? ""}`,
    `brand: ${row.brand ?? ""}`,
    `ingredients: ${row.ingredients ?? ""}`,
    `serving: ${row.householdServingFulltext ?? row.household_serving_fulltext ?? ""}`,
  ]
    .filter((line) => !line.endsWith(": "))
    .join("\n");
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
