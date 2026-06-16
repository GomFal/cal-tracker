import { afterEach, describe, expect, it } from "vitest";
import {
  type AgentToolDecision,
  type ChatAgentProvider,
} from "../agent/chatAgentProvider.js";
import { AgentService } from "../agent/agentService.js";
import {
  type FoodSearchTelemetryEvent,
  type FoodResolverTelemetryEvent,
  type LlmTelemetryEvent,
  type SttTelemetryEvent,
  type TelemetryService,
  type VoiceMealRunTelemetryEvent,
} from "../telemetry/telemetryService.js";
import {
  buildTestApp,
  FakeSpeechToTextProvider,
  registerAndAuth,
} from "./testApp.js";
import { FoodResolver } from "../nutrition/foodResolver.js";
import type {
  FoodDataProvider,
  FoodProviderResolution,
} from "../nutrition/foodResolver.js";
import type { FoodMention } from "@cal-tracker/contracts";

class RecordingTelemetryService implements TelemetryService {
  readonly enabled = true;
  llm: LlmTelemetryEvent[] = [];
  stt: SttTelemetryEvent[] = [];
  voice: VoiceMealRunTelemetryEvent[] = [];
  foodSearch: FoodSearchTelemetryEvent[] = [];
  foodResolver: FoodResolverTelemetryEvent[] = [];
  async recordLlmRun(event: LlmTelemetryEvent) { this.llm.push(event); }
  async recordSttEvent(event: SttTelemetryEvent) { this.stt.push(event); }
  async recordVoiceMealRunEvent(event: VoiceMealRunTelemetryEvent) { this.voice.push(event); }
  async recordFoodSearchEvent(event: FoodSearchTelemetryEvent) { this.foodSearch.push(event); }
  async recordFoodResolverEvent(event: FoodResolverTelemetryEvent) { this.foodResolver.push(event); }
}

class ThrowingChatAgentProvider implements ChatAgentProvider {
  async runWithTools(): Promise<AgentToolDecision> {
    throw new Error("provider_unavailable");
  }
}

class EmptyToolCallAgentProvider implements ChatAgentProvider {
  async runWithTools(): Promise<AgentToolDecision> {
    return { toolCalls: [], rawResponse: {} };
  }
}

class DisallowedToolAgentProvider implements ChatAgentProvider {
  async runWithTools(): Promise<AgentToolDecision> {
    return {
      toolCalls: [
        {
          id: "call_disallowed",
          type: "function",
          function: { name: "missing_tool", arguments: "{}" },
        },
      ],
      rawResponse: {},
    };
  }
}

class InvalidJsonAgentProvider implements ChatAgentProvider {
  async runWithTools(): Promise<AgentToolDecision> {
    return {
      toolCalls: [
        {
          id: "call_invalid",
          type: "function",
          function: { name: "propose_meal_log", arguments: "not-json" },
        },
      ],
      rawResponse: {},
    };
  }
}

class ThrowingFoodDataProvider implements FoodDataProvider {
  readonly id = "throwing_test_provider";
  async resolve(): Promise<FoodProviderResolution> {
    throw new Error("upstream provider down");
  }
}

function makeMention(): FoodMention {
  return {
    originalText: "100 grams of bread",
    canonicalName: "bread",
    canonicalEnglishName: "bread",
    language: "en",
    quantity: 100,
    unit: "g",
    rawUnitText: "grams",
    unitKind: "metric",
    confidence: 0.95,
    marketProduct: false,
  };
}
void makeMention;

const telemetry: RecordingTelemetryService[] = [];

afterEach(() => {
  telemetry.length = 0;
});

describe("AgentService LLM telemetry", () => {
  it("records a provider_error telemetry event when the agent provider throws", async () => {
    const { config, actionExecutor, agentProvider } = buildTestApp({
      agentProvider: new ThrowingChatAgentProvider(),
    });
    const recorder = new RecordingTelemetryService();
    telemetry.push(recorder);
    const service = new AgentService(
      agentProvider,
      actionExecutor,
      config.OPENROUTER_MODEL,
      undefined,
      recorder,
    );

    await expect(
      service.run("test", {
        actorUserId: "00000000-0000-0000-0000-000000000001",
        actorType: "user",
        source: "flutter",
        scopes: [],
        timezone: "UTC",
        locale: "en-US",
        trustedModeEnabled: false,
        traceId: "trace-provider-error",
      }),
    ).rejects.toThrow();

    expect(recorder.llm).toHaveLength(1);
    expect(recorder.llm[0]).toMatchObject({
      outcome: "provider_error",
      providerError: true,
      traceId: "trace-provider-error",
      timingsMs: expect.objectContaining({ total: expect.any(Number) }),
      errorMessage: expect.stringContaining("provider_unavailable"),
    });
  });

  it("records an empty_tool_call telemetry event when the LLM returns no tool calls", async () => {
    const { config, actionExecutor, agentProvider } = buildTestApp({
      agentProvider: new EmptyToolCallAgentProvider(),
    });
    const recorder = new RecordingTelemetryService();
    telemetry.push(recorder);
    const service = new AgentService(
      agentProvider,
      actionExecutor,
      config.OPENROUTER_MODEL,
      undefined,
      recorder,
    );

    const result = await service.run("hello", {
      actorUserId: "00000000-0000-0000-0000-000000000002",
      actorType: "user",
      source: "flutter",
      scopes: [],
      timezone: "UTC",
      locale: "en-US",
      trustedModeEnabled: false,
      traceId: "trace-empty-tool-call",
    });

    expect(result.kind).toBe("clarification_required");
    expect(recorder.llm).toHaveLength(1);
    expect(recorder.llm[0]).toMatchObject({
      outcome: "empty_tool_call",
      emptyToolCall: true,
      traceId: "trace-empty-tool-call",
    });
  });

  it("records a disallowed_tool telemetry event when the LLM picks an unknown tool", async () => {
    const { config, actionExecutor, agentProvider } = buildTestApp({
      agentProvider: new DisallowedToolAgentProvider(),
    });
    const recorder = new RecordingTelemetryService();
    telemetry.push(recorder);
    const service = new AgentService(
      agentProvider,
      actionExecutor,
      config.OPENROUTER_MODEL,
      undefined,
      recorder,
    );

    const result = await service.run("hello", {
      actorUserId: "00000000-0000-0000-0000-000000000003",
      actorType: "user",
      source: "flutter",
      scopes: [],
      timezone: "UTC",
      locale: "en-US",
      trustedModeEnabled: false,
      traceId: "trace-disallowed",
    });

    expect(result.kind).toBe("clarification_required");
    expect(recorder.llm).toHaveLength(1);
    expect(recorder.llm[0]).toMatchObject({
      outcome: "disallowed_tool",
      selectedTool: "missing_tool",
      traceId: "trace-disallowed",
    });
  });

  it("records an invalid_tool_arguments telemetry event when JSON parsing fails", async () => {
    const { config, actionExecutor, agentProvider } = buildTestApp({
      agentProvider: new InvalidJsonAgentProvider(),
    });
    const recorder = new RecordingTelemetryService();
    telemetry.push(recorder);
    const service = new AgentService(
      agentProvider,
      actionExecutor,
      config.OPENROUTER_MODEL,
      undefined,
      recorder,
    );

    const result = await service.run("hello", {
      actorUserId: "00000000-0000-0000-0000-000000000004",
      actorType: "user",
      source: "flutter",
      scopes: ["nutrition.write.propose"],
      timezone: "UTC",
      locale: "en-US",
      trustedModeEnabled: false,
      traceId: "trace-invalid-json",
    });

    expect(result.kind).toBe("clarification_required");
    expect(recorder.llm).toHaveLength(1);
    expect(recorder.llm[0]).toMatchObject({
      outcome: "invalid_tool_arguments",
      selectedTool: "propose_meal_log",
      invalidToolArguments: true,
      traceId: "trace-invalid-json",
      errorMessage: expect.any(String),
    });
  });
});

describe("FoodResolver telemetry", () => {
  it("emits a provider_error telemetry event when the data provider throws", async () => {
    const recorder = new RecordingTelemetryService();
    telemetry.push(recorder);
    const resolver = new FoodResolver(new ThrowingFoodDataProvider(), 0.5, recorder);

    const { items } = await resolver.search("user-1", "rice", undefined, "en-US");

    expect(items).toEqual([]);
    expect(recorder.foodResolver).toHaveLength(1);
    expect(recorder.foodResolver[0]).toMatchObject({
      outcome: "provider_error",
      provider: "throwing_test_provider",
      canonicalName: expect.stringMatching(/rice/),
      errorMessage: "upstream provider down",
    });
  });

  it("does not throw when the telemetry service itself fails", async () => {
    const failingService: TelemetryService = {
      enabled: true,
      async recordLlmRun() { throw new Error("sink-failure"); },
      async recordSttEvent() { throw new Error("sink-failure"); },
      async recordVoiceMealRunEvent() { throw new Error("sink-failure"); },
      async recordFoodSearchEvent() { throw new Error("sink-failure"); },
      async recordFoodResolverEvent() { throw new Error("sink-failure"); },
    };
    const resolver = new FoodResolver(new ThrowingFoodDataProvider(), 0.5, failingService);
    const { items } = await resolver.search("user-2", "rice", undefined, "en-US");
    expect(items).toEqual([]);
  });
});

describe("HTTP route telemetry", () => {
  it("emits started/completed STT telemetry", async () => {
    const recorder = new RecordingTelemetryService();
    telemetry.push(recorder);
    const { request } = buildTestApp({
      sttProvider: new FakeSpeechToTextProvider(),
      telemetryService: recorder,
    });
    const { authHeader } = await registerAndAuth(request);

    const body = new FormData();
    body.append("audio", new Blob(["fake audio"], { type: "audio/m4a" }), "test.m4a");
    const res = await request("http://localhost/v1/stt/transcriptions", {
      method: "POST",
      headers: { authorization: authHeader.authorization },
      body,
    });
    expect(res.status).toBe(200);
    expect(recorder.stt.map((e) => e.outcome)).toEqual(["started", "completed"]);
    expect(recorder.stt[0]).toMatchObject({
      flow: "stt",
      surface: "stt",
      outcome: "started",
      filename: "test.m4a",
      bytes: expect.any(Number),
    });
    expect(recorder.stt[1]).toMatchObject({
      outcome: "completed",
      provider: "test",
      model: "test-model",
      transcriptLength: expect.any(Number),
    });
  });

  it("emits started/failed STT telemetry when the provider throws", async () => {
    const recorder = new RecordingTelemetryService();
    telemetry.push(recorder);
    const throwingProvider: import("../stt/speechToTextProvider.js").SpeechToTextProvider = {
      async transcribe(): Promise<never> {
        throw new Error("stt blew up");
      },
    };
    const { request } = buildTestApp({
      sttProvider: throwingProvider,
      telemetryService: recorder,
    });
    const { authHeader } = await registerAndAuth(request);

    const body = new FormData();
    body.append("audio", new Blob(["fake audio"], { type: "audio/m4a" }), "test.m4a");
    const res = await request("http://localhost/v1/stt/transcriptions", {
      method: "POST",
      headers: { authorization: authHeader.authorization },
      body,
    });
    expect(res.status).toBe(500);
    expect(recorder.stt.map((e) => e.outcome)).toEqual(["started", "failed"]);
    expect(recorder.stt[1]).toMatchObject({
      outcome: "failed",
      errorMessage: "stt blew up",
    });
  });

  it("emits zero-results food search telemetry when the query matches nothing", async () => {
    const recorder = new RecordingTelemetryService();
    telemetry.push(recorder);
    const { request } = buildTestApp({ telemetryService: recorder });
    const { authHeader } = await registerAndAuth(request);

    const res = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ query: "this food does not exist 12345 xyz" }),
    });
    expect(res.status).toBe(200);
    expect(recorder.foodSearch).toHaveLength(1);
    expect(recorder.foodSearch[0]).toMatchObject({
      flow: "food_search",
      surface: "backend",
      zeroResults: true,
      lowConfidence: false,
      queryLength: expect.any(Number),
      queryHash: expect.any(String),
      resultCount: 0,
    });
  });
});
