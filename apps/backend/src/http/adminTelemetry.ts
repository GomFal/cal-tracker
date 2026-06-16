import { HTTPException } from "hono/http-exception";
import { Hono, type Context } from "hono";
import {
  clientTelemetryIngestRequestSchema,
  telemetryEventsQuerySchema,
  telemetryFoodSearchQuerySchema,
  telemetryLlmRunsQuerySchema,
  telemetryOverviewQuerySchema,
  type ClientTelemetryIngestRequest,
  type FoodSearchEventSummary,
  type LlmRunSummary,
  type TelemetryEventSummary,
  type TelemetryEventsResponse,
  type TelemetryFoodSearchResponse,
  type TelemetryLlmRunsResponse,
  type TelemetryOverviewResponse,
  type TelemetryTraceResponse,
} from "@cal-tracker/contracts";
import { AdminAuthService } from "../auth/adminService.js";
import { TelemetryService } from "../telemetry/service.js";
import {
  type FoodSearchEventRecord,
  type LlmRunRecord,
  type StoredUser,
  type TelemetryEventRecord,
} from "../repository/types.js";

const DEFAULT_LOOKBACK_HOURS = 24;

export function registerAdminTelemetryRoutes(input: {
  app: Hono<{ Variables: { authUser: StoredUser; traceId: string } }>;
  adminAuthService: AdminAuthService;
  telemetry: TelemetryService;
}) {
  const { app, telemetry, adminAuthService } = input;

  app.get("/v1/admin/telemetry/overview", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = telemetryOverviewQuerySchema.parse(objectFromQuery(c));
    const range = resolveRange(parsed.from, parsed.to);
    const overview = await telemetry.getOverview(range);
    if (!overview) {
      throw new HTTPException(503, { message: "Telemetry overview unavailable." });
    }
    const response: TelemetryOverviewResponse = {
      from: overview.from,
      to: overview.to,
      totalEvents: overview.totalEvents,
      totalLlmRuns: overview.totalLlmRuns,
      totalFoodSearchEvents: overview.totalFoodSearchEvents,
      uniqueUsers: overview.uniqueUsers,
      uniqueTraces: overview.uniqueTraces,
      eventsBySeverity: overview.eventsBySeverity,
      eventsBySurface: overview.eventsBySurface,
      recentResultKinds: overview.recentResultKinds,
      zeroResultRate: overview.zeroResultRate,
      lowConfidenceRate: overview.lowConfidenceRate,
      providerErrorRate: overview.providerErrorRate,
    };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/events", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = telemetryEventsQuerySchema.parse(objectFromQuery(c));
    const events = await telemetry.listEvents(parsed);
    const response: TelemetryEventsResponse = { events: events.map(toEventSummary) };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/llm-runs", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = telemetryLlmRunsQuerySchema.parse(objectFromQuery(c));
    const runs = await telemetry.listLlmRuns(parsed);
    const response: TelemetryLlmRunsResponse = { llmRuns: runs.map(toLlmRunSummary) };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/food-search", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = telemetryFoodSearchQuerySchema.parse(objectFromQuery(c));
    const events = await telemetry.listFoodSearchEvents(parsed);
    const response: TelemetryFoodSearchResponse = {
      foodSearchEvents: events.map(toFoodSearchEventSummary),
    };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/traces/:traceId", async (c) => {
    await requireAdmin(c, adminAuthService);
    const traceId = c.req.param("traceId");
    if (!traceId) {
      throw new HTTPException(400, { message: "Missing traceId." });
    }
    const [events, llmRuns, foodSearchEvents] = await Promise.all([
      telemetry.listEvents({ traceId, limit: 200 }),
      telemetry.listLlmRuns({ traceId, limit: 100 }),
      telemetry.listFoodSearchEvents({ traceId, limit: 100 }),
    ]);
    const response: TelemetryTraceResponse = {
      traceId,
      events: events.map(toEventSummary),
      llmRuns: llmRuns.map(toLlmRunSummary),
      foodSearchEvents: foodSearchEvents.map(toFoodSearchEventSummary),
    };
    return c.json(response);
  });
}

export function registerClientTelemetryRoutes(input: {
  app: Hono<{ Variables: { authUser: StoredUser; traceId: string } }>;
  telemetry: TelemetryService;
}) {
  const { app, telemetry } = input;
  app.post("/v1/telemetry/client-events", async (c) => {
    const user = c.get("authUser");
    const body = clientTelemetryIngestRequestSchema.parse(await c.req.json()) as ClientTelemetryIngestRequest;
    const result = await telemetry.recordClientEvents({ userId: user.id, events: body.events });
    return c.json(result);
  });
}

async function requireAdmin(
  c: Context<{ Variables: { authUser: StoredUser; traceId: string } }>,
  adminAuthService: AdminAuthService,
): Promise<void> {
  await adminAuthService.authenticate(c.req.header("authorization"));
}

function resolveRange(from: string | undefined, to: string | undefined): { from: string; to: string } {
  const now = new Date();
  const toDate = to ? new Date(to) : now;
  const fromDate = from
    ? new Date(from)
    : new Date(toDate.getTime() - DEFAULT_LOOKBACK_HOURS * 60 * 60 * 1000);
  return {
    from: fromDate.toISOString(),
    to: toDate.toISOString(),
  };
}

function objectFromQuery(c: Context): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of new URL(c.req.url).searchParams.entries()) {
    result[key] = value;
  }
  return result;
}

function toEventSummary(event: TelemetryEventRecord): TelemetryEventSummary {
  return {
    id: event.id,
    traceId: event.traceId,
    userId: event.userId ?? null,
    sessionId: event.sessionId ?? null,
    eventType: event.eventType,
    flow: event.flow ?? null,
    surface: event.surface as TelemetryEventSummary["surface"],
    severity: event.severity as TelemetryEventSummary["severity"],
    status: (event.status as TelemetryEventSummary["status"] | undefined) ?? null,
    route: event.route ?? null,
    method: event.method ?? null,
    actionId: event.actionId ?? null,
    durationMs: event.durationMs ?? null,
    errorCode: event.errorCode ?? null,
    errorMessage: event.errorMessage ?? null,
    appVersion: event.appVersion ?? null,
    appBuild: event.appBuild ?? null,
    platform: event.platform ?? null,
    locale: event.locale ?? null,
    metadata: event.metadata,
    createdAt: event.createdAt,
  };
}

function toLlmRunSummary(run: LlmRunRecord): LlmRunSummary {
  return {
    id: run.id,
    traceId: run.traceId,
    userId: run.userId ?? null,
    source: run.source ?? null,
    locale: run.locale ?? null,
    timezone: run.timezone ?? null,
    model: run.model,
    inputMode: run.inputMode ?? null,
    activeProposalId: run.activeProposalId ?? null,
    decisionSource: run.decisionSource ?? null,
    selectedTool: run.selectedTool ?? null,
    executedTool: run.executedTool ?? null,
    resultKind: run.resultKind ?? null,
    actionCallId: run.actionCallId ?? null,
    promptChars: run.promptChars ?? null,
    toolsJsonChars: run.toolsJsonChars ?? null,
    messagesJsonChars: run.messagesJsonChars ?? null,
    requestPayloadChars: run.requestPayloadChars ?? null,
    promptTokens: run.promptTokens ?? null,
    completionTokens: run.completionTokens ?? null,
    totalTokens: run.totalTokens ?? null,
    reasoningTokens: run.reasoningTokens ?? null,
    firstByteMs: run.firstByteMs ?? null,
    firstToolCallMs: run.firstToolCallMs ?? null,
    largestStreamGapMs: run.largestStreamGapMs ?? null,
    llmMs: run.llmMs ?? null,
    actionMs: run.actionMs ?? null,
    totalMs: run.totalMs ?? null,
    emptyToolCall: run.emptyToolCall,
    invalidToolArguments: run.invalidToolArguments,
    providerError: run.providerError,
    metadata: run.metadata,
    createdAt: run.createdAt,
  };
}

function toFoodSearchEventSummary(event: FoodSearchEventRecord): FoodSearchEventSummary {
  return {
    id: event.id,
    traceId: event.traceId,
    userId: event.userId ?? null,
    queryText: event.queryText ?? null,
    queryHash: event.queryHash ?? null,
    queryLength: event.queryLength,
    locale: event.locale ?? null,
    barcodePresent: event.barcodePresent,
    normalizedSearchEnabled: event.normalizedSearchEnabled ?? null,
    normalizedScope: event.normalizedScope ?? null,
    path: event.path ?? null,
    resultCount: event.resultCount,
    candidateGroupCount: event.candidateGroupCount ?? null,
    topScore: event.topScore ?? null,
    topExternalSource: event.topExternalSource ?? null,
    topResultType: event.topResultType ?? null,
    zeroResults: event.zeroResults,
    lowConfidence: event.lowConfidence,
    selectedRank: event.selectedRank ?? null,
    durationMs: event.durationMs ?? null,
    metadata: event.metadata,
    createdAt: event.createdAt,
  };
}
