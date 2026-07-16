import { describe, expect, it } from "vitest";
import type {
  DraftUsualMealProviderOutput,
  FoodMention,
  MealItem,
} from "@cal-tracker/contracts";
import type {
  AgentMessage,
  AgentToolDecision,
  ChatAgentProvider,
} from "../agent/chatAgentProvider.js";
import type { UsualMealDraftProvider } from "../agent/usualMealDraftProvider.js";
import {
  buildTestApp,
  createTestUsualBreakfastTemplate,
  FakeChatAgentProvider,
  registerAndAuth,
  testBreadItem,
} from "./testApp.js";

class QueueChatAgentProvider implements ChatAgentProvider {
  constructor(private readonly decisions: AgentToolDecision[] = []) {}

  push(decision: AgentToolDecision): void {
    this.decisions.push(decision);
  }

  async runWithTools(): Promise<AgentToolDecision> {
    const decision = this.decisions.shift();
    if (!decision) throw new Error("missing_fake_agent_decision");
    return decision;
  }
}

class CapturingChatAgentProvider implements ChatAgentProvider {
  public messages: AgentMessage[] = [];

  constructor(private readonly decision: AgentToolDecision) {}

  async runWithTools(input: {
    messages: AgentMessage[];
  }): Promise<AgentToolDecision> {
    this.messages = input.messages;
    return this.decision;
  }
}

class ThrowingChatAgentProvider implements ChatAgentProvider {
  async runWithTools(): Promise<AgentToolDecision> {
    throw new Error("provider_unavailable");
  }
}

class FakeUsualMealDraftProvider implements UsualMealDraftProvider {
  constructor(private readonly output: DraftUsualMealProviderOutput) {}

  async draft(): Promise<DraftUsualMealProviderOutput> {
    return this.output;
  }
}

const testRiceItem: MealItem = {
  name: "Cooked rice",
  quantity: 100,
  unit: "g",
  calories: 130,
  proteinGrams: 2.7,
  carbsGrams: 28,
  fatGrams: 0.3,
  source: "test_fixture",
  originalText: "100 grams of rice",
  canonicalName: "rice",
  confidence: 0.9,
};

const testChickenItem: MealItem = {
  name: "Chicken breast",
  quantity: 100,
  unit: "g",
  calories: 165,
  proteinGrams: 31,
  carbsGrams: 0,
  fatGrams: 3.6,
  source: "test_fixture",
  originalText: "100 grams of chicken breast",
  canonicalName: "chicken breast",
  confidence: 0.9,
};

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
    ...overrides,
  };
}

async function createProposalFromItems(
  request: (input: string, init?: RequestInit) => Promise<Response>,
  authHeader: Record<string, string>,
  items: MealItem[],
  phrase = "test proposal",
): Promise<{ id: string; items: MealItem[] }> {
  const response = await request(
    "http://localhost/v1/actions/create_meal_proposal_from_items/execute",
    {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        input: { phrase, items },
        source: "flutter",
      }),
    },
  );
  expect(response.status).toBe(200);
  const body = (await response.json()) as {
    output: { proposal: { id: string; items: MealItem[] } };
  };
  return body.output.proposal;
}

describe("AgentService", () => {
  it("passes Accept-Language through to the LLM context locale", async () => {
    const agentProvider = new CapturingChatAgentProvider({
      toolCalls: [
        {
          id: "call_1",
          type: "function",
          function: {
            name: "get_remaining_targets",
            arguments: JSON.stringify({}),
          },
        },
      ],
      rawResponse: {},
    });
    const { request } = buildTestApp({ agentProvider });
    const { authHeader } = await registerAndAuth(request);

    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: { ...authHeader, "accept-language": "pt-BR" },
      body: JSON.stringify({
        text: "how many calories do I have left",
        source: "flutter",
      }),
    });

    expect(res.status).toBe(200);
    expect(agentProvider.messages[0]?.content).toContain(
      "The user's locale is pt-BR",
    );
  });

  it("maps chicken and rice with quantities to propose_meal_log", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "propose_meal_log",
              arguments: JSON.stringify({
                text: "Add 100 grams of chicken breast and 100 grams of rice",
                mentions: [
                  {
                    originalText: "100 grams of chicken breast",
                    canonicalEnglishName: "chicken breast",
                    quantity: 100,
                    unit: "g",
                    rawUnitText: "grams",
                    unitKind: "metric",
                    confidence: 0.95,
                  },
                  {
                    originalText: "100 grams of rice",
                    canonicalEnglishName: "rice",
                    quantity: 100,
                    unit: "g",
                    rawUnitText: "grams",
                    unitKind: "metric",
                    confidence: 0.95,
                  },
                ],
              }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const auth = await registerAndAuth(request);
    const { authHeader } = auth;
    await createTestUsualBreakfastTemplate(request, authHeader);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of chicken breast and 100 grams of rice",
        source: "flutter",
      }),
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      kind: string;
      proposal?: unknown;
      message: string;
      options?: Array<{ mention: { canonicalEnglishName: string } }>;
      candidateGroups?: Array<{ mention: { canonicalEnglishName: string } }>;
    };
    expect(body.kind).toBe("proposal");
    expect(body.proposal).toBeDefined();
    expect(body.message).toBe("Meal proposal created.");
    expect(body.options).toBeUndefined();
    expect(body.candidateGroups).toEqual(
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
  });

  it("does not override the model-selected tool with meal logging heuristics", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "search_nutrition_database",
              arguments: JSON.stringify({ query: "bread butter" }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const auth = await registerAndAuth(request);
    const { authHeader } = auth;
    await createTestUsualBreakfastTemplate(request, authHeader);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "I want to add a breakfast with 100g of bread and 20g of butter",
        source: "flutter",
      }),
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      kind: string;
      items: { name: string }[];
    };
    expect(body.kind).toBe("nutrition_search");
    expect(body.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: "Bread" }),
        expect.objectContaining({ name: "Butter" }),
      ]),
    );
  });

  it("asks for clarification when the model returns no tool", async () => {
    const { request, repository } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [],
        rawResponse: {},
      }),
    });
    await repository.upsertFoodItem({
      name: "Pechuga de pollo",
      normalizedName: "pechuga de pollo",
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
      name: "Arroz",
      normalizedName: "arroz",
      canonicalName: "arroz",
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
    const auth = await registerAndAuth(request);
    const { authHeader } = auth;
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: { ...authHeader, "accept-language": "es-ES" },
      body: JSON.stringify({
        text: "Añádeme 200 gramos de pechuga de pollo y 300 gramos de arroz por favor",
        source: "flutter",
      }),
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      kind: string;
      message: string;
      proposal?: unknown;
    };
    expect(body.kind).toBe("clarification_required");
    expect(body.proposal).toBeUndefined();
    expect(body.message).toContain("rephrase");
  });

  it("uses model-provided bread and ham mentions for a complete proposal", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "propose_meal_log",
              arguments: JSON.stringify({
                text: "Add 100 grams of bread and 100 grams of ham.",
                mentions: [
                  mention("bread", 100, {
                    originalText: "100 grams of bread",
                  }),
                  mention("ham", 100, { originalText: "100 grams of ham" }),
                ],
              }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of bread and 100 grams of ham.",
        source: "flutter",
      }),
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      kind: string;
      proposal: {
        title: string;
        items: { name: string; quantity: number }[];
      };
    };
    expect(body.kind).toBe("proposal");
    expect(body.proposal.title).toBe("Bread and ham");
    expect(body.proposal.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: "Bread", quantity: 100 }),
        expect.objectContaining({ name: "Ham", quantity: 100 }),
      ]),
    );
  });

  it("rejects malformed model mentions instead of parsing raw text", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "propose_meal_log",
              arguments: JSON.stringify({
                text: "Add 100 grams of bread and 50 of ham.",
                mentions: [
                  {
                    originalText: "100 grams of bread",
                    canonicalEnglishName: "bread",
                    quantity: 100,
                    unit: "g",
                    rawUnitText: "grams",
                    unitKind: "metric",
                    confidence: 0.95,
                  },
                  {
                    originalText: "50 of ham",
                    canonicalEnglishName: "ham",
                    quantity: 50,
                    confidence: 0.9,
                  },
                ],
              }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of bread and 50 of ham.",
        source: "flutter",
      }),
    });

    expect(res.status).toBe(400);
    const body = (await res.json()) as {
      error: { code: string };
    };
    expect(body.error.code).toBe("validation_error");
  });

  it("returns clarification instead of dropping unresolved ingredients", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "propose_meal_log",
              arguments: JSON.stringify({
                text: "Add 100 grams of bread and 100 grams of cheese.",
                mentions: [
                  mention("bread", 100, {
                    originalText: "100 grams of bread",
                  }),
                  mention("cheese", 100, {
                    originalText: "100 grams of cheese",
                  }),
                ],
              }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of bread and 100 grams of cheese.",
        source: "flutter",
      }),
    });

    const body = (await res.json()) as {
      kind: string;
      options: Array<{ mention: { canonicalEnglishName: string } }>;
    };
    expect(body.kind).toBe("clarification_required");
    expect(body.options).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          mention: expect.objectContaining({ canonicalEnglishName: "cheese" }),
        }),
      ]),
    );
  });

  it("asks for clarification when a food uses an unsupported unit", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "propose_meal_log",
              arguments: JSON.stringify({
                text: "Add 1 rice",
                mentions: [
                  mention("rice", 1, {
                    originalText: "1 rice",
                    unit: "rice",
                    rawUnitText: "rice",
                    unitKind: "implicit_count",
                  }),
                ],
              }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ text: "Add 1 rice", source: "flutter" }),
    });

    const body = (await res.json()) as {
      kind: string;
      message: string;
      options: Array<{ reason?: string }>;
    };
    expect(body.kind).toBe("clarification_required");
    expect(body.message).toContain("1 rice");
    expect(body.message).toContain("grams");
    expect(body.message).toContain("cups");
    expect(body.options).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ reason: "unsupported_unit" }),
      ]),
    );
  });

  it("returns a provider unavailable error when the agent provider is unavailable", async () => {
    const { request } = buildTestApp({
      agentProvider: new ThrowingChatAgentProvider(),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of bread and 100 grams of cheese.",
        source: "flutter",
      }),
    });

    expect(res.status).toBe(503);
    const body = (await res.json()) as {
      error: { code: string; message: string };
    };
    expect(body.error.code).toBe("provider_unavailable");
    expect(body.error.message).toBe(
      "The nutrition assistant is temporarily unavailable. Try again shortly.",
    );
  });

  it("maps calories left to get_remaining_targets", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "get_remaining_targets",
              arguments: JSON.stringify({}),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "how many calories do I have left",
        source: "flutter",
      }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.kind).toBe("remaining_targets");
    expect(body.remaining).toBeDefined();
    expect(body.message).toContain("remaining targets");
  });

  it("maps delete snack to confirmation_required", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "delete_meal",
              arguments: JSON.stringify({
                mealId: "00000000-0000-0000-0000-000000000001",
              }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "delete the snack I just added",
        source: "flutter",
      }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.kind).toBe("confirmation_required");
    expect(body.actionId).toBe("delete_meal");
    expect(body.message).toContain("confirm");
  });

  it("maps explicit nutrition search to nutrition_search", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "search_nutrition_database",
              arguments: JSON.stringify({ query: "bread" }),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "search nutrition database for bread",
        source: "flutter",
      }),
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      kind: string;
      items: { name: string }[];
      options: Array<{
        mention: { canonicalEnglishName: string };
        candidates: Array<{ name: string }>;
      }>;
    };
    expect(body.kind).toBe("nutrition_search");
    expect(body.items.some((item) => item.name === "Bread")).toBe(true);
    expect(body.options[0]).toEqual(
      expect.objectContaining({
        mention: expect.objectContaining({ canonicalEnglishName: "bread" }),
        candidates: expect.arrayContaining([
          expect.objectContaining({ name: "Bread" }),
        ]),
      }),
    );
  });

  it("maps usual meal listing to templates", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "get_usual_meals",
              arguments: JSON.stringify({}),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const auth = await registerAndAuth(request);
    const { authHeader } = auth;
    await createTestUsualBreakfastTemplate(request, authHeader);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ text: "show my usual meals", source: "flutter" }),
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      kind: string;
      templates: { title: string }[];
    };
    expect(body.kind).toBe("templates");
    expect(
      body.templates.some((template) => template.title === "Usual breakfast"),
    ).toBe(true);
  });

  it("maps memory lookup, history, and usual meal creation requests to review-only drafts", async () => {
    const agentProvider = new QueueChatAgentProvider();
    const { request, repository } = buildTestApp({
      agentProvider,
      usualMealDraftProvider: new FakeUsualMealDraftProvider({
        title: "Toast",
        aliases: ["toast"],
        mentions: [
          mention("bread", 100, { originalText: "100 grams of bread" }),
        ],
      }),
    });
    const auth = await registerAndAuth(request);
    const { authHeader } = auth;
    await createTestUsualBreakfastTemplate(request, authHeader);

    agentProvider.push({
      toolCalls: [
        {
          id: "call_1",
          type: "function",
          function: {
            name: "query_food_memory",
            arguments: JSON.stringify({ text: "usual breakfast" }),
          },
        },
      ],
      rawResponse: {},
    });
    const memory = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "look up usual breakfast memory",
        source: "flutter",
      }),
    }).then(
      (response) =>
        response.json() as Promise<{ kind: string; matches: unknown[] }>,
    );
    expect(memory.kind).toBe("food_memory");
    expect(memory.matches.length).toBeGreaterThan(0);

    agentProvider.push({
      toolCalls: [
        {
          id: "call_2",
          type: "function",
          function: {
            name: "get_meal_history",
            arguments: JSON.stringify({ limit: 5 }),
          },
        },
      ],
      rawResponse: {},
    });
    const history = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ text: "show meal history", source: "flutter" }),
    }).then(
      (response) =>
        response.json() as Promise<{ kind: string; meals: unknown[] }>,
    );
    expect(history.kind).toBe("history");
    expect(history.meals).toEqual([]);

    agentProvider.push({
      toolCalls: [
        {
          id: "call_3",
          type: "function",
          function: {
            name: "draft_usual_meal",
            arguments: JSON.stringify({
              text: "Create my usual Toast with 100 grams of bread.",
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const drafted = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ text: "create usual toast", source: "flutter" }),
    }).then(
      (response) =>
        response.json() as Promise<{
          kind: string;
          usualMealDraft: {
            draft: {
              title?: string;
              aliases: string[];
              items: Array<{ name: string }>;
            };
            requiresReview: boolean;
          };
        }>,
    );
    expect(drafted.kind).toBe("usual_meal_draft");
    expect(drafted.usualMealDraft.requiresReview).toBe(true);
    expect(drafted.usualMealDraft.draft.title).toBe("Toast");
    expect(drafted.usualMealDraft.draft.aliases).toEqual(["toast"]);
    expect(drafted.usualMealDraft.draft.items).toEqual([
      expect.objectContaining({ name: "Bread" }),
    ]);
    await expect(repository.listTemplates(auth.user.id)).resolves.not.toEqual(
      expect.arrayContaining([expect.objectContaining({ title: "Toast" })]),
    );

    agentProvider.push({
      toolCalls: [
        {
          id: "call_4",
          type: "function",
          function: {
            name: "create_meal_template",
            arguments: JSON.stringify({
              title: "Toast",
              trustedAutoCommitEnabled: false,
              items: [testBreadItem],
              aliases: ["toast"],
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const updated = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ text: "save toast directly", source: "flutter" }),
    }).then(
      (response) =>
        response.json() as Promise<{
          kind: string;
          message: string;
        }>,
    );
    expect(updated.kind).toBe("clarification_required");
    expect(updated.message).toContain("not able");
  });

  it("maps direct commit and correction action results", async () => {
    const agentProvider = new QueueChatAgentProvider();
    const { request } = buildTestApp({ agentProvider });
    const { authHeader } = await registerAndAuth(request);
    const proposal = await createProposalFromItems(
      request,
      authHeader,
      [testChickenItem, testRiceItem],
      "100 grams of chicken breast and 100 grams of rice",
    );

    agentProvider.push({
      toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "commit_meal",
              arguments: JSON.stringify({
                proposalId: proposal.id,
              }),
            },
          },
      ],
      rawResponse: {},
    });
    const committed = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "confirm that proposal",
        source: "flutter",
      }),
    });
    const committedBody = (await committed.json()) as {
      kind: string;
      meal: { id: string; items: Array<Record<string, unknown>> };
    };
    expect(committedBody.kind).toBe("meal_committed");

    const editedItems = committedBody.meal.items.map((item) => {
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

    agentProvider.push({
      toolCalls: [
        {
          id: "call_2",
          type: "function",
          function: {
            name: "correct_meal",
            arguments: JSON.stringify({
              mealId: committedBody.meal.id,
              items: editedItems,
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const corrected = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "No, the chicken was 200 grams.",
        source: "flutter",
      }),
    });
    const correctedBody = (await corrected.json()) as {
      kind: string;
      meal: { items: { name: string; quantity: number }[] };
    };
    expect(correctedBody.kind).toBe("meal_corrected");
    expect(
      correctedBody.meal.items.find((item) => item.name === "Chicken breast")
        ?.quantity,
    ).toBe(200);
  });

  it("runs a full active proposal revision session before commit", async () => {
    const agentProvider = new QueueChatAgentProvider();
    const { request } = buildTestApp({ agentProvider });
    const { authHeader } = await registerAndAuth(request);

    agentProvider.push({
      toolCalls: [
        {
          id: "call_create",
          type: "function",
          function: {
            name: "propose_meal_log",
            arguments: JSON.stringify({
              text: "Add 100 grams of bread and 20 grams of butter",
              mentions: [
                {
                  originalText: "100 grams of bread",
                  canonicalName: "bread",
                  canonicalEnglishName: "bread",
                  quantity: 100,
                  unit: "g",
                  rawUnitText: "grams",
                  unitKind: "metric",
                  confidence: 0.95,
                },
                {
                  originalText: "20 grams of butter",
                  canonicalName: "butter",
                  canonicalEnglishName: "butter",
                  quantity: 20,
                  unit: "g",
                  rawUnitText: "grams",
                  unitKind: "metric",
                  confidence: 0.95,
                },
              ],
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const created = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of bread and 20 grams of butter",
        source: "flutter",
      }),
    });
    expect(created.status).toBe(200);
    const createdBody = (await created.json()) as {
      kind: string;
      proposal: {
        id: string;
        items: { name: string; quantity: number }[];
      };
    };
    expect(createdBody.kind).toBe("proposal");
    const proposalId = createdBody.proposal.id;

    agentProvider.push({
      toolCalls: [
        {
          id: "call_quantity",
          type: "function",
          function: {
            name: "revise_meal_proposal",
            arguments: JSON.stringify({
              instruction: "No, the butter was 40 grams.",
              operations: [
                {
                  type: "update_item_quantity",
                  itemIndex: 1,
                  quantity: 40,
                  unit: "g",
                  rawUnitText: "grams",
                },
              ],
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const quantityRevision = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "No, the butter was 40 grams.",
        activeProposalId: proposalId,
        source: "flutter",
      }),
    });
    expect(quantityRevision.status).toBe(200);
    const quantityBody = (await quantityRevision.json()) as typeof createdBody;
    expect(quantityBody.kind).toBe("proposal");
    expect(quantityBody.proposal.id).toBe(proposalId);
    expect(
      quantityBody.proposal.items.find((item) => item.name === "Butter")
        ?.quantity,
    ).toBe(40);

    agentProvider.push({
      toolCalls: [
        {
          id: "call_add",
          type: "function",
          function: {
            name: "revise_meal_proposal",
            arguments: JSON.stringify({
              proposalId,
              instruction: "Add 50 grams of ham too.",
              operations: [
                {
                  type: "add_item",
                  mention: {
                    originalText: "50 grams of ham",
                    canonicalName: "ham",
                    canonicalEnglishName: "ham",
                    quantity: 50,
                    unit: "g",
                    rawUnitText: "grams",
                    unitKind: "metric",
                    confidence: 0.95,
                  },
                },
              ],
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const addRevision = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 50 grams of ham too.",
        activeProposalId: proposalId,
        source: "flutter",
      }),
    });
    expect(addRevision.status).toBe(200);
    const addBody = (await addRevision.json()) as typeof createdBody;
    expect(addBody.proposal.id).toBe(proposalId);
    expect(addBody.proposal.items.map((item) => item.name)).toEqual([
      "Bread",
      "Butter",
      "Ham",
    ]);

    agentProvider.push({
      toolCalls: [
        {
          id: "call_remove",
          type: "function",
          function: {
            name: "revise_meal_proposal",
            arguments: JSON.stringify({
              proposalId,
              instruction: "Remove the bread.",
              operations: [{ type: "remove_item", matchText: "bread" }],
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const removeRevision = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Remove the bread.",
        activeProposalId: proposalId,
        source: "flutter",
      }),
    });
    expect(removeRevision.status).toBe(200);
    const removeBody = (await removeRevision.json()) as typeof createdBody;
    expect(removeBody.proposal.id).toBe(proposalId);
    expect(removeBody.proposal.items.map((item) => item.name)).toEqual([
      "Butter",
      "Ham",
    ]);

    const committed = await request(
      `http://localhost/v1/meals/proposals/${proposalId}/commit`,
      {
        method: "POST",
        headers: authHeader,
        body: JSON.stringify({}),
      },
    );
    expect(committed.status).toBe(200);
    const committedBody = (await committed.json()) as {
      output: {
        meal: {
          items: { name: string; quantity: number }[];
          nutrition: { calories: number };
        };
      };
    };
    expect(committedBody.output.meal.items).toEqual([
      expect.objectContaining({ name: "Butter", quantity: 40 }),
      expect.objectContaining({ name: "Ham", quantity: 50 }),
    ]);
    expect(committedBody.output.meal.nutrition.calories).toBe(359);

    agentProvider.push({
      toolCalls: [
        {
          id: "call_after_commit",
          type: "function",
          function: {
            name: "revise_meal_proposal",
            arguments: JSON.stringify({
              proposalId,
              instruction: "Make the butter 20 grams.",
              operations: [
                {
                  type: "update_item_quantity",
                  matchText: "butter",
                  quantity: 20,
                  unit: "g",
                },
              ],
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const rejectedRevision = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Make the butter 20 grams.",
        activeProposalId: proposalId,
        source: "flutter",
      }),
    });
    expect(rejectedRevision.status).toBe(400);
  });

  it("includes the active proposal in the model context", async () => {
    const agentProvider = new CapturingChatAgentProvider({
      toolCalls: [
        {
          id: "call_1",
          type: "function",
          function: {
            name: "revise_meal_proposal",
            arguments: JSON.stringify({
              instruction: "Make it 200 grams.",
              operations: [
                {
                  type: "update_item_quantity",
                  itemIndex: 0,
                  quantity: 200,
                  unit: "g",
                },
              ],
            }),
          },
        },
      ],
      rawResponse: {},
    });
    const { request } = buildTestApp({ agentProvider });
    const { authHeader } = await registerAndAuth(request);
    const proposal = await request(
      "http://localhost/v1/actions/create_meal_proposal_from_items/execute",
      {
        method: "POST",
        headers: authHeader,
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

    await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Make it 200 grams.",
        activeProposalId: proposal.output.proposal.id,
        source: "flutter",
      }),
    });

    expect(agentProvider.messages[0]?.content).toContain(
      "Active meal proposal",
    );
    expect(agentProvider.messages[0]?.content).toContain(testBreadItem.name);
  });

  it("returns a provider unavailable error for active proposal revisions", async () => {
    const { request } = buildTestApp({
      agentProvider: new ThrowingChatAgentProvider(),
    });
    const { authHeader } = await registerAndAuth(request);
    const proposal = await request(
      "http://localhost/v1/actions/create_meal_proposal_from_items/execute",
      {
        method: "POST",
        headers: authHeader,
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

    const revised = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "No, the bread was 200 grams.",
        activeProposalId: proposal.output.proposal.id,
        source: "flutter",
      }),
    });

    expect(revised.status).toBe(503);
    const body = (await revised.json()) as {
      error: { code: string; message: string };
    };
    expect(body.error.code).toBe("provider_unavailable");
    expect(body.error.message).toBe(
      "The nutrition assistant is temporarily unavailable. Try again shortly.",
    );
  });

  it("asks for clarification without changing the active proposal when the model returns no tool call", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const proposal = await createProposalFromItems(
      request,
      authHeader,
      [testRiceItem],
      "100 grams of rice",
    );

    const revised = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of bread and 100 grams of butter.",
        activeProposalId: proposal.id,
        source: "flutter",
      }),
    });

    expect(revised.status).toBe(200);
    const body = (await revised.json()) as {
      kind: string;
      message: string;
      proposal: { id: string; items: Array<{ name: string; quantity: number }> };
    };
    expect(body.kind).toBe("clarification_required");
    expect(body.proposal.id).toBe(proposal.id);
    expect(body.proposal.items.map((item) => item.name)).toEqual([
      "Cooked rice",
    ]);
    expect(body.message).toContain("could not safely apply");
  });

  it("returns a provider unavailable error instead of applying add chunks when the provider fails", async () => {
    const { request } = buildTestApp({
      agentProvider: new ThrowingChatAgentProvider(),
    });
    const { authHeader } = await registerAndAuth(request);
    const proposal = await createProposalFromItems(
      request,
      authHeader,
      [testRiceItem],
      "100 grams of rice",
    );

    const revised = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of rice, 100 grams of beef, 100 grams of butter, and 100 grams of bread.",
        activeProposalId: proposal.id,
        source: "flutter",
      }),
    });

    expect(revised.status).toBe(503);
    const body = (await revised.json()) as {
      error: { code: string; message: string };
    };
    expect(body.error.code).toBe("provider_unavailable");
    expect(body.error.message).toBe(
      "The nutrition assistant is temporarily unavailable. Try again shortly.",
    );
  });

  it("returns a provider unavailable error for ambiguous corrections when the provider fails", async () => {
    const { request } = buildTestApp({
      agentProvider: new ThrowingChatAgentProvider(),
    });
    const { authHeader } = await registerAndAuth(request);
    const proposal = await createProposalFromItems(
      request,
      authHeader,
      [testRiceItem],
      "100 grams of rice",
    );

    const revised = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        text: "Add 100 grams of bread and make it better.",
        activeProposalId: proposal.id,
        source: "flutter",
      }),
    });

    expect(revised.status).toBe(503);
    const body = (await revised.json()) as {
      error: { code: string; message: string };
    };
    expect(body.error.code).toBe("provider_unavailable");
    expect(body.error.message).toBe(
      "The nutrition assistant is temporarily unavailable. Try again shortly.",
    );
  });

  it("rejects unknown model-selected actions", async () => {
    const { request } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "nonexistent_action",
              arguments: JSON.stringify({}),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader } = await registerAndAuth(request);
    const res = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ text: "do something weird", source: "flutter" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.kind).toBe("clarification_required");
  });

  it("records action calls through executor", async () => {
    const { request, repository } = buildTestApp({
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_1",
            type: "function",
            function: {
              name: "get_daily_summary",
              arguments: JSON.stringify({}),
            },
          },
        ],
        rawResponse: {},
      }),
    });
    const { authHeader, user } = await registerAndAuth(request);
    await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ text: "daily summary", source: "flutter" }),
    });

    const actionCalls = await repository.listActionCalls(user.id);
    expect(
      actionCalls.some((call) => call.actionId === "get_daily_summary"),
    ).toBe(true);
  });
});
