import { mkdir, appendFile, readdir, rm } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { activeProfileSnapshot } from "./profiler.js";
import {
  redactSensitiveLogValue,
  safeErrorDiagnostic,
} from "./sensitiveDataRedaction.js";

export type LocalRunLogger = {
  enabled: boolean;
  log(event: Record<string, unknown>): Promise<void>;
};

export function createLocalRunLogger(input: {
  enabled: boolean;
  directory: string;
  cwd?: string;
}): LocalRunLogger {
  const directory = isAbsolute(input.directory)
    ? input.directory
    : resolve(input.cwd ?? process.cwd(), input.directory);
  return new JsonlRunLogger(input.enabled, directory);
}

export async function pruneLocalRunLogs(input: {
  directory: string;
  cwd?: string;
  now?: Date;
  maxAgeDays?: number;
}): Promise<number> {
  const directory = isAbsolute(input.directory)
    ? input.directory
    : resolve(input.cwd ?? process.cwd(), input.directory);
  const cutoff = (input.now ?? new Date()).getTime() -
    (input.maxAgeDays ?? 30) * 24 * 60 * 60 * 1000;
  let entries: string[];
  try {
    entries = await readdir(directory);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return 0;
    throw error;
  }
  let removed = 0;
  for (const entry of entries) {
    const match = /^runs-(\d{4}-\d{2}-\d{2})\.jsonl$/.exec(entry);
    if (!match) continue;
    const timestamp = Date.parse(`${match[1]}T00:00:00.000Z`);
    if (!Number.isFinite(timestamp) || timestamp >= cutoff) continue;
    await rm(resolve(directory, entry), { force: true });
    removed++;
  }
  return removed;
}

class JsonlRunLogger implements LocalRunLogger {
  constructor(
    public readonly enabled: boolean,
    private readonly directory: string,
  ) {}

  async log(event: Record<string, unknown>): Promise<void> {
    if (!this.enabled) return;
    const timestamp = new Date();
    const file = resolve(
      this.directory,
      `runs-${timestamp.toISOString().slice(0, 10)}.jsonl`,
    );
    await mkdir(this.directory, { recursive: true });
    const profile = activeProfileSnapshot();
    await appendFile(
      file,
      `${JSON.stringify(redactSensitiveLogValue({
        timestamp: timestamp.toISOString(),
        ...event,
        profile,
      }))}\n`,
      "utf8",
    );
  }
}

export function extractTokenUsage(rawResponse: unknown): Record<string, unknown> | undefined {
  if (!isRecord(rawResponse)) return undefined;
  const usage = rawResponse.usage;
  return isRecord(usage) ? usage : undefined;
}

export function extractReasoningTokens(rawResponse: unknown): number | undefined {
  const usage = extractTokenUsage(rawResponse);
  if (!usage) return undefined;
  const direct = usage.reasoning_tokens;
  if (typeof direct === "number") return direct;
  const completionDetails = usage.completion_tokens_details;
  if (isRecord(completionDetails)) {
    const value = completionDetails.reasoning_tokens;
    if (typeof value === "number") return value;
  }
  return undefined;
}

export function extractGenerationId(rawResponse: unknown): string | undefined {
  if (!isRecord(rawResponse)) return undefined;
  const id = rawResponse.id;
  return typeof id === "string" && id.length > 0 ? id : undefined;
}

export function summarizeError(error: unknown): Record<string, unknown> {
  return safeErrorDiagnostic(error);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
