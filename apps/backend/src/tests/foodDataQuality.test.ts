import { describe, expect, it } from "vitest";
import { classifyFoodQuality, type FoodQualityInput } from "../foodData/quality.js";

function qualityInput(overrides: Partial<FoodQualityInput>): FoodQualityInput {
  return {
    name: "Sample food",
    servingGrams: 100,
    calories: 100,
    proteinGrams: 5,
    carbsGrams: 15,
    fatGrams: 2,
    ...overrides,
  };
}

describe("food data quality classification", () => {
  it("quarantines imported rows with no nutrition", () => {
    const result = classifyFoodQuality(qualityInput({
      calories: 0,
      proteinGrams: 0,
      carbsGrams: 0,
      fatGrams: 0,
    }));

    expect(result.qualityStatus).toBe("quarantined");
    expect(result.isSearchEligible).toBe(false);
    expect(result.qualityFlags).toContain("zero_nutrition");
  });

  it("quarantines imported rows with zero calories but positive macros", () => {
    const result = classifyFoodQuality(qualityInput({
      calories: 0,
      proteinGrams: 0,
      carbsGrams: 78,
      fatGrams: 0,
    }));

    expect(result.qualityStatus).toBe("quarantined");
    expect(result.isSearchEligible).toBe(false);
    expect(result.qualityFlags).toContain("zero_calories_with_macros");
  });

  it("quarantines impossible nutrition values", () => {
    const result = classifyFoodQuality(qualityInput({
      calories: 1200,
      proteinGrams: 20,
      carbsGrams: 140,
      fatGrams: 5,
    }));

    expect(result.qualityStatus).toBe("quarantined");
    expect(result.isSearchEligible).toBe(false);
    expect(result.qualityFlags).toContain("impossible_calories");
    expect(result.qualityFlags).toContain("impossible_macros");
  });

  it("marks moderate macro energy mismatches as suspicious rather than quarantined", () => {
    const result = classifyFoodQuality(qualityInput({
      calories: 400,
      proteinGrams: 0,
      carbsGrams: 20,
      fatGrams: 0,
    }));

    expect(result.qualityStatus).toBe("suspicious");
    expect(result.qualityFlags).toEqual(["macro_energy_mismatch"]);
    expect(result.qualityScore).toBeGreaterThan(0);
  });
});
