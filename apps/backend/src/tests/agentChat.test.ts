import { describe, expect, it, vi } from "vitest";
import type {
  AgentMessage,
  AgentToolDecision,
  ChatAgentProvider,
} from "../agent/chatAgentProvider.js";
import { AgentChatService } from "../agent/agentChatService.js";
import { buildToolContentForModel } from "../agent/toolContent.js";
import { defaultUserScopes, type MealItem } from "@cal-tracker/contracts";
import {
  buildTestApp,
  FakeSpeechToTextProvider,
  registerAndAuth,
} from "./testApp.js";

class QueueChatAgentProvider implements ChatAgentProvider {
  readonly inputs: Array<{ messages: AgentMessage[] }> = [];

  constructor(private readonly decisions: AgentToolDecision[]) {}

  async runWithTools(input: {
    messages: AgentMessage[];
  }): Promise<AgentToolDecision> {
    this.inputs.push({ messages: input.messages });
    const decision = this.decisions.shift();
    if (!decision) throw new Error("missing_fake_agent_decision");
    return decision;
  }
}

describe("agent chat streaming", () => {
  it("streams a multi-step tool call and persists conversation messages", async () => {
    const agentProvider = new QueueChatAgentProvider([
      {
        toolCalls: [
          {
            id: "call_summary",
            type: "function",
            function: {
              name: "get_daily_summary",
              arguments: JSON.stringify({}),
            },
          },
        ],
        rawResponse: {
          id: "gen_chat_tool",
          usage: {
            prompt_tokens: 12,
            completion_tokens: 8,
            total_tokens: 20,
            cost: 0.0002,
          },
        },
        interaction: { messages: [], streamEvents: [] },
      },
      {
        toolCalls: [],
        rawResponse: {
          id: "gen_chat_final",
          usage: {
            prompt_tokens: 14,
            completion_tokens: 16,
            total_tokens: 30,
            cost: 0.0003,
          },
        },
        interaction: {
          messages: [],
          assistantContent: "You have your daily summary above.",
          streamEvents: [],
        },
      },
    ]);
    const { request, telemetry, config } = buildTestApp({ agentProvider });
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        message: "How am I doing today?",
        source: "flutter",
      }),
    });

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/event-stream");
    const events = parseSse(await response.text());
    const conversationId = events.find(
      (event) => event.type === "conversation_started",
    )?.conversationId as string;

    expect(conversationId).toBeDefined();
    expect(events.map((event) => event.type)).toEqual(
      expect.arrayContaining([
        "conversation_started",
        "tool_call_started",
        "tool_call_completed",
        "assistant_delta",
        "done",
      ]),
    );
    expect(
      events.find((event) => event.type === "tool_call_completed")?.result,
    ).toEqual(expect.objectContaining({ kind: "summary" }));
    expect(agentProvider.inputs).toHaveLength(2);
    expect(
      agentProvider.inputs[1]!.messages.some(
        (message) => message.role === "tool",
      ),
    ).toBe(true);

    const persisted = await request(
      `http://localhost/v1/agent/conversations/${conversationId}`,
      { headers: authHeader },
    );
    expect(persisted.status).toBe(200);
    const body = (await persisted.json()) as {
      conversation: { id: string; title: string };
      toolExecutions: Array<{
        schemaVersion: number;
        conversationId: string;
        toolCallId: string;
        status: string;
        result?: { kind: string };
        widget?: { kind: string };
      }>;
      messages: Array<{
        role: string;
        content: string;
        toolCallId?: string;
        traceId?: string;
        turnId?: string;
        inputMode?: string;
        source?: string;
        metadata?: Record<string, unknown>;
      }>;
    };
    expect(body.conversation).toEqual(
      expect.objectContaining({
        id: conversationId,
        title: "How am I doing today?",
      }),
    );
    const completedEvent = events.find(
      (event) => event.type === "tool_call_completed",
    );
    expect(body.toolExecutions).toEqual([
      expect.objectContaining({
        schemaVersion: 1,
        conversationId,
        toolCallId: "call_summary",
        status: "completed",
        result: completedEvent?.result,
        widget: completedEvent?.widget,
      }),
    ]);
    expect(body.messages.map((message) => message.role)).toEqual([
      "user",
      "assistant",
      "tool",
      "assistant",
    ]);
    const turnIds = new Set(body.messages.map((message) => message.turnId));
    expect(turnIds.size).toBe(1);
    expect([...turnIds][0]).toEqual(expect.any(String));
    expect(body.messages.every((message) => message.traceId)).toBe(true);
    expect(body.messages.every((message) => message.inputMode === "text")).toBe(
      true,
    );
    expect(body.messages.every((message) => message.source === "flutter")).toBe(
      true,
    );
    expect(body.messages[0]?.metadata).toEqual(
      expect.objectContaining({
        conversationId,
        inputMode: "text",
        source: "flutter",
        turnId: [...turnIds][0],
      }),
    );
    expect(body.messages[1]?.metadata).toEqual(
      expect.objectContaining({
        iteration: 1,
        toolCallCount: 1,
      }),
    );
    expect(body.messages[2]?.metadata).toEqual(
      expect.objectContaining({
        actionId: "get_daily_summary",
        actionCallId: expect.any(String),
        iteration: 1,
        resultKind: "summary",
      }),
    );
    expect(body.messages[3]?.metadata).toEqual(
      expect.objectContaining({
        iteration: 2,
        resultKind: "assistant_message",
        stopReason: "assistant_message",
      }),
    );

    const turnId = [...turnIds][0] as string;
    const turns = await telemetry.listAgentTurns({ conversationId, limit: 10 });
    expect(turns).toHaveLength(1);
    expect(turns[0]).toMatchObject({
      conversationId,
      turnId,
      inputMode: "text",
      source: "flutter",
      model: config.OPENROUTER_MODEL,
      resultKind: "assistant_message",
      stopReason: "assistant_message",
      status: "success",
      toolCallCount: 1,
      promptTokens: 26,
      completionTokens: 24,
      totalTokens: 50,
      providerCostAmount: 0.0005,
      costCurrency: "USD",
      costSource: "provider",
    });

    const providerCalls = await telemetry.listLlmProviderCalls({
      conversationId,
      limit: 10,
    });
    expect(providerCalls.map((call) => call.providerGenerationId)).toEqual([
      "gen_chat_final",
      "gen_chat_tool",
    ]);
    expect(providerCalls.every((call) => call.turnId === turnId)).toBe(true);
    expect(providerCalls.every((call) => call.costSource === "provider")).toBe(
      true,
    );

    const toolCalls = await telemetry.listAgentToolCalls({
      conversationId,
      limit: 10,
    });
    expect(toolCalls).toHaveLength(1);
    expect(toolCalls[0]).toMatchObject({
      conversationId,
      turnId,
      actionId: "get_daily_summary",
      status: "completed",
    });
  });

  it("marks a persisted started call interrupted when its stream is cancelled", async () => {
    const agentProvider = new QueueChatAgentProvider([
      {
        toolCalls: [
          {
            id: "call_cancelled_summary",
            type: "function",
            function: { name: "get_daily_summary", arguments: "{}" },
          },
        ],
        rawResponse: {},
        interaction: { messages: [], streamEvents: [] },
      },
    ]);
    const { request, repository, actionExecutor, config } = buildTestApp({
      agentProvider,
    });
    const { user } = await registerAndAuth(request);
    const service = new AgentChatService(
      agentProvider,
      actionExecutor,
      repository,
      config.OPENROUTER_MODEL,
    );
    const stream = service.chat({
      text: "Show my summary",
      context: {
        actorUserId: user.id,
        actorType: "user",
        source: "flutter",
        scopes: defaultUserScopes,
        timezone: "UTC",
        locale: "en",
        trustedModeEnabled: false,
        traceId: "trace-cancelled-tool",
      },
    });

    let conversationId: string | undefined;
    for (;;) {
      const next = await stream.next();
      expect(next.done).toBe(false);
      if (next.value?.type === "conversation_started") {
        conversationId = next.value.conversationId;
      }
      if (next.value?.type === "tool_call_started") break;
    }
    await stream.return(undefined);

    expect(conversationId).toBeDefined();
    await expect(
      repository.listAgentToolExecutions(user.id, conversationId!),
    ).resolves.toEqual([
      expect.objectContaining({
        status: "interrupted",
        snapshot: expect.objectContaining({
          status: "interrupted",
          completedAt: expect.any(String),
        }),
      }),
    ]);
  });

  it("lets the LLM resolve a compact candidate preview by reference", async () => {
    const agentProvider = new QueueChatAgentProvider([
      {
        toolCalls: [
          {
            id: "call_candidate",
            type: "function",
            function: {
              name: "resolve_candidate_reference",
              arguments: JSON.stringify({
                candidateRef: "g1c6",
              }),
            },
          },
        ],
        rawResponse: { id: "gen_candidate_tool" },
        interaction: { messages: [], streamEvents: [] },
      },
      {
        toolCalls: [],
        rawResponse: { id: "gen_selection_final" },
        interaction: {
          messages: [],
          assistantContent: "I will use the selected ingredient.",
          streamEvents: [],
        },
      },
    ]);
    const { request, repository } = buildTestApp({ agentProvider });
    const { authHeader, user } = await registerAndAuth(request);
    const conversation = await repository.createAgentConversation(user.id, {
      title: "Search bread",
    });
    const candidates = Array.from({ length: 10 }, (_, index) =>
      chatCandidate(index + 1),
    );
    const toolContent = buildToolContentForModel({
      actionId: "search_nutrition_database",
      actionCallId: "search-action-1",
      toolInput: { query: "bread" },
      mappedResult: {
        kind: "nutrition_search",
        message: "I found matching nutrition items.",
        items: candidates,
        candidateGroups: [{ candidates }],
      },
      rawOutput: { items: candidates, candidateGroups: [{ candidates }] },
      threshold: 0.75,
    });
    const storedToolMessage = await repository.addAgentConversationMessage(
      user.id,
      conversation.id,
      {
        role: "tool",
        content: toolContent.modelContent,
        toolCallId: "call_search",
        metadata: {
          candidateRegistryRef: toolContent.candidateRegistry?.searchRef,
          searchRef: toolContent.candidateRegistry?.searchRef,
          candidateCount: toolContent.candidateRegistry?.candidateCount,
          groupCount: toolContent.candidateRegistry?.groupCount,
          serializerVersion: toolContent.serializerVersion,
        },
      },
    );
    expect(storedToolMessage.metadata).not.toHaveProperty("candidateRegistry");
    expect(toolContent.candidateRegistry).toBeDefined();
    await repository.saveAgentCandidateRegistry({
      userId: user.id,
      conversationId: conversation.id,
      messageId: storedToolMessage.id,
      searchRef: toolContent.candidateRegistry!.searchRef,
      actionId: toolContent.candidateRegistry!.actionId,
      actionCallId: toolContent.candidateRegistry!.actionCallId,
      candidateCount: toolContent.candidateRegistry!.candidateCount,
      groupCount: toolContent.candidateRegistry!.groupCount,
      threshold: toolContent.candidateRegistry!.threshold,
      registry: toolContent.candidateRegistry!,
    });

    const response = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        source: "flutter",
        conversationId: conversation.id,
        message: "Use the sixth result.",
      }),
    });

    expect(response.status).toBe(200);
    const events = parseSse(await response.text());
    expect(events.some((event) => event.type === "assistant_delta")).toBe(true);
    expect(agentProvider.inputs).toHaveLength(2);
    const firstModelMessages = agentProvider.inputs[0]!.messages;
    const previewToolMessage = firstModelMessages.find(
      (message) => message.role === "tool",
    );
    expect(previewToolMessage?.content).toContain("candidatePreview");
    expect(previewToolMessage?.content).toContain("g1c6");
    expect(previewToolMessage?.content).toContain("Candidate 6");
    expect(previewToolMessage?.content).not.toContain("candidateGroups");

    const secondModelMessages = agentProvider.inputs[1]!.messages;
    const selectedToolMessage = [...secondModelMessages]
      .reverse()
      .find((message) => message.role === "tool");
    expect(selectedToolMessage?.content).toContain(
      "Selected nutrition candidate resolved",
    );
    expect(selectedToolMessage?.content).toContain("Candidate 6");
  });

  it("streams model-proposed quick reply buttons", async () => {
    const agentProvider = new QueueChatAgentProvider([
      {
        toolCalls: [
          {
            id: "call_options",
            type: "function",
            function: {
              name: "show_chat_options",
              arguments: JSON.stringify({
                message: "¿La guardo así?",
                options: [
                  { label: "Sí", value: "Sí, guárdala así" },
                  { label: "No", value: "No, quiero editarla" },
                ],
              }),
            },
          },
        ],
        rawResponse: {},
        interaction: { messages: [], streamEvents: [] },
      },
    ]);
    const { request } = buildTestApp({ agentProvider });
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        message: "¿La guardas?",
        source: "flutter",
      }),
    });

    expect(response.status).toBe(200);
    const events = parseSse(await response.text());
    expect(events.map((event) => event.type)).toEqual(
      expect.arrayContaining([
        "conversation_started",
        "assistant_delta",
        "assistant_suggestions",
        "done",
      ]),
    );
    expect(
      events.find((event) => event.type === "assistant_suggestions")
        ?.suggestions,
    ).toEqual([
      { label: "Sí", value: "Sí, guárdala así" },
      { label: "No", value: "No, quiero editarla" },
    ]);
  });

  it("transcribes audio and streams it into the same chat pipeline", async () => {
    const agentProvider = new QueueChatAgentProvider([
      {
        toolCalls: [],
        rawResponse: {},
        interaction: {
          messages: [],
          assistantContent: "I heard the voice message.",
          streamEvents: [],
        },
      },
    ]);
    const { request, telemetry } = buildTestApp({
      agentProvider,
      sttProvider: new FakeSpeechToTextProvider("voice message"),
    });
    const { authHeader } = await registerAndAuth(request);
    const form = new FormData();
    form.append(
      "audio",
      new Blob(["fake audio"], { type: "audio/m4a" }),
      "test.m4a",
    );

    const response = await request("http://localhost/v1/agent/chat/audio", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body: form,
    });

    expect(response.status).toBe(200);
    const events = parseSse(await response.text());
    expect(events.map((event) => event.type)).toContain(
      "transcription_completed",
    );
    expect(
      events.some(
        (event) =>
          event.type === "transcription_completed" &&
          String(event.transcript).includes("voice message"),
      ),
    ).toBe(true);
    expect(
      agentProvider.inputs[0]?.messages.some(
        (message) =>
          message.role === "user" && message.content === "voice message",
      ),
    ).toBe(true);
    const conversationId = events.find(
      (event) => event.type === "conversation_started",
    )?.conversationId as string;
    const turnId = events.find((event) => event.type === "conversation_started")
      ?.turnId as string;
    const transcriptions = await telemetry.listTranscriptionRecords({
      conversationId,
      limit: 10,
    });
    expect(transcriptions).toHaveLength(1);
    expect(transcriptions[0]).toMatchObject({
      conversationId,
      turnId,
      surface: "agent_chat_audio",
      provider: "test",
      model: "test-model",
      transcriptText: "[redacted]",
      transcriptLength: 13,
      status: "completed",
    });
  });

  it("hides immediately and permanently purges a deleted conversation", async () => {
    const agentProvider = new QueueChatAgentProvider([
      {
        toolCalls: [],
        rawResponse: {},
        interaction: {
          messages: [],
          assistantContent: "Done.",
          streamEvents: [],
        },
      },
    ]);
    const { request, repository } = buildTestApp({ agentProvider });
    const { authHeader, user } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        message: "Please remember this chat",
        source: "flutter",
      }),
    });
    expect(response.status).toBe(200);
    const events = parseSse(await response.text());
    const conversationId = events.find(
      (event) => event.type === "conversation_started",
    )?.conversationId as string;

    const deleteResponse = await request(
      `http://localhost/v1/agent/conversations/${conversationId}`,
      { method: "DELETE", headers: authHeader },
    );
    expect(deleteResponse.status).toBe(202);
    await expect(deleteResponse.json()).resolves.toMatchObject({
      ok: true,
      deleted: true,
      hidden: true,
      status: "pending",
    });

    const listResponse = await request(
      "http://localhost/v1/agent/conversations",
      {
        headers: authHeader,
      },
    );
    expect(listResponse.status).toBe(200);
    await expect(listResponse.json()).resolves.toEqual({ conversations: [] });

    const detailResponse = await request(
      `http://localhost/v1/agent/conversations/${conversationId}`,
      { headers: authHeader },
    );
    expect(detailResponse.status).toBe(404);

    const retained = (
      repository as unknown as {
        agentConversationMessages: Map<
          string,
          Array<{ userId: string; role: string }>
        >;
      }
    ).agentConversationMessages.get(conversationId);
    expect(retained?.map((message) => message.userId)).toEqual([
      user.id,
      user.id,
    ]);

    await repository.runPrivacyLifecycle();
    const purged = (
      repository as unknown as {
        agentConversationMessages: Map<string, unknown[]>;
      }
    ).agentConversationMessages.get(conversationId);
    expect(purged).toBeUndefined();
  });

  it("uses the same safe envelope for provider failures without leaking reflected input", async () => {
    const leaked =
      "Antonio comió pizza at https://provider.invalid/debug?token=secret-value sk_reflectedsecret123";
    const localEvents: Record<string, unknown>[] = [];
    const agentProvider: ChatAgentProvider = {
      async runWithTools(): Promise<never> {
        throw new Error(leaked);
      },
    };
    const { request } = buildTestApp({
      agentProvider,
      runLogger: {
        enabled: true,
        async log(event) {
          localEvents.push(event);
        },
      },
    });
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ message: "Help me", source: "flutter" }),
    });
    const traceId = response.headers.get("x-request-id");
    const raw = await response.text();
    const error = parseSse(raw).find((event) => event.type === "error")?.error;

    expect(error).toEqual({
      code: "provider_unavailable",
      message:
        "The nutrition assistant is temporarily unavailable. Try again shortly.",
      traceId,
    });
    expect(raw).not.toContain("Antonio");
    expect(raw).not.toContain("provider.invalid");
    expect(raw).not.toContain("reflectedsecret");
    expect(JSON.stringify(localEvents)).not.toContain("Antonio");
    expect(JSON.stringify(localEvents)).not.toContain("provider.invalid");
    expect(JSON.stringify(localEvents)).not.toContain("reflectedsecret");
    expect(localEvents).toEqual(
      expect.arrayContaining([expect.objectContaining({ traceId })]),
    );
  });

  it("sanitizes unexpected tool failures in SSE and stored conversation data", async () => {
    const leaked =
      "Antonio comió pasta at https://tools.invalid/run?key=secret-value sk_toolsecret123";
    const agentProvider = new QueueChatAgentProvider([
      {
        toolCalls: [
          {
            id: "call_summary_failure",
            type: "function",
            function: { name: "get_daily_summary", arguments: "{}" },
          },
        ],
        rawResponse: {},
      },
      {
        toolCalls: [],
        rawResponse: {},
        interaction: {
          messages: [],
          assistantContent: "Please try again.",
          streamEvents: [],
        },
      },
    ]);
    const { request, actionExecutor } = buildTestApp({ agentProvider });
    vi.spyOn(actionExecutor, "execute").mockRejectedValue(new Error(leaked));
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ message: "Show today", source: "flutter" }),
    });
    const raw = await response.text();
    const events = parseSse(raw);
    const failed = events.find((event) => event.type === "tool_call_failed");
    const conversationId = events.find(
      (event) => event.type === "conversation_started",
    )?.conversationId as string;

    expect(failed?.error).toEqual(
      expect.objectContaining({
        code: "internal_error",
        traceId: response.headers.get("x-request-id"),
      }),
    );
    expect(raw).not.toContain("Antonio");
    expect(raw).not.toContain("tools.invalid");
    expect(raw).not.toContain("toolsecret");

    const stored = await request(
      `http://localhost/v1/agent/conversations/${conversationId}`,
      { headers: authHeader },
    );
    const storedRaw = await stored.text();
    expect(storedRaw).not.toContain("Antonio");
    expect(storedRaw).not.toContain("tools.invalid");
    expect(storedRaw).not.toContain("toolsecret");
  });

  it("returns catalogued JSON errors before opening an SSE stream", async () => {
    const { request } = buildTestApp();
    const unauthenticated = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ message: "hello", source: "flutter" }),
    });
    expect(unauthenticated.status).toBe(401);
    await expect(unauthenticated.json()).resolves.toEqual({
      error: {
        code: "authentication_required",
        message: "Sign in to continue.",
        traceId: unauthenticated.headers.get("x-request-id"),
      },
    });

    const { authHeader } = await registerAndAuth(request);
    const invalid = await request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ message: "", source: "flutter" }),
    });
    expect(invalid.status).toBe(400);
    await expect(invalid.json()).resolves.toEqual({
      error: {
        code: "validation_error",
        message: "Check the request and try again.",
        traceId: invalid.headers.get("x-request-id"),
      },
    });
  });
});

function chatCandidate(rank: number): MealItem {
  return {
    name: `Candidate ${rank}`,
    quantity: 100,
    unit: "g",
    calories: 180 + rank,
    proteinGrams: 6,
    carbsGrams: 28,
    fatGrams: 3,
    source: "database",
    originalText: "bread",
    canonicalName: `candidate ${rank}`,
    externalSource: "test",
    externalId: `candidate-${rank}`,
    confidence: 0.6,
    needsReview: true,
    rank,
    matchScore: 0.6,
  };
}

function parseSse(raw: string): Array<Record<string, unknown>> {
  return raw
    .split("\n\n")
    .map((chunk) => chunk.trim())
    .filter(Boolean)
    .map((chunk) => JSON.parse(chunk.replace(/^data:\s*/, "")));
}

function bearerOnly(authHeader: Record<string, string>) {
  return { authorization: authHeader.authorization };
}
