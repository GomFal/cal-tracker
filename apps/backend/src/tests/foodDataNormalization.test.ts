import { describe, expect, it } from "vitest";
import {
  buildNormalizedFoodSearchDocument,
  normalizeGenericFoodName,
  normalizedIdentityTokenKeys,
  normalizeProductFoodName,
} from "../foodData/normalization.js";
import {
  applyLongNameDecision,
  longNameInputSignature,
  type LongNameDecision,
} from "../foodData/longNameDecisions.js";
import { FOOD_NORMALIZATION_VERSION } from "../foodData/constants.js";
import type { FoodItemRecord } from "../repository/types.js";

describe("food data normalization", () => {
  it("compacts generic USDA-style descriptor names", () => {
    expect(normalizeGenericFoodName("Rice, black, unenriched, raw").displayName)
      .toBe("Black Rice, Raw");
    expect(normalizeGenericFoodName("Rice, red, unenriched, dry, raw").displayName)
      .toBe("Red Rice, Raw");
    expect(normalizeGenericFoodName("Rice, white, long-grain, regular, cooked, enriched, with salt").displayName)
      .toBe("White Rice, Cooked");
  });

  it("preserves meaningful descriptors when they are bundled with low-value source details", () => {
    expect(normalizeGenericFoodName("Rice, white, long-grain, regular, unenriched, cooked without salt").displayName)
      .toBe("White Rice, Cooked");
    expect(normalizeGenericFoodName("Rice, brown, medium-grain, raw (Includes foods for USDA's Food Distribution Program)").displayName)
      .toBe("Brown Rice, Raw");
    expect(normalizeGenericFoodName("Rice, white, short-grain, enriched, uncooked").displayName)
      .toBe("White Rice, Uncooked");
  });

  it("keeps non-state descriptors when a prefix descriptor is promoted into the base name", () => {
    expect(normalizeGenericFoodName("Bread, reduced-calorie, white").displayName)
      .toBe("White Bread, Reduced-calorie");
    expect(normalizeGenericFoodName("Cheese, ricotta, whole milk").displayName)
      .toBe("Whole Milk Cheese, Ricotta");
    expect(normalizeGenericFoodName("Beans, snap, yellow, raw").displayName)
      .toBe("Yellow Beans, Snap, Raw");
  });

  it("bounds long generic display variants while retaining overflow descriptors", () => {
    const normalized = normalizeGenericFoodName(
      "Beef, Australian, imported, Wagyu, rib, small end rib steak/roast, boneless, separable lean and fat, Aust. marble score 9, raw",
    );

    expect(normalized.displayName.split(/\s+/).filter(Boolean).length).toBeLessThanOrEqual(18);
    expect(normalized.hiddenDescriptors).toContain("aust. marble score 9");
  });

  it("does not leave dangling low-value descriptor fragments in compact names", () => {
    expect(normalizeGenericFoodName("Nuts, cashew butter, plain, without salt added").displayName)
      .toBe("Nuts Cashew Butter, Plain");
    expect(normalizeGenericFoodName("Salad dressing, italian dressing, commercial, regular").displayName)
      .toBe("Salad Dressing Italian Dressing");
  });

  it("preserves meaningful generic descriptors before low-value source details", () => {
    expect(normalizeGenericFoodName("Cheese, cheddar (Includes foods for USDA's Food Distribution Program)").displayName)
      .toBe("Cheese Cheddar");
  });

  it("keeps compact generic variants secondary to the source primary entity", () => {
    const chicken = normalizeGenericFoodName("Chicken, feet, boiled");
    expect(chicken.primaryEntityName).toBe("Chicken");
    expect(chicken.primaryEntityAliases).toContain("chicken");
    expect(chicken.primaryEntityAliases).not.toContain("chicken feet");
    expect(chicken.secondaryEntityAliases).toContain("chicken feet");

    const cookies = normalizeGenericFoodName("Cookies, butter, commercially prepared, unenriched");
    expect(cookies.primaryEntityName).toBe("Cookies");
    expect(cookies.primaryEntityAliases).toContain("cookies");
    expect(cookies.primaryEntityAliases).not.toContain("cookies butter");
    expect(cookies.secondaryEntityAliases).toContain("cookies butter");
  });

  it("builds order-invariant identity token keys without filtering tokens", () => {
    expect(normalizedIdentityTokenKeys(["Beef Ground"])).toEqual(["beef ground"]);
    expect(normalizedIdentityTokenKeys(["ground beef"])).toEqual(["beef ground"]);
    expect(normalizedIdentityTokenKeys(["Turkey Ground", "Ground Turkey"]))
      .toEqual(["ground turkey"]);
    expect(normalizedIdentityTokenKeys(["Salt And Vinegar Chips"]))
      .toEqual(["and chips salt vinegar"]);
    expect(normalizedIdentityTokenKeys(["Very Long Descriptor Heavy Product Name"]))
      .toEqual([]);
  });

  it("stores compact order-invariant keys on normalized food documents", () => {
    const document = buildNormalizedFoodSearchDocument(foodItem({
      name: "Beef, ground, 80% lean meat / 20% fat, raw",
      dataType: "SR Legacy",
      source: "usda_fdc",
      externalSource: "usda_fdc",
    }));

    expect(document?.displayName).toBe("Beef Ground, 80% Lean Meat 20% Fat, Raw");
    expect(document?.identityTokenKeys).toContain("beef ground");
    expect(document?.metadata.identityTokenKeys).toContain("beef ground");
  });

  it("builds product display names from product name and brand", () => {
    expect(normalizeProductFoodName("Arroz", "Goya").displayName).toBe("Arroz - Goya");
    expect(normalizeProductFoodName("Goya Arroz", "Goya").displayName).toBe("Goya Arroz");
    expect(normalizeProductFoodName("Pasta", "De Cecco, F.lli De Cecco di Filippo Fara San Martino SpA").displayName)
      .toBe("Pasta - De Cecco");
  });

  it("removes duplicated delimiter brand segments from product base names", () => {
    const product = normalizeProductFoodName("Breakfast Cereal - Acme", "Acme");

    expect(product.baseName).toBe("Breakfast Cereal");
    expect(product.displayName).toBe("Breakfast Cereal - Acme");
    expect(product.brandDisplay).toBe("Acme");
    expect(product.aliases).toContain("Breakfast Cereal - Acme");
  });

  it("removes safe edge brand phrases without guessing brand-only products", () => {
    expect(normalizeProductFoodName("Acme Breakfast Cereal", "Acme").displayName)
      .toBe("Breakfast Cereal - Acme");
    expect(normalizeProductFoodName("Product - Brand", "Product").displayName)
      .toBe("Product - Brand");
    expect(normalizeProductFoodName("Brand", "Brand").displayName)
      .toBe("Brand");
    expect(normalizeProductFoodName("Be Pro +", "Be Pro").displayName)
      .toBe("Be Pro");
    expect(normalizeProductFoodName("- Garbanzos MORA", "Garbanzos MORA").displayName)
      .toBe("Garbanzos Mora");
  });

  it("keeps user-created foods as custom documents while preserving brand display", () => {
    const document = buildNormalizedFoodSearchDocument(foodItem({
      userId: "user-1",
      name: "Protein bar",
      brand: "Kitchen Batch",
      dataType: "User",
      source: "user",
      externalSource: "user",
    }));

    expect(document?.resultType).toBe("custom_food");
    expect(document?.displayName).toBe("Protein Bar - Kitchen Batch");
    expect(document?.brandDisplay).toBe("Kitchen Batch");
  });

  it("bounds product search text while keeping raw detail in metadata", () => {
    const document = buildNormalizedFoodSearchDocument(foodItem({
      name: "Very Long Product Name",
      brand: "Acme, Acme Holding Company With Several Legal Entity Tokens",
      dataType: "Branded",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      ingredients: Array.from({ length: 120 }, (_, index) => `ingredient${index}`).join(" "),
    }));

    expect(document?.searchText).toContain("very long product name");
    expect(document?.searchText).toContain("acme");
    expect(document?.searchText).not.toContain("ingredient119");
    expect(document?.searchText.split(/\s+/).filter(Boolean).length).toBeLessThanOrEqual(80);
    expect(document?.metadata.ingredients).toContain("ingredient119");
  });

  it("bounds generic search text while keeping raw USDA detail in metadata", () => {
    const document = buildNormalizedFoodSearchDocument(foodItem({
      name: "Rice, white, medium-grain, cooked, unenriched, prepared with butter, sauce, and detailed source notes",
      dataType: "Foundation",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      foodCategory: "Cereal Grains and Pasta",
      ingredients: Array.from({ length: 120 }, (_, index) => `genericIngredient${index}`).join(" "),
    }));

    expect(document?.displayName).toContain("Rice");
    expect(document?.searchText).toContain("rice");
    expect(document?.searchText).toContain("cereal grains and pasta");
    expect(document?.searchText).not.toContain("genericingredient119");
    expect(document?.metadata.rawName).toContain("detailed source notes");
    expect(document?.metadata.ingredients).toContain("genericIngredient119");
  });

  it("applies approved long-name decisions with bounded search text and metadata trace", () => {
    const food = foodItem({
      id: "food-long",
      name: "100% Apple Romaine Cucumber Spinach Kale Lemon Cold-pressed Vegetable & Fruit Juice Blend Apple Romaine Cucumber Spinach Kale Lemon",
      brand: "Bolthouse Farms",
      dataType: "Branded",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      foodCategory: "Juice",
      ingredients: Array.from({ length: 120 }, (_, index) => `ingredient${index}`).join(" "),
    });
    const document = buildNormalizedFoodSearchDocument(food);
    const inputSignature = longNameInputSignature({
      source: food.source,
      externalSource: food.externalSource,
      dataType: food.dataType,
      name: food.name,
      normalizedName: food.normalizedName,
      canonicalName: food.canonicalName,
      brand: food.brand,
      foodCategory: food.foodCategory,
      marketCountry: food.marketCountry,
      normalizationVersion: FOOD_NORMALIZATION_VERSION,
    });
    const decision: LongNameDecision = {
      foodItemId: "food-long",
      normalizationVersion: FOOD_NORMALIZATION_VERSION,
      inputSignature,
      status: "approved",
      displayName: "Cold-Pressed Apple Greens Juice - Bolthouse Farms",
      baseName: "Cold-Pressed Apple Greens Juice",
      variantName: "Apple, Romaine, Cucumber, Spinach, Kale, Lemon",
      fullNormalizedDescription: "Cold-pressed vegetable and fruit juice blend with apple, romaine, cucumber, spinach, kale, and lemon.",
      retainedDescriptors: ["cold-pressed", "juice blend"],
      supplementalDescriptors: ["apple", "romaine", "cucumber", "spinach", "kale", "lemon"],
      aliases: ["apple greens juice", "vegetable fruit juice"],
      confidence: 0.93,
      decisionSource: "offline_llm_review",
    };

    const result = applyLongNameDecision(document!, decision, inputSignature);

    expect(result.status).toBe("applied");
    if (result.status !== "applied") return;
    expect(result.doc.displayName).toBe("Cold-Pressed Apple Greens Juice - Bolthouse Farms");
    expect(result.doc.metadata.fullNormalizedDescription).toBe(decision.fullNormalizedDescription);
    expect(result.doc.metadata.rawName).toBe(food.name);
    expect(result.doc.searchText).toContain("apple greens juice");
    expect(result.doc.searchText).not.toContain("ingredient119");
    expect(result.doc.searchText.split(/\s+/).filter(Boolean).length).toBeLessThanOrEqual(80);
    expect(result.doc.searchAliases).toContain("apple greens juice");
    expect(result.doc.searchAliases).not.toContain(food.name);
  });

  it("does not apply stale long-name decisions", () => {
    const document = buildNormalizedFoodSearchDocument(foodItem({
      id: "food-long",
      name: "Long Product Name",
      brand: "Acme",
      dataType: "Branded",
      source: "usda_fdc",
      externalSource: "usda_fdc",
    }));
    const decision: LongNameDecision = {
      foodItemId: "food-long",
      normalizationVersion: FOOD_NORMALIZATION_VERSION,
      inputSignature: "stale-signature",
      status: "approved",
      displayName: "Short Product - Acme",
      baseName: "Short Product",
      retainedDescriptors: [],
      supplementalDescriptors: [],
      aliases: [],
      confidence: 0.9,
      decisionSource: "offline_llm_review",
    };

    const result = applyLongNameDecision(document!, decision, "current-signature");

    expect(result.status).toBe("stale");
  });
});

function foodItem(overrides: Partial<FoodItemRecord>): FoodItemRecord {
  return {
    id: "food-1",
    name: "Sample food",
    normalizedName: "sample food",
    source: "usda_fdc",
    externalSource: "usda_fdc",
    dataType: "Foundation",
    portions: [],
    servingGrams: 100,
    calories: 100,
    proteinGrams: 5,
    carbsGrams: 15,
    fatGrams: 2,
    ...overrides,
  };
}
