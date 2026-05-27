import { mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { FoodCandidateGroup, MealItem } from "@cal-tracker/contracts";
import { loadConfig } from "../src/config/env.js";
import {
  DeterministicFoodTextExtractor,
  FoodResolver,
  LocalFoodDataProvider,
  type FoodSearchResult,
  type FoodResolutionResult,
} from "../src/nutrition/foodResolver.js";
import { ResolverNutritionProvider } from "../src/nutrition/provider.js";
import type { FoodSearchBackend } from "../src/repository/foodSearchBackend.js";
import { PostgresRepository } from "../src/repository/postgres.js";
import { TypesenseFoodSearch } from "../src/repository/typesenseFoodSearch.js";
import { normalizeText } from "../src/utils/normalize.js";
import { agentFoodBenchmarkCases, type BenchmarkCase } from "./agent-food-benchmark-cases.js";

type BenchmarkBackend = "postgres" | "typesense";

type BenchmarkArgs = {
  backend: BenchmarkBackend | "both";
  limit?: number;
  caseId?: string;
  category?: BenchmarkCase["category"];
  concurrency: number;
  freshRunnerPerCase: boolean;
  uniqueUserPerQuery: boolean;
  warmup: number;
  iterations: number;
  outputDir?: string;
  quiet: boolean;
};

type BenchmarkRow = {
  backend: BenchmarkBackend;
  id: string;
  language: string;
  category: string;
  prompt: string;
  tool: BenchmarkCase["expectedTool"];
  expectedKind: BenchmarkCase["expectedKind"];
  resultKind: "proposal" | "nutrition_search" | "clarification_required";
  ok: boolean;
  expectedFoodHit: boolean;
  latencyMs: number;
  iteration: number;
  warmup: boolean;
  itemCount: number;
  candidateGroupCount: number;
  topNames: string[];
  expectedFoods: string[];
  extractedQuery?: string;
  error?: unknown;
};

type Runner = {
  backend: BenchmarkBackend;
  resolver: FoodResolver;
  nutritionProvider: ResolverNutritionProvider;
  close(): Promise<void>;
};

type BackendRunStats = {
  backend: BenchmarkBackend;
  wallMs: number;
};

type BenchmarkTask = {
  benchmarkCase: BenchmarkCase;
  iteration: number;
  warmup: boolean;
};

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const cases = selectCases(args);
  const backends: BenchmarkBackend[] = args.backend === "both"
    ? ["postgres", "typesense"]
    : [args.backend];
  const runId = new Date().toISOString().replace(/[:.]/g, "-");
  const outputDir = resolve(process.cwd(), args.outputDir ?? "../../logs/typesense-benchmarks", runId);
  await mkdir(outputDir, { recursive: true });

  const rows: BenchmarkRow[] = [];
  const runStats: BackendRunStats[] = [];
  for (const backend of backends) {
    const started = performance.now();
    const backendRows = await runBackend(backend, cases, args);
    runStats.push({
      backend,
      wallMs: Math.round(performance.now() - started),
    });
    rows.push(...backendRows);
  }

  const summary = summarizeRows(rows, runStats, args);
  await writeFile(resolve(outputDir, "rows.jsonl"), `${rows.map((row) => JSON.stringify(row)).join("\n")}\n`, "utf8");
  await writeFile(resolve(outputDir, "summary.json"), `${JSON.stringify(summary, null, 2)}\n`, "utf8");
  await writeFile(resolve(outputDir, "summary.md"), renderMarkdownSummary(summary), "utf8");
  console.log(JSON.stringify({ outputDir, summary }, null, 2));
}

async function runBackend(
  backend: BenchmarkBackend,
  cases: BenchmarkCase[],
  args: BenchmarkArgs,
): Promise<BenchmarkRow[]> {
  const rows: BenchmarkRow[] = [];
  const sharedRunner = args.freshRunnerPerCase ? undefined : createRunner(backend);
  try {
    for (const tasks of [
      buildTasks(cases, args.warmup, 0, true),
      buildTasks(cases, args.iterations, args.warmup, false),
    ]) {
      await runPool(tasks, args.concurrency, async (task) => {
        const runner = sharedRunner ?? createRunner(backend);
        try {
          const row = await runCase(
            runner,
            task.benchmarkCase,
            task.iteration,
            task.warmup,
            userIdForCase(backend, task.benchmarkCase, task.iteration, task.warmup, args),
          );
          rows.push(row);
          if (!args.quiet) {
            console.log(`${runner.backend} ${row.id} ${task.warmup ? "warmup" : "run"} ${row.ok ? "ok" : "fail"} ${row.latencyMs}ms ${row.resultKind}`);
          }
        } finally {
          if (!sharedRunner) await runner.close();
        }
      });
    }
  } finally {
    if (sharedRunner) await sharedRunner.close();
  }
  return rows;
}

function buildTasks(
  cases: BenchmarkCase[],
  iterations: number,
  iterationOffset: number,
  warmup: boolean,
): BenchmarkTask[] {
  const tasks: BenchmarkTask[] = [];
  for (let index = 0; index < iterations; index += 1) {
    for (const benchmarkCase of cases) {
      tasks.push({
        benchmarkCase,
        iteration: iterationOffset + index,
        warmup,
      });
    }
  }
  return tasks;
}

async function runCase(
  runner: Runner,
  benchmarkCase: BenchmarkCase,
  iteration: number,
  warmup: boolean,
  userId: string,
): Promise<BenchmarkRow> {
  const started = performance.now();
  try {
    const result = benchmarkCase.expectedTool === "search_nutrition_database"
      ? await runNutritionSearch(runner, benchmarkCase, userId)
      : await runMealResolution(runner, benchmarkCase, userId);
    const latencyMs = Math.round(performance.now() - started);
    const topNames = topResultNames(result.items, result.candidateGroups);
    const resultKind = result.kind;
    const expectedFoodHit = containsExpectedFoods(result, benchmarkCase.expectedFoods);
    return {
      backend: runner.backend,
      id: benchmarkCase.id,
      language: benchmarkCase.language,
      category: benchmarkCase.category,
      prompt: benchmarkCase.prompt,
      tool: benchmarkCase.expectedTool,
      expectedKind: benchmarkCase.expectedKind,
      resultKind,
      ok: resultKind === benchmarkCase.expectedKind && expectedFoodHit,
      expectedFoodHit,
      latencyMs,
      iteration,
      warmup,
      itemCount: result.items.length,
      candidateGroupCount: result.candidateGroups.length,
      topNames,
      expectedFoods: benchmarkCase.expectedFoods,
      extractedQuery: "query" in result ? result.query : undefined,
    };
  } catch (error) {
    return {
      backend: runner.backend,
      id: benchmarkCase.id,
      language: benchmarkCase.language,
      category: benchmarkCase.category,
      prompt: benchmarkCase.prompt,
      tool: benchmarkCase.expectedTool,
      expectedKind: benchmarkCase.expectedKind,
      resultKind: "clarification_required",
      ok: false,
      expectedFoodHit: false,
      latencyMs: Math.round(performance.now() - started),
      iteration,
      warmup,
      itemCount: 0,
      candidateGroupCount: 0,
      topNames: [],
      expectedFoods: benchmarkCase.expectedFoods,
      error: error instanceof Error ? { name: error.name, message: error.message } : String(error),
    };
  }
}

async function runNutritionSearch(
  runner: Runner,
  benchmarkCase: BenchmarkCase,
  userId: string,
): Promise<{
  kind: "nutrition_search";
  query: string;
  items: MealItem[];
  candidateGroups: FoodCandidateGroup[];
}> {
  const query = nutritionQueryForCase(benchmarkCase);
  const result = await runner.nutritionProvider.search(
    userId,
    query,
    undefined,
    benchmarkCase.locale,
  ) as FoodSearchResult;
  return {
    kind: "nutrition_search",
    query,
    items: result.items,
    candidateGroups: result.candidateGroups,
  };
}

async function runMealResolution(
  runner: Runner,
  benchmarkCase: BenchmarkCase,
  userId: string,
): Promise<{
  kind: "proposal" | "clarification_required";
  items: MealItem[];
  candidateGroups: FoodCandidateGroup[];
  unresolvedMentions: unknown[];
}> {
  const resolution: FoodResolutionResult = await runner.resolver.resolveMealText(
    userId,
    benchmarkCase.prompt,
    benchmarkCase.locale,
  );
  return {
    kind: resolution.clarificationRequired ? "clarification_required" : "proposal",
    items: resolution.items,
    candidateGroups: resolution.candidateGroups,
    unresolvedMentions: resolution.unresolvedMentions,
  };
}

function createRunner(backend: BenchmarkBackend): Runner {
  const config = loadConfig();
  let searchBackend: FoodSearchBackend;
  let close = async () => {};
  if (backend === "postgres") {
    const repository = new PostgresRepository(config.DATABASE_URL);
    searchBackend = repository;
    close = () => repository.close();
  } else {
    searchBackend = new TypesenseFoodSearch({
      protocol: config.TYPESENSE_PROTOCOL,
      host: config.TYPESENSE_HOST,
      port: config.TYPESENSE_PORT,
      apiKey: config.TYPESENSE_API_KEY,
      collection: config.TYPESENSE_COLLECTION,
    });
  }
  const resolver = new FoodResolver(
    new DeterministicFoodTextExtractor(),
    new LocalFoodDataProvider(searchBackend),
    config.FOOD_RESOLVER_MIN_CONFIDENCE,
  );
  return {
    backend,
    resolver,
    nutritionProvider: new ResolverNutritionProvider(resolver),
    close,
  };
}

function nutritionQueryForCase(benchmarkCase: BenchmarkCase): string {
  const text = benchmarkCase.prompt.replace(/[?.!]+$/g, "").trim();
  const patterns = [
    /^busca en la base nutricional\s+(.+)$/i,
    /^consulta el alimento\s+(.+)$/i,
    /^busca informacion nutricional de\s+(.+)$/i,
    /^consulta en la base de alimentos\s+(.+)$/i,
    /^busca nutricion para\s+(.+)$/i,
    /^consulta\s+(.+?)\s+en la base nutricional$/i,
    /^busca\s+(.+)$/i,
    /^consulta\s+(.+)$/i,
    /^search the nutrition database for\s+(.+)$/i,
    /^search nutrition database for\s+(.+)$/i,
    /^search nutrition for\s+(.+)$/i,
    /^find nutrition entries for\s+(.+)$/i,
    /^search the database for\s+(.+)$/i,
    /^look up\s+(.+?)\s+in the food database$/i,
    /^look up\s+(.+?)\s+in the nutrition database$/i,
    /^look up\s+(.+)$/i,
    /^find food data for\s+(.+)$/i,
    /^search for\s+(.+)$/i,
  ];
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (match?.[1]) return match[1].trim();
  }
  return text;
}

function selectCases(args: BenchmarkArgs): BenchmarkCase[] {
  let selected = agentFoodBenchmarkCases.filter((item) =>
    item.expectedTool === "search_nutrition_database" ||
    item.expectedTool === "propose_meal_log"
  );
  if (args.caseId) selected = selected.filter((item) => item.id === args.caseId);
  if (args.category) selected = selected.filter((item) => item.category === args.category);
  if (args.limit !== undefined) selected = selected.slice(0, args.limit);
  if (selected.length === 0) throw new Error("No benchmark cases selected");
  return selected;
}

function summarizeRows(rows: BenchmarkRow[], runStats: BackendRunStats[], args: BenchmarkArgs) {
  const measured = rows.filter((row) => !row.warmup);
  const backendSummaries: Partial<Record<BenchmarkBackend, ReturnType<typeof summarizeBackend>>> = {};
  const statsByBackend = new Map(runStats.map((item) => [item.backend, item]));
  for (const backend of ["postgres", "typesense"] as BenchmarkBackend[]) {
    const summary = summarizeBackend(
      measured.filter((row) => row.backend === backend),
      statsByBackend.get(backend),
    );
    if (summary.total > 0) backendSummaries[backend] = summary;
  }
  return {
    settings: {
      backend: args.backend,
      category: args.category,
      limit: args.limit,
      concurrency: args.concurrency,
      warmup: args.warmup,
      iterations: args.iterations,
      freshRunnerPerCase: args.freshRunnerPerCase,
      uniqueUserPerQuery: args.uniqueUserPerQuery,
    },
    totalRows: rows.length,
    measuredRows: measured.length,
    byBackend: backendSummaries,
    comparison: compareBackends(measured),
  };
}

function summarizeBackend(rows: BenchmarkRow[], runStats?: BackendRunStats) {
  const groups = {
    all: rows,
    nutrition_search: rows.filter((row) => row.category === "nutrition_search"),
    meal_log: rows.filter((row) => row.category === "meal_log"),
    portion_units: rows.filter((row) => row.category === "portion_units"),
    clarification: rows.filter((row) => row.category === "clarification"),
  };
  return {
    total: rows.length,
    passed: rows.filter((row) => row.ok).length,
    okRate: ratio(rows.filter((row) => row.ok).length, rows.length),
    expectedFoodHitRate: ratio(rows.filter((row) => row.expectedFoodHit).length, rows.length),
    wallMs: runStats?.wallMs ?? 0,
    throughputQps: runStats && runStats.wallMs > 0
      ? ratio(rows.length, runStats.wallMs / 1000)
      : 0,
    latencyMs: percentileSummary(rows.map((row) => row.latencyMs)),
    byCategory: Object.fromEntries(
      Object.entries(groups).map(([name, list]) => [name, {
        total: list.length,
        okRate: ratio(list.filter((row) => row.ok).length, list.length),
        latencyMs: percentileSummary(list.map((row) => row.latencyMs)),
      }]),
    ),
    failures: rows.filter((row) => !row.ok).slice(0, 20).map((row) => ({
      id: row.id,
      category: row.category,
      expectedKind: row.expectedKind,
      resultKind: row.resultKind,
      expectedFoodHit: row.expectedFoodHit,
      topNames: row.topNames,
      error: row.error,
    })),
  };
}

function compareBackends(rows: BenchmarkRow[]) {
  const postgres = rows.filter((row) => row.backend === "postgres");
  const typesense = rows.filter((row) => row.backend === "typesense");
  if (postgres.length === 0 || typesense.length === 0) return undefined;
  const postgresByKey = new Map(postgres.map((row) => [comparisonKey(row), row]));
  const pairs = typesense
    .map((typeRow) => {
      const pgRow = postgresByKey.get(comparisonKey(typeRow));
      if (!pgRow) return undefined;
      return { pgRow, typeRow };
    })
    .filter((pair): pair is { pgRow: BenchmarkRow; typeRow: BenchmarkRow } => Boolean(pair));
  return {
    pairs: pairs.length,
    speedup: percentileSummary(pairs.map((pair) =>
      pair.typeRow.latencyMs > 0 ? pair.pgRow.latencyMs / pair.typeRow.latencyMs : 0,
    )),
    top3OverlapRate: ratio(sum(pairs.map((pair) => topOverlap(pair.pgRow.topNames, pair.typeRow.topNames, 3))), pairs.length),
    top10OverlapRate: ratio(sum(pairs.map((pair) => topOverlap(pair.pgRow.topNames, pair.typeRow.topNames, 10))), pairs.length),
  };
}

function comparisonKey(row: BenchmarkRow): string {
  return `${row.id}:${row.iteration}`;
}

function topOverlap(left: string[], right: string[], size: number): number {
  const leftSet = new Set(left.slice(0, size).map(normalizeText));
  const rightSet = new Set(right.slice(0, size).map(normalizeText));
  if (leftSet.size === 0 && rightSet.size === 0) return 1;
  if (leftSet.size === 0 || rightSet.size === 0) return 0;
  let overlap = 0;
  for (const item of leftSet) {
    if (rightSet.has(item)) overlap += 1;
  }
  return overlap / Math.max(leftSet.size, rightSet.size);
}

function renderMarkdownSummary(summary: ReturnType<typeof summarizeRows>): string {
  const lines = [
    "# Food retrieval benchmark",
    "",
    `- Measured rows: ${summary.measuredRows}`,
  ];
  for (const [backend, item] of Object.entries(summary.byBackend)) {
    lines.push(
      "",
      `## ${backend}`,
      `- Passed: ${item.passed}/${item.total} (${item.okRate})`,
      `- Expected food hit rate: ${item.expectedFoodHitRate}`,
      `- Wall time: ${item.wallMs}ms`,
      `- Throughput: ${item.throughputQps} qps`,
      `- Latency p50/p90/p99 ms: ${item.latencyMs.p50}/${item.latencyMs.p90}/${item.latencyMs.p99}`,
      "### Failures",
      ...(item.failures.length > 0
        ? item.failures.map((failure) => `- ${failure.id}: kind=${failure.resultKind}, foodHit=${failure.expectedFoodHit}, top=${failure.topNames.join(" | ")}`)
        : ["- none"]),
    );
  }
  if (summary.comparison) {
    lines.push(
      "",
      "## Comparison",
      `- Pairs: ${summary.comparison.pairs}`,
      `- Speedup p50/p90/p99: ${summary.comparison.speedup.p50}/${summary.comparison.speedup.p90}/${summary.comparison.speedup.p99}`,
      `- Top-3 overlap: ${summary.comparison.top3OverlapRate}`,
      `- Top-10 overlap: ${summary.comparison.top10OverlapRate}`,
    );
  }
  return `${lines.join("\n")}\n`;
}

function topResultNames(items: MealItem[], groups: FoodCandidateGroup[]): string[] {
  const names = new Set<string>();
  for (const item of items) {
    if (item.name) names.add(item.name);
  }
  for (const group of groups) {
    for (const candidate of group.candidates ?? []) {
      if (candidate.name) names.add(candidate.name);
    }
  }
  return [...names].slice(0, 20);
}

function containsExpectedFoods(
  result: { items: MealItem[]; candidateGroups: FoodCandidateGroup[] },
  expectedFoods: string[],
): boolean {
  const names = topResultNames(result.items, result.candidateGroups);
  const haystack = normalizeText(names.join(" "));
  return expectedFoods.every((food) => haystack.includes(normalizeText(food)));
}

function percentileSummary(values: number[]) {
  return {
    min: values.length ? Math.min(...values) : 0,
    p50: percentile(values, 0.5),
    p90: percentile(values, 0.9),
    p99: percentile(values, 0.99),
    max: values.length ? Math.max(...values) : 0,
    avg: ratio(sum(values), values.length),
  };
}

function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * p))]!;
}

function ratio(numerator: number, denominator: number): number {
  if (denominator === 0) return 0;
  return Math.round((numerator / denominator) * 1000) / 1000;
}

function sum(values: number[]): number {
  return values.reduce((total, value) => total + value, 0);
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

function parseArgs(args: string[]): BenchmarkArgs {
  const parsed: BenchmarkArgs = {
    backend: "postgres",
    concurrency: 1,
    freshRunnerPerCase: false,
    uniqueUserPerQuery: false,
    warmup: 0,
    iterations: 1,
    quiet: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--backend") {
      const backend = args[++index];
      if (backend !== "postgres" && backend !== "typesense" && backend !== "both") {
        throw new Error("--backend must be postgres, typesense, or both");
      }
      parsed.backend = backend;
    } else if (arg === "--limit") {
      parsed.limit = Number(args[++index]);
    } else if (arg === "--case") {
      parsed.caseId = args[++index];
    } else if (arg === "--category") {
      const category = args[++index] as BenchmarkCase["category"];
      if (!["meal_log", "nutrition_search", "portion_units", "clarification"].includes(category)) {
        throw new Error("--category must be meal_log, nutrition_search, portion_units, or clarification");
      }
      parsed.category = category;
    } else if (arg === "--concurrency") {
      parsed.concurrency = Number(args[++index]);
    } else if (arg === "--fresh-runner-per-case") {
      parsed.freshRunnerPerCase = true;
    } else if (arg === "--unique-user-per-query") {
      parsed.uniqueUserPerQuery = true;
    } else if (arg === "--warmup") {
      parsed.warmup = Number(args[++index]);
    } else if (arg === "--iterations") {
      parsed.iterations = Number(args[++index]);
    } else if (arg === "--output-dir") {
      parsed.outputDir = args[++index];
    } else if (arg === "--quiet") {
      parsed.quiet = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  parsed.concurrency = sanitizeNonNegativeInt(parsed.concurrency, "concurrency", 1);
  parsed.warmup = sanitizeNonNegativeInt(parsed.warmup, "warmup", 0);
  parsed.iterations = sanitizeNonNegativeInt(parsed.iterations, "iterations", 1);
  if (parsed.limit !== undefined) parsed.limit = sanitizeNonNegativeInt(parsed.limit, "limit", 1);
  return parsed;
}

function sanitizeNonNegativeInt(value: number, name: string, min: number): number {
  if (!Number.isInteger(value) || value < min) throw new Error(`${name} must be an integer >= ${min}`);
  return value;
}

function userIdForCase(
  backend: BenchmarkBackend,
  benchmarkCase: BenchmarkCase,
  iteration: number,
  warmup: boolean,
  args: BenchmarkArgs,
): string {
  if (!args.uniqueUserPerQuery) return benchmarkUserId();
  return benchmarkUserId(`${backend}:${benchmarkCase.id}:${iteration}:${warmup ? "warmup" : "run"}`);
}

function benchmarkUserId(seed = "default"): string {
  if (seed === "default") return "00000000-0000-0000-0000-000000000001";
  const hash = createHash("sha1").update(seed).digest("hex");
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-4${hash.slice(13, 16)}-8${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
