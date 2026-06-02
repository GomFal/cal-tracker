import { describe, expect, it } from "vitest";
import type { Sql } from "postgres";
import {
  assertRequiredDatabaseName,
  assertRequiredSchema,
  consumeRequireDbNameArg,
} from "../db/scriptGuards.js";

describe("script guards", () => {
  it("consumes required database and schema arguments", () => {
    expect(consumeRequireDbNameArg([
      "--scope",
      "full",
      "--require-db-name",
      "cal_tracker",
      "--require-schema",
      "cal_tracker_dev",
    ])).toEqual({
      argv: ["--scope", "full"],
      requiredDbName: "cal_tracker",
      requiredSchema: "cal_tracker_dev",
    });
  });

  it("throws when the current database does not match", async () => {
    await expect(assertRequiredDatabaseName(fakeSql({ database_name: "other" }), "cal_tracker"))
      .rejects.toThrow('Refusing to mutate database "other". Expected "cal_tracker".');
  });

  it("throws when the current schema does not match", async () => {
    await expect(assertRequiredSchema(fakeSql({ schema_name: "cal_tracker_pro" }), "cal_tracker_dev"))
      .rejects.toThrow('Refusing to mutate schema "cal_tracker_pro". Expected "cal_tracker_dev".');
  });

  it("does nothing when no guard value is required", async () => {
    await expect(assertRequiredDatabaseName(fakeSql({ database_name: "other" }), undefined)).resolves.toBeUndefined();
    await expect(assertRequiredSchema(fakeSql({ schema_name: "other" }), undefined)).resolves.toBeUndefined();
  });
});

function fakeSql(row: Record<string, unknown>): Sql {
  return (() => Promise.resolve([row])) as unknown as Sql;
}
