import { describe, expect, it } from "vitest";
import {
  evaluateQuery,
  extractConflictCandidates,
  extractValidationQueries,
  isPrimaryPositionMatch,
  normalizedTokens,
  type NormalizedSearchDoc,
  type SearchResultRow,
} from "../../scripts/validate-food-search-primary-position.js";

describe("food search primary-position validation", () => {
  it("extracts secondary-token conflicts while ignoring numeric-only validation tokens", () => {
    const candidates = extractConflictCandidates([
      doc({ foodId: "cookies", displayName: "Cookies Butter", baseName: "Cookies Butter", primaryEntityName: "Cookies", primaryEntityAliases: ["cookies"] }),
      doc({ foodId: "butter", displayName: "Butter Salted", baseName: "Butter Salted", primaryEntityName: "Butter", primaryEntityAliases: ["butter"] }),
      doc({ foodId: "fat", displayName: "Fat Chicken", baseName: "Fat Chicken", primaryEntityName: "Fat", primaryEntityAliases: ["fat"] }),
      doc({ foodId: "chicken", displayName: "Chicken Breast", baseName: "Chicken Breast", primaryEntityName: "Chicken", primaryEntityAliases: ["chicken"] }),
      doc({ foodId: "foo", displayName: "Foo And 12", baseName: "Foo And 12", primaryEntityName: "Foo", primaryEntityAliases: ["foo"] }),
      doc({ foodId: "and", displayName: "And Food", baseName: "And Food", primaryEntityName: "And", primaryEntityAliases: ["and"] }),
      doc({ foodId: "12", displayName: "12 Food", baseName: "12 Food", primaryEntityName: "12", primaryEntityAliases: ["12"] }),
    ]);

    expect(candidates).toEqual(expect.arrayContaining([
      expect.objectContaining({ foodId: "cookies", token: "butter" }),
      expect.objectContaining({ foodId: "fat", token: "chicken" }),
      expect.objectContaining({ foodId: "foo", token: "and" }),
    ]));
    expect(candidates).not.toEqual(expect.arrayContaining([
      expect.objectContaining({ foodId: "butter", token: "butter" }),
      expect.objectContaining({ foodId: "foo", token: "12" }),
      expect.objectContaining({ foodId: "12", token: "12" }),
    ]));
  });

  it("does not generate validation queries for numeric-only package tokens", () => {
    const docs = [
      doc({
        foodId: "one",
        resultType: "product",
        displayName: "Cdc Milk Chocolate - 1",
        baseName: "Cdc Milk Chocolate",
        variantName: "1",
        primaryEntityName: "Cdc Milk Chocolate",
        primaryEntityAliases: ["cdc milk chocolate"],
      }),
      doc({
        foodId: "twelve",
        resultType: "product",
        displayName: "12 Food",
        baseName: "12 Food",
        primaryEntityName: "12",
        primaryEntityAliases: ["12"],
      }),
    ];

    const candidates = extractConflictCandidates(docs);
    const queries = extractValidationQueries(docs, candidates, { includeAllProducts: true });

    expect(candidates).toEqual([]);
    expect(queries).not.toEqual(expect.arrayContaining([
      expect.objectContaining({ query: "1" }),
      expect.objectContaining({ query: "12" }),
    ]));
  });

  it("extracts generic primary queries and product collision queries", () => {
    const docs = [
      doc({ foodId: "cookies", displayName: "Cookies Butter", baseName: "Cookies Butter", primaryEntityName: "Cookies", primaryEntityAliases: ["cookies"] }),
      doc({ foodId: "butter", displayName: "Butter Salted", baseName: "Butter Salted", primaryEntityName: "Butter", primaryEntityAliases: ["butter"] }),
      doc({
        foodId: "product",
        resultType: "product",
        displayName: "Butter Cookie Snack",
        baseName: "Butter Cookie Snack",
        primaryEntityName: "Butter Cookie Snack",
        primaryEntityAliases: ["butter cookie snack"],
      }),
    ];

    const candidates = extractConflictCandidates(docs);
    const queries = extractValidationQueries(docs, candidates);

    expect(queries).toEqual(expect.arrayContaining([
      expect.objectContaining({ query: "butter", reasons: expect.arrayContaining(["generic_primary", "conflict_token"]) }),
      expect.objectContaining({ query: "cookies", reasons: ["generic_primary"] }),
      expect.objectContaining({ query: "butter cookie snack", reasons: ["product_collision"] }),
    ]));
  });

  it("uses primary-alias leading tokens for conflict extraction", () => {
    const candidates = extractConflictCandidates([
      doc({ foodId: "foo", displayName: "Foo And", baseName: "Foo And", primaryEntityName: "Foo", primaryEntityAliases: ["foo"] }),
      doc({ foodId: "peas", displayName: "Peas And Carrots", baseName: "Peas And Carrots", primaryEntityName: "Peas And Carrots", primaryEntityAliases: ["peas and carrots"] }),
    ]);

    expect(candidates).toEqual([]);
  });

  it("evaluates primary-position ranking gates", () => {
    const candidate = {
      token: "butter",
      locale: "en",
      foodId: "cookies",
      displayName: "Cookies Butter",
      primaryEntityName: "Cookies",
      baseName: "Cookies Butter",
      resultType: "generic_food" as const,
    };

    expect(evaluateQuery(
      { query: "butter", locale: "en" },
      [
        result({ rank: 1, foodId: "butter", name: "Butter", primaryEntityAliases: ["butter"] }),
        result({ rank: 5, foodId: "cookies", name: "Cookies Butter", primaryEntityAliases: ["cookies"] }),
      ],
      [candidate],
    )[0]).toEqual(expect.objectContaining({ status: "pass" }));

    expect(evaluateQuery(
      { query: "butter", locale: "en" },
      [
        result({ rank: 1, foodId: "cookies", name: "Cookies Butter", primaryEntityAliases: ["cookies"] }),
        result({ rank: 2, foodId: "butter", name: "Butter", primaryEntityAliases: ["butter"] }),
      ],
      [candidate],
    )[0]).toEqual(expect.objectContaining({ status: "fail", failureReason: "top_not_primary" }));

    expect(evaluateQuery(
      { query: "butter", locale: "en" },
      [result({ rank: 1, foodId: "cookies", name: "Cookies Butter", primaryEntityAliases: ["cookies"] })],
      [candidate],
    )[0]).toEqual(expect.objectContaining({ status: "fail", failureReason: "no_primary_match" }));

    expect(evaluateQuery(
      { query: "butter", locale: "en" },
      [result({ rank: 1, foodId: "butter", name: "Butter", primaryEntityAliases: ["butter"] })],
      [candidate],
    )[0]).toEqual(expect.objectContaining({ status: "pass", candidateRank: undefined }));
  });

  it("matches primary aliases at the primary position", () => {
    expect(isPrimaryPositionMatch("milk", result({ primaryEntityAliases: ["milk"] }))).toBe(true);
    expect(isPrimaryPositionMatch("milk", result({ primaryEntityAliases: ["milk goat"] }))).toBe(true);
    expect(isPrimaryPositionMatch("milk goat", result({ primaryEntityAliases: ["milk"] }))).toBe(true);
    expect(isPrimaryPositionMatch("milk", result({ primaryEntityAliases: ["almond milk"] }))).toBe(false);
    expect(isPrimaryPositionMatch("black rice", result({
      name: "Black Rice, Raw",
      normalizedBaseName: "Black Rice",
      primaryEntityAliases: ["rice"],
    }))).toBe(true);
    expect(isPrimaryPositionMatch("rice", result({
      name: "Black Rice, Raw",
      normalizedBaseName: "Black Rice",
      primaryEntityAliases: ["cookies"],
    }))).toBe(false);
    expect(isPrimaryPositionMatch("tuna", result({
      name: "Fish Tuna, Raw",
      normalizedBaseName: "Fish Tuna",
      primaryEntityName: "Fish",
      primaryEntityAliases: ["fish"],
      resultType: "generic_food",
    }))).toBe(true);
    expect(isPrimaryPositionMatch("tuna", result({
      name: "Fish Tuna Snack",
      normalizedBaseName: "Fish Tuna Snack",
      primaryEntityName: "Fish",
      primaryEntityAliases: ["fish"],
      resultType: "product",
    }))).toBe(false);
    expect(isPrimaryPositionMatch("big", result({
      name: "Mcdonald's Big Mac",
      normalizedBaseName: "Mcdonald's Big Mac",
      primaryEntityName: "Mcdonald's",
      primaryEntityAliases: ["mcdonald s"],
      resultType: "generic_food",
    }))).toBe(false);
    expect(isPrimaryPositionMatch("rice", result({
      name: "Cereals Cream Of Rice",
      normalizedBaseName: "Cereals Cream Of Rice",
      primaryEntityName: "Cereals",
      primaryEntityAliases: ["cereals"],
      resultType: "generic_food",
    }))).toBe(false);
  });

  it("uses every normalized token except empty split artifacts", () => {
    expect(normalizedTokens("Foo and 12 with butter")).toEqual(["foo", "and", "12", "with", "butter"]);
  });
});

function doc(overrides: Partial<NormalizedSearchDoc>): NormalizedSearchDoc {
  return {
    foodId: "food",
    locale: "en",
    resultType: "generic_food",
    displayName: "Food",
    baseName: "Food",
    primaryEntityName: "Food",
    primaryEntityAliases: ["food"],
    secondaryEntityAliases: [],
    ...overrides,
  };
}

function result(overrides: Partial<SearchResultRow>): SearchResultRow {
  return {
    rank: 1,
    foodId: "food",
    name: "Food",
    primaryEntityName: "Food",
    primaryEntityAliases: ["food"],
    finalScore: 1,
    ...overrides,
  };
}
