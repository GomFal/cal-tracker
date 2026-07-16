/**
 * Minimal telemetry service contract used by the backend instrumentation
 * adapter. This module intentionally has no DB or HTTP dependencies so it can
 * be wired into the rest of the backend without waiting for the telemetry
 * schema migrations. The default `NoopTelemetryService` is a no-op sink; a
 * future DB-backed implementation can be injected through the same interface.
 *
 * All `record*` methods are best-effort: implementations must swallow errors so
 * telemetry failures never affect user requests.
 */

import { createHash } from "node:crypto";

export type LlmTelemetryEvent = {
  flow: "llm_run";
  surface: "agent";
  traceId: string;
  userId?: string;
  conversationId?: string;
  turnId?: string;
  provider?: string;
  providerRequestId?: string;
  providerGenerationId?: string;
  model: string;
  source?: string;
  locale?: string;
  timezone?: string;
  inputMode?: "text" | "voice";
  activeProposalId?: string;
  outcome:
    | "success"
    | "provider_error"
    | "empty_tool_call"
    | "invalid_tool_arguments"
    | "disallowed_tool";
  selectedTool?: string;
  executedTool?: string;
  resultKind?: string;
  actionCallId?: string;
  timingsMs?: {
    llm?: number;
    action?: number;
    total?: number;
  };
  promptChars?: number;
  toolsJsonChars?: number;
  messagesJsonChars?: number;
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  firstByteMs?: number;
  firstToolCallMs?: number;
  largestStreamGapMs?: number;
  emptyToolCall?: boolean;
  invalidToolArguments?: boolean;
  providerError?: boolean;
  providerCostAmount?: number;
  estimatedCostAmount?: number;
  costCurrency?: string;
  costSource?: string;
  pricingSnapshot?: Record<string, unknown>;
  errorMessage?: string;
  metadata?: Record<string, unknown>;
};

export type AgentTurnTelemetryEvent = {
  traceId: string;
  turnId: string;
  userId?: string;
  conversationId?: string;
  inputMode?: "text" | "voice";
  source?: string;
  activeProposalId?: string;
  model?: string;
  inputText?: string;
  assistantText?: string;
  resultKind?: string;
  stopReason?: string;
  iterationCount: number;
  toolCallCount: number;
  promptChars?: number;
  messagesJsonChars?: number;
  toolsJsonChars?: number;
  requestPayloadChars?: number;
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  providerCostAmount?: number;
  estimatedCostAmount?: number;
  costCurrency?: string;
  costSource?: string;
  pricingSnapshot?: Record<string, unknown>;
  firstByteMs?: number;
  firstToolCallMs?: number;
  largestStreamGapMs?: number;
  llmMs?: number;
  actionMs?: number;
  totalMs?: number;
  status: "success" | "failure" | "partial";
  errorCode?: string;
  errorMessage?: string;
  metadata?: Record<string, unknown>;
  completedAt?: string;
};

export type AgentToolCallTelemetryEvent = {
  agentTurnId?: string;
  conversationId?: string;
  traceId: string;
  turnId?: string;
  userId?: string;
  toolCallId?: string;
  actionCallId?: string;
  actionId: string;
  arguments?: unknown;
  resultSummary?: unknown;
  status: "started" | "completed" | "failed" | "skipped";
  errorMessage?: string;
  startedAt: string;
  completedAt?: string;
  durationMs?: number;
  metadata?: Record<string, unknown>;
};

export type LlmProviderCallTelemetryEvent = {
  traceId: string;
  userId?: string;
  conversationId?: string;
  agentTurnId?: string;
  turnId?: string;
  actionCallId?: string;
  featureSurface: string;
  provider: string;
  providerRequestId?: string;
  providerGenerationId?: string;
  requestedModel: string;
  servedModel?: string;
  routing?: unknown;
  inputMode?: "text" | "voice";
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  cachedInputTokens?: number;
  audioTokens?: number;
  imageTokens?: number;
  providerCostAmount?: number;
  estimatedCostAmount?: number;
  costCurrency?: string;
  costSource: "provider" | "estimate" | "unknown";
  inputTokenUnitPrice?: number;
  outputTokenUnitPrice?: number;
  reasoningTokenUnitPrice?: number;
  cachedInputTokenUnitPrice?: number;
  audioTokenUnitPrice?: number;
  imageTokenUnitPrice?: number;
  pricingSource?: string;
  pricingVersion?: string;
  pricingEffectiveAt?: string;
  status: "success" | "failure";
  errorCode?: string;
  errorMessage?: string;
  durationMs?: number;
  metadata?: Record<string, unknown>;
};

export type TranscriptionTelemetryRecordEvent = {
  traceId: string;
  userId?: string;
  conversationId?: string;
  turnId?: string;
  surface: "stt" | "voice_meal" | "agent_chat_audio";
  provider?: string;
  model?: string;
  language?: string;
  audioMimeType?: string;
  audioBytes?: number;
  audioDurationMs?: number;
  transcriptText?: string;
  transcriptLength: number;
  durationMs?: number;
  status: "started" | "completed" | "failed";
  errorCode?: string;
  errorMessage?: string;
  downstreamResultKind?: string;
  metadata?: Record<string, unknown>;
};

export type SttTelemetryEvent = {
  flow: "stt";
  surface: "stt";
  traceId: string;
  userId: string;
  outcome: "started" | "completed" | "failed";
  stage: "transcription";
  filename?: string;
  mimeType?: string;
  bytes?: number;
  provider?: string;
  model?: string;
  language?: string;
  transcriptLength?: number;
  durationMs?: number;
  errorCode?: string;
  errorMessage?: string;
  metadata?: Record<string, unknown>;
};

export type VoiceMealRunTelemetryEvent = {
  flow: "voice_meal";
  surface: "agent";
  traceId: string;
  userId: string;
  outcome: "started" | "completed" | "failed";
  stage: "voice_meal_run";
  filename?: string;
  mimeType?: string;
  bytes?: number;
  source?: string;
  provider?: string;
  model?: string;
  transcriptLength?: number;
  resultKind?: string;
  errorStage?: "stt" | "agent" | "validation";
  errorMessage?: string;
  timingsMs?: {
    stt?: number;
    agent?: number;
    total?: number;
  };
  metadata?: Record<string, unknown>;
};

export type FoodSearchTelemetryEvent = {
  flow: "food_search";
  surface: "backend";
  traceId: string;
  userId: string;
  queryText?: string;
  queryLength: number;
  queryHash?: string;
  locale?: string;
  barcode?: string;
  resultCount: number;
  candidateGroupCount: number;
  topScore?: number;
  topExternalSource?: string;
  topResultType?: string;
  zeroResults: boolean;
  lowConfidence: boolean;
  selectedRank?: number;
  durationMs?: number;
  metadata?: Record<string, unknown>;
};

export type FoodResolverTelemetryEvent = {
  flow: "food_resolver";
  surface: "db";
  traceId?: string;
  userId?: string;
  outcome: "provider_error";
  provider: string;
  canonicalName?: string;
  originalText?: string;
  mentionCount?: number;
  errorCode?: string;
  errorMessage?: string;
  metadata?: Record<string, unknown>;
};

export type TelemetryEvent =
  | LlmTelemetryEvent
  | SttTelemetryEvent
  | VoiceMealRunTelemetryEvent
  | FoodSearchTelemetryEvent
  | FoodResolverTelemetryEvent;

export interface TelemetryService {
  readonly enabled: boolean;
  recordLlmRun(event: LlmTelemetryEvent): Promise<unknown>;
  recordAgentTurn(event: AgentTurnTelemetryEvent): Promise<unknown>;
  recordAgentToolCall(event: AgentToolCallTelemetryEvent): Promise<unknown>;
  recordLlmProviderCall(event: LlmProviderCallTelemetryEvent): Promise<unknown>;
  recordTranscriptionRecord(event: TranscriptionTelemetryRecordEvent): Promise<unknown>;
  recordSttEvent(event: SttTelemetryEvent): Promise<unknown>;
  recordVoiceMealRunEvent(event: VoiceMealRunTelemetryEvent): Promise<unknown>;
  recordFoodSearchEvent(event: FoodSearchTelemetryEvent): Promise<unknown>;
  recordFoodResolverEvent(event: FoodResolverTelemetryEvent): Promise<unknown>;
}

const NOOP_PROMISE = Promise.resolve();

export class NoopTelemetryService implements TelemetryService {
  readonly enabled = false;
  async recordLlmRun(): Promise<void> { return NOOP_PROMISE; }
  async recordAgentTurn(): Promise<void> { return NOOP_PROMISE; }
  async recordAgentToolCall(): Promise<void> { return NOOP_PROMISE; }
  async recordLlmProviderCall(): Promise<void> { return NOOP_PROMISE; }
  async recordTranscriptionRecord(): Promise<void> { return NOOP_PROMISE; }
  async recordSttEvent(): Promise<void> { return NOOP_PROMISE; }
  async recordVoiceMealRunEvent(): Promise<void> { return NOOP_PROMISE; }
  async recordFoodSearchEvent(): Promise<void> { return NOOP_PROMISE; }
  async recordFoodResolverEvent(): Promise<void> { return NOOP_PROMISE; }
}

export class FireAndForgetTelemetryService implements TelemetryService {
  readonly enabled: boolean;

  constructor(private readonly sink: TelemetryService) {
    this.enabled = sink.enabled;
  }

  async recordLlmRun(event: LlmTelemetryEvent): Promise<void> {
    this.schedule("llm_run", () => this.sink.recordLlmRun(event));
  }

  async recordAgentTurn(event: AgentTurnTelemetryEvent): Promise<void> {
    this.schedule("agent_turn", () => this.sink.recordAgentTurn(event));
  }

  async recordAgentToolCall(event: AgentToolCallTelemetryEvent): Promise<void> {
    this.schedule("agent_tool_call", () => this.sink.recordAgentToolCall(event));
  }

  async recordLlmProviderCall(event: LlmProviderCallTelemetryEvent): Promise<void> {
    this.schedule("llm_provider_call", () => this.sink.recordLlmProviderCall(event));
  }

  async recordTranscriptionRecord(event: TranscriptionTelemetryRecordEvent): Promise<void> {
    this.schedule("transcription_record", () => this.sink.recordTranscriptionRecord(event));
  }

  async recordSttEvent(event: SttTelemetryEvent): Promise<void> {
    this.schedule("stt", () => this.sink.recordSttEvent(event));
  }

  async recordVoiceMealRunEvent(event: VoiceMealRunTelemetryEvent): Promise<void> {
    this.schedule("voice_meal_run", () => this.sink.recordVoiceMealRunEvent(event));
  }

  async recordFoodSearchEvent(event: FoodSearchTelemetryEvent): Promise<void> {
    this.schedule("food_search", () => this.sink.recordFoodSearchEvent(event));
  }

  async recordFoodResolverEvent(event: FoodResolverTelemetryEvent): Promise<void> {
    this.schedule("food_resolver", () => this.sink.recordFoodResolverEvent(event));
  }

  private schedule(label: string, emit: () => Promise<unknown>): void {
    try {
      void emit().catch((error) => {
        console.warn(`telemetry.${label}.failed`, describeError(error));
      });
    } catch (error) {
      console.warn(`telemetry.${label}.failed`, describeError(error));
    }
  }
}

/**
 * Console-backed telemetry service. Used as a development default so the
 * adapter always has a visible sink without requiring the DB foundation. It
 * writes a single JSON line per event and never throws.
 */
export class ConsoleTelemetryService implements TelemetryService {
  readonly enabled = true;
  constructor(private readonly logger: (line: string) => void = console.log) {}

  async recordLlmRun(event: LlmTelemetryEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.llm_run ${JSON.stringify(stripUndefined(event))}`));
  }
  async recordAgentTurn(event: AgentTurnTelemetryEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.agent_turn ${JSON.stringify(stripUndefined(event))}`));
  }
  async recordAgentToolCall(event: AgentToolCallTelemetryEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.agent_tool_call ${JSON.stringify(stripUndefined(event))}`));
  }
  async recordLlmProviderCall(event: LlmProviderCallTelemetryEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.llm_provider_call ${JSON.stringify(stripUndefined(event))}`));
  }
  async recordTranscriptionRecord(event: TranscriptionTelemetryRecordEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.transcription_record ${JSON.stringify(stripUndefined(event))}`));
  }
  async recordSttEvent(event: SttTelemetryEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.stt ${JSON.stringify(stripUndefined(event))}`));
  }
  async recordVoiceMealRunEvent(event: VoiceMealRunTelemetryEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.voice_meal_run ${JSON.stringify(stripUndefined(event))}`));
  }
  async recordFoodSearchEvent(event: FoodSearchTelemetryEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.food_search ${JSON.stringify(stripUndefined(event))}`));
  }
  async recordFoodResolverEvent(event: FoodResolverTelemetryEvent): Promise<void> {
    this.safe(() => this.logger(`telemetry.food_resolver ${JSON.stringify(stripUndefined(event))}`));
  }

  private safe(emit: () => void): void {
    try {
      emit();
    } catch (error) {
      console.warn("telemetry.console.failed", describeError(error));
    }
  }
}

function describeError(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

function stripUndefined<T extends Record<string, unknown>>(value: T): Partial<T> {
  const out: Partial<T> = {};
  for (const [key, val] of Object.entries(value)) {
    if (val !== undefined) {
      (out as Record<string, unknown>)[key] = val;
    }
  }
  return out;
}

/**
 * Compose multiple telemetry services so events fan out to a no-op fallback
 * and a console sink, or to a future DB sink plus console logging. Failures in
 * any one service are isolated and never propagated.
 */
export class CompositeTelemetryService implements TelemetryService {
  readonly enabled: boolean;
  constructor(private readonly services: TelemetryService[]) {
    this.enabled = services.some((service) => service.enabled);
  }
  async recordLlmRun(event: LlmTelemetryEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordLlmRun(event))));
  }
  async recordAgentTurn(event: AgentTurnTelemetryEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordAgentTurn(event))));
  }
  async recordAgentToolCall(event: AgentToolCallTelemetryEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordAgentToolCall(event))));
  }
  async recordLlmProviderCall(event: LlmProviderCallTelemetryEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordLlmProviderCall(event))));
  }
  async recordTranscriptionRecord(event: TranscriptionTelemetryRecordEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordTranscriptionRecord(event))));
  }
  async recordSttEvent(event: SttTelemetryEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordSttEvent(event))));
  }
  async recordVoiceMealRunEvent(event: VoiceMealRunTelemetryEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordVoiceMealRunEvent(event))));
  }
  async recordFoodSearchEvent(event: FoodSearchTelemetryEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordFoodSearchEvent(event))));
  }
  async recordFoodResolverEvent(event: FoodResolverTelemetryEvent): Promise<void> {
    await Promise.all(this.services.map((s) => safeRecord(() => s.recordFoodResolverEvent(event))));
  }
}

async function safeRecord(emit: () => Promise<unknown>): Promise<void> {
  try {
    await emit();
  } catch (error) {
    console.warn("telemetry.service.failed", describeError(error));
  }
}

export const DEFAULT_TELEMETRY_SERVICE: TelemetryService = new NoopTelemetryService();

export function hashQueryForTelemetry(query: string): string {
  return createHash("sha256").update(query).digest("hex").slice(0, 32);
}
