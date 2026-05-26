import { describe, expect, it } from "vitest";
import { FoodResolver, type FoodDataProvider, type FoodTextExtractor } from "../nutrition/foodResolver.js";
import { ResolverNutritionProvider } from "../nutrition/provider.js";

describe("ResolverNutritionProvider", () => {
  it("does not fall back to legacy hardcoded ingredient aliases", async () => {
    const extractor: FoodTextExtractor = {
      async extract() {
        return [];
      },
    };
    const providerStub: FoodDataProvider = {
      id: "local",
      async resolve() {
        return [];
      },
    };
    const resolver = new FoodResolver(extractor, providerStub, 0.75);
    const provider = new ResolverNutritionProvider(resolver);

    await expect(
      provider.estimateMeal("user-id", "pollo con arroz"),
    ).resolves.toEqual([]);
  });
});
