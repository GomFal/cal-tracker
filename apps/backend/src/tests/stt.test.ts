import { describe, expect, it } from "vitest";
import type { ChatAgentProvider, AgentToolDecision } from "../agent/chatAgentProvider.js";
import type { LocalRunLogger } from "../observability/localRunLogger.js";
import {
  buildTestApp,
  FakeChatAgentProvider,
  FakeSpeechToTextProvider,
  registerAndAuth,
} from "./testApp.js";

describe("STT endpoint", () => {
  it("rejects unauthenticated requests", async () => {
    const { request } = buildTestApp();
    const res = await request("http://localhost/v1/stt/transcriptions", { method: "POST" });
    expect(res.status).toBe(401);
  });

  it("rejects unauthenticated voice meal requests", async () => {
    const { request } = buildTestApp();
    const res = await request("http://localhost/v1/voice/meal-runs", { method: "POST" });
    expect(res.status).toBe(401);
  });

  it("rejects missing audio", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);
    const body = new FormData();
    const res = await request("http://localhost/v1/stt/transcriptions", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body
    });
    expect(res.status).toBe(400);
    const json = await res.json();
    expect(json.error.message).toContain("Missing audio file");
  });

  it("rejects unsupported mime type", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const body = new FormData();
    body.append("audio", new Blob(["fake audio"], { type: "audio/mp3" }), "test.mp3");

    const res = await request("http://localhost/v1/stt/transcriptions", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body
    });
    expect(res.status).toBe(415);
    const json = await res.json();
    expect(json.error.message).toContain("Unsupported audio format");
  });

  it("rejects invalid voice meal audio uploads", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const missingAudio = await request("http://localhost/v1/voice/meal-runs", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body: new FormData()
    });
    expect(missingAudio.status).toBe(400);

    const invalidMimeBody = new FormData();
    invalidMimeBody.append("audio", new Blob(["fake audio"], { type: "audio/mp3" }), "test.mp3");
    const invalidMime = await request("http://localhost/v1/voice/meal-runs", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body: invalidMimeBody
    });
    expect(invalidMime.status).toBe(415);
  });

  it("returns fake transcript with test provider", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const body = new FormData();
    body.append("audio", new Blob(["fake audio"], { type: "audio/m4a" }), "test.m4a");

    const res = await request("http://localhost/v1/stt/transcriptions", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body
    });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.transcript).toBe("fake transcript from test");
    expect(json.provider).toBe("test");
    expect(json.model).toBe("test-model");
    expect(json.traceId).toBeDefined();
  });

  it("transcribes audio and creates a meal result in a single request", async () => {
    const runLogger = new CollectingRunLogger();
    const { request } = buildTestApp({
      runLogger,
      sttProvider: new FakeSpeechToTextProvider("100 grams bread"),
      agentProvider: new FakeChatAgentProvider({
        toolCalls: [
          {
            id: "call_voice_meal",
            type: "function",
            function: {
              name: "propose_meal_log",
              arguments: JSON.stringify({ text: "100 grams bread" }),
            },
          },
        ],
        rawResponse: {
          usage: {
            prompt_tokens: 10,
            completion_tokens: 4,
            completion_tokens_details: { reasoning_tokens: 2 },
          },
        },
      }),
    });
    const { authHeader } = await registerAndAuth(request);

    const body = new FormData();
    body.append("audio", new Blob(["fake audio"], { type: "audio/m4a" }), "test.m4a");

    const res = await request("http://localhost/v1/voice/meal-runs", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body
    });

    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.transcript).toBe("100 grams bread");
    expect(json.provider).toBe("test");
    expect(json.model).toBe("test-model");
    expect(json.traceId).toBeDefined();
    expect(json.result.kind).toBe("proposal");
    expect(json.result.proposal.items[0].name).toBe("Bread");
    expect(runLogger.events).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: "agent.run",
          selectedTool: "propose_meal_log",
          resultKind: "proposal",
          reasoningTokens: 2,
          timingsMs: expect.objectContaining({
            llm: expect.any(Number),
            action: expect.any(Number),
            total: expect.any(Number),
          }),
        }),
        expect.objectContaining({
          type: "voice.meal_run",
          transcript: "100 grams bread",
          resultKind: "proposal",
          timingsMs: expect.objectContaining({
            stt: expect.any(Number),
            agent: expect.any(Number),
            total: expect.any(Number),
          }),
        }),
      ]),
    );
  });

  it("returns clarification for empty transcripts without calling the agent", async () => {
    const agentProvider = new CountingAgentProvider();
    const { request } = buildTestApp({
      sttProvider: new FakeSpeechToTextProvider("   "),
      agentProvider,
    });
    const { authHeader } = await registerAndAuth(request);

    const body = new FormData();
    body.append("audio", new Blob(["fake audio"], { type: "audio/m4a" }), "test.m4a");

    const res = await request("http://localhost/v1/voice/meal-runs", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body
    });

    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.transcript).toBe("   ");
    expect(json.result.kind).toBe("clarification_required");
    expect(json.result.message).toContain("could not understand");
    expect(agentProvider.calls).toBe(0);
  });

  it("does not return raw provider errors to clients", async () => {
    const { request } = buildTestApp({
      sttProvider: new ThrowingSpeechToTextProvider(),
    });
    const { authHeader } = await registerAndAuth(request);

    const body = new FormData();
    body.append("audio", new Blob(["fake audio"], { type: "audio/m4a" }), "test.m4a");

    const res = await request("http://localhost/v1/stt/transcriptions", {
      method: "POST",
      headers: bearerOnly(authHeader),
      body
    });

    expect(res.status).toBe(500);
    const json = await res.json();
    expect(json.error.code).toBe("internal_error");
    expect(json.error.message).toBe("We could not complete that request. Try again.");
    expect(json.error.message).not.toContain("provider secret exploded");
  });
});

function bearerOnly(authHeader: Record<string, string>): Record<string, string> {
  return { authorization: authHeader.authorization };
}

class CountingAgentProvider implements ChatAgentProvider {
  calls = 0;

  async runWithTools(): Promise<AgentToolDecision> {
    this.calls += 1;
    return { toolCalls: [], rawResponse: {} };
  }
}

class CollectingRunLogger implements LocalRunLogger {
  enabled = true;
  events: Record<string, unknown>[] = [];

  async log(event: Record<string, unknown>): Promise<void> {
    this.events.push(event);
  }
}

class ThrowingSpeechToTextProvider {
  async transcribe(): Promise<never> {
    throw new Error("provider secret exploded");
  }
}
