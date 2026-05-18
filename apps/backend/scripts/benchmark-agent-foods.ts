import { mkdir, writeFile, appendFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { and, eq } from "drizzle-orm";
import { ActionExecutor } from "../src/actions/executor.js";
import { AuthService } from "../src/auth/service.js";
import { loadConfig } from "../src/config/env.js";
import { createDbClient, type AppDb } from "../src/db/client.js";
import { foodItems, users } from "../src/db/schema.js";
import { LocalBgeM3EmbeddingProvider } from "../src/embeddings/provider.js";
import { createApp } from "../src/http/app.js";
import { MemoryRetrievalService } from "../src/memory/retrieval.js";
import {
  DeterministicFoodTextExtractor,
  FoodResolver,
  LocalFoodDataProvider,
  OpenFoodFactsFoodDataProvider,
  UsdaFoodDataProvider,
} from "../src/nutrition/foodResolver.js";
import { ResolverNutritionProvider } from "../src/nutrition/provider.js";
import { runWithProfile, type ProfileSnapshot, type ProfileSpan } from "../src/observability/profiler.js";
import type { LocalRunLogger } from "../src/observability/localRunLogger.js";
import { PostgresRepository } from "../src/repository/postgres.js";
import type { SpeechToTextProvider, TranscriptionResult } from "../src/stt/speechToTextProvider.js";
import { agentFoodBenchmarkCases, type BenchmarkCase } from "./agent-food-benchmark-cases.js";

type BenchmarkRow = {
  id: string;
  language: string;
  category: string;
  prompt: string;
  status: number;
  ok: boolean;
  latencyMs: number;
  expectedTool: string;
  selectedTool?: string;
  executedTool?: string;
  expectedKind: string;
  resultKind?: string;
  checks: Record<string, boolean>;
  usage?: unknown;
  reasoningTokens?: number;
  generationId?: string;
  generation?: OpenRouterGeneration;
  timingsMs?: unknown;
  providerTimingsMs?: unknown;
  profile?: ProfileSnapshot;
  response?: unknown;
  runLog?: Record<string, unknown>;
  error?: unknown;
};

type OpenRouterGeneration = {
  costUsd?: number;
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  raw?: unknown;
};

class MemoryRunLogger implements LocalRunLogger {
  readonly enabled = true;
  readonly events: Array<Record<string, unknown>> = [];

  async log(event: Record<string, unknown>): Promise<void> {
    this.events.push(event);
  }

  findByTraceId(traceId: string): Record<string, unknown> | undefined {
    return [...this.events].reverse().find((event) => event.traceId === traceId);
  }
}

class NoopSpeechToTextProvider implements SpeechToTextProvider {
  async transcribe(): Promise<TranscriptionResult> {
    throw new Error("stt_not_used_by_agent_benchmark");
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const selectedCases = selectCases(args);
  validateCases(selectedCases);

  if (process.env.AGENT_BENCHMARK_LIVE !== "1" || args.dryRun) {
    const counts = countCases(selectedCases);
    console.log(JSON.stringify({
      dryRun: true,
      liveRequired: "Set AGENT_BENCHMARK_LIVE=1 to run real OpenRouter calls.",
      cases: selectedCases.length,
      counts,
    }, null, 2));
    return;
  }

  const config = loadConfig();
  const repository = new PostgresRepository(config.DATABASE_URL);
  const client = createDbClient(config.DATABASE_URL);
  const runLogger = new MemoryRunLogger();
  const app = createBenchmarkApp(config, repository, runLogger);
  const runId = new Date().toISOString().replace(/[:.]/g, "-");
  const outputDir = resolve(process.cwd(), args.outputDir ?? "../../logs/agent-benchmarks", runId);
  await mkdir(outputDir, { recursive: true });

  const email = `agent-benchmark-${runId}@bettercalories.local`;
  const password = "BenchmarkPassword123!";
  let accessToken = "";
  const rows: BenchmarkRow[] = [];

  try {
    const registered = await requestJson(app, "/v1/auth/register", {
      email,
      password,
      displayName: "Agent Benchmark",
    });
    accessToken = String((registered.body as { accessToken?: string }).accessToken ?? "");
    if (!accessToken) throw new Error("benchmark_auth_failed");

    await runPool(selectedCases, args.concurrency ?? 1, async (benchmarkCase) => {
      const row = await runCase({
        app,
        db: client.db,
        config,
        runLogger,
        outputDir,
        runId,
        accessToken,
        benchmarkCase,
      });
      rows.push(row);
      await appendFile(resolve(outputDir, "rows.jsonl"), `${JSON.stringify(row)}\n`, "utf8");
      console.log(`${row.id} ${row.ok ? "ok" : "fail"} ${row.latencyMs}ms tool=${row.executedTool ?? row.selectedTool ?? "none"} kind=${row.resultKind ?? "none"}`);
    });

    const summary = summarizeRows(rows);
    await writeFile(resolve(outputDir, "summary.json"), `${JSON.stringify(summary, null, 2)}\n`, "utf8");
    await writeFile(resolve(outputDir, "summary.md"), renderMarkdownSummary(summary), "utf8");
    console.log(JSON.stringify({ outputDir, summary }, null, 2));
  } finally {
    await cleanupBenchmarkUser(client.db, email);
    await client.close();
    await repository.close();
  }
}

function createBenchmarkApp(
  config: ReturnType<typeof loadConfig>,
  repository: PostgresRepository,
  runLogger: LocalRunLogger,
) {
  const authService = new AuthService(config, repository);
  const embeddingProvider = config.EMBEDDING_BASE_URL
    ? new LocalBgeM3EmbeddingProvider(
        config.EMBEDDING_BASE_URL,
        config.EMBEDDING_MODEL,
        config.EMBEDDING_DIMENSIONS,
      )
    : undefined;
  const foodResolver = new FoodResolver(
    new DeterministicFoodTextExtractor(),
    [
      new LocalFoodDataProvider(repository, { embeddingProvider }),
      new OpenFoodFactsFoodDataProvider(
        config.OPENFOODFACTS_BASE_URL,
        config.OPENFOODFACTS_USER_AGENT,
      ),
      ...(config.USDA_LIVE_FALLBACK_ENABLED
        ? [new UsdaFoodDataProvider(config.USDA_FDC_API_KEY)]
        : []),
    ],
    repository,
    config.FOOD_RESOLVER_MIN_CONFIDENCE,
  );
  const nutritionProvider = new ResolverNutritionProvider(foodResolver);
  const actionExecutor = new ActionExecutor(
    config,
    repository,
    nutritionProvider,
    new MemoryRetrievalService(repository, embeddingProvider),
  );
  return createApp({
    config,
    repository,
    authService,
    actionExecutor,
    sttProvider: new NoopSpeechToTextProvider(),
    runLogger,
  });
}

async function runCase(input: {
  app: ReturnType<typeof createApp>;
  db: AppDb;
  config: ReturnType<typeof loadConfig>;
  runLogger: MemoryRunLogger;
  outputDir: string;
  runId: string;
  accessToken: string;
  benchmarkCase: BenchmarkCase;
}): Promise<BenchmarkRow> {
  const traceId = `bench-${input.runId}-${input.benchmarkCase.id}`;
  const started = Date.now();
  try {
    const { result, profile } = await runWithProfile(
      "benchmark.agent_case",
      {
        id: input.benchmarkCase.id,
        language: input.benchmarkCase.language,
        category: input.benchmarkCase.category,
      },
      () => requestJson(input.app, "/v1/agent/runs", {
        text: input.benchmarkCase.prompt,
        source: "flutter",
      }, {
        authorization: `Bearer ${input.accessToken}`,
        "accept-language": input.benchmarkCase.locale,
        "x-user-timezone": input.benchmarkCase.language === "es" ? "Atlantic/Canary" : "America/New_York",
        "x-request-id": traceId,
      }),
    );
    const runLog = input.runLogger.findByTraceId(traceId);
    const generationId = stringField(runLog, "generationId");
    const generation = generationId
      ? await fetchOpenRouterGeneration(input.config.OPENROUTER_API_KEY, generationId)
      : undefined;
    const checks = await evaluateCase(input.db, input.benchmarkCase, result.body, runLog);
    const ok = result.status === 200 && Object.values(checks).every(Boolean);
    return {
      id: input.benchmarkCase.id,
      language: input.benchmarkCase.language,
      category: input.benchmarkCase.category,
      prompt: input.benchmarkCase.prompt,
      status: result.status,
      ok,
      latencyMs: Date.now() - started,
      expectedTool: input.benchmarkCase.expectedTool,
      selectedTool: stringField(runLog, "selectedTool"),
      executedTool: stringField(runLog, "executedTool") ?? stringField(runLog, "selectedTool"),
      expectedKind: input.benchmarkCase.expectedKind,
      resultKind: stringField(runLog, "resultKind") ?? stringField(result.body, "kind"),
      checks,
      usage: runLog?.usage,
      reasoningTokens: numberField(runLog, "reasoningTokens") ?? generation?.reasoningTokens,
      generationId,
      generation,
      timingsMs: runLog?.timingsMs,
      providerTimingsMs: runLog?.providerTimingsMs,
      profile: (runLog?.profile as ProfileSnapshot | undefined) ?? profile,
      response: result.body,
      runLog,
    };
  } catch (error) {
    return {
      id: input.benchmarkCase.id,
      language: input.benchmarkCase.language,
      category: input.benchmarkCase.category,
      prompt: input.benchmarkCase.prompt,
      status: 0,
      ok: false,
      latencyMs: Date.now() - started,
      expectedTool: input.benchmarkCase.expectedTool,
      expectedKind: input.benchmarkCase.expectedKind,
      checks: { status: false },
      error: error instanceof Error ? { message: error.message, name: error.name } : String(error),
    };
  }
}

async function requestJson(
  app: ReturnType<typeof createApp>,
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<{ status: number; body: unknown }> {
  const response = await app.fetch(new Request(`http://localhost${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  }));
  const text = await response.text();
  return {
    status: response.status,
    body: text ? JSON.parse(text) : null,
  };
}

async function evaluateCase(
  db: AppDb,
  benchmarkCase: BenchmarkCase,
  body: unknown,
  runLog?: Record<string, unknown>,
): Promise<Record<string, boolean>> {
  const resultKind = stringField(runLog, "resultKind") ?? stringField(body, "kind");
  const executedTool = stringField(runLog, "executedTool") ?? stringField(runLog, "selectedTool");
  const checks: Record<string, boolean> = {
    status: true,
    tool: executedTool === benchmarkCase.expectedTool,
    kind: resultKind === benchmarkCase.expectedKind,
    foods: containsExpectedFoods(body, benchmarkCase.expectedFoods),
  };
  if (benchmarkCase.culturalCheck) {
    checks.cultural = await culturalCheck(db, benchmarkCase, body);
  }
  return checks;
}

function containsExpectedFoods(body: unknown, expectedFoods: string[]): boolean {
  const haystack = JSON.stringify(body).toLowerCase();
  return expectedFoods.every((food) => haystack.includes(food.toLowerCase()));
}

async function culturalCheck(
  db: AppDb,
  benchmarkCase: BenchmarkCase,
  body: unknown,
): Promise<boolean> {
  const groups = candidateGroupsFromBody(body);
  if (groups.length === 0) return benchmarkCase.expectedKind === "clarification_required";
  for (const group of groups) {
    const candidates = Array.isArray(group.candidates) ? group.candidates : [];
    if (candidates.length === 0) continue;
    const keyed = await Promise.all(candidates.slice(0, 8).map((candidate) => foodKeyForCandidate(db, candidate)));
    const first = keyed[0];
    if (benchmarkCase.language === "es") {
      if (keyed.some((item) => item.foodKey === "es") && first?.foodKey !== "es") return false;
    } else if (
      first?.foodKey &&
      first.foodKey !== "en" &&
      first.externalSource !== "usda_fdc"
    ) {
      return false;
    }
  }
  return true;
}

function candidateGroupsFromBody(body: unknown): Array<{ candidates?: unknown[] }> {
  if (!isRecord(body)) return [];
  const options = body.options;
  if (Array.isArray(options)) {
    return options.filter(isRecord).map((group) => group as { candidates?: unknown[] });
  }
  return [];
}

async function foodKeyForCandidate(
  db: AppDb,
  candidate: unknown,
): Promise<{ foodKey?: string; externalSource?: string }> {
  if (!isRecord(candidate)) return {};
  const externalSource = typeof candidate.externalSource === "string" ? candidate.externalSource : undefined;
  const externalId = typeof candidate.externalId === "string" ? candidate.externalId : undefined;
  if (!externalSource || !externalId) return { externalSource };
  const [row] = await db
    .select({
      foodKey: foodItems.foodKey,
      externalSource: foodItems.externalSource,
    })
    .from(foodItems)
    .where(and(
      eq(foodItems.externalSource, externalSource),
      eq(foodItems.externalId, externalId),
    ))
    .limit(1);
  return {
    foodKey: row?.foodKey ?? undefined,
    externalSource: row?.externalSource ?? externalSource,
  };
}

async function fetchOpenRouterGeneration(
  apiKey: string,
  generationId: string,
): Promise<OpenRouterGeneration | undefined> {
  try {
    const response = await fetch(`https://openrouter.ai/api/v1/generation?id=${encodeURIComponent(generationId)}`, {
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (!response.ok) return undefined;
    const raw = await response.json() as { data?: Record<string, unknown> };
    const data = raw.data ?? {};
    return {
      costUsd: numberFromUnknown(data.total_cost ?? data.cost),
      promptTokens: numberFromUnknown(data.prompt_tokens),
      completionTokens: numberFromUnknown(data.completion_tokens),
      totalTokens: numberFromUnknown(data.total_tokens),
      reasoningTokens: numberFromUnknown(data.reasoning_tokens),
      raw,
    };
  } catch {
    return undefined;
  }
}

function summarizeRows(rows: BenchmarkRow[]) {
  const groups = {
    all: rows,
    es: rows.filter((row) => row.language === "es"),
    en: rows.filter((row) => row.language === "en"),
  };
  const spanStats = summarizeSpans(rows.flatMap((row) => flattenSpans(row.profile?.spans ?? [])));
  const costRows = rows
    .map((row) => row.generation?.costUsd ?? usageCost(row.usage))
    .filter((value): value is number => typeof value === "number");
  return {
    total: rows.length,
    passed: rows.filter((row) => row.ok).length,
    accuracy: Object.fromEntries(Object.entries(groups).map(([name, list]) => [name, ratio(list.filter((row) => row.ok).length, list.length)])),
    toolAccuracy: ratio(rows.filter((row) => row.checks.tool).length, rows.length),
    kindAccuracy: ratio(rows.filter((row) => row.checks.kind).length, rows.length),
    foodAccuracy: ratio(rows.filter((row) => row.checks.foods).length, rows.length),
    culturalAccuracy: ratio(rows.filter((row) => row.checks.cultural !== false).length, rows.length),
    latencyMs: percentileSummary(rows.map((row) => row.latencyMs)),
    tokenUsage: summarizeUsage(rows),
    costUsd: {
      total: sum(costRows),
      average: ratio(sum(costRows), costRows.length),
      measuredRows: costRows.length,
    },
    spans: spanStats,
    failures: rows.filter((row) => !row.ok).slice(0, 20).map((row) => ({
      id: row.id,
      language: row.language,
      expectedTool: row.expectedTool,
      actualTool: row.executedTool ?? row.selectedTool,
      expectedKind: row.expectedKind,
      actualKind: row.resultKind,
      checks: row.checks,
      error: row.error,
    })),
  };
}

function summarizeUsage(rows: BenchmarkRow[]) {
  const usages = rows.map((row) => isRecord(row.usage) ? row.usage : undefined).filter(Boolean) as Record<string, unknown>[];
  return {
    promptTokens: sum(usages.map((usage) => numberFromUnknown(usage.prompt_tokens) ?? 0)),
    completionTokens: sum(usages.map((usage) => numberFromUnknown(usage.completion_tokens) ?? 0)),
    totalTokens: sum(usages.map((usage) => numberFromUnknown(usage.total_tokens) ?? 0)),
    reasoningTokens: sum(rows.map((row) => row.reasoningTokens ?? 0)),
    measuredRows: usages.length,
  };
}

function usageCost(usage: unknown): number | undefined {
  if (!isRecord(usage)) return undefined;
  return numberFromUnknown(usage.cost);
}

function renderMarkdownSummary(summary: ReturnType<typeof summarizeRows>): string {
  return [
    "# Agent food benchmark",
    "",
    `- Cases: ${summary.total}`,
    `- Passed: ${summary.passed}`,
    `- Accuracy all/es/en: ${summary.accuracy.all} / ${summary.accuracy.es} / ${summary.accuracy.en}`,
    `- Tool/kind/food/cultural: ${summary.toolAccuracy} / ${summary.kindAccuracy} / ${summary.foodAccuracy} / ${summary.culturalAccuracy}`,
    `- Latency p50/p90/p99 ms: ${summary.latencyMs.p50} / ${summary.latencyMs.p90} / ${summary.latencyMs.p99}`,
    `- Tokens prompt/completion/reasoning/total: ${summary.tokenUsage.promptTokens} / ${summary.tokenUsage.completionTokens} / ${summary.tokenUsage.reasoningTokens} / ${summary.tokenUsage.totalTokens}`,
    `- Cost USD measured/total/avg: ${summary.costUsd.measuredRows} / ${summary.costUsd.total} / ${summary.costUsd.average}`,
    "",
    "## Top spans",
    ...summary.spans.slice(0, 20).map((span) => `- ${span.name}: count=${span.count}, totalMs=${span.totalMs}, p90Ms=${span.p90Ms}`),
    "",
    "## Failures",
    ...summary.failures.map((failure) => `- ${failure.id}: tool ${failure.actualTool ?? "none"} expected ${failure.expectedTool}; kind ${failure.actualKind ?? "none"} expected ${failure.expectedKind}`),
    "",
  ].join("\n");
}

function summarizeSpans(spans: ProfileSpan[]) {
  const byName = new Map<string, number[]>();
  for (const span of spans) {
    const durations = byName.get(span.name) ?? [];
    durations.push(span.durationMs ?? 0);
    byName.set(span.name, durations);
  }
  return [...byName.entries()]
    .map(([name, durations]) => ({
      name,
      count: durations.length,
      totalMs: sum(durations),
      p50Ms: percentile(durations, 0.5),
      p90Ms: percentile(durations, 0.9),
      p99Ms: percentile(durations, 0.99),
    }))
    .sort((a, b) => b.totalMs - a.totalMs);
}

function flattenSpans(spans: ProfileSpan[]): ProfileSpan[] {
  return spans.flatMap((span) => [span, ...flattenSpans(span.children ?? [])]);
}

async function cleanupBenchmarkUser(db: AppDb, email: string) {
  try {
    await db.delete(users).where(eq(users.email, email));
  } catch (error) {
    console.warn("benchmark.cleanup.failed", error instanceof Error ? error.message : String(error));
  }
}

async function runPool<T>(
  items: T[],
  concurrency: number,
  worker: (item: T) => Promise<void>,
) {
  const queue = [...items];
  await Promise.all(Array.from({ length: Math.max(1, concurrency) }, async () => {
    while (queue.length > 0) {
      const item = queue.shift();
      if (item) await worker(item);
    }
  }));
}

function parseArgs(args: string[]) {
  const parsed: { limit?: number; caseId?: string; concurrency?: number; outputDir?: string; dryRun?: boolean } = {};
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--dry-run") parsed.dryRun = true;
    if (arg === "--limit") parsed.limit = Number(args[++index]);
    if (arg === "--case") parsed.caseId = args[++index];
    if (arg === "--concurrency") parsed.concurrency = Number(args[++index]);
    if (arg === "--output-dir") parsed.outputDir = args[++index];
  }
  return parsed;
}

function selectCases(args: ReturnType<typeof parseArgs>) {
  let cases = agentFoodBenchmarkCases;
  if (args.caseId) cases = cases.filter((item) => item.id === args.caseId);
  if (args.limit) cases = cases.slice(0, args.limit);
  return cases;
}

export function validateCases(cases = agentFoodBenchmarkCases) {
  const ids = new Set<string>();
  if (cases.length === 0) throw new Error("No benchmark cases selected.");
  for (const item of cases) {
    if (ids.has(item.id)) throw new Error(`Duplicate benchmark case id: ${item.id}`);
    ids.add(item.id);
    if (!item.prompt || !item.expectedTool || !item.expectedKind) throw new Error(`Invalid benchmark case: ${item.id}`);
    if (item.prompt.toLowerCase().includes("bedca")) throw new Error(`BEDCA is not allowed in benchmark case: ${item.id}`);
  }
  if (cases === agentFoodBenchmarkCases) {
    const counts = countCases(cases);
    if (cases.length !== 100 || counts.es !== 50 || counts.en !== 50) {
      throw new Error(`Expected 100 cases with 50 ES and 50 EN, got ${JSON.stringify(counts)}`);
    }
  }
}

function countCases(cases: BenchmarkCase[]) {
  return {
    es: cases.filter((item) => item.language === "es").length,
    en: cases.filter((item) => item.language === "en").length,
    mealLog: cases.filter((item) => item.category === "meal_log").length,
    nutritionSearch: cases.filter((item) => item.category === "nutrition_search").length,
    portionUnits: cases.filter((item) => item.category === "portion_units").length,
    clarification: cases.filter((item) => item.category === "clarification").length,
  };
}

function percentileSummary(values: number[]) {
  return {
    min: Math.min(...values),
    p50: percentile(values, 0.5),
    p90: percentile(values, 0.9),
    p99: percentile(values, 0.99),
    max: Math.max(...values),
    average: ratio(sum(values), values.length),
  };
}

function percentile(values: number[], p: number) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * p))] ?? 0;
}

function ratio(numerator: number, denominator: number) {
  return denominator === 0 ? 0 : Number((numerator / denominator).toFixed(4));
}

function sum(values: number[]) {
  return Number(values.reduce((total, value) => total + value, 0).toFixed(6));
}

function stringField(value: unknown, key: string): string | undefined {
  if (!isRecord(value)) return undefined;
  const field = value[key];
  return typeof field === "string" ? field : undefined;
}

function numberField(value: unknown, key: string): number | undefined {
  if (!isRecord(value)) return undefined;
  return numberFromUnknown(value[key]);
}

function numberFromUnknown(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() && Number.isFinite(Number(value))) return Number(value);
  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack ?? error.message : error);
    process.exitCode = 1;
  });
}
