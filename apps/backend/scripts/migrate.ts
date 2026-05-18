import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { migrate as migrateDrizzle } from "drizzle-orm/postgres-js/migrator";
import { loadConfig } from "../src/config/env.js";
import { createDbClient } from "../src/db/client.js";
import { databaseSchema, prepareSchema } from "./schema.js";

const config = loadConfig();
const client = createDbClient(config.DATABASE_URL, { max: 1 });
const legacyMigrationDir = resolve(process.cwd(), "../../infra/db/migrations");
const drizzleMigrationDir = resolve(process.cwd(), "../../infra/db/drizzle");
const schema = databaseSchema();

await prepareSchema(client.sql, schema);

await client.sql`CREATE TABLE IF NOT EXISTS schema_migrations (filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`;

for (const filename of readdirSync(legacyMigrationDir).filter((name) => name.endsWith(".sql")).sort()) {
  const applied = await client.sql`SELECT filename FROM schema_migrations WHERE filename = ${filename}`;
  if (applied.length > 0) continue;
  const body = readFileSync(resolve(legacyMigrationDir, filename), "utf8");
  await client.sql.begin(async (tx) => {
    await tx.unsafe(body);
    await tx`INSERT INTO schema_migrations (filename) VALUES (${filename})`;
  });
  console.log(`Applied ${filename} to ${schema}`);
}

await migrateDrizzle(client.db, {
  migrationsFolder: drizzleMigrationDir,
  migrationsSchema: schema,
  migrationsTable: "__drizzle_migrations"
});

await client.close();
