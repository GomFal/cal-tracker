import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { validateDrizzleMigrationIntegrity } from "../../scripts/check-drizzle-migration-integrity.js";

const tempDirs: string[] = [];

afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) rmSync(dir, { force: true, recursive: true });
  }
});

describe("validateDrizzleMigrationIntegrity", () => {
  it("accepts matching SQL files and journal entries", () => {
    const drizzleDir = createDrizzleDir({
      sqlTags: ["0000_base", "0001_feature"],
      entries: [
        { idx: 0, version: "7", when: 1, tag: "0000_base", breakpoints: true },
        { idx: 1, version: "7", when: 2, tag: "0001_feature", breakpoints: true },
      ],
    });

    expect(() => validateDrizzleMigrationIntegrity(drizzleDir)).not.toThrow();
  });

  it("fails when an SQL migration file is missing from the journal", () => {
    const drizzleDir = createDrizzleDir({
      sqlTags: ["0000_base", "0001_missing_journal"],
      entries: [
        { idx: 0, version: "7", when: 1, tag: "0000_base", breakpoints: true },
      ],
    });

    expect(() => validateDrizzleMigrationIntegrity(drizzleDir)).toThrow(
      /SQL migration files missing from _journal\.json: 0001_missing_journal/,
    );
  });

  it("fails when the journal references a missing SQL file", () => {
    const drizzleDir = createDrizzleDir({
      sqlTags: ["0000_base"],
      entries: [
        { idx: 0, version: "7", when: 1, tag: "0000_base", breakpoints: true },
        { idx: 1, version: "7", when: 2, tag: "0001_missing_sql", breakpoints: true },
      ],
    });

    expect(() => validateDrizzleMigrationIntegrity(drizzleDir)).toThrow(
      /Journal entries missing SQL files: 0001_missing_sql\.sql/,
    );
  });

  it("fails when journal tags are duplicated", () => {
    const drizzleDir = createDrizzleDir({
      sqlTags: ["0000_base"],
      entries: [
        { idx: 0, version: "7", when: 1, tag: "0000_base", breakpoints: true },
        { idx: 1, version: "7", when: 2, tag: "0000_base", breakpoints: true },
      ],
    });

    expect(() => validateDrizzleMigrationIntegrity(drizzleDir)).toThrow(
      /Duplicate journal tags: 0000_base/,
    );
  });

  it("fails when journal indexes are duplicated", () => {
    const drizzleDir = createDrizzleDir({
      sqlTags: ["0000_base", "0001_feature"],
      entries: [
        { idx: 0, version: "7", when: 1, tag: "0000_base", breakpoints: true },
        { idx: 0, version: "7", when: 2, tag: "0001_feature", breakpoints: true },
      ],
    });

    expect(() => validateDrizzleMigrationIntegrity(drizzleDir)).toThrow(
      /Duplicate journal idx values: 0/,
    );
  });

  it("fails when journal indexes are not sequential from zero", () => {
    const drizzleDir = createDrizzleDir({
      sqlTags: ["0000_base", "0001_feature"],
      entries: [
        { idx: 0, version: "7", when: 1, tag: "0000_base", breakpoints: true },
        { idx: 2, version: "7", when: 2, tag: "0001_feature", breakpoints: true },
      ],
    });

    expect(() => validateDrizzleMigrationIntegrity(drizzleDir)).toThrow(
      /Journal idx values must be sequential from 0 to 1/,
    );
  });
});

function createDrizzleDir(input: {
  sqlTags: string[];
  entries: Array<Record<string, unknown>>;
}): string {
  const drizzleDir = mkdtempSync(join(tmpdir(), "cal-tracker-drizzle-"));
  tempDirs.push(drizzleDir);
  mkdirSync(join(drizzleDir, "meta"));
  for (const tag of input.sqlTags) {
    writeFileSync(join(drizzleDir, `${tag}.sql`), "select 1;\n", "utf8");
  }
  writeFileSync(
    join(drizzleDir, "meta", "_journal.json"),
    JSON.stringify(
      { version: "7", dialect: "postgresql", entries: input.entries },
      null,
      2,
    ),
    "utf8",
  );
  return drizzleDir;
}
