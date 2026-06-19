import { createHash } from "node:crypto";
import { summarizeError } from "../observability/localRunLogger.js";
import type {
  AdminActionCallFilter,
  AdminConversationFilter,
  AgentToolCallTelemetryFilter,
  AgentToolCallTelemetryRecord,
  AgentTurnTelemetryFilter,
  AgentTurnTelemetryRecord,
  AgentConversationMessageRecord,
  AgentConversationRecord,
  ActionCallRecord,
  FoodSearchEventRecord,
  LlmRunRecord,
  TelemetryEventRecord,
  TelemetryEventFilter,
  LlmRunFilter,
  FoodSearchEventFilter,
  LlmCostFilter,
  LlmCostOverview,
  LlmProviderCallFilter,
  LlmProviderCallRecord,
  TelemetryOverview,
  TranscriptionRecord,
  TranscriptionRecordFilter,
} from "../repository/types.js";
import type { AppRepository } from "../repository/types.js";
import {
  type ClientTelemetryEventInput,
  type TelemetrySeverity,
  type TelemetryStatus,
  type TelemetrySurface,
} from "@cal-tracker/contracts";
import type {
  FoodResolverTelemetryEvent,
  FoodSearchTelemetryEvent,
  AgentToolCallTelemetryEvent,
  AgentTurnTelemetryEvent,
  LlmTelemetryEvent,
  LlmProviderCallTelemetryEvent,
  SttTelemetryEvent,
  TranscriptionTelemetryRecordEvent,
  VoiceMealRunTelemetryEvent,
} from "./telemetryService.js";

const MAX_METADATA_BYTES = 4 * 1024;
const MAX_METADATA_VALUE_LENGTH = 200;
const MAX_METADATA_KEY_LENGTH = 80;
const MAX_METADATA_KEYS = 32;
const MAX_METADATA_DEPTH = 3;
const MAX_HISTORY_LIMIT = 200;
const REDACTED_METADATA_VALUE = "[redacted]";
const MAX_DEPTH_METADATA_VALUE = "[max_depth]";

export type TelemetryEventInput = Omit<TelemetryEventRecord, "id" | "createdAt" | "metadata"> & {
  metadata?: Record<string, unknown>;
};

export type LlmRunTelemetryInput = Omit<LlmRunRecord, "id" | "createdAt" | "metadata"> & {
  metadata?: Record<string, unknown>;
};

export type FoodSearchEventTelemetryInput = Omit<FoodSearchEventRecord, "id" | "createdAt" | "metadata" | "queryLength"> & {
  queryLength?: number;
  metadata?: Record<string, unknown>;
};

export interface TelemetrySink {
  recordEvent(event: TelemetryEventInput): Promise<TelemetryEventRecord | undefined>;
  recordLlmRun(run: LlmRunTelemetryInput | LlmTelemetryEvent): Promise<LlmRunRecord | undefined>;
  recordAgentTurn(event: AgentTurnTelemetryEvent): Promise<AgentTurnTelemetryRecord | undefined>;
  recordAgentToolCall(event: AgentToolCallTelemetryEvent): Promise<AgentToolCallTelemetryRecord | undefined>;
  recordLlmProviderCall(event: LlmProviderCallTelemetryEvent): Promise<LlmProviderCallRecord | undefined>;
  recordTranscriptionRecord(event: TranscriptionTelemetryRecordEvent): Promise<TranscriptionRecord | undefined>;
  recordFoodSearchEvent(event: FoodSearchEventTelemetryInput | FoodSearchTelemetryEvent): Promise<FoodSearchEventRecord | undefined>;
  recordSttEvent(event: SttTelemetryEvent): Promise<TelemetryEventRecord | undefined>;
  recordVoiceMealRunEvent(event: VoiceMealRunTelemetryEvent): Promise<TelemetryEventRecord | undefined>;
  recordFoodResolverEvent(event: FoodResolverTelemetryEvent): Promise<TelemetryEventRecord | undefined>;
}

export class TelemetryService implements TelemetrySink {
  constructor(
    private readonly repository: AppRepository,
    private readonly options: { enabled?: boolean } = {},
  ) {}

  get enabled(): boolean {
    return this.options.enabled ?? true;
  }

  async recordEvent(event: TelemetryEventInput): Promise<TelemetryEventRecord | undefined> {
    if (!this.enabled) return undefined;
    try {
      return await this.repository.createTelemetryEvent({
        ...event,
        errorMessage: truncateString(event.errorMessage, MAX_METADATA_VALUE_LENGTH),
        metadata: sanitizeMetadata(event.metadata),
      });
    } catch (error) {
      console.warn("telemetry.event_write_failed", summarizeError(error));
      return undefined;
    }
  }

  async recordLlmRun(run: LlmRunTelemetryInput | LlmTelemetryEvent): Promise<LlmRunRecord | undefined> {
    if (!this.enabled) return undefined;
    const normalized = normalizeLlmRun(run);
    try {
      return await this.repository.createLlmRun({
        ...normalized,
        metadata: sanitizeMetadata(normalized.metadata),
      });
    } catch (error) {
      console.warn("telemetry.llm_run_write_failed", summarizeError(error));
      return undefined;
    }
  }

  async recordAgentTurn(event: AgentTurnTelemetryEvent): Promise<AgentTurnTelemetryRecord | undefined> {
    if (!this.enabled) return undefined;
    try {
      return await this.repository.createAgentTurnTelemetry({
        ...event,
        pricingSnapshot: event.pricingSnapshot ?? {},
        metadata: sanitizeMetadata(event.metadata),
      });
    } catch (error) {
      console.warn("telemetry.agent_turn_write_failed", summarizeError(error));
      return undefined;
    }
  }

  async recordAgentToolCall(event: AgentToolCallTelemetryEvent): Promise<AgentToolCallTelemetryRecord | undefined> {
    if (!this.enabled) return undefined;
    try {
      return await this.repository.createAgentToolCallTelemetry({
        ...event,
        metadata: sanitizeMetadata(event.metadata),
      });
    } catch (error) {
      console.warn("telemetry.agent_tool_call_write_failed", summarizeError(error));
      return undefined;
    }
  }

  async recordLlmProviderCall(event: LlmProviderCallTelemetryEvent): Promise<LlmProviderCallRecord | undefined> {
    if (!this.enabled) return undefined;
    try {
      return await this.repository.createLlmProviderCall({
        ...event,
        metadata: sanitizeMetadata(event.metadata),
      });
    } catch (error) {
      console.warn("telemetry.llm_provider_call_write_failed", summarizeError(error));
      return undefined;
    }
  }

  async recordTranscriptionRecord(event: TranscriptionTelemetryRecordEvent): Promise<TranscriptionRecord | undefined> {
    if (!this.enabled) return undefined;
    try {
      return await this.repository.createTranscriptionRecord({
        ...event,
        metadata: sanitizeMetadata(event.metadata),
      });
    } catch (error) {
      console.warn("telemetry.transcription_record_write_failed", summarizeError(error));
      return undefined;
    }
  }

  async recordFoodSearchEvent(
    event: FoodSearchEventTelemetryInput | FoodSearchTelemetryEvent,
  ): Promise<FoodSearchEventRecord | undefined> {
    if (!this.enabled) return undefined;
    const normalized = normalizeFoodSearchEvent(event);
    const query = summarizeQuery(normalized.queryText);
    const queryLength = normalized.queryLength ?? query.length;
    try {
      return await this.repository.createFoodSearchEvent({
        ...normalized,
        queryText: undefined,
        queryHash: normalized.queryHash ?? query.hash,
        queryLength,
        metadata: sanitizeMetadata(normalized.metadata),
      });
    } catch (error) {
      console.warn("telemetry.food_search_write_failed", summarizeError(error));
      return undefined;
    }
  }

  async recordSttEvent(event: SttTelemetryEvent): Promise<TelemetryEventRecord | undefined> {
    return this.recordEvent({
      traceId: event.traceId,
      userId: event.userId,
      eventType: `stt.transcription.${event.outcome}`,
      flow: event.flow,
      surface: event.surface,
      severity: event.outcome === "failed" ? "error" : "info",
      status: outcomeStatus(event.outcome),
      route: "/v1/stt/transcriptions",
      method: "POST",
      durationMs: event.durationMs,
      errorCode: event.errorCode,
      errorMessage: event.errorMessage,
      metadata: {
        stage: event.stage,
        filename: event.filename,
        mimeType: event.mimeType,
        bytes: event.bytes,
        provider: event.provider,
        model: event.model,
        language: event.language,
        transcriptLength: event.transcriptLength,
        ...event.metadata,
      },
    });
  }

  async recordVoiceMealRunEvent(event: VoiceMealRunTelemetryEvent): Promise<TelemetryEventRecord | undefined> {
    return this.recordEvent({
      traceId: event.traceId,
      userId: event.userId,
      eventType: `voice.meal_run.${event.outcome}`,
      flow: event.flow,
      surface: event.surface,
      severity: event.outcome === "failed" ? "error" : "info",
      status: outcomeStatus(event.outcome),
      route: "/v1/voice/meal-runs",
      method: "POST",
      durationMs: event.timingsMs?.total,
      errorCode: event.errorStage,
      errorMessage: event.errorMessage,
      metadata: {
        stage: event.stage,
        filename: event.filename,
        mimeType: event.mimeType,
        bytes: event.bytes,
        source: event.source,
        provider: event.provider,
        model: event.model,
        transcriptLength: event.transcriptLength,
        resultKind: event.resultKind,
        timingsMs: event.timingsMs,
        ...event.metadata,
      },
    });
  }

  async recordFoodResolverEvent(event: FoodResolverTelemetryEvent): Promise<TelemetryEventRecord | undefined> {
    return this.recordEvent({
      traceId: event.traceId ?? `resolver-${randomShortId()}`,
      userId: event.userId,
      eventType: "food_resolver.provider_error",
      flow: event.flow,
      surface: event.surface,
      severity: "warning",
      status: "partial",
      errorCode: event.errorCode,
      errorMessage: event.errorMessage,
      metadata: {
        provider: event.provider,
        canonicalName: event.canonicalName,
        originalText: event.originalText,
        mentionCount: event.mentionCount,
        outcome: event.outcome,
        ...event.metadata,
      },
    });
  }

  async recordClientEvents(input: {
    userId: string;
    events: ClientTelemetryEventInput[];
  }): Promise<{ accepted: number }> {
    if (!this.enabled) return { accepted: 0 };
    let accepted = 0;
    for (const event of input.events) {
      const eventType = normalizeClientEventType(event.eventType);
      if (!eventType) continue;
      const traceId = event.traceId?.trim() || `client-${randomShortId()}`;
      const result = await this.recordEvent({
        traceId,
        userId: input.userId,
        sessionId: event.sessionId,
        eventType,
        flow: event.flow,
        surface: "mobile",
        severity: event.severity,
        status: event.status,
        route: event.route,
        method: event.method,
        actionId: event.actionId,
        durationMs: event.durationMs,
        errorCode: event.errorCode,
        errorMessage: event.errorMessage,
        appVersion: event.appVersion,
        appBuild: event.appBuild,
        platform: event.platform,
        locale: event.locale,
        metadata: event.metadata,
      });
      if (result) accepted += 1;
    }
    return { accepted };
  }

  async listEvents(filter: TelemetryEventFilter): Promise<TelemetryEventRecord[]> {
    try {
      return await this.repository.listTelemetryEvents({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_events_failed", summarizeError(error));
      return [];
    }
  }

  async listLlmRuns(filter: LlmRunFilter): Promise<LlmRunRecord[]> {
    try {
      return await this.repository.listLlmRuns({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_llm_runs_failed", summarizeError(error));
      return [];
    }
  }

  async listAdminAgentConversations(
    filter: AdminConversationFilter,
  ): Promise<AgentConversationRecord[]> {
    try {
      return await this.repository.listAdminAgentConversations({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_admin_conversations_failed", summarizeError(error));
      return [];
    }
  }

  async getAdminAgentConversationMessages(
    conversationId: string,
    includeHidden = false,
  ): Promise<AgentConversationMessageRecord[]> {
    try {
      return await this.repository.getAdminAgentConversationMessages(
        conversationId,
        includeHidden,
      );
    } catch (error) {
      console.warn("telemetry.get_admin_conversation_failed", summarizeError(error));
      return [];
    }
  }

  async listAgentConversationMessagesByTrace(
    traceId: string,
    includeHidden = false,
  ): Promise<AgentConversationMessageRecord[]> {
    try {
      return await this.repository.listAgentConversationMessagesByTrace(
        traceId,
        includeHidden,
      );
    } catch (error) {
      console.warn("telemetry.list_trace_messages_failed", summarizeError(error));
      return [];
    }
  }

  async listAdminActionCalls(filter: AdminActionCallFilter): Promise<ActionCallRecord[]> {
    try {
      return await this.repository.listAdminActionCalls({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_admin_action_calls_failed", summarizeError(error));
      return [];
    }
  }

  async listAgentTurns(filter: AgentTurnTelemetryFilter): Promise<AgentTurnTelemetryRecord[]> {
    try {
      return await this.repository.listAgentTurnTelemetry({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_agent_turns_failed", summarizeError(error));
      return [];
    }
  }

  async listAgentToolCalls(filter: AgentToolCallTelemetryFilter): Promise<AgentToolCallTelemetryRecord[]> {
    try {
      return await this.repository.listAgentToolCallTelemetry({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_agent_tool_calls_failed", summarizeError(error));
      return [];
    }
  }

  async listLlmProviderCalls(filter: LlmProviderCallFilter): Promise<LlmProviderCallRecord[]> {
    try {
      return await this.repository.listLlmProviderCalls({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_provider_calls_failed", summarizeError(error));
      return [];
    }
  }

  async listTranscriptionRecords(filter: TranscriptionRecordFilter): Promise<TranscriptionRecord[]> {
    try {
      return await this.repository.listTranscriptionRecords({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_transcriptions_failed", summarizeError(error));
      return [];
    }
  }

  async getLlmCostOverview(filter: LlmCostFilter): Promise<LlmCostOverview | undefined> {
    try {
      return await this.repository.getLlmCostOverview(filter);
    } catch (error) {
      console.warn("telemetry.cost_overview_failed", summarizeError(error));
      return undefined;
    }
  }

  async listFoodSearchEvents(
    filter: FoodSearchEventFilter,
  ): Promise<FoodSearchEventRecord[]> {
    try {
      return await this.repository.listFoodSearchEvents({
        ...filter,
        limit: clampLimit(filter.limit),
      });
    } catch (error) {
      console.warn("telemetry.list_food_search_failed", summarizeError(error));
      return [];
    }
  }

  async getOverview(input: { from: string; to: string }): Promise<TelemetryOverview | undefined> {
    if (!this.enabled) {
      return emptyOverview(input);
    }
    try {
      return await this.repository.getTelemetryOverview(input);
    } catch (error) {
      console.warn("telemetry.overview_failed", summarizeError(error));
      return undefined;
    }
  }
}

function normalizeLlmRun(run: LlmRunTelemetryInput | LlmTelemetryEvent): LlmRunTelemetryInput {
  if (!("outcome" in run)) return run;
  return {
    traceId: run.traceId,
    userId: run.userId,
    source: run.source,
    locale: run.locale,
    timezone: run.timezone,
    conversationId: run.conversationId,
    turnId: run.turnId,
    provider: run.provider,
    providerRequestId: run.providerRequestId,
    providerGenerationId: run.providerGenerationId,
    model: run.model,
    inputMode: run.inputMode,
    activeProposalId: run.activeProposalId,
    decisionSource: run.outcome,
    selectedTool: run.selectedTool,
    executedTool: run.executedTool,
    resultKind: run.resultKind,
    actionCallId: run.actionCallId,
    promptChars: run.promptChars,
    toolsJsonChars: run.toolsJsonChars,
    messagesJsonChars: run.messagesJsonChars,
    promptTokens: run.promptTokens,
    completionTokens: run.completionTokens,
    totalTokens: run.totalTokens,
    reasoningTokens: run.reasoningTokens,
    firstByteMs: run.firstByteMs,
    firstToolCallMs: run.firstToolCallMs,
    largestStreamGapMs: run.largestStreamGapMs,
    llmMs: run.timingsMs?.llm,
    actionMs: run.timingsMs?.action,
    totalMs: run.timingsMs?.total,
    emptyToolCall: Boolean(run.emptyToolCall || run.outcome === "empty_tool_call"),
    invalidToolArguments: Boolean(run.invalidToolArguments || run.outcome === "invalid_tool_arguments"),
    providerError: Boolean(run.providerError || run.outcome === "provider_error"),
    providerCostAmount: run.providerCostAmount,
    estimatedCostAmount: run.estimatedCostAmount,
    costCurrency: run.costCurrency,
    costSource: run.costSource,
    pricingSnapshot: run.pricingSnapshot,
    metadata: {
      outcome: run.outcome,
      errorMessage: run.errorMessage,
      ...run.metadata,
    },
  };
}

function normalizeFoodSearchEvent(
  event: FoodSearchEventTelemetryInput | FoodSearchTelemetryEvent,
): FoodSearchEventTelemetryInput {
  if (!("flow" in event)) return event;
  return {
    traceId: event.traceId,
    userId: event.userId,
    queryText: event.queryText,
    queryHash: event.queryHash,
    queryLength: event.queryLength,
    locale: event.locale,
    barcodePresent: Boolean(event.barcode),
    path: "backend_search",
    resultCount: event.resultCount,
    candidateGroupCount: event.candidateGroupCount,
    topScore: event.topScore,
    topExternalSource: event.topExternalSource,
    topResultType: event.topResultType,
    zeroResults: event.zeroResults,
    lowConfidence: event.lowConfidence,
    selectedRank: event.selectedRank,
    durationMs: event.durationMs,
    metadata: {
      barcodePresent: Boolean(event.barcode),
      ...event.metadata,
    },
  };
}

function outcomeStatus(outcome: "started" | "completed" | "failed"): TelemetryStatus {
  if (outcome === "failed") return "failure";
  if (outcome === "completed") return "success";
  return "partial";
}

function emptyOverview(input: { from: string; to: string }): TelemetryOverview {
  return {
    from: input.from,
    to: input.to,
    totalEvents: 0,
    totalLlmRuns: 0,
    totalFoodSearchEvents: 0,
    totalConversations: 0,
    totalAgentTurns: 0,
    totalProviderCalls: 0,
    totalTranscriptions: 0,
    providerCostAmount: 0,
    estimatedCostAmount: 0,
    unknownCostCount: 0,
    uniqueUsers: 0,
    uniqueTraces: 0,
    eventsBySeverity: {},
    eventsBySurface: {},
    recentResultKinds: {},
    zeroResultRate: 0,
    lowConfidenceRate: 0,
    providerErrorRate: 0
  };
}

function clampLimit(value: number | undefined): number {
  if (!Number.isFinite(value)) return 50;
  if (value === undefined) return 50;
  return Math.min(Math.max(Math.floor(value), 1), MAX_HISTORY_LIMIT);
}

function sanitizeMetadata(metadata: Record<string, unknown> | undefined): Record<string, unknown> {
  if (!metadata) return {};
  const result: Record<string, unknown> = {};
  let totalBytes = 0;
  for (const [rawKey, value] of Object.entries(metadata)) {
    if (Object.keys(result).length >= MAX_METADATA_KEYS) break;
    const key = rawKey.slice(0, MAX_METADATA_KEY_LENGTH);
    const sanitized = sanitizeValue(value, rawKey, 0);
    const cost = byteLength(key) + byteLength(JSON.stringify(sanitized));
    if (totalBytes + cost > MAX_METADATA_BYTES) break;
    totalBytes += cost;
    result[key] = sanitized;
  }
  return result;
}

function truncateString(value: string | undefined, maxLength: number): string | undefined {
  if (value === undefined) return undefined;
  return value.length > maxLength ? `${value.slice(0, maxLength)}…` : value;
}

function sanitizeValue(value: unknown, keyHint = "", depth = 0): unknown {
  if (isSensitiveMetadataKey(keyHint)) return REDACTED_METADATA_VALUE;
  if (value === null || value === undefined) return value;
  if (typeof value === "string") {
    return value.length > MAX_METADATA_VALUE_LENGTH
      ? `${value.slice(0, MAX_METADATA_VALUE_LENGTH)}…`
      : value;
  }
  if (typeof value === "number" || typeof value === "boolean") return value;
  if (Array.isArray(value)) {
    if (depth >= MAX_METADATA_DEPTH) return MAX_DEPTH_METADATA_VALUE;
    return value.slice(0, 16).map((entry) => sanitizeValue(entry, keyHint, depth + 1));
  }
  if (typeof value === "object") {
    if (depth >= MAX_METADATA_DEPTH) return MAX_DEPTH_METADATA_VALUE;
    const result: Record<string, unknown> = {};
    let totalBytes = 0;
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (Object.keys(result).length >= MAX_METADATA_KEYS) break;
      const key = k.slice(0, MAX_METADATA_KEY_LENGTH);
      const sanitized = sanitizeValue(v, k, depth + 1);
      const cost = byteLength(key) + byteLength(JSON.stringify(sanitized));
      if (totalBytes + cost > MAX_METADATA_VALUE_LENGTH * 2) break;
      totalBytes += cost;
      result[key] = sanitized;
    }
    return result;
  }
  return String(value).slice(0, MAX_METADATA_VALUE_LENGTH);
}

function summarizeQuery(query: string | undefined): { hash: string | undefined; length: number } {
  if (typeof query !== "string" || query.length === 0) {
    return { hash: undefined, length: 0 };
  }
  const length = query.length;
  return {
    hash: createHash("sha256").update(query).digest("hex").slice(0, 32),
    length
  };
}

function normalizeClientEventType(eventType: string): string | undefined {
  const trimmed = eventType.trim();
  return trimmed.startsWith("mobile.") ? trimmed : undefined;
}

function isSensitiveMetadataKey(key: string): boolean {
  const normalized = key.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (!normalized) return false;
  if (isAlwaysSensitiveMetadataKey(normalized)) return true;
  if (isTelemetryMetricKey(normalized)) return false;
  return SENSITIVE_CONTENT_METADATA_KEY_TERMS.some((term) => normalized.includes(term));
}

function isAlwaysSensitiveMetadataKey(normalizedKey: string): boolean {
  return (
    normalizedKey === "token" ||
    normalizedKey.endsWith("token") ||
    SENSITIVE_SECRET_METADATA_KEY_TERMS.some((term) => normalizedKey.includes(term))
  );
}

function isTelemetryMetricKey(normalizedKey: string): boolean {
  return (
    normalizedKey.endsWith("hash") ||
    normalizedKey.endsWith("length") ||
    normalizedKey.endsWith("count") ||
    normalizedKey.endsWith("ms") ||
    normalizedKey.endsWith("duration") ||
    normalizedKey.endsWith("present") ||
    normalizedKey.endsWith("enabled") ||
    normalizedKey.endsWith("score") ||
    normalizedKey.endsWith("rank")
  );
}

const SENSITIVE_SECRET_METADATA_KEY_TERMS = [
  "authorization",
  "authheader",
  "bearer",
  "cookie",
  "credential",
  "passwd",
  "password",
  "secret",
  "apikey",
];

const SENSITIVE_CONTENT_METADATA_KEY_TERMS = [
  "email",
  "originaltext",
  "query",
  "transcript",
];

function byteLength(value: string | undefined): number {
  if (value === undefined) return 0;
  return Buffer.byteLength(value, "utf8");
}

function randomShortId(): string {
  return createHash("sha256")
    .update(`${Date.now()}-${Math.random().toString(36).slice(2)}`)
    .digest("hex")
    .slice(0, 16);
}

export function isTelemetrySurface(value: unknown): value is TelemetrySurface {
  return (
    value === "backend" ||
    value === "mobile" ||
    value === "agent" ||
    value === "stt" ||
    value === "db" ||
    value === "admin"
  );
}

export function isTelemetrySeverity(value: unknown): value is TelemetrySeverity {
  return value === "info" || value === "warning" || value === "error";
}

export function isTelemetryStatus(value: unknown): value is TelemetryStatus {
  return value === "success" || value === "failure" || value === "partial" || value === "abandoned";
}
