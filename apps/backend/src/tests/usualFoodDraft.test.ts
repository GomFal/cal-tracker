import { describe, expect, it } from "vitest";
import type { DraftUsualFoodProviderOutput } from "@cal-tracker/contracts";
import type { UsualFoodDraftProvider } from "../agent/usualFoodDraftProvider.js";
import {
  buildTestApp,
  FakeChatAgentProvider,
  registerAndAuth,
} from "./testApp.js";

class FakeUsualFoodDraftProvider implements UsualFoodDraftProvider {
  readonly inputs: Array<{ text: string; locale: string; traceId: string }> = [];

  constructor(private readonly output: DraftUsualFoodProviderOutput) {}

  async draft(input: {
    text: string;
    locale: string;
    traceId: string;
  }): Promise<DraftUsualFoodProviderOutput> {
    this.inputs.push(input);
    return this.output;
  }
}

describe("usual food AI draft", () => {
  it("returns a complete review-only draft from explicit provider fields", async () => {
    const provider = new FakeUsualFoodDraftProvider({
      name: "Arroz Hacendado",
      brand: "Hacendado",
      servingGrams: 100,
      nutrition: {
        calories: 360,
        proteinGrams: 7,
        carbsGrams: 79,
        fatGrams: 1,
      },
      nutrients: { saltGrams: 0.01 },
      aliases: [],
      explicitFields: [
        "name",
        "brand",
        "servingGrams",
        "calories",
        "proteinGrams",
        "carbsGrams",
        "fatGrams",
        "nutrients",
      ],
    });
    const { request, repository } = buildTestApp({
      usualFoodDraftProvider: provider,
    });
    const auth = await registerAndAuth(request);

    const response = await request("http://localhost/v1/usual-foods/draft", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({
        text: "Crea mi arroz Hacendado con los valores de la etiqueta.",
      }),
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      draft: {
        name: "Arroz Hacendado",
        brand: "Hacendado",
        servingGrams: 100,
        nutrition: {
          calories: 360,
          proteinGrams: 7,
          carbsGrams: 79,
          fatGrams: 1,
        },
        nutrients: { saltGrams: 0.01 },
        aliases: [],
        missingRequiredFields: [],
      },
      requiresReview: true,
    });
    const foods = await repository.listFoods(auth.user.id);
    expect(foods.filter((food) => food.userId === auth.user.id)).toHaveLength(0);
  });

  it("reports missing required fields and ignores provider values not marked explicit", async () => {
    const provider = new FakeUsualFoodDraftProvider({
      name: "Arroz Hacendado",
      brand: "Hacendado",
      nutrition: {
        calories: 360,
      },
      aliases: [],
      explicitFields: ["name", "brand"],
    });
    const { request } = buildTestApp({ usualFoodDraftProvider: provider });
    const auth = await registerAndAuth(request);

    const response = await request(
      "http://localhost/v1/actions/draft_usual_food/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            text: "Crea mi arroz Hacendado, no tengo los macros todavia.",
          },
          source: "flutter",
        }),
      },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      confirmationRequired: boolean;
      output: {
        draft: {
          nutrition?: { calories?: number };
          missingRequiredFields: string[];
        };
        message?: string;
        requiresReview: boolean;
      };
    };
    expect(body.confirmationRequired).toBe(false);
    expect(body.output.requiresReview).toBe(true);
    expect(body.output.draft.nutrition?.calories).toBeUndefined();
    expect(body.output.draft.missingRequiredFields).toEqual([
      "servingGrams",
      "calories",
      "proteinGrams",
      "carbsGrams",
      "fatGrams",
    ]);
    expect(body.output.message).toBe(
      "Missing required nutrition values. Please complete them before saving.",
    );
  });

  it("does not persist a food item when drafting through the action executor", async () => {
    const provider = new FakeUsualFoodDraftProvider({
      name: "Custom Yogurt",
      servingGrams: 125,
      nutrition: {
        calories: 80,
        proteinGrams: 5,
        carbsGrams: 9,
        fatGrams: 1.5,
      },
      aliases: [],
      explicitFields: [
        "name",
        "servingGrams",
        "calories",
        "proteinGrams",
        "carbsGrams",
        "fatGrams",
      ],
    });
    const { request, repository } = buildTestApp({
      usualFoodDraftProvider: provider,
    });
    const auth = await registerAndAuth(request);
    const before = (await repository.listFoods(auth.user.id)).filter(
      (food) => food.userId === auth.user.id,
    );

    const response = await request(
      "http://localhost/v1/actions/draft_usual_food/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: { text: "Draft a yogurt label I typed manually." },
          source: "flutter",
        }),
      },
    );

    expect(response.status).toBe(200);
    const after = (await repository.listFoods(auth.user.id)).filter(
      (food) => food.userId === auth.user.id,
    );
    expect(after).toEqual(before);
  });

  it("maps global agent usual ingredient creation requests to a review-only draft", async () => {
    const provider = new FakeUsualFoodDraftProvider({
      name: "Custom Yogurt",
      servingGrams: 125,
      nutrition: {
        calories: 80,
        proteinGrams: 5,
        carbsGrams: 9,
        fatGrams: 1.5,
      },
      aliases: [],
      explicitFields: [
        "name",
        "servingGrams",
        "calories",
        "proteinGrams",
        "carbsGrams",
        "fatGrams",
      ],
    });
    const { request, repository } = buildTestApp({
      usualFoodDraftProvider: provider,
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "draft_usual_food",
              arguments: JSON.stringify({
                text: "Save this as my usual yogurt from the label.",
              }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const auth = await registerAndAuth(request);

    const response = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({
        text: "Save this as my usual yogurt from the label.",
        source: "flutter",
      }),
    });

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      kind: string;
      usualFoodDraft: { draft: { name?: string }; requiresReview: boolean };
    };
    expect(body.kind).toBe("usual_food_draft");
    expect(body.usualFoodDraft.requiresReview).toBe(true);
    expect(body.usualFoodDraft.draft.name).toBe("Custom Yogurt");
    const foods = await repository.listFoods(auth.user.id);
    expect(foods.filter((food) => food.userId === auth.user.id)).toHaveLength(0);
  });
});
