import type { Sql } from "postgres";

export function consumeRequireDbNameArg(argv: string[]): {
  argv: string[];
  requiredDbName?: string;
  requiredSchema?: string;
} {
  const result: string[] = [];
  let requiredDbName: string | undefined;
  let requiredSchema: string | undefined;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--require-db-name") {
      const value = argv[++index];
      if (!value) throw new Error("--require-db-name requires a value.");
      requiredDbName = value;
    } else if (arg === "--require-schema") {
      const value = argv[++index];
      if (!value) throw new Error("--require-schema requires a value.");
      requiredSchema = value;
    } else {
      result.push(arg);
    }
  }
  return { argv: result, requiredDbName, requiredSchema };
}

export async function assertRequiredDatabaseName(
  sql: Sql,
  requiredDbName: string | undefined,
): Promise<void> {
  if (!requiredDbName) return;
  const [row] = await sql`SELECT current_database() AS database_name`;
  const currentDbName = String(row?.database_name ?? "");
  if (currentDbName !== requiredDbName) {
    throw new Error(`Refusing to mutate database "${currentDbName}". Expected "${requiredDbName}".`);
  }
}

export async function assertRequiredSchema(
  sql: Sql,
  requiredSchema: string | undefined,
): Promise<void> {
  if (!requiredSchema) return;
  const [row] = await sql`SELECT current_schema() AS schema_name`;
  const currentSchema = String(row?.schema_name ?? "");
  if (currentSchema !== requiredSchema) {
    throw new Error(`Refusing to mutate schema "${currentSchema}". Expected "${requiredSchema}".`);
  }
}
