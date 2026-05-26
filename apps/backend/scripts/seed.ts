import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { databaseSchema, prepareSchema } from "./schema.js";

const config = loadConfig();
const client = createDbClient(config.DATABASE_URL, { max: 1 });
const schema = databaseSchema();

await prepareSchema(client.sql, schema);

console.log("Database schema prepared. Food items must be imported from a trusted provider with provenance.");
await client.close();
