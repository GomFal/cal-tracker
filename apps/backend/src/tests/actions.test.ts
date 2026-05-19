import { describe, expect, it, vi } from "vitest";
import type { FoodMention } from "@cal-tracker/contracts";
import {
  buildTestApp,
  createTestUsualBreakfastTemplate,
  registerAndAuth,
  testBreadItem,
} from "./testApp.js";

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
          input: {
            text: "Add 100 grams of chicken breast and 100 grams of rice",
          },
          source: "flutter",
        }),
      },
    );
    expect(proposalResponse.status).toBe(200);
    const proposalEnvelope = (await proposalResponse.json()) as {
      output: {
        proposal: { id: string; title: string; items: unknown[] };
        options: Array<{ mention: { canonicalEnglishName: string } }>;
        candidateGroups: Array<{ mention: { canonicalEnglishName: string } }>;
      };
    };
    expect(proposalEnvelope.output.proposal.title).toBe("Chicken and rice");
    expect(proposalEnvelope.output.proposal.items).toHaveLength(2);
    expect(proposalEnvelope.output.options).toEqual(
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
    expect(proposalEnvelope.output.candidateGroups).toEqual(
      proposalEnvelope.output.options,
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
        hydrationGoalGlasses: 10,
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
              hydrationGoalGlasses: number;
            };
          };
        }>,
    );
    expect(yesterdayBefore.output.summary.target.calories).toBe(1800);
    expect(yesterdayBefore.output.summary.hydrationGoalGlasses).toBe(10);

    const todayGoals = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: today,
        calories: 2400,
        hydrationGoalGlasses: 14,
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
              hydrationGoalGlasses: number;
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
              hydrationGoalGlasses: number;
            };
          };
        }>,
    );

    expect(yesterdayAfter.output.summary.target.calories).toBe(1800);
    expect(yesterdayAfter.output.summary.hydrationGoalGlasses).toBe(10);
    expect(todayAfter.output.summary.target.calories).toBe(2400);
    expect(todayAfter.output.summary.hydrationGoalGlasses).toBe(14);
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
          input: {
            text: "Add 100 grams of chicken breast and 100 grams of rice",
          },
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

  it("uses model-provided food mentions without extracting text again", async () => {
    const throwingExtractor = {
      async extract(): Promise<FoodMention[]> {
        throw new Error("text extractor should not be called");
      },
    };
    const { request } = buildTestApp({ foodTextExtractor: throwingExtractor });
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
          items: { name: string; canonicalName?: string; quantity: number }[];
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
    expect(body.output.instrumentation.phasesMs).not.toHaveProperty(
      "resolve_meal_text",
    );
    expect(body.output.proposal.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: "Chicken breast", quantity: 100 }),
        expect.objectContaining({ name: "Cooked rice", quantity: 100 }),
      ]),
    );
    expect(body.output.proposal.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ canonicalName: "pollo" }),
        expect.objectContaining({ canonicalName: "arroz" }),
      ]),
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
          input: { text: "Add 1 rice" },
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
          input: {
            text: "Add 100 grams of chicken breast and 100 grams of rice",
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
          input: {
            text: "Add 100 grams of chicken breast and 100 grams of rice",
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
          input: { text: "two eggs" },
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
