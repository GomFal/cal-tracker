import { drizzle, type PostgresJsDatabase } from "drizzle-orm/postgres-js";
import postgres, { type Options, type Sql } from "postgres";
import * as schema from "./schema.js";

export type AppDb = PostgresJsDatabase<typeof schema>;

export type AppDbClient = {
  db: AppDb;
  sql: Sql;
  close: () => Promise<void>;
};

export function createDbClient(databaseUrl: string, options: Options<Record<string, never>> = {}): AppDbClient {
  const sql = postgres(databaseUrl, options);
  return {
    db: drizzle(sql, { schema }),
    sql,
    close: () => sql.end({ timeout: 5 })
  };
}
