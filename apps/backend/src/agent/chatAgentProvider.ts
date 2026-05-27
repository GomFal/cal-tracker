import { withSpan } from "../observability/profiler.js";

export type AgentMessage =
  | { role: "system"; content: string }
  | { role: "user"; content: string }
  | { role: "assistant"; content: string; toolCalls?: AgentToolCall[] }
  | { role: "tool"; toolCallId: string; content: string };

export type AgentToolCall = {
  id: string;
  type: "function";
  function: {
    name: string;
    arguments: string;
  };
};

export type AgentToolDefinition = {
  type: "function";
  function: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
};

export type AgentStreamEvent = {
  atMs: number;
  type: string;
  toolCallIndex?: number;
  toolNameDelta?: string;
  toolArgumentsDelta?: string;
  contentDelta?: string;
  reasoningDelta?: string;
};

export type AgentProviderTimings = {
  firstByteMs?: number;
  firstDeltaMs?: number;
  firstContentMs?: number;
  firstReasoningMs?: number;
  firstToolCallMs?: number;
  generationMs: number;
  totalMs: number;
  largestStreamGapMs?: number;
  largestStreamGapAfterMs?: number;
  streamEventCount: number;
};

export type AgentToolDecision = {
  toolCalls: AgentToolCall[];
  rawResponse: unknown;
  timingsMs?: AgentProviderTimings;
  providerRouting?: OpenRouterProviderRouting;
  interaction?: {
    messages: AgentMessage[];
    assistantContent?: string;
    assistantReasoning?: string;
    streamEvents: AgentStreamEvent[];
  };
};

export interface ChatAgentProvider {
  runWithTools(input: {
    messages: AgentMessage[];
    tools: AgentToolDefinition[];
    model: string;
    traceId: string;
  }): Promise<AgentToolDecision>;
}

export type OpenRouterProviderRouting = {
  sort: "price" | "throughput" | "latency";
  preferred_max_latency: {
    p50: number;
    p90: number;
    p99: number;
  };
  preferred_min_throughput: {
    p50: number;
    p90: number;
  };
  require_parameters: boolean;
  allow_fallbacks: boolean;
};

export class RemoteChatAgentProvider implements ChatAgentProvider {
  constructor(
    private readonly apiKey: string,
    private readonly baseUrl: string = "https://openrouter.ai/api/v1",
    private readonly timeoutMs = 10000,
    private readonly providerRouting: OpenRouterProviderRouting = defaultOpenRouterProviderRouting(),
  ) {}

  async runWithTools(input: {
    messages: AgentMessage[];
    tools: AgentToolDefinition[];
    model: string;
    traceId: string;
  }): Promise<AgentToolDecision> {
    return withSpan(
      "RemoteChatAgentProvider.runWithTools",
      {
        model: input.model,
        toolCount: input.tools.length,
        messageCount: input.messages.length,
        toolsJsonChars: JSON.stringify(input.tools).length,
        messagesJsonChars: JSON.stringify(input.messages).length,
      },
      async () => this.runWithToolsInternal(input),
    );
  }

  private async runWithToolsInternal(input: {
    messages: AgentMessage[];
    tools: AgentToolDefinition[];
    model: string;
    traceId: string;
  }): Promise<AgentToolDecision> {
    const requestBody = {
      model: input.model,
      messages: input.messages,
      tools: input.tools,
      tool_choice: "auto",
      max_tokens: 2048,
      stream: true,
      stream_options: { include_usage: true },
      provider: this.providerRouting,
    };
    const timeout = providerTimeout(this.timeoutMs);
    try {
      const res = await withSpan(
        "OpenRouter.chatCompletions.fetch",
        {
          requestBodyChars: JSON.stringify(requestBody).length,
          toolCount: input.tools.length,
        },
        () => timeout.run(fetch(`${this.baseUrl}/chat/completions`, {
          method: "POST",
          signal: timeout.signal,
          headers: {
            Authorization: `Bearer ${this.apiKey}`,
            "Content-Type": "application/json",
            "HTTP-Referer": process.env.APP_BASE_URL ?? "",
            "X-Title": "Cal Tracker Agent",
          },
          body: JSON.stringify(requestBody),
        })),
      );

      if (!res.ok) {
        const err = await timeout.run(res.text());
        throw new Error(`LLM provider error: ${res.status} ${err}`);
      }

      if (!res.body) throw new Error("Empty stream from LLM provider");

      const streamed = await withSpan(
        "OpenRouter.chatCompletions.readStream",
        undefined,
        () => timeout.run(readChatCompletionStream(res.body!)),
      );

      return {
        toolCalls: streamed.toolCalls.map((tc) => ({
          id: tc.id,
          type: "function",
          function: {
            name: tc.name,
            arguments: tc.arguments,
          },
        })),
        rawResponse: {
          id: streamed.id,
          choices: [
            {
              message: {
                role: "assistant",
                content: streamed.assistantContent || null,
                tool_calls: streamed.toolCalls.map((tc) => ({
                  id: tc.id,
                  type: "function",
                  function: { name: tc.name, arguments: tc.arguments },
                })),
                reasoning: streamed.assistantReasoning || undefined,
              },
            },
          ],
          usage: streamed.usage,
          timingsMs: streamed.timingsMs,
          providerRouting: this.providerRouting,
        },
        timingsMs: streamed.timingsMs,
        providerRouting: this.providerRouting,
        interaction: {
          messages: input.messages,
          assistantContent: streamed.assistantContent || undefined,
          assistantReasoning: streamed.assistantReasoning || undefined,
          streamEvents: streamed.streamEvents,
        },
      };
    } finally {
      timeout.clear();
    }
  }
}

export function defaultOpenRouterProviderRouting(): OpenRouterProviderRouting {
  return {
    sort: "latency",
    preferred_max_latency: {
      p50: 0.6,
      p90: 1.5,
      p99: 3,
    },
    preferred_min_throughput: {
      p50: 80,
      p90: 40,
    },
    require_parameters: false,
    allow_fallbacks: true,
  };
}

type StreamedToolCall = {
  id: string;
  type: "function";
  name: string;
  arguments: string;
};

async function readChatCompletionStream(body: ReadableStream<Uint8Array>): Promise<{
  id?: string;
  toolCalls: StreamedToolCall[];
  assistantContent: string;
  assistantReasoning: string;
  usage?: unknown;
  timingsMs: AgentProviderTimings;
  streamEvents: AgentStreamEvent[];
}> {
  const started = Date.now();
  const reader = body.getReader();
  const decoder = new TextDecoder();
  const toolCallParts = new Map<number, StreamedToolCall>();
  const streamEvents: AgentStreamEvent[] = [];
  let assistantContent = "";
  let assistantReasoning = "";
  let usage: unknown;
  let id: string | undefined;
  let buffer = "";
  let firstByteMs: number | undefined;
  let firstDeltaMs: number | undefined;
  let firstContentMs: number | undefined;
  let firstReasoningMs: number | undefined;
  let firstToolCallMs: number | undefined;

  while (true) {
    const chunk = await reader.read();
    if (chunk.done) break;
    const now = Date.now();
    firstByteMs ??= now - started;
    buffer += decoder.decode(chunk.value, { stream: true });
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith("data:")) continue;
      const data = trimmed.slice("data:".length).trim();
      if (!data || data === "[DONE]") continue;

      const parsed = JSON.parse(data) as Record<string, unknown>;
      if (!id && typeof parsed.id === "string") id = parsed.id;
      if (parsed.usage) usage = parsed.usage;
      const choices = Array.isArray(parsed.choices) ? parsed.choices : [];
      for (const choice of choices) {
        if (!isRecord(choice)) continue;
        const delta = isRecord(choice.delta) ? choice.delta : undefined;
        if (!delta) continue;

        const eventAtMs = Date.now() - started;
        const contentDelta = typeof delta.content === "string" ? delta.content : "";
        const reasoningDelta = reasoningTextDelta(delta);
        const toolCalls = Array.isArray(delta.tool_calls) ? delta.tool_calls : [];

        if (contentDelta || reasoningDelta || toolCalls.length > 0) {
          firstDeltaMs ??= eventAtMs;
        }
        if (contentDelta) {
          firstContentMs ??= eventAtMs;
          assistantContent += contentDelta;
          streamEvents.push({
            atMs: eventAtMs,
            type: "content_delta",
            contentDelta,
          });
        }
        if (reasoningDelta) {
          firstReasoningMs ??= eventAtMs;
          assistantReasoning += reasoningDelta;
          streamEvents.push({
            atMs: eventAtMs,
            type: "reasoning_delta",
            reasoningDelta,
          });
        }

        for (const toolCall of toolCalls) {
          if (!isRecord(toolCall)) continue;
          const index = typeof toolCall.index === "number" ? toolCall.index : 0;
          const existing =
            toolCallParts.get(index) ??
            {
              id: "",
              type: "function" as const,
              name: "",
              arguments: "",
            };
          if (typeof toolCall.id === "string") existing.id += toolCall.id;
          if (typeof toolCall.type === "string" && toolCall.type === "function") {
            existing.type = "function";
          }
          const fn = isRecord(toolCall.function) ? toolCall.function : {};
          const nameDelta = typeof fn.name === "string" ? fn.name : "";
          const argsDelta = typeof fn.arguments === "string" ? fn.arguments : "";
          existing.name += nameDelta;
          existing.arguments += argsDelta;
          toolCallParts.set(index, existing);
          firstToolCallMs ??= eventAtMs;
          streamEvents.push({
            atMs: eventAtMs,
            type: "tool_call_delta",
            toolCallIndex: index,
            toolNameDelta: nameDelta || undefined,
            toolArgumentsDelta: argsDelta || undefined,
          });
        }
      }
    }
  }

  const totalMs = Date.now() - started;
  const largestGap = largestStreamGap(streamEvents);
  return {
    id,
    toolCalls: [...toolCallParts.entries()]
      .sort(([a], [b]) => a - b)
      .map(([, value], index) => ({
        ...value,
        id: value.id || `call_${index}`,
      })),
    assistantContent,
    assistantReasoning,
    usage,
    timingsMs: {
      firstByteMs,
      firstDeltaMs,
      firstContentMs,
      firstReasoningMs,
      firstToolCallMs,
      generationMs: totalMs,
      totalMs,
      largestStreamGapMs: largestGap?.gapMs,
      largestStreamGapAfterMs: largestGap?.afterMs,
      streamEventCount: streamEvents.length,
    },
    streamEvents,
  };
}

function largestStreamGap(
  events: AgentStreamEvent[],
): { gapMs: number; afterMs: number } | undefined {
  if (events.length < 2) return undefined;
  let largest = { gapMs: 0, afterMs: events[0]!.atMs };
  for (let index = 1; index < events.length; index++) {
    const previous = events[index - 1]!;
    const current = events[index]!;
    const gapMs = current.atMs - previous.atMs;
    if (gapMs > largest.gapMs) largest = { gapMs, afterMs: previous.atMs };
  }
  return largest.gapMs > 0 ? largest : undefined;
}

function reasoningTextDelta(delta: Record<string, unknown>): string {
  const direct = delta.reasoning ?? delta.reasoning_content;
  if (typeof direct === "string") return direct;
  const details = delta.reasoning_details;
  if (Array.isArray(details)) {
    return details
      .map((detail) =>
        isRecord(detail) && typeof detail.text === "string" ? detail.text : "",
      )
      .join("");
  }
  return "";
}

function providerTimeout(timeoutMs: number): {
  signal: AbortSignal;
  run<T>(promise: Promise<T>): Promise<T>;
  clear(): void;
} {
  const controller = new AbortController();
  let timeout: ReturnType<typeof setTimeout>;
  const timedOut = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => {
      controller.abort();
      reject(new Error(`LLM provider timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    timeout.unref?.();
  });
  return {
    signal: controller.signal,
    run<T>(promise: Promise<T>): Promise<T> {
      return Promise.race([promise, timedOut]);
    },
    clear(): void {
      clearTimeout(timeout);
    },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
