import { describe, expect, it } from "vitest";
import type {
  DraftUsualMealProviderOutput,
  FoodMention,
} from "@cal-tracker/contracts";
import type { UsualMealDraftProvider } from "../agent/usualMealDraftProvider.js";
import { buildTestApp, registerAndAuth } from "./testApp.js";

class FakeUsualMealDraftProvider implements UsualMealDraftProvider {
  readonly inputs: Array<{ text: string; locale: string; traceId: string }> = [];

  constructor(private readonly output: DraftUsualMealProviderOutput) {}

  async draft(input: {
    text: string;
    locale: string;
    traceId: string;
  }): Promise<DraftUsualMealProviderOutput> {
    this.inputs.push(input);
    return this.output;
  }
}

function mention(
  canonicalEnglishName: string,
  quantity: number,
  overrides: Partial<FoodMention> = {},
): FoodMention {
  const unit = overrides.unit ?? "g";
  const rawUnitText = overrides.rawUnitText ?? (unit === "g" ? "grams" : unit);
  return {
    originalText:
      overrides.originalText ??
      `${quantity} ${rawUnitText} of ${canonicalEnglishName}`,
    canonicalName: overrides.canonicalName ?? canonicalEnglishName,
    canonicalEnglishName,
    language: overrides.language ?? "en",
    quantity,
    unit,
    rawUnitText,
    unitKind: overrides.unitKind ?? (unit === "g" ? "metric" : "unknown"),
    confidence: overrides.confidence ?? 0.95,
    marketProduct: overrides.marketProduct ?? false,
    ...overrides,
  };
}

describe("usual meal AI draft", () => {
  it("returns a review-only draft with resolved ingredients and does not persist a template", async () => {
    const provider = new FakeUsualMealDraftProvider({
      title: "Toast breakfast",
      aliases: ["weekday toast"],
      mentions: [
        mention("bread", 100, { originalText: "100 grams of bread" }),
        mention("butter", 20, { originalText: "20 grams of butter" }),
      ],
    });
    const { request, repository } = buildTestApp({
      usualMealDraftProvider: provider,
    });
    const auth = await registerAndAuth(request);

    const response = await request(
      "http://localhost/v1/meal-templates/draft",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          text: "Create my usual Toast breakfast with 100g bread and 20g butter.",
        }),
      },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      draft: {
        title?: string;
        aliases: string[];
        items: Array<{ name: string; quantity: number }>;
        nutrition?: { calories: number };
        missingRequiredFields: string[];
      };
      requiresReview: boolean;
      clarificationRequired?: boolean;
    };
    expect(body.requiresReview).toBe(true);
    expect(body.clarificationRequired).toBe(false);
    expect(body.draft.title).toBe("Toast breakfast");
    expect(body.draft.aliases).toEqual(["weekday toast"]);
    expect(body.draft.items).toEqual([
      expect.objectContaining({ name: "Bread", quantity: 100 }),
      expect.objectContaining({ name: "Butter", quantity: 20 }),
    ]);
    expect(body.draft.nutrition?.calories).toBe(408);
    expect(body.draft.missingRequiredFields).toEqual([]);
    await expect(repository.listTemplates(auth.user.id)).resolves.toEqual([]);
  });

  it("returns clarification and candidates when an ingredient cannot be resolved", async () => {
    const provider = new FakeUsualMealDraftProvider({
      title: "Snack plate",
      aliases: [],
      mentions: [
        mention("bread", 100, { originalText: "100 grams of bread" }),
        mention("cheese", 50, { originalText: "50 grams of cheese" }),
      ],
    });
    const { request } = buildTestApp({ usualMealDraftProvider: provider });
    const auth = await registerAndAuth(request);

    const response = await request(
      "http://localhost/v1/actions/draft_usual_meal/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: { text: "Draft snack plate with bread and cheese." },
          source: "flutter",
        }),
      },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      confirmationRequired: boolean;
      output: {
        draft: { items: Array<{ name: string }>; missingRequiredFields: string[] };
        clarificationRequired: boolean;
        unresolvedMentions: Array<{ canonicalEnglishName?: string }>;
        options: Array<{ reason?: string; candidates: unknown[] }>;
      };
    };
    expect(body.confirmationRequired).toBe(false);
    expect(body.output.clarificationRequired).toBe(true);
    expect(body.output.draft.items).toEqual([
      expect.objectContaining({ name: "Bread" }),
    ]);
    expect(body.output.draft.missingRequiredFields).toEqual([]);
    expect(body.output.unresolvedMentions).toEqual([
      expect.objectContaining({ canonicalEnglishName: "cheese" }),
    ]);
    expect(body.output.options).toEqual([
      expect.objectContaining({ reason: "no_database_match", candidates: [] }),
    ]);
  });

  it("can draft a usual meal from a user-owned usual food item", async () => {
    const provider = new FakeUsualMealDraftProvider({
      title: "Custom rice bowl",
      aliases: [],
      mentions: [
        mention("custom rice", 150, { originalText: "150 grams of custom rice" }),
      ],
    });
    const { request } = buildTestApp({ usualMealDraftProvider: provider });
    const auth = await registerAndAuth(request);

    const usualFoodResponse = await request("http://localhost/v1/usual-foods", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({
        name: "Custom Rice",
        canonicalName: "custom rice",
        servingGrams: 100,
        nutrition: {
          calories: 200,
          proteinGrams: 4,
          carbsGrams: 44,
          fatGrams: 1,
        },
        aliases: [],
      }),
    });
    expect(usualFoodResponse.status).toBe(200);
    const usualFoodBody = (await usualFoodResponse.json()) as {
      output: { usualFood: { id: string } };
    };

    const response = await request(
      "http://localhost/v1/actions/draft_usual_meal/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: { text: "Draft my custom rice bowl." },
          source: "flutter",
        }),
      },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      output: {
        draft: {
          items: Array<{
            name: string;
            source?: string;
            externalSource?: string;
            externalId?: string;
            calories: number;
          }>;
        };
      };
    };
    expect(body.output.draft.items).toEqual([
      expect.objectContaining({
        name: "Custom Rice",
        source: "user_custom",
        externalSource: "user_custom",
        externalId: usualFoodBody.output.usualFood.id,
        calories: 300,
      }),
    ]);
  });
});
