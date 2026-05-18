import { createHash } from "node:crypto";
import postgres from "postgres";
import { loadConfig } from "../src/config/env.js";
import { LocalBgeM3EmbeddingProvider } from "../src/embeddings/provider.js";
import { PostgresRepository } from "../src/repository/postgres.js";

const config = loadConfig();
const sql = postgres(config.DATABASE_URL, { max: 1 });
const repository = new PostgresRepository(config.DATABASE_URL);
const embeddingProvider = new LocalBgeM3EmbeddingProvider(
  config.EMBEDDING_BASE_URL ?? "http://localhost:8081",
  config.EMBEDDING_MODEL,
  config.EMBEDDING_DIMENSIONS,
);

const batchSize = Number(process.env.FOOD_EMBEDDING_BATCH_SIZE ?? 64);
const limit = process.env.FOOD_EMBEDDING_LIMIT
  ? Number(process.env.FOOD_EMBEDDING_LIMIT)
  : undefined;

const model = await repository.getActiveEmbeddingModel();
if (!model) {
  throw new Error("active_embedding_model_not_found");
}

const rows = await sql`
  SELECT food_items.*
  FROM food_items
  LEFT JOIN food_item_embeddings existing
    ON existing.food_item_id = food_items.id
   AND existing.embedding_model_id = ${model.id}
  WHERE food_items.user_id IS NULL
    AND (
      (food_items.external_source = 'bedca' AND food_items.data_type = 'BEDCA')
      OR (food_items.external_source = 'usda_fdc' AND food_items.data_type IN ('SR Legacy', 'Foundation'))
    )
  ORDER BY
    CASE
      WHEN food_items.external_source = 'bedca' THEN 0
      WHEN food_items.data_type = 'SR Legacy' THEN 1
      WHEN food_items.data_type = 'Foundation' THEN 2
      ELSE 3
    END,
    food_items.name
  ${limit ? sql`LIMIT ${limit}` : sql``}
`;

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
  const existing = await sql`
    SELECT food_item_id, embedded_text_hash
    FROM food_item_embeddings
    WHERE embedding_model_id = ${model.id}
      AND food_item_id IN ${sql(batch.map((item) => item.foodItemId))}
  `;
  const hashes = new Map(
    existing.map((row) => [
      row.food_item_id as string,
      row.embedded_text_hash as string,
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
      embeddingModelId: model.id,
      embeddedText: item.text,
      embeddedTextHash: item.hash,
      embedding,
    });
    embedded += 1;
  }
  console.log(`Embedded ${embedded} foods, skipped ${skipped}`);
}

await sql.end();
console.log(`Food embeddings complete. Embedded ${embedded}, skipped ${skipped}.`);

function embeddedFoodText(row: Record<string, unknown>): string {
  const bedcaNameEn = bedcaEnglishName(row.nutrients_json);
  return [
    `name: ${row.name ?? ""}`,
    `canonical: ${row.canonical_name ?? row.normalized_name ?? ""}`,
    `english: ${bedcaNameEn ?? ""}`,
    `category: ${row.food_category ?? ""}`,
    `data type: ${row.data_type ?? ""}`,
    `source: ${row.external_source ?? row.source ?? ""}`,
    `brand: ${row.brand ?? ""}`,
    `ingredients: ${row.ingredients ?? ""}`,
    `serving: ${row.household_serving_fulltext ?? ""}`,
  ]
    .filter((line) => !line.endsWith(": "))
    .join("\n");
}

function bedcaEnglishName(value: unknown): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const name = (value as { name_en?: unknown }).name_en;
  return typeof name === "string" && name.trim().length > 0
    ? name.trim()
    : undefined;
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
