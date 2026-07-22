import { describe, expect, it } from "vitest";
import type {
  AgentMessage,
  AgentToolDecision,
  ChatAgentProvider,
} from "../agent/chatAgentProvider.js";
import { buildTestApp, registerAndAuth } from "./testApp.js";

class QueueProvider implements ChatAgentProvider {
  calls = 0;
  constructor(private readonly decisions: AgentToolDecision[]) {}
  async runWithTools(_input: {
    messages: AgentMessage[];
  }): Promise<AgentToolDecision> {
    this.calls++;
    const decision = this.decisions.shift();
    if (!decision) throw new Error("provider_called_after_direct_commit");
    return decision;
  }
}

function sse(text: string) {
  return text
    .split("\n\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line.replace(/^data: /, "")));
}

describe("direct agent-chat meal proposal commit", () => {
  it("commits once without invoking the provider and persists a reloadable tool entry", async () => {
    const provider = new QueueProvider([
      {
        toolCalls: [
          {
            id: "proposal-call",
            type: "function",
            function: {
              name: "propose_meal_log",
              arguments: JSON.stringify({
                text: "100 g bread",
                mentions: [
                  {
                    originalText: "100 g bread",
                    canonicalName: "bread",
                    canonicalEnglishName: "bread",
                    language: "en",
                    quantity: 100,
                    unit: "g",
                    rawUnitText: "g",
                    unitKind: "metric",
                    confidence: 0.95,
                  },
                ],
              }),
            },
          },
        ],
        rawResponse: {},
        interaction: { messages: [], streamEvents: [] },
      },
      {
        toolCalls: [],
        rawResponse: {},
        interaction: {
          messages: [],
          streamEvents: [],
          assistantContent: "Review the proposal.",
        },
      },
    ]);
    const { request } = buildTestApp({ agentProvider: provider });
    const { authHeader } = await registerAndAuth(request);
    const chat = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ message: "100 g bread", source: "flutter" }),
    });
    const events = sse(await chat.text());
    const conversationId = events.find(
      (event) => event.type === "conversation_started",
    ).conversationId;
    const completed = events.find(
      (event) => event.type === "tool_call_completed",
    );
    const proposal = completed.result.proposal;
    const callsBeforeCommit = provider.calls;
    const body = {
      sourceToolCallId: completed.toolCall.id,
      clientMutationId: "11111111-1111-4111-8111-111111111111",
    };
    const first = await request(
      `http://localhost/v1/agent/conversations/${conversationId}/meal-proposals/${proposal.id}/commit`,
      { method: "POST", headers: authHeader, body: JSON.stringify(body) },
    );
    expect(first.status).toBe(200);
    expect((await first.clone().json()).reused).toBe(false);
    const retry = await request(
      `http://localhost/v1/agent/conversations/${conversationId}/meal-proposals/${proposal.id}/commit`,
      { method: "POST", headers: authHeader, body: JSON.stringify(body) },
    );
    expect(retry.status).toBe(200);
    expect((await retry.json()).reused).toBe(true);
    expect(provider.calls).toBe(callsBeforeCommit);
    const history = await request(
      `http://localhost/v1/agent/conversations/${conversationId}`,
      { headers: authHeader },
    );
    const persisted = (await history.json()) as {
      messages: Array<{
        content: string;
        metadata?: { sourceProposalId?: string };
      }>;
    };
    expect(
      persisted.messages.filter(
        (message) => message.metadata?.sourceProposalId === proposal.id,
      ),
    ).toHaveLength(1);
  });

  it("serializes concurrent commits with distinct retry keys", async () => {
    const { request, repository } = buildTestApp();
    const { authHeader, user } = await registerAndAuth(request);
    const conversation = await repository.createAgentConversation(user.id);
    const proposal = await repository.createProposal(user.id, {
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
      items: [
        {
          name: "Bread",
          quantity: 100,
          unit: "g",
          calories: 265,
          proteinGrams: 9,
          carbsGrams: 49,
          fatGrams: 3.2,
          source: "test",
        },
      ],
    });
    await repository.addAgentConversationMessage(user.id, conversation.id, {
      role: "tool",
      content: "{}",
      toolCallId: "proposal-call",
      metadata: {
        actionId: "propose_meal_log",
        proposalId: proposal.id,
      },
    });
    const endpoint = `http://localhost/v1/agent/conversations/${conversation.id}/meal-proposals/${proposal.id}/commit`;
    const responses = await Promise.all(
      [
        "33333333-3333-4333-8333-333333333333",
        "44444444-4444-4444-8444-444444444444",
      ].map((clientMutationId) =>
        request(endpoint, {
          method: "POST",
          headers: authHeader,
          body: JSON.stringify({
            sourceToolCallId: "proposal-call",
            clientMutationId,
          }),
        }),
      ),
    );

    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    const bodies = await Promise.all(responses.map((response) => response.json()));
    expect(bodies.filter((body) => body.reused === false)).toHaveLength(1);
    expect(bodies.filter((body) => body.reused === true)).toHaveLength(1);
    expect(await repository.listMeals(user.id)).toHaveLength(1);
    const messages = await repository.listAgentConversationMessages(
      user.id,
      conversation.id,
    );
    expect(
      messages.filter(
        (message) =>
          (message.metadata as { sourceProposalId?: string } | undefined)
            ?.sourceProposalId === proposal.id,
      ),
    ).toHaveLength(1);
  });

  it("does not disclose another user's proposal or conversation", async () => {
    const { request, repository } = buildTestApp();
    const owner = await registerAndAuth(request);
    const other = await registerAndAuth(request);
    const conversation = await repository.createAgentConversation(
      owner.user.id,
    );
    const proposal = await repository.createProposal(owner.user.id, {
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
      items: [
        {
          name: "Bread",
          quantity: 100,
          unit: "g",
          calories: 265,
          proteinGrams: 9,
          carbsGrams: 49,
          fatGrams: 3.2,
          source: "test",
        },
      ],
    });
    const response = await request(
      `http://localhost/v1/agent/conversations/${conversation.id}/meal-proposals/${proposal.id}/commit`,
      {
        method: "POST",
        headers: other.authHeader,
        body: JSON.stringify({
          sourceToolCallId: "unknown",
          clientMutationId: "22222222-2222-4222-8222-222222222222",
        }),
      },
    );
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(await response.text()).not.toContain(proposal.id);

    await repository.addAgentConversationMessage(owner.user.id, conversation.id, {
      role: "tool",
      content: "{}",
      toolCallId: "owner-proposal-call",
      metadata: {
        actionId: "propose_meal_log",
        proposalId: proposal.id,
      },
    });
    const unrelatedConversation = await repository.createAgentConversation(
      owner.user.id,
    );
    const sourceMismatch = await request(
      `http://localhost/v1/agent/conversations/${unrelatedConversation.id}/meal-proposals/${proposal.id}/commit`,
      {
        method: "POST",
        headers: owner.authHeader,
        body: JSON.stringify({
          sourceToolCallId: "owner-proposal-call",
          clientMutationId: "55555555-5555-4555-8555-555555555555",
        }),
      },
    );
    expect(sourceMismatch.status).toBeGreaterThanOrEqual(400);
    expect(await sourceMismatch.text()).not.toContain(proposal.id);
  });
});
