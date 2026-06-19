import { HTTPException } from "hono/http-exception";
import { Hono, type Context } from "hono";
import {
  adminTelemetryActionCallsQuerySchema,
  adminTelemetryAgentToolCallsQuerySchema,
  adminTelemetryAgentTurnsQuerySchema,
  adminTelemetryConversationsQuerySchema,
  adminTelemetryCostQuerySchema,
  adminTelemetryProviderCallsQuerySchema,
  adminTelemetryTranscriptionsQuerySchema,
  clientTelemetryIngestRequestSchema,
  telemetryEventsQuerySchema,
  telemetryFoodSearchQuerySchema,
  telemetryLlmRunsQuerySchema,
  telemetryOverviewQuerySchema,
  type AdminActionCallSummary,
  type AdminActionCallsResponse,
  type AdminAgentConversationDetailResponse,
  type AdminAgentConversationsResponse,
  type AdminAgentToolCallSummary,
  type AdminAgentToolCallsResponse,
  type AdminAgentTurnSummary,
  type AdminAgentTurnsResponse,
  type AdminLlmCostResponse,
  type AdminLlmProviderCallSummary,
  type AdminLlmProviderCallsResponse,
  type AdminTranscriptionSummary,
  type AdminTranscriptionsResponse,
  type AgentConversationMessage,
  type AgentConversationSummary,
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
  type ActionCallRecord,
  type AgentConversationMessageRecord,
  type AgentConversationRecord,
  type AgentToolCallTelemetryRecord,
  type AgentTurnTelemetryRecord,
  type FoodSearchEventRecord,
  type LlmRunRecord,
  type LlmProviderCallRecord,
  type StoredUser,
  type TelemetryEventRecord,
  type TranscriptionRecord,
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
      totalConversations: overview.totalConversations,
      totalAgentTurns: overview.totalAgentTurns,
      totalProviderCalls: overview.totalProviderCalls,
      totalTranscriptions: overview.totalTranscriptions,
      providerCostAmount: overview.providerCostAmount,
      estimatedCostAmount: overview.estimatedCostAmount,
      unknownCostCount: overview.unknownCostCount,
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

  app.get("/v1/admin/telemetry/conversations", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = adminTelemetryConversationsQuerySchema.parse(objectFromQuery(c));
    const conversations = await telemetry.listAdminAgentConversations(parsed);
    const response: AdminAgentConversationsResponse = {
      conversations: conversations.map(toConversationSummary),
    };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/conversations/:conversationId", async (c) => {
    await requireAdmin(c, adminAuthService);
    const conversationId = c.req.param("conversationId");
    const includeHidden = c.req.query("includeHidden") === "true";
    const conversations = await telemetry.listAdminAgentConversations({
      conversationId,
      includeHidden,
      limit: 1,
    });
    const conversation = conversations[0];
    if (!conversation) {
      throw new HTTPException(404, { message: "agent_conversation_not_found" });
    }
    const messages = await telemetry.getAdminAgentConversationMessages(
      conversationId,
      includeHidden,
    );
    const response: AdminAgentConversationDetailResponse = {
      conversation: toConversationSummary(conversation),
      messages: messages.map(toConversationMessage),
    };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/action-calls", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = adminTelemetryActionCallsQuerySchema.parse(objectFromQuery(c));
    const actionCalls = await telemetry.listAdminActionCalls(parsed);
    const response: AdminActionCallsResponse = {
      actionCalls: actionCalls.map(toActionCallSummary),
    };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/agent-turns", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = adminTelemetryAgentTurnsQuerySchema.parse(objectFromQuery(c));
    const agentTurns = await telemetry.listAgentTurns(parsed);
    const response: AdminAgentTurnsResponse = {
      agentTurns: agentTurns.map(toAgentTurnSummary),
    };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/agent-tool-calls", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = adminTelemetryAgentToolCallsQuerySchema.parse(objectFromQuery(c));
    const agentToolCalls = await telemetry.listAgentToolCalls(parsed);
    const response: AdminAgentToolCallsResponse = {
      agentToolCalls: agentToolCalls.map(toAgentToolCallSummary),
    };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/llm-provider-calls", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = adminTelemetryProviderCallsQuerySchema.parse(objectFromQuery(c));
    const providerCalls = await telemetry.listLlmProviderCalls(parsed);
    const response: AdminLlmProviderCallsResponse = {
      providerCalls: providerCalls.map(toProviderCallSummary),
    };
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/llm-cost", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = adminTelemetryCostQuerySchema.parse(objectFromQuery(c));
    const range = resolveRange(parsed.from, parsed.to);
    const overview = await telemetry.getLlmCostOverview({
      ...range,
      userId: parsed.userId,
      conversationId: parsed.conversationId,
      traceId: parsed.traceId,
    });
    if (!overview) {
      throw new HTTPException(503, { message: "LLM cost overview unavailable." });
    }
    const response: AdminLlmCostResponse = overview;
    return c.json(response);
  });

  app.get("/v1/admin/telemetry/transcriptions", async (c) => {
    await requireAdmin(c, adminAuthService);
    const parsed = adminTelemetryTranscriptionsQuerySchema.parse(objectFromQuery(c));
    const transcriptions = await telemetry.listTranscriptionRecords(parsed);
    const response: AdminTranscriptionsResponse = {
      transcriptions: transcriptions.map(toTranscriptionSummary),
    };
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
    const [
      events,
      llmRuns,
      foodSearchEvents,
      conversationMessages,
      agentTurns,
      agentToolCalls,
      actionCalls,
      providerCalls,
      transcriptions,
    ] = await Promise.all([
      telemetry.listEvents({ traceId, limit: 200 }),
      telemetry.listLlmRuns({ traceId, limit: 100 }),
      telemetry.listFoodSearchEvents({ traceId, limit: 100 }),
      telemetry.listAgentConversationMessagesByTrace(traceId, true),
      telemetry.listAgentTurns({ traceId, limit: 100 }),
      telemetry.listAgentToolCalls({ traceId, limit: 100 }),
      telemetry.listAdminActionCalls({ traceId, limit: 100 }),
      telemetry.listLlmProviderCalls({ traceId, limit: 100 }),
      telemetry.listTranscriptionRecords({ traceId, limit: 100 }),
    ]);
    const response: TelemetryTraceResponse = {
      traceId,
      events: events.map(toEventSummary),
      llmRuns: llmRuns.map(toLlmRunSummary),
      foodSearchEvents: foodSearchEvents.map(toFoodSearchEventSummary),
      conversationMessages: conversationMessages.map(toConversationMessage),
      agentTurns: agentTurns.map(toAgentTurnSummary),
      agentToolCalls: agentToolCalls.map(toAgentToolCallSummary),
      actionCalls: actionCalls.map(toActionCallSummary),
      providerCalls: providerCalls.map(toProviderCallSummary),
      transcriptions: transcriptions.map(toTranscriptionSummary),
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
    conversationId: run.conversationId ?? null,
    turnId: run.turnId ?? null,
    provider: run.provider ?? null,
    providerRequestId: run.providerRequestId ?? null,
    providerGenerationId: run.providerGenerationId ?? null,
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
    providerCostAmount: run.providerCostAmount ?? null,
    estimatedCostAmount: run.estimatedCostAmount ?? null,
    costCurrency: run.costCurrency ?? null,
    costSource: run.costSource ?? null,
    pricingSnapshot: run.pricingSnapshot ?? {},
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

function toConversationSummary(
  conversation: AgentConversationRecord,
): AgentConversationSummary {
  return {
    id: conversation.id,
    userId: conversation.userId,
    title: conversation.title,
    hiddenFromUserAt: conversation.hiddenFromUserAt ?? null,
    createdAt: conversation.createdAt,
    updatedAt: conversation.updatedAt,
  };
}

function toConversationMessage(
  message: AgentConversationMessageRecord,
): AgentConversationMessage {
  return {
    id: message.id,
    conversationId: message.conversationId,
    userId: message.userId,
    role: message.role,
    content: message.content,
    toolCalls: message.toolCalls,
    toolCallId: message.toolCallId ?? null,
    traceId: message.traceId ?? null,
    turnId: message.turnId ?? null,
    inputMode: message.inputMode ?? null,
    source: message.source ?? null,
    activeProposalId: message.activeProposalId ?? null,
    metadata: message.metadata,
    createdAt: message.createdAt,
  };
}

function toActionCallSummary(call: ActionCallRecord): AdminActionCallSummary {
  return {
    id: call.id,
    userId: call.userId,
    actionId: call.actionId,
    source: call.source,
    input: call.input,
    output: call.output,
    error: call.error,
    confirmationStatus: call.confirmationStatus,
    traceId: call.traceId,
    latencyMs: call.latencyMs,
    createdAt: call.createdAt,
  };
}

function toAgentTurnSummary(turn: AgentTurnTelemetryRecord): AdminAgentTurnSummary {
  return {
    id: turn.id,
    conversationId: turn.conversationId ?? null,
    traceId: turn.traceId,
    turnId: turn.turnId,
    userId: turn.userId ?? null,
    inputMode: turn.inputMode ?? null,
    source: turn.source ?? null,
    activeProposalId: turn.activeProposalId ?? null,
    model: turn.model ?? null,
    inputText: turn.inputText ?? null,
    assistantText: turn.assistantText ?? null,
    resultKind: turn.resultKind ?? null,
    stopReason: turn.stopReason ?? null,
    iterationCount: turn.iterationCount,
    toolCallCount: turn.toolCallCount,
    promptTokens: turn.promptTokens ?? null,
    completionTokens: turn.completionTokens ?? null,
    totalTokens: turn.totalTokens ?? null,
    reasoningTokens: turn.reasoningTokens ?? null,
    providerCostAmount: turn.providerCostAmount ?? null,
    estimatedCostAmount: turn.estimatedCostAmount ?? null,
    costCurrency: turn.costCurrency ?? null,
    costSource: turn.costSource ?? null,
    firstByteMs: turn.firstByteMs ?? null,
    firstToolCallMs: turn.firstToolCallMs ?? null,
    largestStreamGapMs: turn.largestStreamGapMs ?? null,
    llmMs: turn.llmMs ?? null,
    actionMs: turn.actionMs ?? null,
    totalMs: turn.totalMs ?? null,
    status: turn.status,
    errorCode: turn.errorCode ?? null,
    errorMessage: turn.errorMessage ?? null,
    metadata: turn.metadata,
    completedAt: turn.completedAt ?? null,
    createdAt: turn.createdAt,
  };
}

function toAgentToolCallSummary(
  call: AgentToolCallTelemetryRecord,
): AdminAgentToolCallSummary {
  return {
    id: call.id,
    agentTurnId: call.agentTurnId ?? null,
    conversationId: call.conversationId ?? null,
    traceId: call.traceId,
    turnId: call.turnId ?? null,
    userId: call.userId ?? null,
    toolCallId: call.toolCallId ?? null,
    actionCallId: call.actionCallId ?? null,
    actionId: call.actionId,
    arguments: call.arguments,
    resultSummary: call.resultSummary,
    status: call.status,
    errorMessage: call.errorMessage ?? null,
    startedAt: call.startedAt,
    completedAt: call.completedAt ?? null,
    durationMs: call.durationMs ?? null,
    metadata: call.metadata,
    createdAt: call.createdAt,
  };
}

function toProviderCallSummary(
  call: LlmProviderCallRecord,
): AdminLlmProviderCallSummary {
  return {
    id: call.id,
    traceId: call.traceId,
    userId: call.userId ?? null,
    conversationId: call.conversationId ?? null,
    agentTurnId: call.agentTurnId ?? null,
    turnId: call.turnId ?? null,
    actionCallId: call.actionCallId ?? null,
    featureSurface: call.featureSurface,
    provider: call.provider,
    providerRequestId: call.providerRequestId ?? null,
    providerGenerationId: call.providerGenerationId ?? null,
    requestedModel: call.requestedModel,
    servedModel: call.servedModel ?? null,
    routing: call.routing,
    inputMode: call.inputMode ?? null,
    promptTokens: call.promptTokens ?? null,
    completionTokens: call.completionTokens ?? null,
    totalTokens: call.totalTokens ?? null,
    reasoningTokens: call.reasoningTokens ?? null,
    providerCostAmount: call.providerCostAmount ?? null,
    estimatedCostAmount: call.estimatedCostAmount ?? null,
    costCurrency: call.costCurrency ?? null,
    costSource: call.costSource,
    pricingSource: call.pricingSource ?? null,
    pricingVersion: call.pricingVersion ?? null,
    status: call.status,
    errorCode: call.errorCode ?? null,
    errorMessage: call.errorMessage ?? null,
    durationMs: call.durationMs ?? null,
    metadata: call.metadata,
    createdAt: call.createdAt,
  };
}

function toTranscriptionSummary(
  record: TranscriptionRecord,
): AdminTranscriptionSummary {
  return {
    id: record.id,
    traceId: record.traceId,
    userId: record.userId ?? null,
    conversationId: record.conversationId ?? null,
    turnId: record.turnId ?? null,
    surface: record.surface,
    provider: record.provider ?? null,
    model: record.model ?? null,
    language: record.language ?? null,
    audioMimeType: record.audioMimeType ?? null,
    audioBytes: record.audioBytes ?? null,
    audioDurationMs: record.audioDurationMs ?? null,
    transcriptText: record.transcriptText ?? null,
    transcriptLength: record.transcriptLength,
    durationMs: record.durationMs ?? null,
    status: record.status,
    errorCode: record.errorCode ?? null,
    errorMessage: record.errorMessage ?? null,
    downstreamResultKind: record.downstreamResultKind ?? null,
    metadata: record.metadata,
    createdAt: record.createdAt,
  };
}
