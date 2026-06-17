import { describe, expect, it } from "vitest";
import type { FoodMention } from "@cal-tracker/contracts";
import { FoodResolver, type FoodDataProvider } from "../nutrition/foodResolver.js";
import { ResolverNutritionProvider } from "../nutrition/provider.js";

describe("ResolverNutritionProvider", () => {
  it("resolves only structured food mentions", async () => {
    const providerStub: FoodDataProvider = {
      id: "local",
      async resolve() {
        return [
          {
            name: "Bread",
            quantity: 100,
            unit: "g",
            calories: 265,
            proteinGrams: 9,
            carbsGrams: 49,
            fatGrams: 3.2,
            source: "test",
            confidence: 0.95,
          },
        ];
      },
    };
    const resolver = new FoodResolver(providerStub, 0.75);
    const provider = new ResolverNutritionProvider(resolver);
    const bread: FoodMention = {
      originalText: "100 grams of bread",
      canonicalName: "bread",
      canonicalEnglishName: "bread",
      quantity: 100,
      unit: "g",
      rawUnitText: "grams",
      unitKind: "metric",
      confidence: 0.95,
    };

    await expect(
      provider.resolveMealMentions("user-id", [bread]),
    ).resolves.toEqual(
      expect.objectContaining({
        clarificationRequired: false,
        items: [expect.objectContaining({ name: "Bread" })],
      }),
    );
  });
});
