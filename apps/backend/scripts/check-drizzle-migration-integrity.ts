import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

type DrizzleJournalEntry = {
  idx: unknown;
  tag: unknown;
};

type DrizzleJournal = {
  version: unknown;
  dialect: unknown;
  entries: unknown;
};

const migrationFilePattern = /^\d{4}_.+\.sql$/;

export function validateDrizzleMigrationIntegrity(drizzleDir: string): void {
  const errors: string[] = [];
  const journalPath = join(drizzleDir, "meta", "_journal.json");

  if (!existsSync(journalPath)) {
    throw new Error(`Drizzle migration journal not found: ${journalPath}`);
  }

  const journal = readJournal(journalPath);
  if (typeof journal.version !== "string") {
    errors.push("meta/_journal.json must define a string version");
  }
  if (typeof journal.dialect !== "string") {
    errors.push("meta/_journal.json must define a string dialect");
  }
  if (!Array.isArray(journal.entries)) {
    errors.push("meta/_journal.json must define an entries array");
    throw integrityError(errors);
  }

  const entries = journal.entries as DrizzleJournalEntry[];
  const sqlTags = readdirSync(drizzleDir)
    .filter((filename) => migrationFilePattern.test(filename))
    .map((filename) => filename.replace(/\.sql$/, ""))
    .sort();
  const journalTags = entries
    .map((entry) => entry.tag)
    .filter((tag): tag is string => typeof tag === "string")
    .sort();
  const malformedEntries = entries
    .map((entry, index) => ({ entry, index }))
    .filter(({ entry }) => typeof entry.tag !== "string" || !Number.isInteger(entry.idx));

  if (malformedEntries.length > 0) {
    errors.push(
      `Malformed journal entries at indexes: ${malformedEntries
        .map(({ index }) => index)
        .join(", ")}`,
    );
  }

  const sqlMissingFromJournal = sqlTags.filter((tag) => !journalTags.includes(tag));
  if (sqlMissingFromJournal.length > 0) {
    errors.push(
      `SQL migration files missing from _journal.json: ${sqlMissingFromJournal.join(", ")}`,
    );
  }

  const journalMissingSql = journalTags.filter((tag) => !sqlTags.includes(tag));
  if (journalMissingSql.length > 0) {
    errors.push(
      `Journal entries missing SQL files: ${journalMissingSql
        .map((tag) => `${tag}.sql`)
        .join(", ")}`,
    );
  }

  const duplicateTags = duplicates(journalTags);
  if (duplicateTags.length > 0) {
    errors.push(`Duplicate journal tags: ${duplicateTags.join(", ")}`);
  }

  const idxValues = entries
    .map((entry) => entry.idx)
    .filter((idx): idx is number => Number.isInteger(idx))
    .sort((a, b) => a - b);
  const duplicateIdxValues = duplicates(idxValues);
  if (duplicateIdxValues.length > 0) {
    errors.push(`Duplicate journal idx values: ${duplicateIdxValues.join(", ")}`);
  }

  const expectedIdxValues = Array.from({ length: entries.length }, (_, index) => index);
  if (
    idxValues.length !== expectedIdxValues.length ||
    idxValues.some((idx, index) => idx !== expectedIdxValues[index])
  ) {
    errors.push(
      `Journal idx values must be sequential from 0 to ${entries.length - 1}`,
    );
  }

  if (errors.length > 0) {
    throw integrityError(errors);
  }
}

function readJournal(journalPath: string): DrizzleJournal {
  try {
    return JSON.parse(readFileSync(journalPath, "utf8")) as DrizzleJournal;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Could not parse Drizzle migration journal ${journalPath}: ${message}`);
  }
}

function duplicates<T extends string | number>(values: T[]): T[] {
  const seen = new Set<T>();
  const duplicated = new Set<T>();
  for (const value of values) {
    if (seen.has(value)) {
      duplicated.add(value);
    }
    seen.add(value);
  }
  return [...duplicated].sort();
}

function integrityError(errors: string[]): Error {
  return new Error(`Invalid Drizzle migration metadata:\n- ${errors.join("\n- ")}`);
}

function isCliEntryPoint(): boolean {
  const scriptPath = process.argv[1];
  return scriptPath !== undefined && pathToFileURL(resolve(scriptPath)).href === import.meta.url;
}

if (isCliEntryPoint()) {
  const drizzleDir = process.argv[2]
    ? resolve(process.argv[2])
    : resolve(process.cwd(), "../../infra/db/drizzle");
  validateDrizzleMigrationIntegrity(drizzleDir);
  console.log(`Drizzle migration metadata is complete: ${drizzleDir}`);
}
