import { describe, expect, it } from "vitest";
import { PostgresRepository } from "../repository/postgres.js";
import { buildTestApp, loginAdmin, registerAndAuth } from "./testApp.js";

describe("admin telemetry routes", () => {
  it("rejects normal user tokens with 401", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/admin/telemetry/overview", {
      headers: authHeader
    });
    expect(response.status).toBe(401);
    const body = await response.json() as { error: { code: string; message: string } };
    expect(body.error.code).toBe("admin_token_invalid");
  });

  it("returns an overview for admin users", async () => {
    const { request, telemetry } = buildTestApp();
    const admin = await loginAdmin(request);
    const user = await registerAndAuth(request);
    await telemetry.recordLlmRun({
      traceId: "trace-admin-1",
      userId: user.user.id,
      conversationId: "00000000-0000-0000-0000-000000000101",
      turnId: "00000000-0000-0000-0000-000000000102",
      provider: "openrouter",
      providerRequestId: "req_admin_1",
      providerGenerationId: "gen_admin_1",
      model: "test-model",
      resultKind: "proposal",
      selectedTool: "propose_meal_log",
      executedTool: "propose_meal_log",
      emptyToolCall: false,
      invalidToolArguments: false,
      providerError: false,
      promptTokens: 10,
      completionTokens: 20,
      totalTokens: 30,
      providerCostAmount: 0.00042,
      costCurrency: "USD",
      costSource: "provider",
      llmMs: 250,
      totalMs: 300,
      metadata: { source: "text" }
    });
    await telemetry.recordFoodSearchEvent({
      traceId: "trace-admin-2",
      userId: user.user.id,
      queryLength: 6,
      resultCount: 0,
      zeroResults: true,
      lowConfidence: false,
      barcodePresent: false,
      durationMs: 32,
      metadata: { query: "pizza" }
    });
    await telemetry.recordEvent({
      traceId: "trace-admin-3",
      userId: user.user.id,
      eventType: "mobile.api_request_failed",
      surface: "mobile",
      severity: "warning",
      status: "failure",
      route: "/v1/agent/runs",
      errorCode: "agent_provider_unavailable",
      durationMs: 1234
    });
    await telemetry.recordAgentTurn({
      traceId: "trace-admin-1",
      turnId: "00000000-0000-0000-0000-000000000102",
      userId: user.user.id,
      conversationId: "00000000-0000-0000-0000-000000000101",
      inputMode: "text",
      source: "flutter",
      model: "test-model",
      resultKind: "proposal",
      stopReason: "assistant_response",
      iterationCount: 1,
      toolCallCount: 1,
      promptTokens: 10,
      completionTokens: 20,
      totalTokens: 30,
      providerCostAmount: 0.00042,
      costCurrency: "USD",
      costSource: "provider",
      totalMs: 300,
      status: "success",
      completedAt: new Date().toISOString()
    });
    await telemetry.recordLlmProviderCall({
      traceId: "trace-admin-1",
      userId: user.user.id,
      conversationId: "00000000-0000-0000-0000-000000000101",
      turnId: "00000000-0000-0000-0000-000000000102",
      featureSurface: "agent_chat",
      provider: "openrouter",
      providerRequestId: "req_admin_1",
      providerGenerationId: "gen_admin_1",
      requestedModel: "test-model",
      servedModel: "test-model",
      promptTokens: 10,
      completionTokens: 20,
      totalTokens: 30,
      providerCostAmount: 0.00042,
      costCurrency: "USD",
      costSource: "provider",
      status: "success",
      durationMs: 250
    });
    await telemetry.recordTranscriptionRecord({
      traceId: "trace-admin-4",
      userId: user.user.id,
      surface: "agent_chat_audio",
      provider: "test",
      model: "test-model",
      audioMimeType: "audio/m4a",
      audioBytes: 123,
      transcriptText: "I had toast",
      transcriptLength: 11,
      status: "completed",
      durationMs: 20
    });

    const response = await request("http://localhost/v1/admin/telemetry/overview", {
      headers: admin.authHeader
    });
    expect(response.status).toBe(200);
    const body = await response.json() as {
      totalEvents: number;
      totalLlmRuns: number;
      totalFoodSearchEvents: number;
      totalAgentTurns: number;
      totalProviderCalls: number;
      totalTranscriptions: number;
      providerCostAmount: number;
      unknownCostCount: number;
      eventsBySeverity: Record<string, number>;
      recentResultKinds: Record<string, number>;
      zeroResultRate: number;
    };
    expect(body.totalLlmRuns).toBeGreaterThanOrEqual(1);
    expect(body.totalFoodSearchEvents).toBeGreaterThanOrEqual(1);
    expect(body.totalEvents).toBeGreaterThanOrEqual(1);
    expect(body.eventsBySeverity.warning ?? 0).toBeGreaterThanOrEqual(1);
    expect(body.recentResultKinds.proposal ?? 0).toBeGreaterThanOrEqual(1);
    expect(body.zeroResultRate).toBeGreaterThanOrEqual(1);
    expect(body.totalAgentTurns).toBeGreaterThanOrEqual(1);
    expect(body.totalProviderCalls).toBeGreaterThanOrEqual(1);
    expect(body.totalTranscriptions).toBeGreaterThanOrEqual(1);
    expect(body.providerCostAmount).toBeGreaterThan(0);
    expect(body.unknownCostCount).toBe(0);
  });

  it("returns events filtered by traceId", async () => {
    const { request, telemetry } = buildTestApp();
    const admin = await loginAdmin(request);
    const user = await registerAndAuth(request);
    await telemetry.recordEvent({
      traceId: "trace-shared",
      userId: user.user.id,
      eventType: "backend.api_request_started",
      surface: "backend",
      severity: "info"
    });
    await telemetry.recordEvent({
      traceId: "trace-shared",
      userId: user.user.id,
      eventType: "backend.api_request_completed",
      surface: "backend",
      severity: "info",
      durationMs: 32
    });
    await telemetry.recordEvent({
      traceId: "trace-other",
      userId: user.user.id,
      eventType: "backend.api_request_started",
      surface: "backend",
      severity: "info"
    });

    const response = await request("http://localhost/v1/admin/telemetry/events?traceId=trace-shared&limit=10", {
      headers: admin.authHeader
    });
    expect(response.status).toBe(200);
    const body = await response.json() as { events: Array<{ traceId: string; eventType: string }> };
    expect(body.events.length).toBe(2);
    for (const event of body.events) {
      expect(event.traceId).toBe("trace-shared");
    }
  });

  it("returns a complete trace view including conversations, agent turns, provider calls, action calls, and transcriptions", async () => {
    const { request, telemetry, repository } = buildTestApp();
    const admin = await loginAdmin(request);
    const user = await registerAndAuth(request);
    const conversation = await repository.createAgentConversation(user.user.id, {
      title: "Trace detail chat",
    });
    await repository.addAgentConversationMessage(user.user.id, conversation.id, {
      role: "user",
      content: "I ate bread",
      toolCalls: [],
      traceId: "trace-detail",
      turnId: "00000000-0000-0000-0000-000000000202",
      inputMode: "voice",
      source: "flutter",
      metadata: { source: "test" },
    });
    await repository.recordActionCall({
      userId: user.user.id,
      actionId: "propose_meal_log",
      source: "agent_chat",
      input: { text: "bread" },
      output: { kind: "proposal" },
      confirmationStatus: "not_required",
      traceId: "trace-detail",
      latencyMs: 45,
    });
    await telemetry.recordEvent({
      traceId: "trace-detail",
      userId: user.user.id,
      eventType: "agent.run_started",
      surface: "agent",
      severity: "info"
    });
    await telemetry.recordLlmRun({
      traceId: "trace-detail",
      userId: user.user.id,
      conversationId: conversation.id,
      turnId: "00000000-0000-0000-0000-000000000202",
      provider: "openrouter",
      model: "test-model",
      resultKind: "proposal",
      emptyToolCall: false,
      invalidToolArguments: false,
      providerError: false
    });
    await telemetry.recordAgentTurn({
      traceId: "trace-detail",
      turnId: "00000000-0000-0000-0000-000000000202",
      userId: user.user.id,
      conversationId: conversation.id,
      inputMode: "voice",
      source: "flutter",
      model: "test-model",
      inputText: "I ate bread",
      assistantText: "Here is a proposal.",
      resultKind: "proposal",
      stopReason: "assistant_response",
      iterationCount: 1,
      toolCallCount: 1,
      totalTokens: 33,
      estimatedCostAmount: 0.0002,
      costCurrency: "USD",
      costSource: "estimate",
      status: "success",
      completedAt: new Date().toISOString()
    });
    await telemetry.recordAgentToolCall({
      conversationId: conversation.id,
      traceId: "trace-detail",
      turnId: "00000000-0000-0000-0000-000000000202",
      userId: user.user.id,
      toolCallId: "call_trace_detail",
      actionId: "propose_meal_log",
      arguments: { text: "bread" },
      resultSummary: { kind: "proposal" },
      status: "completed",
      startedAt: new Date().toISOString(),
      completedAt: new Date().toISOString(),
      durationMs: 45
    });
    await telemetry.recordLlmProviderCall({
      traceId: "trace-detail",
      userId: user.user.id,
      conversationId: conversation.id,
      turnId: "00000000-0000-0000-0000-000000000202",
      featureSurface: "agent_chat",
      provider: "openrouter",
      providerRequestId: "req_trace_detail",
      providerGenerationId: "gen_trace_detail",
      requestedModel: "test-model",
      servedModel: "served-test-model",
      promptTokens: 11,
      completionTokens: 22,
      totalTokens: 33,
      estimatedCostAmount: 0.0002,
      costCurrency: "USD",
      costSource: "estimate",
      status: "success",
      durationMs: 123
    });
    await telemetry.recordTranscriptionRecord({
      traceId: "trace-detail",
      userId: user.user.id,
      conversationId: conversation.id,
      turnId: "00000000-0000-0000-0000-000000000202",
      surface: "agent_chat_audio",
      provider: "test",
      model: "test-model",
      audioMimeType: "audio/m4a",
      audioBytes: 345,
      transcriptText: "I ate bread",
      transcriptLength: 11,
      status: "completed",
      durationMs: 30
    });
    await telemetry.recordFoodSearchEvent({
      traceId: "trace-detail",
      userId: user.user.id,
      queryLength: 4,
      resultCount: 3,
      zeroResults: false,
      lowConfidence: false,
      barcodePresent: false
    });

    const response = await request("http://localhost/v1/admin/telemetry/traces/trace-detail", {
      headers: admin.authHeader
    });
    expect(response.status).toBe(200);
    const body = await response.json() as {
      traceId: string;
      events: unknown[];
      llmRuns: Array<{ model: string }>;
      foodSearchEvents: Array<{ resultCount: number }>;
      conversationMessages: Array<{ conversationId: string; inputMode: string }>;
      agentTurns: Array<{ turnId: string; conversationId: string }>;
      agentToolCalls: Array<{ actionId: string; turnId: string }>;
      actionCalls: Array<{ actionId: string; traceId: string }>;
      providerCalls: Array<{ providerGenerationId: string; totalTokens: number }>;
      transcriptions: Array<{ transcriptText: string; conversationId: string }>;
    };
    expect(body.traceId).toBe("trace-detail");
    expect(body.events.length).toBe(1);
    expect(body.llmRuns[0]?.model).toBe("test-model");
    expect(body.foodSearchEvents[0]?.resultCount).toBe(3);
    expect(body.conversationMessages[0]).toMatchObject({
      conversationId: conversation.id,
      inputMode: "voice",
    });
    expect(body.agentTurns[0]).toMatchObject({
      turnId: "00000000-0000-0000-0000-000000000202",
      conversationId: conversation.id,
    });
    expect(body.agentToolCalls[0]).toMatchObject({
      actionId: "propose_meal_log",
      turnId: "00000000-0000-0000-0000-000000000202",
    });
    expect(body.actionCalls[0]).toMatchObject({
      actionId: "propose_meal_log",
      traceId: "trace-detail",
    });
    expect(body.providerCalls[0]).toMatchObject({
      providerGenerationId: "gen_trace_detail",
      totalTokens: 33,
    });
    expect(body.transcriptions[0]).toMatchObject({
      transcriptText: "I ate bread",
      conversationId: conversation.id,
    });
  });

  it("exposes hidden conversations only when includeHidden=true", async () => {
    const { request, repository } = buildTestApp();
    const admin = await loginAdmin(request);
    const user = await registerAndAuth(request);
    const conversation = await repository.createAgentConversation(user.user.id, {
      title: "Hidden admin audit chat",
    });
    await repository.addAgentConversationMessage(user.user.id, conversation.id, {
      role: "user",
      content: "private beta message",
      toolCalls: [],
      traceId: "trace-hidden-chat",
      turnId: "00000000-0000-0000-0000-000000000302",
      inputMode: "text",
      source: "flutter",
      metadata: {},
    });
    await repository.hideAgentConversationFromUser(user.user.id, conversation.id);

    const visibleOnly = await request(
      "http://localhost/v1/admin/telemetry/conversations?traceId=trace-hidden-chat",
      { headers: admin.authHeader },
    );
    expect(visibleOnly.status).toBe(200);
    await expect(visibleOnly.json()).resolves.toEqual({ conversations: [] });

    const includingHidden = await request(
      "http://localhost/v1/admin/telemetry/conversations?traceId=trace-hidden-chat&includeHidden=true",
      { headers: admin.authHeader },
    );
    expect(includingHidden.status).toBe(200);
    const listBody = await includingHidden.json() as {
      conversations: Array<{ id: string; hiddenFromUserAt: string | null }>;
    };
    expect(listBody.conversations[0]).toMatchObject({
      id: conversation.id,
      hiddenFromUserAt: expect.any(String),
    });

    const detail = await request(
      `http://localhost/v1/admin/telemetry/conversations/${conversation.id}?includeHidden=true`,
      { headers: admin.authHeader },
    );
    expect(detail.status).toBe(200);
    const detailBody = await detail.json() as {
      messages: Array<{ content: string; traceId: string }>;
    };
    expect(detailBody.messages[0]).toMatchObject({
      content: "private beta message",
      traceId: "trace-hidden-chat",
    });
  });

  it("returns new admin telemetry list endpoints and LLM cost breakdowns", async () => {
    const { request, telemetry, repository } = buildTestApp();
    const admin = await loginAdmin(request);
    const user = await registerAndAuth(request);
    const conversation = await repository.createAgentConversation(user.user.id, {
      title: "Cost chat",
    });
    const turnId = "00000000-0000-0000-0000-000000000402";
    await repository.recordActionCall({
      userId: user.user.id,
      actionId: "commit_meal_log",
      source: "agent_chat",
      input: { id: "proposal" },
      output: { kind: "meal_committed" },
      confirmationStatus: "confirmed",
      traceId: "trace-list-surfaces",
      latencyMs: 88,
    });
    await telemetry.recordAgentTurn({
      traceId: "trace-list-surfaces",
      turnId,
      userId: user.user.id,
      conversationId: conversation.id,
      inputMode: "text",
      source: "flutter",
      model: "test-model",
      resultKind: "meal_committed",
      stopReason: "assistant_response",
      iterationCount: 2,
      toolCallCount: 1,
      totalTokens: 40,
      providerCostAmount: 0.001,
      costCurrency: "USD",
      costSource: "provider",
      status: "success",
      completedAt: new Date().toISOString()
    });
    await telemetry.recordAgentToolCall({
      conversationId: conversation.id,
      traceId: "trace-list-surfaces",
      turnId,
      userId: user.user.id,
      toolCallId: "call_commit",
      actionId: "commit_meal_log",
      arguments: { id: "proposal" },
      resultSummary: { kind: "meal_committed" },
      status: "completed",
      startedAt: new Date().toISOString(),
      completedAt: new Date().toISOString(),
      durationMs: 88,
    });
    await telemetry.recordLlmProviderCall({
      traceId: "trace-list-surfaces",
      userId: user.user.id,
      conversationId: conversation.id,
      turnId,
      featureSurface: "agent_chat",
      provider: "openrouter",
      providerRequestId: "req_list",
      providerGenerationId: "gen_list",
      requestedModel: "test-model",
      servedModel: "test-model",
      promptTokens: 15,
      completionTokens: 25,
      totalTokens: 40,
      providerCostAmount: 0.001,
      costCurrency: "USD",
      costSource: "provider",
      status: "success",
      durationMs: 140,
    });
    await telemetry.recordTranscriptionRecord({
      traceId: "trace-list-surfaces",
      userId: user.user.id,
      conversationId: conversation.id,
      turnId,
      surface: "stt",
      provider: "test",
      model: "test-model",
      transcriptText: "commit it",
      transcriptLength: 9,
      status: "completed",
    });

    const [turns, tools, actions, providers, transcriptions, cost] =
      await Promise.all([
        request("http://localhost/v1/admin/telemetry/agent-turns?traceId=trace-list-surfaces", { headers: admin.authHeader }),
        request("http://localhost/v1/admin/telemetry/agent-tool-calls?traceId=trace-list-surfaces", { headers: admin.authHeader }),
        request("http://localhost/v1/admin/telemetry/action-calls?traceId=trace-list-surfaces", { headers: admin.authHeader }),
        request("http://localhost/v1/admin/telemetry/llm-provider-calls?traceId=trace-list-surfaces", { headers: admin.authHeader }),
        request("http://localhost/v1/admin/telemetry/transcriptions?traceId=trace-list-surfaces", { headers: admin.authHeader }),
        request("http://localhost/v1/admin/telemetry/llm-cost?traceId=trace-list-surfaces", { headers: admin.authHeader }),
      ]);

    expect(turns.status).toBe(200);
    expect(tools.status).toBe(200);
    expect(actions.status).toBe(200);
    expect(providers.status).toBe(200);
    expect(transcriptions.status).toBe(200);
    expect(cost.status).toBe(200);
    await expect(turns.json()).resolves.toMatchObject({
      agentTurns: [expect.objectContaining({ turnId, totalTokens: 40 })],
    });
    await expect(tools.json()).resolves.toMatchObject({
      agentToolCalls: [expect.objectContaining({ actionId: "commit_meal_log" })],
    });
    await expect(actions.json()).resolves.toMatchObject({
      actionCalls: [expect.objectContaining({ actionId: "commit_meal_log" })],
    });
    await expect(providers.json()).resolves.toMatchObject({
      providerCalls: [expect.objectContaining({ providerGenerationId: "gen_list" })],
    });
    await expect(transcriptions.json()).resolves.toMatchObject({
      transcriptions: [expect.objectContaining({ transcriptText: "commit it" })],
    });
    await expect(cost.json()).resolves.toMatchObject({
      totalProviderCostAmount: 0.001,
      totalEstimatedCostAmount: 0,
      unknownCostCount: 0,
      byConversation: [expect.objectContaining({ key: conversation.id, providerCostAmount: 0.001 })],
      byTurn: [expect.objectContaining({ key: turnId, totalTokens: 40 })],
    });
  });

  it("rejects the admin endpoints without a bearer token", async () => {
    const { request } = buildTestApp();
    const response = await request("http://localhost/v1/admin/telemetry/overview");
    expect(response.status).toBe(401);
  });
});

describe("client telemetry ingestion", () => {
  it("accepts a batch of client events for the authenticated user", async () => {
    const { request, telemetry } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/telemetry/client-events", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        events: [
          {
            eventType: "mobile.api_request_failed",
            flow: "voice_meal",
            surface: "mobile",
            severity: "warning",
            status: "failure",
            traceId: "trace-client-1",
            route: "/v1/agent/runs",
            method: "POST",
            durationMs: 1500,
            errorCode: "agent_provider_unavailable",
            appVersion: "1.0.0",
            appBuild: "100",
            platform: "android",
            locale: "en-US",
            metadata: { hint: "first" }
          },
          {
            eventType: "mobile.food_search_results",
            flow: "search",
            surface: "mobile",
            severity: "info",
            traceId: "trace-client-2",
            metadata: { resultCount: 4 }
          }
        ]
      })
    });
    expect(response.status).toBe(200);
    const body = await response.json() as { accepted: number };
    expect(body.accepted).toBe(2);

    const events = await telemetry.listEvents({ traceId: "trace-client-1", limit: 10 });
    expect(events[0]).toMatchObject({
      eventType: "mobile.api_request_failed",
      surface: "mobile",
    });

    const me = await request("http://localhost/v1/auth/me", { headers: authHeader });
    expect(me.status).toBe(200);
  });

  it("rejects non-mobile client telemetry event types", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/telemetry/client-events", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        events: [
          {
            eventType: "backend.api_request_completed",
            surface: "mobile",
            severity: "info",
            traceId: "trace-client-dropped-backend"
          }
        ]
      })
    });
    expect(response.status).toBe(400);
  });

  it("rejects an oversized batch with a 400", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);
    const events = Array.from({ length: 60 }, (_, index) => ({
      eventType: "mobile.api_request_failed",
      surface: "mobile",
      severity: "warning",
      traceId: `trace-${index}`
    }));

    const response = await request("http://localhost/v1/telemetry/client-events", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ events })
    });
    expect(response.status).toBe(400);
  });

  it("rejects invalid severity values", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/telemetry/client-events", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        events: [
          {
            eventType: "mobile.api_request_failed",
            surface: "mobile",
            severity: "fatal"
          }
        ]
      })
    });
    expect(response.status).toBe(400);
  });

  it("rejects non-mobile client telemetry surfaces", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/telemetry/client-events", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({
        events: [
          {
            eventType: "backend.api_request_failed",
            surface: "backend",
            severity: "warning"
          }
        ]
      })
    });
    expect(response.status).toBe(400);
  });
});

describe("Postgres telemetry overview", () => {
  it("uses a global unique trace count instead of summing table-local trace counts", async () => {
    const repository = new PostgresRepository("postgres://cal_tracker:cal_tracker@localhost:5432/cal_tracker");
    const executeResponses: Array<Record<string, unknown>[]> = [
      [{
        total_events: 2,
        total_llm_runs: 2,
        total_food_search_events: 2,
        event_unique_traces: 2,
        llm_unique_traces: 2,
        food_unique_traces: 2,
        unique_traces: 2,
        zero_results_count: 1,
        low_confidence_count: 1,
        provider_error_count: 1
      }],
      [{ user_id: "user-a" }, { user_id: "user-b" }],
      [{ severity: "warning", count: 2 }],
      [{ surface: "mobile", count: 2 }],
      [{ result_kind: "proposal", count: 2 }]
    ];

    (repository as unknown as { execute: () => Promise<Record<string, unknown>[]> }).execute =
      async () => executeResponses.shift() ?? [];

    try {
      const overview = await repository.getTelemetryOverview({
        from: "2026-06-16T00:00:00.000Z",
        to: "2026-06-16T23:59:59.999Z"
      });

      expect(overview.uniqueTraces).toBe(2);
      expect(overview.uniqueUsers).toBe(2);
      expect(overview.zeroResultRate).toBe(0.5);
      expect(overview.providerErrorRate).toBe(0.5);
    } finally {
      await repository.close();
    }
  });
});

describe("telemetry service", () => {
  it("sanitizes long metadata blobs and keeps records compact", async () => {
    const { telemetry } = buildTestApp();
    const result = await telemetry.recordEvent({
      traceId: "trace-sanitize",
      eventType: "backend.api_request_failed",
      surface: "backend",
      severity: "error",
      status: "failure",
      errorCode: "internal_error",
      errorMessage: "x".repeat(5_000),
      metadata: {
        longValue: "y".repeat(2_000),
        nested: {
          authorization: "Bearer secret",
          deep: "z".repeat(2_000),
          child: {
            password: "pw",
            transcript: "spoken meal details",
            queryHash: "abc123",
            queryLength: 42
          }
        },
        email: "user@example.com",
        originalText: "raw food mention",
        promptTokens: 123,
        ok: "small"
      }
    });
    expect(result).toBeDefined();
    expect(result?.metadata.ok).toBe("small");
    expect(result?.metadata.email).toBe("[redacted]");
    expect(result?.metadata.originalText).toBe("[redacted]");
    expect(result?.metadata.promptTokens).toBe(123);
    expect(result?.metadata.nested).toMatchObject({
      authorization: "[redacted]",
      child: {
        password: "[redacted]",
        transcript: "[redacted]",
        queryHash: "abc123",
        queryLength: 42
      }
    });
  });

  it("does not store raw search query text and records query metrics", async () => {
    const { telemetry } = buildTestApp();
    const longQuery = "apple ".repeat(40);
    const result = await telemetry.recordFoodSearchEvent({
      traceId: "trace-query",
      queryText: longQuery,
      resultCount: 0,
      zeroResults: true,
      lowConfidence: false,
      barcodePresent: false
    });
    expect(result).toBeDefined();
    expect(result?.queryText).toBeUndefined();
    expect(result?.queryLength).toBe(longQuery.length);
    expect(result?.queryHash).toMatch(/^[a-f0-9]{32}$/);
  });

  it("returns zero counts when the service is disabled", async () => {
    const { repository } = buildTestApp();
    const { TelemetryService } = await import("../telemetry/service.js");
    const disabled = new TelemetryService(repository, { enabled: false });
    const result = await disabled.recordEvent({
      traceId: "trace-disabled",
      eventType: "backend.api_request_failed",
      surface: "backend",
      severity: "info"
    });
    expect(result).toBeUndefined();
    const overview = await disabled.getOverview({
      from: new Date(Date.now() - 60_000).toISOString(),
      to: new Date().toISOString()
    });
    expect(overview).toBeDefined();
    expect(overview?.totalEvents).toBe(0);
  });
});
