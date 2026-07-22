import { describe, expect, it } from "vitest";
import { commitAgentChatMealCorrectionResponseSchema } from "@cal-tracker/contracts";
import type {
  AgentMessage,
  AgentToolDecision,
  ChatAgentProvider,
} from "../agent/chatAgentProvider.js";
import { buildTestApp, registerAndAuth, testBreadItem } from "./testApp.js";

class QueueProvider implements ChatAgentProvider {
  readonly decisions: AgentToolDecision[] = [];

  async runWithTools(_input: {
    messages: AgentMessage[];
  }): Promise<AgentToolDecision> {
    const decision = this.decisions.shift();
    if (!decision) throw new Error("unexpected_provider_call");
    return decision;
  }
}

function sse(text: string) {
  return text
    .split("\n\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line.replace(/^data: /, "")));
}

async function preparePreview() {
  const provider = new QueueProvider();
  const app = buildTestApp({ agentProvider: provider });
  const auth = await registerAndAuth(app.request);
  const proposal = await app.repository.createProposal(auth.user.id, {
    phrase: "bread",
    title: "Bread",
    status: "pending",
    confidence: 1,
    requiresConfirmation: true,
    trustedAutoCommitEligible: false,
    source: "test",
    nutrition: {
      calories: 265,
      proteinGrams: 9,
      carbsGrams: 49,
      fatGrams: 3.2,
    },
    items: [testBreadItem],
  });
  const meal = await app.repository.createMealFromProposal(
    auth.user.id,
    proposal,
    "2026-07-22T12:00:00.000Z",
  );
  provider.decisions.push(
    {
      toolCalls: [{
        id: "meal-correction-preview-call",
        type: "function",
        function: {
          name: "preview_meal_correction",
          arguments: JSON.stringify({
            mealId: meal.id,
            instruction: "Make bread 200 grams",
            operations: [{
              type: "update_item_quantity",
              itemIndex: 0,
              quantity: 200,
              unit: "g",
            }],
          }),
        },
      }],
      rawResponse: {},
      interaction: { messages: [], streamEvents: [] },
    },
    {
      toolCalls: [],
      rawResponse: {},
      interaction: {
        messages: [],
        streamEvents: [],
        assistantContent: "Review the correction.",
      },
    },
  );
  const chat = await app.request("http://localhost/v1/agent/chat", {
    method: "POST",
    headers: auth.authHeader,
    body: JSON.stringify({ message: "Correct that meal", source: "flutter" }),
  });
  const events = sse(await chat.text());
  const conversationId = events.find(
    (event) => event.type === "conversation_started",
  ).conversationId as string;
  const completed = events.find(
    (event) => event.type === "tool_call_completed",
  );
  expect(completed.result.kind).toBe("meal_correction_preview");
  expect(completed.result.meal.items[0].quantity).toBe(200);
  expect((await app.repository.getMeal(auth.user.id, meal.id))?.items[0]?.quantity)
    .toBe(100);
  return {
    ...app,
    auth,
    meal,
    conversationId,
    sourceToolCallId: completed.toolCall.id as string,
  };
}

describe("direct agent-chat meal correction", () => {
  it("commits the persisted preview once and replays the exact canonical result", async () => {
    const prepared = await preparePreview();
    const endpoint =
      `http://localhost/v1/agent/conversations/${prepared.conversationId}` +
      `/meal-corrections/${prepared.meal.id}/commit`;
    const responses = await Promise.all(
      [
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      ].map((clientMutationId) =>
        prepared.request(endpoint, {
          method: "POST",
          headers: prepared.auth.authHeader,
          body: JSON.stringify({
            sourceToolCallId: prepared.sourceToolCallId,
            clientMutationId,
          }),
        }),
      ),
    );
    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    const bodies = await Promise.all(responses.map((response) => response.json()));
    for (const body of bodies) {
      expect(() => commitAgentChatMealCorrectionResponseSchema.parse(body))
        .not.toThrow();
    }
    expect(bodies.filter((body) => body.reused === false)).toHaveLength(1);
    expect(bodies.filter((body) => body.reused === true)).toHaveLength(1);
    expect(bodies[0].result).toEqual(bodies[1].result);
    expect(bodies[0].clientMutationId).toBe(bodies[1].clientMutationId);
    expect(bodies[0].result.confirmedMutation.mutationId)
      .toBe(bodies[0].clientMutationId);
    expect(bodies[0].result.confirmedMutation.effects).toEqual([
      expect.objectContaining({
        domain: "meals",
        operation: "upsert",
        entityId: prepared.meal.id,
      }),
    ]);
    expect(
      (await prepared.repository.getMeal(
        prepared.auth.user.id,
        prepared.meal.id,
      ))?.items[0]?.quantity,
    ).toBe(200);

    const messages = await prepared.repository.listAgentConversationMessages(
      prepared.auth.user.id,
      prepared.conversationId,
    );
    const commits = messages.filter(
      (message) =>
        (message.metadata as { actionId?: string } | undefined)?.actionId ===
          "correct_meal",
    );
    expect(commits).toHaveLength(1);
    expect(
      (commits[0]?.metadata as { uiResult?: unknown } | undefined)?.uiResult,
    ).toEqual(bodies[0].result);
  });

  it("returns stable 409 when the meal changed or was deleted after preview", async () => {
    const changed = await preparePreview();
    await changed.repository.updateMeal(changed.auth.user.id, {
      ...changed.meal,
      title: "Changed elsewhere",
    });
    const changedResponse = await changed.request(
      `http://localhost/v1/agent/conversations/${changed.conversationId}` +
        `/meal-corrections/${changed.meal.id}/commit`,
      {
        method: "POST",
        headers: changed.auth.authHeader,
        body: JSON.stringify({
          sourceToolCallId: changed.sourceToolCallId,
          clientMutationId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        }),
      },
    );
    expect(changedResponse.status).toBe(409);
    expect((await changedResponse.json()).error.code)
      .toBe("meal_changed_since_preview");

    const deleted = await preparePreview();
    await deleted.repository.softDeleteMeal(deleted.auth.user.id, deleted.meal.id);
    const deletedResponse = await deleted.request(
      `http://localhost/v1/agent/conversations/${deleted.conversationId}` +
        `/meal-corrections/${deleted.meal.id}/commit`,
      {
        method: "POST",
        headers: deleted.auth.authHeader,
        body: JSON.stringify({
          sourceToolCallId: deleted.sourceToolCallId,
          clientMutationId: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
        }),
      },
    );
    expect(deletedResponse.status).toBe(409);
    expect((await deletedResponse.json()).error.code)
      .toBe("meal_changed_since_preview");
  });
});
