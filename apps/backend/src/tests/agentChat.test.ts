import { describe, expect, it } from "vitest";
import type {
  AgentMessage,
  AgentToolDecision,
  ChatAgentProvider,
} from "../agent/chatAgentProvider.js";
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
        rawResponse: {},
        interaction: { messages: [], streamEvents: [] },
      },
      {
        toolCalls: [],
        rawResponse: {},
        interaction: {
          messages: [],
          assistantContent: "You have your daily summary above.",
          streamEvents: [],
        },
      },
    ]);
    const { request } = buildTestApp({ agentProvider });
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
      messages: Array<{ role: string; content: string; toolCallId?: string }>;
    };
    expect(body.messages.map((message) => message.role)).toEqual([
      "user",
      "assistant",
      "tool",
      "assistant",
    ]);
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
    const { request } = buildTestApp({
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
  });
});

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
