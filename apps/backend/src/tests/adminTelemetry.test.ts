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
      model: "test-model",
      resultKind: "proposal",
      selectedTool: "propose_meal_log",
      executedTool: "propose_meal_log",
      emptyToolCall: false,
      invalidToolArguments: false,
      providerError: false,
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

    const response = await request("http://localhost/v1/admin/telemetry/overview", {
      headers: admin.authHeader
    });
    expect(response.status).toBe(200);
    const body = await response.json() as {
      totalEvents: number;
      totalLlmRuns: number;
      totalFoodSearchEvents: number;
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

  it("returns a complete trace view including llm runs and food searches", async () => {
    const { request, telemetry } = buildTestApp();
    const admin = await loginAdmin(request);
    const user = await registerAndAuth(request);
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
      model: "test-model",
      resultKind: "proposal",
      emptyToolCall: false,
      invalidToolArguments: false,
      providerError: false
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
    };
    expect(body.traceId).toBe("trace-detail");
    expect(body.events.length).toBe(1);
    expect(body.llmRuns[0]?.model).toBe("test-model");
    expect(body.foodSearchEvents[0]?.resultCount).toBe(3);
  });

  it("rejects the admin endpoints without a bearer token", async () => {
    const { request } = buildTestApp();
    const response = await request("http://localhost/v1/admin/telemetry/overview");
    expect(response.status).toBe(401);
  });
});

describe("client telemetry ingestion", () => {
  it("accepts a batch of client events for the authenticated user", async () => {
    const { request } = buildTestApp();
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

    const me = await request("http://localhost/v1/auth/me", { headers: authHeader });
    expect(me.status).toBe(200);
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
        nested: { deep: "z".repeat(2_000) },
        ok: "small"
      }
    });
    expect(result).toBeDefined();
    expect(result?.metadata.ok).toBe("small");
  });

  it("truncates stored search query text and records a hash", async () => {
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
    expect(result?.queryText?.length).toBeLessThanOrEqual(120);
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
