import { describe, expect, it, vi } from "vitest";
import type { FoodMention, MealItem } from "@cal-tracker/contracts";
import {
  buildTestApp,
  createTestUsualBreakfastTemplate,
  registerAndAuth,
  testBreadItem,
} from "./testApp.js";

type TestRequest = (input: string, init?: RequestInit) => Promise<Response>;

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

const chickenRiceInput = {
  text: "Add 100 grams of chicken breast and 100 grams of rice",
  mentions: [
    mention("chicken breast", 100, {
      originalText: "100 grams of chicken breast",
    }),
    mention("rice", 100, { originalText: "100 grams of rice" }),
  ],
};

async function createChickenBreadRiceButterProposal(
  request: TestRequest,
  authHeader: Record<string, string>,
): Promise<{ id: string; items: MealItem[] }> {
  const response = await request(
    "http://localhost/v1/actions/propose_meal_log/execute",
    {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        input: {
          text: "Add 100g of chicken, 100g of bread, 100g of rice and 100g of butter.",
          mentions: [
            mention("chicken", 100, { originalText: "100g of chicken" }),
            mention("bread", 100, { originalText: "100g of bread" }),
            mention("rice", 100, { originalText: "100g of rice" }),
            mention("butter", 100, { originalText: "100g of butter" }),
          ],
        },
        source: "flutter",
      }),
    },
  );
  expect(response.status).toBe(200);
  const body = (await response.json()) as {
    output: { proposal: { id: string; items: MealItem[] } };
  };
  expect(body.output.proposal.items.map((item) => item.name)).toEqual(
    expect.arrayContaining(["Chicken breast", "Bread", "Cooked rice", "Butter"]),
  );
  return body.output.proposal;
}

function redMeatMention(): FoodMention {
  return {
    originalText: "10 grams of red meat",
    canonicalName: "red meat",
    canonicalEnglishName: "red meat",
    language: "en",
    quantity: 10,
    unit: "g",
    rawUnitText: "grams",
    unitKind: "metric",
    confidence: 0.9,
    marketProduct: false,
  };
}

describe("action loop", () => {
  it("creates a proposal from explicit selected meal items", async () => {
    const { request, repository } = buildTestApp();
    const recordFoodFeedback = vi.fn(async () => undefined);
    Object.assign(repository, { recordFoodFeedback });
    const auth = await registerAndAuth(request);

    const response = await request(
      "http://localhost/v1/actions/create_meal_proposal_from_items/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            phrase: "selected food matches",
            items: [testBreadItem],
          },
          source: "flutter",
        }),
      },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      output: { proposal: { title: string; items: unknown[] } };
    };
    expect(body.output.proposal.title).toBe("Bread");
    expect(body.output.proposal.items).toHaveLength(1);
    expect(recordFoodFeedback).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: auth.user.id,
        action: "selected",
        query: "selected food matches",
        metadata: expect.objectContaining({
          eventType: "selected_for_proposal",
          explicitSelection: true,
          itemName: "Bread",
        }),
      }),
    );
  });

  it("revises a pending proposal and records correction feedback", async () => {
    const { request, repository } = buildTestApp();
    const recordFoodFeedback = vi.fn(async () => undefined);
    Object.assign(repository, { recordFoodFeedback });
    const auth = await registerAndAuth(request);

    const created = await request(
      "http://localhost/v1/actions/create_meal_proposal_from_items/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            phrase: "100 grams of bread",
            items: [testBreadItem],
          },
          source: "flutter",
        }),
      },
    ).then(
      (response) =>
        response.json() as Promise<{ output: { proposal: { id: string } } }>,
    );

    const revised = await request(
      "http://localhost/v1/actions/revise_meal_proposal/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            proposalId: created.output.proposal.id,
            instruction: "Make the bread 200 grams.",
            operations: [
              {
                type: "update_item_quantity",
                matchText: "bread",
                quantity: 200,
                unit: "g",
              },
            ],
          },
          source: "flutter",
        }),
      },
    );

    expect(revised.status).toBe(200);
    const body = (await revised.json()) as {
      output: {
        proposal: {
          id: string;
          status: string;
          nutrition: { calories: number };
          items: { name: string; quantity: number }[];
        };
      };
    };
    expect(body.output.proposal.id).toBe(created.output.proposal.id);
    expect(body.output.proposal.status).toBe("corrected");
    expect(body.output.proposal.items[0]).toEqual(
      expect.objectContaining({ name: "Bread", quantity: 200 }),
    );
    expect(body.output.proposal.nutrition.calories).toBe(530);
    expect(recordFoodFeedback).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: auth.user.id,
        action: "corrected",
        metadata: expect.objectContaining({
          eventType: "proposal_corrected",
          proposalId: created.output.proposal.id,
          revisionOperationCount: 1,
        }),
      }),
    );
  });

  it("asks for clarification when a proposal revision cannot resolve a new food", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const created = await request(
      "http://localhost/v1/actions/create_meal_proposal_from_items/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            phrase: "100 grams of bread",
            items: [testBreadItem],
          },
          source: "flutter",
        }),
      },
    ).then(
      (response) =>
        response.json() as Promise<{ output: { proposal: { id: string } } }>,
    );

    const revised = await request(
      "http://localhost/v1/actions/revise_meal_proposal/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            proposalId: created.output.proposal.id,
            instruction: "Add 100 grams of zzzzzzz.",
            operations: [
              {
                type: "add_item",
                mention: {
                  originalText: "100 grams of zzzzzzz",
                  canonicalName: "zzzzzzz",
                  canonicalEnglishName: "zzzzzzz",
                  quantity: 100,
                  unit: "g",
                  rawUnitText: "grams",
                  unitKind: "metric",
                  confidence: 0.9,
                  marketProduct: false,
                },
              },
            ],
          },
          source: "flutter",
        }),
      },
    );

    expect(revised.status).toBe(200);
    const body = (await revised.json()) as {
      output: { clarificationRequired?: boolean; options?: unknown[] };
    };
    expect(body.output.clarificationRequired).toBe(true);
    expect(body.output.options).toBeDefined();
  });

  it("persists valid deletion when a correction also adds an unresolved food", async () => {
    const { request, repository } = buildTestApp();
    const recordFoodFeedback = vi.fn(async () => undefined);
    Object.assign(repository, { recordFoodFeedback });
    const auth = await registerAndAuth(request);
    const proposal = await createChickenBreadRiceButterProposal(
      request,
      auth.authHeader,
    );

    const revised = await request(
      "http://localhost/v1/actions/revise_meal_proposal/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            proposalId: proposal.id,
            instruction:
              "Add to this food 10 grams of red meat and delete the 100 grams of butter.",
            operations: [
              {
                type: "add_item",
                mention: redMeatMention(),
              },
              {
                type: "remove_item",
                matchText: "butter",
              },
            ],
          },
          source: "flutter",
        }),
      },
    );

    expect(revised.status).toBe(200);
    const body = (await revised.json()) as {
      output: {
        clarificationRequired?: boolean;
        message?: string;
        proposal: { id: string; status: string; items: MealItem[] };
        unresolvedMentions?: FoodMention[];
        options?: Array<{
          mention: FoodMention;
          candidates: MealItem[];
          reason?: string;
        }>;
      };
    };
    expect(body.output.clarificationRequired).toBe(true);
    expect(body.output.proposal.id).toBe(proposal.id);
    expect(body.output.proposal.status).toBe("corrected");
    expect(body.output.proposal.items.map((item) => item.name)).toEqual(
      expect.arrayContaining(["Chicken breast", "Bread", "Cooked rice"]),
    );
    expect(
      body.output.proposal.items.some((item) => item.name === "Butter"),
    ).toBe(false);
    expect(
      body.output.proposal.items.some((item) =>
        item.name.toLowerCase().includes("red meat"),
      ),
    ).toBe(false);
    expect(body.output.message).toContain("red meat");
    expect(body.output.unresolvedMentions).toEqual([
      expect.objectContaining({ canonicalEnglishName: "red meat" }),
    ]);
    expect(body.output.options).toEqual([
      expect.objectContaining({
        mention: expect.objectContaining({
          originalText: "10 grams of red meat",
          canonicalEnglishName: "red meat",
        }),
        candidates: [],
        reason: "no_database_match",
      }),
    ]);
    expect(recordFoodFeedback).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: auth.user.id,
        action: "corrected",
        metadata: expect.objectContaining({
          partial: true,
          appliedRevisionOperationCount: 1,
          unresolvedMentionCount: 1,
        }),
      }),
    );
  });

  it.each([
    {
      label: "without exact quantity",
      instruction: "Delete the butter.",
      operation: { type: "remove_item", matchText: "butter" },
    },
    {
      label: "with exact quantity by item index",
      instruction: "Delete the 100 grams of butter.",
      operation: { type: "remove_item", itemIndex: 3 },
    },
    {
      label: "with compact exact quantity",
      instruction: "Delete 100g butter.",
      operation: { type: "remove_item", matchText: "butter" },
    },
    {
      label: "with Spanish phrasing",
      instruction: "Elimina la mantequilla.",
      operation: { type: "remove_item", itemIndex: 3 },
    },
  ])("removes butter from a proposal $label", async ({ instruction, operation }) => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const proposal = await createChickenBreadRiceButterProposal(
      request,
      auth.authHeader,
    );

    const revised = await request(
      "http://localhost/v1/actions/revise_meal_proposal/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            proposalId: proposal.id,
            instruction,
            operations: [operation],
          },
          source: "flutter",
        }),
      },
    );

    expect(revised.status).toBe(200);
    const body = (await revised.json()) as {
      output: { proposal: { id: string; items: MealItem[] } };
    };
    expect(body.output.proposal.id).toBe(proposal.id);
    expect(body.output.proposal.items.map((item) => item.name)).toEqual(
      expect.arrayContaining(["Chicken breast", "Bread", "Cooked rice"]),
    );
    expect(
      body.output.proposal.items.some((item) => item.name === "Butter"),
    ).toBe(false);
  });

  it("creates a chicken and rice proposal, commits it, and includes it in the daily summary", async () => {
    const { request, repository } = buildTestApp();
    const recordFoodFeedback = vi.fn(async () => undefined);
    Object.assign(repository, { recordFoodFeedback });
    const auth = await registerAndAuth(request);

    const proposalResponse = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: chickenRiceInput,
          source: "flutter",
        }),
      },
    );
    expect(proposalResponse.status).toBe(200);
    const proposalEnvelope = (await proposalResponse.json()) as {
      output: {
        proposal: {
          id: string;
          title: string;
          items: unknown[];
        };
        options: Array<{ mention: { canonicalEnglishName: string } }>;
        candidateGroups: Array<{ mention: { canonicalEnglishName: string } }>;
      };
    };
    expect(proposalEnvelope.output.proposal.title).toBe(
      "Chicken breast and rice",
    );
    expect(proposalEnvelope.output.proposal.items).toHaveLength(2);
    expect(proposalEnvelope.output.options).toEqual([]);
    expect(proposalEnvelope.output.candidateGroups).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          mention: expect.objectContaining({
            canonicalEnglishName: "chicken breast",
          }),
        }),
        expect.objectContaining({
          mention: expect.objectContaining({ canonicalEnglishName: "rice" }),
        }),
      ]),
    );

    const commitResponse = await request(
      `http://localhost/v1/meals/proposals/${proposalEnvelope.output.proposal.id}/commit`,
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({}),
      },
    );
    expect(commitResponse.status).toBe(200);
    const committed = (await commitResponse.json()) as {
      output: { meal: { id: string; nutrition: { calories: number } } };
    };
    expect(committed.output.meal.nutrition.calories).toBeGreaterThan(250);
    expect(recordFoodFeedback).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: auth.user.id,
        action: "logged",
        metadata: expect.objectContaining({
          eventType: "proposal_committed",
          proposalId: proposalEnvelope.output.proposal.id,
          mealId: committed.output.meal.id,
        }),
      }),
    );

    const summary = await request(
      `http://localhost/v1/summary/daily?date=${new Date().toISOString().slice(0, 10)}`,
      {
        headers: auth.authHeader,
      },
    );
    const summaryBody = (await summary.json()) as {
      output: { summary: { meals: unknown[]; consumed: { calories: number } } };
    };
    expect(summaryBody.output.summary.meals).toHaveLength(1);
    expect(summaryBody.output.summary.consumed.calories).toBe(
      committed.output.meal.nutrition.calories,
    );

    const calls = await repository.listActionCalls(auth.user.id);
    const audits = await repository.listAuditEvents(auth.user.id);
    expect(calls.some((call) => call.actionId === "commit_meal")).toBe(true);
    expect(
      audits.some((event) => event.eventType === "action.commit_meal"),
    ).toBe(true);
  });

  it("updates daily goals and keeps previous day target snapshots", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const today = dateOffset(0);
    const yesterday = dateOffset(-1);

    const initialGoals = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: yesterday,
        calories: 1800,
        hydrationGoalLiters: 2.5,
      }),
    });
    expect(initialGoals.status).toBe(200);

    const yesterdayBefore = await request(
      `http://localhost/v1/summary/daily?date=${yesterday}`,
      { headers: auth.authHeader },
    ).then(
      (response) =>
        response.json() as Promise<{
          output: {
            summary: {
              target: { calories: number };
              hydrationGoalLiters: number;
            };
          };
        }>,
    );
    expect(yesterdayBefore.output.summary.target.calories).toBe(1800);
    expect(yesterdayBefore.output.summary.hydrationGoalLiters).toBe(2.5);

    const todayGoals = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: today,
        calories: 2400,
        hydrationGoalLiters: 3,
      }),
    });
    expect(todayGoals.status).toBe(200);

    const yesterdayAfter = await request(
      `http://localhost/v1/summary/daily?date=${yesterday}`,
      { headers: auth.authHeader },
    ).then(
      (response) =>
        response.json() as Promise<{
          output: {
            summary: {
              target: { calories: number };
              hydrationGoalLiters: number;
            };
          };
        }>,
    );
    const todayAfter = await request(
      `http://localhost/v1/summary/daily?date=${today}`,
      { headers: auth.authHeader },
    ).then(
      (response) =>
        response.json() as Promise<{
          output: {
            summary: {
              target: { calories: number };
              hydrationGoalLiters: number;
            };
          };
        }>,
    );

    expect(yesterdayAfter.output.summary.target.calories).toBe(1800);
    expect(yesterdayAfter.output.summary.hydrationGoalLiters).toBe(2.5);
    expect(todayAfter.output.summary.target.calories).toBe(2400);
    expect(todayAfter.output.summary.hydrationGoalLiters).toBe(3);
  });

  it("starts new users without a configured calorie target and marks calories configured when saved", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const today = dateOffset(0);

    const initialSummary = await request(
      `http://localhost/v1/summary/daily?date=${today}`,
      { headers: auth.authHeader },
    ).then(
      (response) =>
        response.json() as Promise<{
          output: {
            summary: {
              calorieTargetConfigured: boolean;
              calorieTargetSource: string;
              target: {
                calories: number;
                proteinGrams: number;
                carbsGrams: number;
                fatGrams: number;
              };
              remaining: {
                proteinGrams: number;
                carbsGrams: number;
                fatGrams: number;
              };
              macroMode?: string;
              hydrationGoalLiters: number;
              waterConsumedLiters: number;
            };
          };
        }>,
    );

    expect(initialSummary.output.summary.target.calories).toBe(2200);
    expect(initialSummary.output.summary.target.proteinGrams).toBe(0);
    expect(initialSummary.output.summary.target.carbsGrams).toBe(0);
    expect(initialSummary.output.summary.target.fatGrams).toBe(0);
    expect(initialSummary.output.summary.remaining.proteinGrams).toBe(0);
    expect(initialSummary.output.summary.remaining.carbsGrams).toBe(0);
    expect(initialSummary.output.summary.remaining.fatGrams).toBe(0);
    expect(initialSummary.output.summary.macroMode).toBeUndefined();
    expect(initialSummary.output.summary.calorieTargetConfigured).toBe(false);
    expect(initialSummary.output.summary.calorieTargetSource).toBe("default");
    expect(initialSummary.output.summary.hydrationGoalLiters).toBe(0);
    expect(initialSummary.output.summary.waterConsumedLiters).toBe(0);

    const update = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: today,
        calories: 1900,
        calorieTargetSource: "calculator",
      }),
    });
    expect(update.status).toBe(200);

    const updatedSummary = await request(
      `http://localhost/v1/summary/daily?date=${today}`,
      { headers: auth.authHeader },
    ).then(
      (response) =>
        response.json() as Promise<{
          output: {
            summary: {
              calorieTargetConfigured: boolean;
              calorieTargetSource: string;
              target: {
                calories: number;
                proteinGrams: number;
                carbsGrams: number;
                fatGrams: number;
              };
              remaining: {
                proteinGrams: number;
                carbsGrams: number;
                fatGrams: number;
              };
              macroMode?: string;
            };
          };
        }>,
    );
    expect(updatedSummary.output.summary.target.calories).toBe(1900);
    expect(updatedSummary.output.summary.target.proteinGrams).toBe(0);
    expect(updatedSummary.output.summary.target.carbsGrams).toBe(0);
    expect(updatedSummary.output.summary.target.fatGrams).toBe(0);
    expect(updatedSummary.output.summary.remaining.proteinGrams).toBe(0);
    expect(updatedSummary.output.summary.remaining.carbsGrams).toBe(0);
    expect(updatedSummary.output.summary.remaining.fatGrams).toBe(0);
    expect(updatedSummary.output.summary.macroMode).toBeUndefined();
    expect(updatedSummary.output.summary.calorieTargetConfigured).toBe(true);
    expect(updatedSummary.output.summary.calorieTargetSource).toBe("calculator");
  });

  it("updates daily hydration in quarter-liter steps and clamps to the configured goal", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const today = dateOffset(0);

    const invalidGoal = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: today,
        hydrationGoalLiters: 1.3,
      }),
    });
    expect(invalidGoal.status).toBe(400);

    const goal = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: today,
        hydrationGoalLiters: 2.5,
      }),
    });
    expect(goal.status).toBe(200);

    const water = await request("http://localhost/v1/hydration/daily", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: today,
        waterConsumedLiters: 1.25,
      }),
    }).then(
      (response) =>
        response.json() as Promise<{
          summary: { hydrationGoalLiters: number; waterConsumedLiters: number };
        }>,
    );
    expect(water.summary.hydrationGoalLiters).toBe(2.5);
    expect(water.summary.waterConsumedLiters).toBe(1.25);

    const clamped = await request("http://localhost/v1/hydration/daily", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: today,
        waterConsumedLiters: 9,
      }),
    }).then(
      (response) =>
        response.json() as Promise<{
          summary: { hydrationGoalLiters: number; waterConsumedLiters: number };
        }>,
    );
    expect(clamped.summary.waterConsumedLiters).toBe(2.5);

    const loweredGoal = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: today,
        hydrationGoalLiters: 1,
      }),
    });
    expect(loweredGoal.status).toBe(200);

    const lowered = await request(
      `http://localhost/v1/summary/daily?date=${today}`,
      { headers: auth.authHeader },
    ).then(
      (response) =>
        response.json() as Promise<{
          output: {
            summary: { hydrationGoalLiters: number; waterConsumedLiters: number };
          };
        }>,
    );
    expect(lowered.output.summary.hydrationGoalLiters).toBe(1);
    expect(lowered.output.summary.waterConsumedLiters).toBe(1);
  });

  it("commits optional meal labels and exposes them in summaries", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const labels = [
      { type: "breakfast", label: "Breakfast" },
      { type: "lunch", label: "Lunch" },
      { type: "dinner", label: "Dinner" },
      { type: "snack", label: "Snack" },
      { type: "pre_workout", label: "Pre-workout" },
      { type: "post_workout", label: "Post-workout" },
      { type: "other", label: "Brunch" },
      null,
    ];

    for (const label of labels) {
      const proposal = await request(
        "http://localhost/v1/actions/create_meal_proposal_from_items/execute",
        {
          method: "POST",
          headers: auth.authHeader,
          body: JSON.stringify({
            input: {
              phrase: `selected food match ${label?.label ?? "none"}`,
              title: label?.label ?? "Unlabeled meal",
              items: [testBreadItem],
            },
            source: "flutter",
          }),
        },
      ).then(
        (response) =>
          response.json() as Promise<{ output: { proposal: { id: string } } }>,
      );

      const committed = await request(
        `http://localhost/v1/meals/proposals/${proposal.output.proposal.id}/commit`,
        {
          method: "POST",
          headers: auth.authHeader,
          body: JSON.stringify({ mealLabel: label }),
        },
      );
      expect(committed.status).toBe(200);
      const body = (await committed.json()) as {
        output: {
          meal: {
            mealLabel: { type: string; label: string } | null;
          };
        };
      };
      expect(body.output.meal.mealLabel).toEqual(label);
    }

    const summary = await request(
      `http://localhost/v1/summary/daily?date=${new Date().toISOString().slice(0, 10)}`,
      { headers: auth.authHeader },
    );
    const summaryBody = (await summary.json()) as {
      output: {
        summary: {
          meals: Array<{ mealLabel: { label: string } | null }>;
        };
      };
    };
    expect(summaryBody.output.summary.meals).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          mealLabel: { type: "breakfast", label: "Breakfast" },
        }),
        expect.objectContaining({
          mealLabel: { type: "other", label: "Brunch" },
        }),
        expect.objectContaining({ mealLabel: null }),
      ]),
    );
  });

  it("rejects empty custom meal labels", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const proposal = await request(
      "http://localhost/v1/actions/create_meal_proposal_from_items/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            phrase: "selected food match",
            items: [testBreadItem],
          },
          source: "flutter",
        }),
      },
    ).then(
      (response) =>
        response.json() as Promise<{ output: { proposal: { id: string } } }>,
    );

    const committed = await request(
      `http://localhost/v1/meals/proposals/${proposal.output.proposal.id}/commit`,
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({ mealLabel: { type: "other", label: "   " } }),
      },
    );

    expect(committed.status).toBe(400);
  });

  it("preserves explicit gram quantities for meat and rice", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const proposalResponse = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: chickenRiceInput,
          source: "flutter",
        }),
      },
    );

    expect(proposalResponse.status).toBe(200);
    const body = (await proposalResponse.json()) as {
      output: {
        proposal: {
          items: { name: string; quantity: number }[];
        };
      };
    };
    expect(body.output.proposal.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: "Chicken breast", quantity: 100 }),
        expect.objectContaining({ name: "Cooked rice", quantity: 100 }),
      ]),
    );
  });

  it("creates a proposal for every item in comma-separated metric input", async () => {
    const { request, repository } = buildTestApp();
    await repository.upsertFoodItem({
      name: "Meat",
      normalizedName: "meat",
      canonicalName: "meat",
      source: "test_fixture",
      servingGrams: 100,
      calories: 250,
      proteinGrams: 26,
      carbsGrams: 0,
      fatGrams: 15,
    });
    const auth = await registerAndAuth(request);

    const proposalResponse = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            text: "Add 100 grams of chicken, 100 grams of rice and 100 grams of meat.",
            mentions: [
              mention("chicken", 100, {
                originalText: "100 grams of chicken",
              }),
              mention("rice", 100, { originalText: "100 grams of rice" }),
              mention("meat", 100, { originalText: "100 grams of meat" }),
            ],
          },
          source: "flutter",
        }),
      },
    );

    expect(proposalResponse.status).toBe(200);
    const body = (await proposalResponse.json()) as {
      output: {
        clarificationRequired?: boolean;
        proposal: {
          items: { name: string; quantity: number; unit: string }[];
        };
      };
    };
    expect(body.output.clarificationRequired).not.toBe(true);
    expect(body.output.proposal.items).toHaveLength(3);
    expect(body.output.proposal.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          name: "Chicken breast",
          quantity: 100,
          unit: "g",
        }),
        expect.objectContaining({
          name: "Cooked rice",
          quantity: 100,
          unit: "g",
        }),
        expect.objectContaining({ name: "Meat", quantity: 100, unit: "g" }),
      ]),
    );
  });

  it("limits meal clarification options to the unresolved ingredients only", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const proposalResponse = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            text: "Add 100 grams of rice, 100 grams of beef, 100 grams of butter and 100 grams of bread.",
            mentions: [
              mention("rice", 100, { originalText: "100 grams of rice" }),
              mention("beef", 100, { originalText: "100 grams of beef" }),
              mention("butter", 100, {
                originalText: "100 grams of butter",
              }),
              mention("bread", 100, { originalText: "100 grams of bread" }),
            ],
          },
          source: "flutter",
        }),
      },
    );

    expect(proposalResponse.status).toBe(200);
    const body = (await proposalResponse.json()) as {
      output: {
        clarificationRequired?: boolean;
        message?: string;
        proposal?: { items: Array<{ name: string }> };
        resolvedItems?: Array<{ name: string }>;
        unresolvedMentions?: FoodMention[];
        options?: Array<{
          mention: FoodMention;
          candidates: MealItem[];
          reason?: string;
        }>;
        candidateGroups?: Array<{
          mention: FoodMention;
          candidates: MealItem[];
          reason?: string;
        }>;
      };
    };
    expect(body.output.clarificationRequired).toBe(true);
    expect(body.output.proposal?.items.map((item) => item.name)).toEqual(
      expect.arrayContaining(["Cooked rice", "Butter", "Bread"]),
    );
    expect(body.output.resolvedItems?.map((item) => item.name)).toEqual(
      expect.arrayContaining(["Cooked rice", "Butter", "Bread"]),
    );
    expect(body.output.unresolvedMentions).toEqual([
      expect.objectContaining({ canonicalEnglishName: "beef" }),
    ]);
    expect(body.output.options).toEqual([
      expect.objectContaining({
        mention: expect.objectContaining({ canonicalEnglishName: "beef" }),
        reason: "no_database_match",
      }),
    ]);
    expect(body.output.candidateGroups).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          mention: expect.objectContaining({ canonicalEnglishName: "rice" }),
        }),
        expect.objectContaining({
          mention: expect.objectContaining({ canonicalEnglishName: "beef" }),
        }),
        expect.objectContaining({
          mention: expect.objectContaining({ canonicalEnglishName: "butter" }),
        }),
        expect.objectContaining({
          mention: expect.objectContaining({ canonicalEnglishName: "bread" }),
        }),
      ]),
    );
    expect(body.output.message).toContain("beef");
    expect(body.output.message).not.toContain("rice");
    expect(body.output.message).not.toContain("butter");
    expect(body.output.message).not.toContain("bread");
  });

  it("uses model-provided food mentions directly", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const proposalResponse = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            text: "He comido 100 gramos de pollo y 100 gramos de arroz",
            mentions: [
              {
                originalText: "100 gramos de pollo",
                canonicalName: "pollo",
                canonicalEnglishName: "chicken breast",
                language: "es",
                quantity: 100,
                unit: "g",
                rawUnitText: "gramos",
                unitKind: "metric",
                confidence: 0.95,
                marketProduct: false,
              },
              {
                originalText: "100 gramos de arroz",
                canonicalName: "arroz",
                canonicalEnglishName: "rice",
                language: "es",
                quantity: 100,
                unit: "g",
                rawUnitText: "gramos",
                unitKind: "metric",
                confidence: 0.95,
                marketProduct: false,
              },
            ],
          },
          source: "flutter",
        }),
      },
    );

    expect(proposalResponse.status).toBe(200);
    const body = (await proposalResponse.json()) as {
      output: {
        proposal: {
          title: string;
          items: {
            name: string;
            canonicalName?: string;
            language?: string;
            quantity: number;
          }[];
        };
        instrumentation: {
          inputMode: string;
          phasesMs: Record<string, number>;
        };
      };
    };
    expect(body.output.instrumentation.inputMode).toBe("model_mentions");
    expect(body.output.instrumentation.phasesMs).toHaveProperty(
      "resolve_provided_mentions",
    );
    expect(body.output.proposal.title).toBe("Pollo y arroz");
    expect(body.output.proposal.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: "Chicken breast", quantity: 100 }),
        expect.objectContaining({ name: "Cooked rice", quantity: 100 }),
      ]),
    );
    expect(body.output.proposal.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ canonicalName: "pollo", language: "es" }),
        expect.objectContaining({ canonicalName: "arroz", language: "es" }),
      ]),
    );
  });

  it("keeps same-language Spanish connectors after corrections", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const created = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            text: "Añade 100 gramos de pollo, 100 gramos de arroz y 100 gramos de pan",
            mentions: [
              mention("chicken breast", 100, {
                originalText: "100 gramos de pollo",
                canonicalName: "pollo",
                language: "es",
                rawUnitText: "gramos",
              }),
              mention("rice", 100, {
                originalText: "100 gramos de arroz",
                canonicalName: "arroz",
                language: "es",
                rawUnitText: "gramos",
              }),
              mention("bread", 100, {
                originalText: "100 gramos de pan",
                canonicalName: "pan",
                language: "es",
                rawUnitText: "gramos",
              }),
            ],
          },
          source: "flutter",
        }),
      },
    );
    expect(created.status).toBe(200);
    const createdBody = (await created.json()) as {
      output: { proposal: { id: string; title: string } };
    };
    expect(createdBody.output.proposal.title).toBe("Pollo, arroz y pan");

    const revised = await request(
      "http://localhost/v1/actions/revise_meal_proposal/execute",
      {
        method: "POST",
        headers: { ...auth.authHeader, "accept-language": "en-US" },
        body: JSON.stringify({
          input: {
            proposalId: createdBody.output.proposal.id,
            instruction: "Remove the chicken.",
            operations: [{ type: "remove_item", itemIndex: 0 }],
          },
          source: "flutter",
        }),
      },
    );
    expect(revised.status).toBe(200);
    const revisedBody = (await revised.json()) as {
      output: { proposal: { title: string } };
    };
    expect(revisedBody.output.proposal.title).toBe("Arroz y pan");
  });

  it("uses comma-only titles when corrections create mixed ingredient languages", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const created = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: { ...auth.authHeader, "accept-language": "en-US" },
        body: JSON.stringify({
          input: chickenRiceInput,
          source: "flutter",
        }),
      },
    );
    expect(created.status).toBe(200);
    const createdBody = (await created.json()) as {
      output: { proposal: { id: string; title: string } };
    };
    expect(createdBody.output.proposal.title).toBe("Chicken breast and rice");

    const revised = await request(
      "http://localhost/v1/actions/revise_meal_proposal/execute",
      {
        method: "POST",
        headers: { ...auth.authHeader, "accept-language": "es-ES" },
        body: JSON.stringify({
          input: {
            proposalId: createdBody.output.proposal.id,
            instruction: "Añade 100 gramos de pan.",
            operations: [
              {
                type: "add_item",
                mention: mention("bread", 100, {
                  originalText: "100 gramos de pan",
                  canonicalName: "pan",
                  language: "es",
                  rawUnitText: "gramos",
                }),
              },
            ],
          },
          source: "flutter",
        }),
      },
    );
    expect(revised.status).toBe(200);
    const revisedBody = (await revised.json()) as {
      output: { proposal: { title: string } };
    };
    expect(revisedBody.output.proposal.title).toBe(
      "Chicken breast, rice, pan",
    );
  });

  it("requires clarification instead of creating a proposal for unsupported food units", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const proposalResponse = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            text: "Add 1 rice",
            mentions: [
              mention("rice", 1, {
                originalText: "1 rice",
                unit: "rice",
                rawUnitText: "rice",
                unitKind: "implicit_count",
              }),
            ],
          },
          source: "flutter",
        }),
      },
    );

    expect(proposalResponse.status).toBe(200);
    const body = (await proposalResponse.json()) as {
      output: {
        clarificationRequired: boolean;
        proposal?: unknown;
        message: string;
        options: Array<{ reason?: string }>;
      };
    };
    expect(body.output.clarificationRequired).toBe(true);
    expect(body.output.proposal).toBeUndefined();
    expect(body.output.message).toContain("1 rice");
    expect(body.output.options).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ reason: "unsupported_unit" }),
      ]),
    );
  });

  it("returns grouped candidates for nutrition database search", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const response = await request(
      "http://localhost/v1/actions/search_nutrition_database/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: { query: "bread" },
          source: "flutter",
        }),
      },
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      output: {
        items: Array<{ name: string }>;
        candidates: Array<{
          mention: { canonicalEnglishName: string };
          candidates: Array<{ name: string; rank?: number }>;
        }>;
        candidateGroups: Array<{
          mention: { canonicalEnglishName: string };
          candidates: Array<{ name: string; rank?: number }>;
        }>;
      };
    };
    expect(body.output.items.some((item) => item.name === "Bread")).toBe(true);
    expect(body.output.candidates[0]).toEqual(
      expect.objectContaining({
        mention: expect.objectContaining({ canonicalEnglishName: "bread" }),
        candidates: expect.arrayContaining([
          expect.objectContaining({ name: "Bread", rank: 1 }),
        ]),
      }),
    );
    expect(body.output.candidateGroups).toEqual(body.output.candidates);
  });

  it("corrects a committed meal with an explicit item list", async () => {
    const { request, repository } = buildTestApp();
    const recordFoodFeedback = vi.fn(async () => undefined);
    Object.assign(repository, { recordFoodFeedback });
    const auth = await registerAndAuth(request);
    const proposal = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: chickenRiceInput,
          source: "flutter",
        }),
      },
    ).then(
      (response) =>
        response.json() as Promise<{ output: { proposal: { id: string } } }>,
    );
    const meal = await request(
      `http://localhost/v1/meals/proposals/${proposal.output.proposal.id}/commit`,
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({}),
      },
    ).then(
      (response) =>
        response.json() as Promise<{
          output: {
            meal: {
              id: string;
              nutrition: { calories: number };
              items: Array<Record<string, unknown>>;
            };
          };
        }>,
    );

    const editedItems = meal.output.meal.items.map((item) => {
      if (item.name !== "Chicken breast") return item;
      return {
        ...item,
        quantity: 200,
        calories: 330,
        proteinGrams: 62,
        carbsGrams: 0,
        fatGrams: 7.2,
      };
    });

    const corrected = await request(
      `http://localhost/v1/meals/${meal.output.meal.id}/correct`,
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({ items: editedItems }),
      },
    );
    expect(corrected.status).toBe(200);
    const body = (await corrected.json()) as {
      output: {
        meal: {
          nutrition: { calories: number };
          items: { name: string; quantity: number }[];
        };
      };
    };
    expect(
      body.output.meal.items.find((item) => item.name === "Chicken breast")
        ?.quantity,
    ).toBe(200);
    expect(body.output.meal.nutrition.calories).toBeGreaterThan(
      meal.output.meal.nutrition.calories,
    );
    expect(recordFoodFeedback).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: auth.user.id,
        action: "corrected",
        metadata: expect.objectContaining({
          eventType: "meal_corrected",
          mealId: meal.output.meal.id,
          itemName: "Chicken breast",
        }),
      }),
    );
  });

  it("rejects text-only meal corrections", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const proposal = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: chickenRiceInput,
          source: "flutter",
        }),
      },
    ).then(
      (response) =>
        response.json() as Promise<{ output: { proposal: { id: string } } }>,
    );
    const meal = await request(
      `http://localhost/v1/meals/proposals/${proposal.output.proposal.id}/commit`,
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({}),
      },
    ).then(
      (response) =>
        response.json() as Promise<{ output: { meal: { id: string } } }>,
    );

    const corrected = await request(
      `http://localhost/v1/meals/${meal.output.meal.id}/correct`,
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          correctionText: "No, the chicken was 200 grams.",
        }),
      },
    );

    expect(corrected.status).toBe(400);
  });

  it("requires confirmation token before deleting a meal", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);
    const proposal = await request(
      "http://localhost/v1/actions/propose_meal_log/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            text: "two eggs",
            mentions: [
              mention("egg", 2, {
                originalText: "two eggs",
                unit: "egg",
                rawUnitText: "eggs",
                unitKind: "implicit_count",
              }),
            ],
          },
          source: "flutter",
        }),
      },
    ).then(
      (response) =>
        response.json() as Promise<{ output: { proposal: { id: string } } }>,
    );
    const meal = await request(
      `http://localhost/v1/meals/proposals/${proposal.output.proposal.id}/commit`,
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({}),
      },
    ).then(
      (response) =>
        response.json() as Promise<{ output: { meal: { id: string } } }>,
    );

    const firstDelete = await request(
      `http://localhost/v1/meals/${meal.output.meal.id}`,
      { method: "DELETE", headers: auth.authHeader },
    );
    const firstBody = (await firstDelete.json()) as {
      output: { deleted: boolean; confirmationRequired: boolean };
    };
    expect(firstBody.output).toEqual({
      deleted: false,
      confirmationRequired: true,
    });

    const confirmedDelete = await request(
      `http://localhost/v1/meals/${meal.output.meal.id}?confirmationToken=DELETE`,
      { method: "DELETE", headers: auth.authHeader },
    );
    const confirmedBody = (await confirmedDelete.json()) as {
      output: { deleted: boolean; confirmationRequired: boolean };
    };
    expect(confirmedBody.output).toEqual({
      deleted: true,
      confirmationRequired: false,
    });
  });

  it("always returns a proposal for usual meals even when legacy trusted switches are enabled", async () => {
    const { request, repository } = buildTestApp();
    const auth = await registerAndAuth(request);

    const settings = await request("http://localhost/v1/settings", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({ trustedModeEnabled: true }),
    });
    expect(settings.status).toBe(200);

    await createTestUsualBreakfastTemplate(request, auth.authHeader);
    const templates = await request("http://localhost/v1/meal-templates", {
      headers: auth.authHeader,
    }).then(
      (response) =>
        response.json() as Promise<{
          output: {
            templates: { id: string; items: unknown[]; aliases: string[] }[];
          };
        }>,
    );
    const breakfast = templates.output.templates[0]!;

    const update = await request(
      "http://localhost/v1/actions/update_meal_template/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({
          input: {
            templateId: breakfast.id,
            trustedAutoCommitEnabled: true,
            aliases: breakfast.aliases,
            items: breakfast.items,
          },
          source: "flutter",
        }),
      },
    );
    expect(update.status).toBe(200);

    const run = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({
        text: "I had my usual breakfast.",
        source: "flutter",
      }),
    });
    expect(run.status).toBe(200);
    const body = (await run.json()) as {
      proposal?: { id: string; requiresConfirmation: boolean };
      meal?: { id: string };
      message: string;
    };
    expect(body.meal).toBeUndefined();
    expect(body.proposal?.id).toBeTruthy();
    expect(body.proposal?.requiresConfirmation).toBe(true);
    expect(body.message).toMatch(/proposal created/i);

    const audits = await repository.listAuditEvents(auth.user.id);
    expect(
      audits.some(
        (event) => event.eventType === "trusted_auto_commit.meal_committed",
      ),
    ).toBe(false);
  });
});

function dateOffset(days: number) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
