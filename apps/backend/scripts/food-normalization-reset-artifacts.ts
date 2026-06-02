import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { assertRequiredDatabaseName, assertRequiredSchema, consumeRequireDbNameArg } from "../src/db/scriptGuards.js";

const { requiredDbName, requiredSchema } = consumeRequireDbNameArg(process.argv.slice(2));
const config = loadConfig();
const client = createDbClient(config.DATABASE_URL, { max: 1 });

try {
  await assertRequiredDatabaseName(client.sql, requiredDbName);
  await assertRequiredSchema(client.sql, requiredSchema);
  await client.sql`TRUNCATE food_normalized_search_documents, food_normalization_review`;
  console.log("Cleared food_normalized_search_documents and food_normalization_review.");
} finally {
  await client.close();
}
