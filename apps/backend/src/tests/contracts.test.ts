import { describe, expect, it } from "vitest";
import {
  actionDefinitions,
  actionById,
  foodMentionSchema,
  mealItemSchema,
  searchNutritionDatabaseOutputSchema,
} from "@cal-tracker/contracts";

describe("contracts", () => {
  it("defines all MVP actions with schemas and permissions", () => {
    const expected = [
      "query_food_memory",
      "search_nutrition_database",
      "propose_meal_log",
      "commit_meal",
      "create_meal_proposal_from_items",
      "correct_meal",
      "revise_meal_proposal",
      "delete_meal",
      "get_daily_summary",
      "get_remaining_targets",
      "get_meal_history",
      "get_usual_meals",
      "create_meal_template",
      "update_meal_template",
      "delete_meal_template",
    ];
    expect(actionDefinitions.map((action) => action.id)).toEqual(expected);
    for (const id of expected) {
      const action = actionById.get(id)!;
      expect(action.inputSchema).toBeTruthy();
      expect(action.outputSchema).toBeTruthy();
      expect(action.permissionScope).toBeTruthy();
    }
  });

  it("accepts optional candidate metadata and grouped nutrition search candidates", () => {
    const item = mealItemSchema.parse({
      name: "Bread",
      quantity: 100,
      unit: "g",
      calories: 265,
      proteinGrams: 9,
      carbsGrams: 49,
      fatGrams: 3.2,
      source: "test_fixture",
      rank: 1,
      matchScore: 0.95,
      lexicalScore: 0.9,
      vectorScore: 0.8,
      preferenceScore: 0.7,
      matchReason: "local_match",
    });

    expect(item.rank).toBe(1);
    expect(
      searchNutritionDatabaseOutputSchema.parse({
        items: [item],
        candidates: [
          {
            mention: {
              originalText: "bread",
              canonicalEnglishName: "bread",
              quantity: 100,
              unit: "g",
              confidence: 0.95,
              marketProduct: false,
            },
            candidates: [item],
          },
        ],
        candidateGroups: [
          {
            mention: {
              originalText: "bread",
              canonicalEnglishName: "bread",
              quantity: 100,
              unit: "g",
              confidence: 0.95,
              marketProduct: false,
            },
            candidates: [item],
          },
        ],
      }).candidateGroups,
    ).toHaveLength(1);
  });

  it("accepts language-aware food mentions while preserving legacy mentions", () => {
    expect(
      foodMentionSchema.parse({
        originalText: "pan",
        canonicalName: "pan",
        language: "es",
        quantity: 100,
        unit: "g",
        confidence: 0.95,
        marketProduct: false,
      }).canonicalName,
    ).toBe("pan");

    expect(
      foodMentionSchema.parse({
        originalText: "bread",
        canonicalEnglishName: "bread",
        quantity: 100,
        unit: "g",
        confidence: 0.95,
        marketProduct: false,
      }).canonicalEnglishName,
    ).toBe("bread");
  });
});
