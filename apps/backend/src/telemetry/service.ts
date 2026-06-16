import { createHash } from "node:crypto";
import { summarizeError } from "../observability/localRunLogger.js";
import type {
  FoodSearchEventRecord,
  LlmRunRecord,
  TelemetryEventRecord,
  TelemetryEventFilter,
  LlmRunFilter,
  FoodSearchEventFilter,
  TelemetryOverview,
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
  LlmTelemetryEvent,
  SttTelemetryEvent,
  VoiceMealRunTelemetryEvent,
} from "./telemetryService.js";

const MAX_METADATA_BYTES = 4 * 1024;
const MAX_QUERY_LENGTH = 120;
const MAX_METADATA_VALUE_LENGTH = 200;
const MAX_METADATA_KEY_LENGTH = 80;
const MAX_METADATA_KEYS = 32;
const MAX_HISTORY_LIMIT = 200;

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

  async recordFoodSearchEvent(
    event: FoodSearchEventTelemetryInput | FoodSearchTelemetryEvent,
  ): Promise<FoodSearchEventRecord | undefined> {
    if (!this.enabled) return undefined;
    const normalized = normalizeFoodSearchEvent(event);
    const sanitizedQuery = truncateQuery(normalized.queryText);
    const queryLength = normalized.queryLength ?? sanitizedQuery.length;
    try {
      return await this.repository.createFoodSearchEvent({
        ...normalized,
        queryText: sanitizedQuery.text,
        queryHash: normalized.queryHash ?? sanitizedQuery.hash,
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
      const traceId = event.traceId?.trim() || `client-${randomShortId()}`;
      const result = await this.recordEvent({
        traceId,
        userId: input.userId,
        sessionId: event.sessionId,
        eventType: event.eventType,
        flow: event.flow,
        surface: event.surface,
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
    const sanitized = sanitizeValue(value);
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

function sanitizeValue(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (typeof value === "string") {
    return value.length > MAX_METADATA_VALUE_LENGTH
      ? `${value.slice(0, MAX_METADATA_VALUE_LENGTH)}…`
      : value;
  }
  if (typeof value === "number" || typeof value === "boolean") return value;
  if (Array.isArray(value)) {
    return value.slice(0, 16).map((entry) => sanitizeValue(entry));
  }
  if (typeof value === "object") {
    const result: Record<string, unknown> = {};
    let totalBytes = 0;
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (Object.keys(result).length >= MAX_METADATA_KEYS) break;
      const key = k.slice(0, MAX_METADATA_KEY_LENGTH);
      const sanitized = sanitizeValue(v);
      const cost = byteLength(key) + byteLength(JSON.stringify(sanitized));
      if (totalBytes + cost > MAX_METADATA_VALUE_LENGTH * 2) break;
      totalBytes += cost;
      result[key] = sanitized;
    }
    return result;
  }
  return String(value).slice(0, MAX_METADATA_VALUE_LENGTH);
}

function truncateQuery(query: string | undefined): { text: string | undefined; hash: string | undefined; length: number } {
  if (typeof query !== "string" || query.length === 0) {
    return { text: undefined, hash: undefined, length: 0 };
  }
  const length = query.length;
  const truncated = query.length > MAX_QUERY_LENGTH ? query.slice(0, MAX_QUERY_LENGTH) : query;
  return {
    text: truncated,
    hash: createHash("sha256").update(query).digest("hex").slice(0, 32),
    length
  };
}

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
