import { describe, expect, it } from "vitest";
import { postgresFoodSearchTesting } from "../repository/postgres.js";
import type { FoodSearchCandidate } from "../repository/types.js";

function candidate(
  name: string,
  finalScore: number,
  lexicalScore = finalScore,
): FoodSearchCandidate {
  return {
    id: name.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
    name,
    normalizedName: name.toLowerCase(),
    canonicalName: name.toLowerCase(),
    source: "test",
    externalSource: "test",
    externalId: name,
    dataType: "SR Legacy",
    servingGrams: 100,
    calories: 100,
    proteinGrams: 1,
    carbsGrams: 1,
    fatGrams: 1,
    lexicalScore,
    preferenceScore: 0,
    finalScore,
  };
}

describe("Postgres food search helpers", () => {
  it("builds normalized search locale profiles without caller scope", () => {
    expect(
      postgresFoodSearchTesting.normalizedFoodSearchProfile({
        query: "rice",
        locale: "en-US",
      }),
    ).toEqual({
      locales: ["en", "any", "es"],
    });
    expect(
      postgresFoodSearchTesting.normalizedFoodSearchProfile({
        query: "arroz",
        locale: "es-ES",
      }),
    ).toEqual({
      locales: ["es", "any", "en"],
    });
  });

  it("plans legacy full-corpus search as generic locale profiles before market products", () => {
    expect(
      postgresFoodSearchTesting.foodSearchProfiles({
        query: "arroz",
        locale: "es-ES",
      }),
    ).toEqual([
      {
        scope: "generic",
        locales: ["es", "any"],
        scopeRank: 0,
        continueAfterLimit: true,
      },
      {
        scope: "generic",
        locales: ["en"],
        scopeRank: 0,
        continueAfterLimit: true,
      },
      {
        scope: "market",
        locales: ["es", "en", "any"],
        scopeRank: 1,
      },
    ]);
  });

  it("sorts non-barcode search by internal corpus rank before score", () => {
    const generic = {
      candidate: candidate("Cheese", 0.6),
      scopeRank: postgresFoodSearchTesting.foodSearchScopeRankForSort(
        { query: "cheese" },
        0,
      ),
    };
    const product = {
      candidate: candidate("Cheese Crackers", 0.95),
      scopeRank: postgresFoodSearchTesting.foodSearchScopeRankForSort(
        { query: "cheese" },
        1,
      ),
    };

    expect(
      [product, generic]
        .sort(postgresFoodSearchTesting.compareFoodSearchRankedCandidates)
        .map((entry) => entry.candidate.name),
    ).toEqual(["Cheese", "Cheese Crackers"]);
  });

  it("preserves score ordering for barcode searches", () => {
    const lowerScore = candidate("Market Cheese", 0.6);
    const higherScore = candidate("Market Cheese Exact", 0.95);

    const barcodeEntries = [
      {
        candidate: lowerScore,
        scopeRank: postgresFoodSearchTesting.foodSearchScopeRankForSort(
          { query: "cheese", barcode: "000111222333" },
          1,
        ),
      },
      {
        candidate: higherScore,
        scopeRank: postgresFoodSearchTesting.foodSearchScopeRankForSort(
          { query: "cheese", barcode: "000111222333" },
          0,
        ),
      },
    ];
    expect(
      barcodeEntries
        .sort(postgresFoodSearchTesting.compareFoodSearchRankedCandidates)
        .map((entry) => entry.candidate.name),
    ).toEqual(["Market Cheese Exact", "Market Cheese"]);
  });
});
