import { afterEach, describe, expect, it, vi } from "vitest";
import type { FoodMention } from "@cal-tracker/contracts";
import {
  DeterministicFoodTextExtractor,
  FoodResolver,
  LocalFoodDataProvider,
  OpenRouterFoodTextExtractor,
  scoreUsdaCandidate,
  type FoodDataProvider,
} from "../nutrition/foodResolver.js";
import { InMemoryRepository } from "../repository/inMemory.js";
import { seedTestFoods } from "./foodFixtures.js";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
  vi.restoreAllMocks();
});

function testFoodRepository(): InMemoryRepository {
  const repository = InMemoryRepository.seeded();
  seedTestFoods(repository);
  return repository;
}

function mention(name: string, originalText = name): FoodMention {
  return {
    originalText,
    canonicalName: name,
    canonicalEnglishName: name,
    quantity: 100,
    unit: "g",
    rawUnitText: "g",
    unitKind: "metric",
    confidence: 0.95,
    marketProduct: false,
  };
}

function normalizeFixtureFoodName(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

describe("scoreUsdaCandidate", () => {
  it("ranks plain salmon candidates above product-form matches without ingredient-specific rules", () => {
    const salmon = mention("salmon");
    const fishOil = scoreUsdaCandidate(
      { description: "Fish oil, salmon", dataType: "Foundation" },
      salmon,
    );
    const rawSalmon = scoreUsdaCandidate(
      { description: "Fish, salmon, chinook, raw", dataType: "Foundation" },
      salmon,
    );

    expect(rawSalmon?.confidence).toBeGreaterThan(0.75);
    expect(fishOil?.confidence ?? 0).toBeLessThan(rawSalmon?.confidence ?? 0);
    expect(fishOil?.confidence ?? 0).toBeLessThan(0.75);
  });

  it("penalizes unrelated blend ingredients while preserving requested product forms", () => {
    const oliveOil = mention("olive oil");
    const blend = scoreUsdaCandidate(
      { description: "Oil, corn, peanut, and olive", dataType: "Foundation" },
      oliveOil,
    );
    const extraVirgin = scoreUsdaCandidate(
      { description: "Oil, olive, extra virgin", dataType: "Foundation" },
      oliveOil,
    );

    expect(extraVirgin?.confidence).toBeGreaterThan(0.75);
    expect(blend?.confidence ?? 0).toBeLessThan(
      extraVirgin?.confidence ?? 0,
    );
  });

  it("rejects USDA candidates that do not contain every canonical token", () => {
    expect(
      scoreUsdaCandidate(
        { description: "Lunchmeat, chicken, sliced", dataType: "Foundation" },
        mention("chicken breast"),
      ),
    ).toBeNull();
  });

  it("does not penalize USDA poultry taxonomy for grilled chicken breast", () => {
    const score = scoreUsdaCandidate(
      {
        description:
          "Chicken, broiler or fryers, breast, skinless, boneless, meat only, cooked, grilled",
        dataType: "SR Legacy",
      },
      mention("grilled chicken breast", "pechuga de pollo a la plancha"),
    );

    expect(score?.confidence).toBeGreaterThan(0.75);
  });

  it("prefers exact first USDA description segments over compound food names", () => {
    const rice = mention("rice");
    const riceVariant = scoreUsdaCandidate(
      {
        description: "Rice, white, medium-grain, enriched, cooked",
        dataType: "SR Legacy",
      },
      rice,
    );
    const riceNoodles = scoreUsdaCandidate(
      { description: "Rice noodles, cooked", dataType: "SR Legacy" },
      rice,
    );
    const invertedRiceNoodles = scoreUsdaCandidate(
      { description: "Noodles, rice", dataType: "SR Legacy" },
      rice,
    );

    expect(riceVariant?.confidence).toBeGreaterThan(0.75);
    expect(riceVariant?.confidence ?? 0).toBeGreaterThan(
      riceNoodles?.confidence ?? 0,
    );
    expect(invertedRiceNoodles).toBeNull();
  });

  it.each([
    {
      query: "apple",
      basic: "Apple, raw, with skin",
      compound: "Apple juice, canned or bottled",
      inverted: "Juice, apple",
    },
    {
      query: "tomato",
      basic: "Tomatoes, red, ripe, raw, year round average",
      compound: "Tomato sauce, canned",
      inverted: "Sauce, tomato",
    },
    {
      query: "egg",
      basic: "Egg, whole, raw, fresh",
      compound: "Egg noodles, cooked, enriched",
      inverted: "Noodles, egg",
    },
    {
      query: "milk",
      basic: "Milk, whole, 3.25% milkfat",
      compound: "Milk chocolate candy",
      inverted: "Chocolate milk",
    },
    {
      query: "orange",
      basic: "Oranges, raw, navels",
      compound: "Orange juice, raw",
      inverted: "Juice, orange",
    },
    {
      query: "chicken",
      basic: "Chicken, broilers or fryers, meat only, cooked, roasted",
      compound: "Chicken nuggets, frozen, cooked",
      inverted: "Nuggets, chicken",
    },
  ])(
    "prefers the basic $query USDA segment over product-form matches",
    ({ query, basic, compound, inverted }) => {
      const requestedFood = mention(query);
      const basicScore = scoreUsdaCandidate(
        { description: basic, dataType: "SR Legacy" },
        requestedFood,
      );
      const compoundScore = scoreUsdaCandidate(
        { description: compound, dataType: "SR Legacy" },
        requestedFood,
      );
      const invertedScore = scoreUsdaCandidate(
        { description: inverted, dataType: "SR Legacy" },
        requestedFood,
      );

      expect(basicScore?.confidence).toBeGreaterThan(0.75);
      expect(basicScore?.confidence ?? 0).toBeGreaterThan(
        compoundScore?.confidence ?? 0,
      );
      expect(basicScore?.confidence ?? 0).toBeGreaterThan(
        invertedScore?.confidence ?? 0,
      );
    },
  );
});

describe("FoodResolver candidate groups", () => {
  it("keeps up to ten ranked alternatives for every detected mention", async () => {
    const provider: FoodDataProvider = {
      id: "test-provider",
      async resolve() {
        return Array.from({ length: 12 }, (_, index) => ({
          name: `Candidate ${index + 1}`,
          quantity: 100,
          unit: "g",
          calories: 100 + index,
          proteinGrams: 10,
          carbsGrams: 10,
          fatGrams: 2,
          source: "test",
          confidence: 0.99 - index * 0.01,
        }));
      },
    };
    const resolver = new FoodResolver(
      {
        async extract() {
          return [mention("candidate")];
        },
      },
      provider,
      0.75,
    );

    const result = await resolver.resolveMealText("user-1", "candidate");

    expect(result.candidateGroups).toHaveLength(1);
    expect(result.candidateGroups[0]!.candidates).toHaveLength(10);
    expect(result.candidateGroups[0]!.candidates[0]).toEqual(
      expect.objectContaining({
        name: "Candidate 1",
        rank: 1,
        matchScore: 0.99,
        lexicalScore: 0.99,
        matchReason: "test",
      }),
    );
    expect(result.items[0]).toBe(result.candidateGroups[0]!.candidates[0]);
  });

  it("orders alternatives by the visible recommendation probability", async () => {
    const provider: FoodDataProvider = {
      id: "test-provider",
      async resolve() {
        return [
          {
            name: "Lexical favorite",
            quantity: 100,
            unit: "g",
            calories: 110,
            proteinGrams: 20,
            carbsGrams: 0,
            fatGrams: 3,
            source: "test",
            confidence: 0.64,
            matchScore: 0.5,
            lexicalScore: 0.9,
            rank: 1,
          },
          {
            name: "Best probability",
            quantity: 100,
            unit: "g",
            calories: 120,
            proteinGrams: 21,
            carbsGrams: 0,
            fatGrams: 4,
            source: "test",
            confidence: 0.95,
            matchScore: 0.43,
            lexicalScore: 0.45,
            rank: 3,
          },
          {
            name: "Middle probability",
            quantity: 100,
            unit: "g",
            calories: 115,
            proteinGrams: 20,
            carbsGrams: 1,
            fatGrams: 3,
            source: "test",
            confidence: 0.8,
            matchScore: 0.47,
            lexicalScore: 0.55,
            rank: 2,
          },
        ];
      },
    };
    const resolver = new FoodResolver(
      {
        async extract() {
          return [mention("candidate")];
        },
      },
      provider,
      0.75,
    );

    const result = await resolver.resolveMealText("user-1", "candidate");

    expect(result.candidateGroups[0]!.candidates.map((item) => item.name)).toEqual(
      ["Best probability", "Middle probability", "Lexical favorite"],
    );
    expect(result.candidateGroups[0]!.candidates.map((item) => item.rank)).toEqual([
      1,
      2,
      3,
    ]);
    expect(result.items[0]?.name).toBe("Best probability");
  });
});

describe("FoodResolver", () => {
  it("extracts every metric item in comma-separated ingredient lists", async () => {
    const mentions = await new DeterministicFoodTextExtractor().extract(
      "Add 100 grams of chicken, 100 grams of rice and 100 grams of meat.",
    );

    expect(mentions).toHaveLength(3);
    expect(mentions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "chicken",
          canonicalName: "chicken",
          canonicalEnglishName: "chicken",
          language: "en",
          quantity: 100,
          unit: "g",
        }),
        expect.objectContaining({
          originalText: "rice",
          canonicalName: "rice",
          canonicalEnglishName: "rice",
          language: "en",
          quantity: 100,
          unit: "g",
        }),
        expect.objectContaining({
          originalText: "meat",
          canonicalName: "meat",
          canonicalEnglishName: "meat",
          language: "en",
          quantity: 100,
          unit: "g",
        }),
      ]),
    );
  });

  it("extracts Spanish quantities without translating food names in deterministic fallback", async () => {
    const mentions = await new DeterministicFoodTextExtractor().extract(
      "Añade a mi desayuno 100 gramos de pan y 100 gramos de jamón.",
    );

    expect(mentions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "pan",
          canonicalName: "pan",
          canonicalEnglishName: "pan",
          language: "es",
          quantity: 100,
          unit: "g",
        }),
        expect.objectContaining({
          originalText: "jamon",
          canonicalName: "jamon",
          canonicalEnglishName: "jamon",
          language: "es",
          quantity: 100,
          unit: "g",
        }),
      ]),
    );
  });

  it("inherits the previous metric unit for same-list quantities without units", async () => {
    const mentions = await new DeterministicFoodTextExtractor().extract(
      "Añade 300 gramos de pollo y 200 de pan.",
    );

    expect(mentions).toHaveLength(2);
    expect(mentions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          canonicalName: "pollo",
          language: "es",
          quantity: 300,
          unit: "g",
          unitKind: "metric",
        }),
        expect.objectContaining({
          originalText: "200 de pan",
          canonicalName: "pan",
          language: "es",
          quantity: 200,
          unit: "g",
          rawUnitText: "gramos",
          unitKind: "metric",
        }),
      ]),
    );
  });

  it("does not inherit metric units for ordinary count foods", async () => {
    const mentions = await new DeterministicFoodTextExtractor().extract(
      "Añade 300 gramos de pollo y 2 huevos.",
    );

    expect(mentions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          canonicalName: "pollo",
          quantity: 300,
          unit: "g",
        }),
        expect.objectContaining({
          canonicalName: "huevo",
          quantity: 2,
          unitKind: "implicit_count",
        }),
      ]),
    );
    expect(
      mentions.find((mention) => mention.canonicalName === "huevo")?.unit,
    ).not.toBe("g");
  });

  it("does not include polite trailing text in the canonical food name", async () => {
    const mentions = await new DeterministicFoodTextExtractor().extract(
      "Añádeme 200 gramos de pechuga de pollo y 300 gramos de arroz por favor",
    );

    expect(mentions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          canonicalName: "pechuga pollo",
          quantity: 200,
          unit: "g",
        }),
        expect.objectContaining({
          originalText: "arroz por favor",
          canonicalName: "arroz",
          quantity: 300,
          unit: "g",
        }),
      ]),
    );
  });

  it("keeps Open Food Facts products out of generic search and available in market search", async () => {
    const repository = InMemoryRepository.seeded();
    await repository.upsertFoodItem({
      name: "Arroz",
      normalizedName: "arroz",
      canonicalName: "arroz",
      brand: "Producto Test",
      barcode: "1111111111111",
      source: "openfoodfacts",
      externalSource: "openfoodfacts",
      externalId: "es-arroz",
      dataType: "Open Food Facts",
      foodKey: "es",
      servingGrams: 100,
      calories: 130,
      proteinGrams: 2.7,
      carbsGrams: 28,
      fatGrams: 0.3,
    });
    await repository.upsertFoodItem({
      name: "Rice, white, cooked",
      normalizedName: "rice",
      canonicalName: "rice",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "usda-rice",
      dataType: "SR Legacy",
      servingGrams: 100,
      calories: 130,
      proteinGrams: 2.7,
      carbsGrams: 28,
      fatGrams: 0.3,
    });
    await repository.upsertFoodItem({
      name: "Rice Brand Snack",
      normalizedName: "rice brand snack",
      canonicalName: "rice snack",
      brand: "Rice Brand",
      barcode: "2222222222222",
      source: "openfoodfacts",
      externalSource: "openfoodfacts",
      externalId: "en-rice-product",
      dataType: "Open Food Facts",
      foodKey: "en",
      servingGrams: 100,
      calories: 420,
      proteinGrams: 8,
      carbsGrams: 72,
      fatGrams: 12,
    });

    await expect(
      repository.searchFoodsHybrid("user-1", {
        query: "arroz",
        locale: "es-ES",
        scope: "generic",
      }),
    ).resolves.toEqual([]);
    await expect(
      repository.searchFoodsHybrid("user-1", {
        query: "arroz",
        locale: "es-ES",
        scope: "market",
      }),
    ).resolves.toEqual([
      expect.objectContaining({ externalId: "es-arroz", foodKey: "es" }),
    ]);
    await expect(
      repository.searchFoodsHybrid("user-1", {
        query: "rice",
        locale: "en-US",
        scope: "generic",
      }),
    ).resolves.toEqual([
      expect.objectContaining({ externalId: "usda-rice" }),
    ]);
  });

  it("ranks first-token food matches above later-token matches", async () => {
    const repository = InMemoryRepository.seeded();
    await repository.upsertFoodItem({
      name: "Noodles, rice",
      normalizedName: "noodles rice",
      canonicalName: "noodles rice",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "usda-noodles-rice",
      dataType: "SR Legacy",
      servingGrams: 100,
      calories: 109,
      proteinGrams: 1.8,
      carbsGrams: 24.9,
      fatGrams: 0.2,
    });
    await repository.upsertFoodItem({
      name: "Rice noodles",
      normalizedName: "rice noodles",
      canonicalName: "rice noodles",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "usda-rice-noodles",
      dataType: "SR Legacy",
      servingGrams: 100,
      calories: 109,
      proteinGrams: 1.8,
      carbsGrams: 24.9,
      fatGrams: 0.2,
    });
    await repository.upsertFoodItem({
      name: "Rice, grain",
      normalizedName: "rice grain",
      canonicalName: "rice grain",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "usda-rice-grain",
      dataType: "SR Legacy",
      servingGrams: 100,
      calories: 130,
      proteinGrams: 2.7,
      carbsGrams: 28,
      fatGrams: 0.3,
    });

    const riceResults = await repository.searchFoodsHybrid("user-1", {
      query: "rice",
      locale: "en-US",
      scope: "generic",
    });
    expect(riceResults.map((food) => food.externalId)).toEqual([
      "usda-rice-grain",
      "usda-rice-noodles",
      "usda-noodles-rice",
    ]);

    const noodleResults = await repository.searchFoodsHybrid("user-1", {
      query: "rice noodles",
      locale: "en-US",
      scope: "generic",
    });
    expect(noodleResults[0]).toEqual(
      expect.objectContaining({ externalId: "usda-rice-noodles" }),
    );
  });

  it("matches food names with typos and prefix queries", async () => {
    const repository = InMemoryRepository.seeded();
    await repository.upsertFoodItem({
      name: "Pechuga de pollo",
      normalizedName: "pechuga pollo",
      canonicalName: "pechuga pollo",
      source: "openfoodfacts",
      externalSource: "openfoodfacts",
      externalId: "es-pechuga-pollo",
      dataType: "Open Food Facts",
      foodKey: "es",
      servingGrams: 100,
      calories: 165,
      proteinGrams: 31,
      carbsGrams: 0,
      fatGrams: 3.6,
    });
    await repository.upsertFoodItem({
      name: "Yogur natural",
      normalizedName: "yogur natural",
      canonicalName: "yogur natural",
      source: "openfoodfacts",
      externalSource: "openfoodfacts",
      externalId: "es-yogur-natural",
      dataType: "Open Food Facts",
      foodKey: "es",
      servingGrams: 100,
      calories: 63,
      proteinGrams: 3.5,
      carbsGrams: 4.7,
      fatGrams: 3.3,
    });

    await expect(
      repository.searchFoodsHybrid("user-1", {
        query: "pechga pollo",
        locale: "es-ES",
        scope: "generic",
      }),
    ).resolves.toEqual([
      expect.objectContaining({ externalId: "es-pechuga-pollo" }),
    ]);
    await expect(
      repository.searchFoodsHybrid("user-1", {
        query: "iogur",
        locale: "es-ES",
        scope: "generic",
      }),
    ).resolves.toEqual([
      expect.objectContaining({ externalId: "es-yogur-natural" }),
    ]);
    await expect(
      repository.searchFoodsHybrid("user-1", {
        query: "yog",
        locale: "es-ES",
        scope: "generic",
      }),
    ).resolves.toEqual([
      expect.objectContaining({ externalId: "es-yogur-natural" }),
    ]);
  });

  it.each([
    {
      query: "apple",
      basic: "Apple, raw, with skin",
      compound: "Apple juice, canned or bottled",
      inverted: "Juice, apple",
    },
    {
      query: "tomato",
      basic: "Tomatoes, red, ripe, raw",
      compound: "Tomato sauce, canned",
      inverted: "Sauce, tomato",
    },
    {
      query: "egg",
      basic: "Egg, whole, raw, fresh",
      compound: "Egg noodles, cooked, enriched",
      inverted: "Noodles, egg",
    },
    {
      query: "milk",
      basic: "Milk, whole, 3.25% milkfat",
      compound: "Milk chocolate candy",
      inverted: "Chocolate milk",
    },
    {
      query: "orange",
      basic: "Oranges, raw, navels",
      compound: "Orange juice, raw",
      inverted: "Juice, orange",
    },
    {
      query: "chicken",
      basic: "Chicken, broilers or fryers, meat only, cooked, roasted",
      compound: "Chicken nuggets, frozen, cooked",
      inverted: "Nuggets, chicken",
    },
  ])(
    "resolves a basic $query mention before compound product-form matches",
    async ({ query, basic, compound, inverted }) => {
      const repository = InMemoryRepository.seeded();
      for (const [index, name] of [basic, compound, inverted].entries()) {
        await repository.upsertFoodItem({
          name,
          normalizedName: normalizeFixtureFoodName(name),
          canonicalName: normalizeFixtureFoodName(name),
          source: "usda_fdc",
          externalSource: "usda_fdc",
          externalId: `${query}-${index}`,
          dataType: "SR Legacy",
          servingGrams: 100,
          calories: 100,
          proteinGrams: 1,
          carbsGrams: 10,
          fatGrams: 1,
        });
      }
      const resolver = new FoodResolver(
        new DeterministicFoodTextExtractor(),
        new LocalFoodDataProvider(repository),
        0.75,
      );

      const result = await resolver.resolveMealText(
        "user-1",
        `Add 100 grams of ${query}`,
        "en-US",
      );

      expect(result.clarificationRequired).toBe(false);
      expect(result.items[0]).toEqual(expect.objectContaining({ name: basic }));
      expect(result.candidateGroups[0]?.candidates[0]).toEqual(
        expect.objectContaining({ name: basic }),
      );
    },
  );

  it("infers Spanish for deterministic fallback before local food search", async () => {
    const repository = InMemoryRepository.seeded();
    await repository.upsertFoodItem({
      name: "Game meat, bison, ground, cooked, pan-broiled",
      normalizedName: "game meat bison ground cooked pan broiled",
      canonicalName: "game meat bison ground cooked pan broiled",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "usda-pan-broiled",
      dataType: "SR Legacy",
      servingGrams: 100,
      calories: 238,
      proteinGrams: 23.8,
      carbsGrams: 0,
      fatGrams: 15.2,
    });
    await repository.upsertFoodItem({
      name: "Pan",
      normalizedName: "pan",
      canonicalName: "pan",
      source: "test_fixture",
      externalSource: "test_fixture",
      externalId: "generic-pan-es",
      dataType: "Generic",
      foodKey: "es",
      servingGrams: 100,
      calories: 269,
      proteinGrams: 9,
      carbsGrams: 51,
      fatGrams: 3.8,
    });
    const resolver = new FoodResolver(
      new DeterministicFoodTextExtractor(),
      new LocalFoodDataProvider(repository),
      0.65,
    );

    const result = await resolver.resolveMealText(
      "user-1",
      "Añádeme 200 gramos de pan",
    );

    expect(result.clarificationRequired).toBe(false);
    expect(result.items[0]).toEqual(
      expect.objectContaining({
        name: "Pan",
        externalSource: "test_fixture",
        externalId: "generic-pan-es",
        calories: 538,
      }),
    );
    expect(result.candidateGroups[0]?.mention.language).toBe("es");
  });

  it("extracts count-based egg units in Spanish and English", async () => {
    const extractor = new DeterministicFoodTextExtractor();

    await expect(extractor.extract("Añade un huevo")).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "un huevo",
          canonicalEnglishName: "huevo",
          quantity: 1,
          unit: "egg",
          rawUnitText: "huevo",
          unitKind: "implicit_count",
        }),
      ]),
    );
    await expect(extractor.extract("Add one egg")).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "one egg",
          canonicalEnglishName: "egg",
          quantity: 1,
          unit: "egg",
          rawUnitText: "egg",
          unitKind: "implicit_count",
        }),
      ]),
    );
    await expect(extractor.extract("Add 2 eggs")).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "2 eggs",
          canonicalEnglishName: "egg",
          quantity: 2,
          unit: "egg",
          rawUnitText: "eggs",
          unitKind: "implicit_count",
        }),
      ]),
    );
    await expect(extractor.extract("Add one XL egg")).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "one xl egg",
          canonicalEnglishName: "egg",
          quantity: 1,
          unit: "egg",
          portionDescriptor: "extra large",
        }),
      ]),
    );
    await expect(extractor.extract("Add 2 small bananas")).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "2 small bananas",
          canonicalEnglishName: "banana",
          quantity: 2,
          unit: "bananas",
          portionDescriptor: "small",
        }),
      ]),
    );
  });

  it("extracts household portions and unsupported implicit counts without validating them", async () => {
    const extractor = new DeterministicFoodTextExtractor();

    await expect(extractor.extract("Add 1 cup rice")).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "1 cup rice",
          canonicalEnglishName: "rice",
          quantity: 1,
          unit: "cup",
          rawUnitText: "cup",
          unitKind: "household",
        }),
      ]),
    );
    await expect(extractor.extract("Add 1 rice")).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          originalText: "1 rice",
          canonicalEnglishName: "rice",
          quantity: 1,
          unit: "rice",
          rawUnitText: "rice",
          unitKind: "implicit_count",
        }),
      ]),
    );
  });

  it("rejects unsupported bare count units instead of defaulting to grams", async () => {
    const repository = testFoodRepository();
    const resolver = new FoodResolver(
      new DeterministicFoodTextExtractor(),
      new LocalFoodDataProvider(repository),
      0.75,
    );

    const result = await resolver.resolveMealText("user-1", "Add 1 rice");

    expect(result.clarificationRequired).toBe(true);
    expect(result.items).toHaveLength(0);
    expect(result.unresolvedMentions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          canonicalEnglishName: "rice",
          quantity: 1,
          unit: "rice",
        }),
      ]),
    );
    expect(result.candidateGroups).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          mention: expect.objectContaining({ canonicalEnglishName: "rice" }),
          reason: "unsupported_unit",
        }),
      ]),
    );
  });

  it("uses imported local USDA portions without external lookup", async () => {
    globalThis.fetch = vi.fn(async () => new Response("{}", { status: 500 })) as typeof fetch;
    const repository = InMemoryRepository.seeded();
    await repository.upsertFoodItem({
      name: "Rice, white, cooked",
      normalizedName: "rice",
      canonicalName: "rice",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "2001",
      dataType: "SR Legacy",
      servingGrams: 100,
      calories: 130,
      proteinGrams: 2.7,
      carbsGrams: 28,
      fatGrams: 0.3,
      portions: [
        {
          id: "portion-1",
          foodItemId: "food-1",
          usdaPortionId: "100",
          amount: 1,
          unit: "cup",
          gramWeight: 200,
          normalizedAliases: ["cup"],
          kind: "household",
          sourceDescription: "1 cup cooked",
        },
      ],
    });
    const resolver = new FoodResolver(
      new DeterministicFoodTextExtractor(),
      new LocalFoodDataProvider(repository),
      0.75,
    );

    const result = await resolver.resolveMealText("user-1", "Add 1 cup rice");

    expect(globalThis.fetch).not.toHaveBeenCalled();
    expect(result.clarificationRequired).toBe(false);
    expect(result.items[0]).toEqual(
      expect.objectContaining({
        externalSource: "usda_fdc",
        externalId: "2001",
        quantity: 1,
        unit: "cup",
        calories: 260,
        resolvedGrams: 200,
      }),
    );
    await expect(repository.searchFoods("user-1", "rice")).resolves.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          externalId: "2001",
          servingGrams: 100,
          calories: 130,
        }),
      ]),
    );
  });

  it("prefers local SR Legacy generic rows over Foundation rows", async () => {
    const repository = InMemoryRepository.seeded();
    await repository.upsertFoodItem({
      name: "Chicken breast, raw",
      normalizedName: "chicken breast",
      canonicalName: "chicken breast",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "3001",
      dataType: "Foundation",
      servingGrams: 100,
      calories: 170,
      proteinGrams: 30,
      carbsGrams: 0,
      fatGrams: 4,
    });
    await repository.upsertFoodItem({
      name: "Chicken breast, raw",
      normalizedName: "chicken breast",
      canonicalName: "chicken breast",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "3002",
      dataType: "SR Legacy",
      servingGrams: 100,
      calories: 165,
      proteinGrams: 31,
      carbsGrams: 0,
      fatGrams: 3.6,
    });
    const resolver = new FoodResolver(
      new DeterministicFoodTextExtractor(),
      new LocalFoodDataProvider(repository),
      0.75,
    );

    const result = await resolver.resolveMealText(
      "user-1",
      "Add 100 grams chicken breast",
    );

    expect(result.clarificationRequired).toBe(false);
    expect(result.items[0]).toEqual(
      expect.objectContaining({
        externalId: "3002",
        calories: 165,
      }),
    );
  });

  it("resolves local SR Legacy grilled chicken breast from a Spanish mention", async () => {
    const repository = InMemoryRepository.seeded();
    await repository.upsertFoodItem({
      name: "Chicken, broiler or fryers, breast, skinless, boneless, meat only, cooked, grilled",
      normalizedName:
        "chicken broiler or fryers breast skinless boneless meat only cooked grilled",
      canonicalName:
        "chicken broiler or fryers breast skinless boneless meat only cooked grilled",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "171534",
      dataType: "SR Legacy",
      servingGrams: 100,
      calories: 151,
      proteinGrams: 30.5,
      carbsGrams: 0,
      fatGrams: 3.2,
    });
    const resolver = new FoodResolver(
      new DeterministicFoodTextExtractor(),
      new LocalFoodDataProvider(repository),
      0.75,
    );

    const result = await resolver.resolveMealMentions("user-1", [
      {
        ...mention("grilled chicken breast", "pechuga de pollo a la plancha"),
        quantity: 300,
      },
    ]);

    expect(result.clarificationRequired).toBe(false);
    expect(result.items[0]).toEqual(
      expect.objectContaining({
        externalId: "171534",
        quantity: 300,
        unit: "g",
      }),
    );
  });

  it("does not use branded USDA rows for generic searches but allows barcode intent", async () => {
    const repository = InMemoryRepository.seeded();
    await repository.upsertFoodItem({
      name: "Cheese Crackers",
      normalizedName: "cheese",
      canonicalName: "cheese",
      brand: "Test Brand",
      barcode: "000111222333",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "4001",
      dataType: "Branded",
      servingGrams: 100,
      calories: 500,
      proteinGrams: 8,
      carbsGrams: 60,
      fatGrams: 25,
    });
    const resolver = new FoodResolver(
      new DeterministicFoodTextExtractor(),
      new LocalFoodDataProvider(repository),
      0.75,
    );

    const generic = await resolver.resolveMealText("user-1", "Add 100 grams cheese");
    expect(generic.clarificationRequired).toBe(true);
    expect(generic.items).toHaveLength(0);

    const barcode = await resolver.search("user-1", "cheese", "000111222333");
    expect(barcode.items[0]).toEqual(
      expect.objectContaining({
        name: "Cheese Crackers",
        externalId: "4001",
      }),
    );
    expect(barcode.candidateGroups[0]?.candidates[0]).toBe(barcode.items[0]);
  });

  it("keeps gram-based egg quantities when the user gives grams", async () => {
    const repository = testFoodRepository();
    const resolver = new FoodResolver(
      new DeterministicFoodTextExtractor(),
      new LocalFoodDataProvider(repository),
      0.75,
    );

    const result = await resolver.resolveMealText(
      "user-1",
      "Add 100 grams of egg.",
    );

    expect(result.clarificationRequired).toBe(false);
    expect(result.items[0]).toEqual(
      expect.objectContaining({
        name: "Egg",
        quantity: 100,
        unit: "g",
        calories: 144,
      }),
    );
  });

  it("does not silently create a partial proposal when one extracted ingredient is unresolved", async () => {
    const repository = testFoodRepository();
    const resolver = new FoodResolver(
      new DeterministicFoodTextExtractor(),
      new LocalFoodDataProvider(repository),
      0.75,
    );

    const result = await resolver.resolveMealText(
      "user-1",
      "Add 100 grams of bread and 100 grams of cheese.",
    );

    expect(result.clarificationRequired).toBe(true);
    expect(result.items).toHaveLength(1);
    expect(result.items[0]?.name).toBe("Bread");
    expect(result.unresolvedMentions).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ canonicalEnglishName: "cheese" }),
      ]),
    );
  });

});
