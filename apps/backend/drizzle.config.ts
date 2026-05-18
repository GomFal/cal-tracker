import { defineConfig } from "drizzle-kit";

const databaseUrl = process.env.DATABASE_URL ?? "postgres://cal_tracker:cal_tracker@localhost:5432/cal_tracker";
const databaseSchema = process.env.DATABASE_SCHEMA?.trim() || "public";

export default defineConfig({
  schema: "./src/db/schema.ts",
  out: "../../infra/db/drizzle",
  dialect: "postgresql",
  dbCredentials: {
    url: databaseUrl
  },
  schemaFilter: databaseSchema,
  migrations: {
    schema: databaseSchema,
    table: "__drizzle_migrations",
    prefix: "index"
  }
});
