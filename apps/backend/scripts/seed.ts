import { and, eq } from "drizzle-orm";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { embeddingModels } from "../src/db/schema.js";
import { databaseSchema, prepareSchema } from "./schema.js";

const config = loadConfig();
const client = createDbClient(config.DATABASE_URL, { max: 1 });
const schema = databaseSchema();

await prepareSchema(client.sql, schema);

const [existing] = await client.db
  .select({ id: embeddingModels.id })
  .from(embeddingModels)
  .where(and(
    eq(embeddingModels.provider, config.EMBEDDING_PROVIDER),
    eq(embeddingModels.model, config.EMBEDDING_MODEL),
    eq(embeddingModels.dimensions, config.EMBEDDING_DIMENSIONS),
  ))
  .limit(1);

if (!existing) {
  await client.db.insert(embeddingModels).values({
    provider: config.EMBEDDING_PROVIDER,
    model: config.EMBEDDING_MODEL,
    dimensions: config.EMBEDDING_DIMENSIONS,
  });
}

console.log("Seeded embedding model metadata. Food items must be imported from a trusted provider with provenance.");
await client.close();
