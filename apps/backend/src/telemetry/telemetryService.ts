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

export type LlmTelemetryEvent = {
  flow: "llm_run";
  surface: "agent";
  traceId: string;
  userId?: string;
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
  errorMessage?: string;
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
  recordSttEvent(event: SttTelemetryEvent): Promise<unknown>;
  recordVoiceMealRunEvent(event: VoiceMealRunTelemetryEvent): Promise<unknown>;
  recordFoodSearchEvent(event: FoodSearchTelemetryEvent): Promise<unknown>;
  recordFoodResolverEvent(event: FoodResolverTelemetryEvent): Promise<unknown>;
}

const NOOP_PROMISE = Promise.resolve();

export class NoopTelemetryService implements TelemetryService {
  readonly enabled = false;
  async recordLlmRun(): Promise<void> { return NOOP_PROMISE; }
  async recordSttEvent(): Promise<void> { return NOOP_PROMISE; }
  async recordVoiceMealRunEvent(): Promise<void> { return NOOP_PROMISE; }
  async recordFoodSearchEvent(): Promise<void> { return NOOP_PROMISE; }
  async recordFoodResolverEvent(): Promise<void> { return NOOP_PROMISE; }
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
  // Tiny non-cryptographic hash so we can correlate search telemetry without
  // storing raw transcripts. Best-effort; collisions are fine for telemetry.
  let hash = 2166136261 >>> 0;
  for (let i = 0; i < query.length; i += 1) {
    hash ^= query.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}
