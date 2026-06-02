import { describe, expect, it } from "vitest";
import {
  aggregateSourceResultTypeMix,
  buildBenchmarkTargets,
  buildCaseComparisons,
  detectDuplicateFlood,
  evaluateGlobalChecks,
  evaluateRunChecks,
  ndcgAt,
  percentile,
  percentileSummary,
  reciprocalRank,
  summarizeSqlProfilePlan,
  type Args,
  type SearchResultRow,
  type SearchRun,
} from "../../scripts/benchmark-food-search.js";

describe("food search benchmark helpers", () => {
  it("calculates stable latency percentiles", () => {
    expect(percentile([50, 10, 30, 20, 40], 0.5)).toBe(30);
    expect(percentile([50, 10, 30, 20, 40], 0.9)).toBe(40);
    expect(percentileSummary([10, 20, 40])).toEqual({
      min: 10,
      p50: 20,
      p90: 20,
      p99: 20,
      max: 40,
      average: 23.33,
    });
  });

  it("detects duplicate display-name flooding", () => {
    const flood = detectDuplicateFlood([
      "White Rice, Cooked",
      "White Rice, Cooked",
      "White Rice, Cooked",
      "Brown Rice",
    ]);

    expect(flood.maxDuplicateCount).toBe(3);
    expect(flood.uniqueDisplayRatio).toBe(0.5);
    expect(flood.floodedDisplayNames).toEqual([
      { displayName: "White Rice, Cooked", count: 3 },
    ]);
  });

  it("aggregates source and result-type mix", () => {
    expect(aggregateSourceResultTypeMix([
      result({ externalSource: "usda_fdc", resultType: "generic_food" }),
      result({ externalSource: "usda_fdc", resultType: "generic_food" }),
      result({ externalSource: "openfoodfacts", resultType: "product" }),
    ])).toEqual([
      { source: "usda_fdc", resultType: "generic_food", rows: 2 },
      { source: "openfoodfacts", resultType: "product", rows: 1 },
    ]);
  });

  it("calculates relevance metrics when judgments exist", () => {
    const rows = [
      result({ rank: 1, returnedName: "Brown Rice" }),
      result({ rank: 2, returnedName: "White Rice" }),
      result({ rank: 3, returnedName: "Rice Snack" }),
    ];

    expect(reciprocalRank(rows, [{ name: "White Rice", grade: 3 }])).toBe(0.5);
    expect(ndcgAt(rows, [{ name: "White Rice", grade: 3 }], 3)).toBe(0.6309);
  });

  it("evaluates normalized acceptance gates", () => {
    const run: SearchRun = {
      targetLabel: "normalized",
      targetRole: "single",
      mode: "normalized",
      scope: "sample",
      caseId: "rice",
      query: "rice",
      locale: "en",
      kind: "broad_generic",
      topK: 3,
      latenciesMs: [10, 12],
      latency: percentileSummary([10, 12]),
      topResult: result({ rank: 1, returnedName: "White Rice", resultType: "generic_food" }),
      results: [
        result({ rank: 1, returnedName: "White Rice", resultType: "generic_food" }),
        result({ rank: 2, returnedName: "Brown Rice", resultType: "generic_food" }),
        result({ rank: 3, returnedName: "Rice Product", resultType: "product" }),
      ],
      sourceResultTypeMix: [],
      duplicateFlood: detectDuplicateFlood(["White Rice", "Brown Rice", "Rice Product"]),
      quarantinedRows: 0,
      ineligibleRows: 0,
      outsideSampleRows: 0,
      knownBadRows: 0,
      sampledGenericCoverage: true,
      sampledGenericCoverageCount: 2,
      mrr: null,
      ndcgAt5: null,
      ndcgAt10: null,
      checks: [],
    };

    expect(evaluateRunChecks(run, { id: "rice", query: "rice", locale: "en", kind: "broad_generic" }))
      .toEqual(expect.arrayContaining([
        expect.objectContaining({ name: "no_quarantined_rows", ok: true }),
        expect.objectContaining({ name: "broad_generic_top3_contains_generic", ok: true }),
        expect.objectContaining({ name: "broad_generic_top_result_is_generic", ok: true }),
      ]));
  });

  it("allows per-case speed gates for tiny absolute latencies and duplicate-quality wins", () => {
    const tinyLegacy = run({ mode: "legacy", caseId: "barcode", latency: percentileSummary([1]), latenciesMs: [1] });
    const tinyNormalized = run({ mode: "normalized", caseId: "barcode", latency: percentileSummary([3]), latenciesMs: [3] });
    const duplicateLegacy = run({
      mode: "legacy",
      caseId: "rice",
      latency: percentileSummary([10]),
      latenciesMs: [10],
      duplicateFlood: detectDuplicateFlood(["Rice", "Rice", "Rice", "Brown Rice"]),
    });
    const duplicateNormalized = run({
      mode: "normalized",
      caseId: "rice",
      latency: percentileSummary([50]),
      latenciesMs: [50],
      duplicateFlood: detectDuplicateFlood(["White Rice", "Brown Rice", "Red Rice", "Black Rice"]),
      checks: [{ name: "quality", ok: true }],
    });

    const checks = evaluateGlobalChecks(
      [tinyLegacy, tinyNormalized, duplicateLegacy, duplicateNormalized],
      {
        legacy: percentileSummary([100]),
        normalized: percentileSummary([70]),
      },
      ["legacy", "normalized"],
    );

    expect(checks).toEqual(expect.arrayContaining([
      expect.objectContaining({ name: "case_not_materially_slower:barcode", ok: true }),
      expect.objectContaining({ name: "case_not_materially_slower:rice", ok: true }),
    ]));
  });

  it("builds cross-database benchmark targets", () => {
    const targets = buildBenchmarkTargets({
      ...args(),
      baselineDbUrl: "postgres://u:p@localhost:5432/cal_tracker",
      candidateDbUrl: "postgres://u:p@localhost:5432/cal_tracker_normalized",
      scope: "full",
    }, "postgres://u:p@localhost:5432/default_db");

    expect(targets).toEqual([
      expect.objectContaining({
        label: "baseline-legacy",
        role: "baseline",
        mode: "legacy",
        scope: "full",
        databaseName: "cal_tracker",
      }),
      expect.objectContaining({
        label: "normalized-full",
        role: "candidate",
        mode: "normalized",
        scope: "full",
        databaseName: "cal_tracker_normalized",
      }),
    ]);
  });

  it("compares baseline and candidate runs by case", () => {
    const baseline = run({
      targetLabel: "baseline-legacy",
      targetRole: "baseline",
      mode: "legacy",
      caseId: "rice",
      query: "rice",
      latency: percentileSummary([40]),
      latenciesMs: [40],
      duplicateFlood: detectDuplicateFlood(["Rice", "Rice", "Rice", "Brown Rice"]),
      topResult: result({ returnedName: "Rice" }),
    });
    const candidate = run({
      targetLabel: "normalized-full",
      targetRole: "candidate",
      mode: "normalized",
      caseId: "rice",
      query: "rice",
      latency: percentileSummary([18]),
      latenciesMs: [18],
      duplicateFlood: detectDuplicateFlood(["White Rice", "Brown Rice", "Red Rice", "Black Rice"]),
      topResult: result({ returnedName: "White Rice" }),
      checks: [{ name: "quality", ok: true }],
    });

    expect(buildCaseComparisons([baseline, candidate])).toEqual([
      expect.objectContaining({
        caseId: "rice",
        baselineTargetLabel: "baseline-legacy",
        candidateTargetLabel: "normalized-full",
        p50Ratio: 0.45,
        duplicateMaxDelta: -2,
        candidateQualityOk: true,
        latencyOk: true,
        ok: true,
      }),
    ]);
  });

  it("summarizes SQL profile evidence from explain JSON", () => {
    const summary = summarizeSqlProfilePlan([
      {
        "Planning Time": 1.25,
        "Execution Time": 12.5,
        Plan: {
          "Node Type": "Limit",
          "Actual Rows": 10,
          "Shared Hit Blocks": 3,
          Plans: [
            {
              "Node Type": "Index Scan",
              "Index Name": "food_normalized_search_documents_search_vector_idx",
              "Shared Hit Blocks": 4,
            },
            {
              "Node Type": "Seq Scan",
              "Relation Name": "food_items",
              "Shared Read Blocks": 2,
            },
          ],
        },
      },
    ], {
      targetLabel: "normalized-full",
      caseId: "rice",
      query: "rice",
      locale: "en",
    });

    expect(summary).toEqual(expect.objectContaining({
      planningTimeMs: 1.25,
      executionTimeMs: 12.5,
      actualRows: 10,
      indexNames: ["food_normalized_search_documents_search_vector_idx"],
      sequentialScans: ["food_items"],
      sharedHitBlocks: 7,
      sharedReadBlocks: 2,
      rawPlanFile: "sql-profile-rice-normalized-full.json",
    }));
  });
});

function result(overrides: Partial<SearchResultRow>): SearchResultRow {
  return {
    rank: 1,
    foodId: "food-1",
    returnedName: "Food",
    source: "usda_fdc",
    externalSource: "usda_fdc",
    resultType: "generic_food",
    qualityFlags: [],
    inNormalizedSample: true,
    lexicalScore: 1,
    finalScore: 1,
    ...overrides,
  };
}

function run(overrides: Partial<SearchRun>): SearchRun {
  return {
    targetLabel: "normalized",
    targetRole: "single",
    mode: "normalized",
    scope: "sample",
    caseId: "case",
    query: "query",
    locale: "en",
    kind: "broad_generic",
    topK: 10,
    latenciesMs: [10],
    latency: percentileSummary([10]),
    topResult: result({ rank: 1 }),
    results: [result({ rank: 1 })],
    sourceResultTypeMix: [],
    duplicateFlood: detectDuplicateFlood(["Food"]),
    quarantinedRows: 0,
    ineligibleRows: 0,
    outsideSampleRows: 0,
    knownBadRows: 0,
    sampledGenericCoverage: false,
    sampledGenericCoverageCount: 0,
    mrr: null,
    ndcgAt5: null,
    ndcgAt10: null,
    checks: [],
    ...overrides,
  };
}

function args(overrides: Partial<Args> = {}): Args {
  return {
    mode: "compare",
    scope: "sample",
    topK: 10,
    iterations: 5,
    warmup: 1,
    repeat: 1,
    reportOnly: false,
    sampleSetName: "normalized_search_v1",
    baselineLabel: "baseline-legacy",
    candidateLabel: "normalized-full",
    profileSql: false,
    profileTopN: 5,
    ...overrides,
  };
}
