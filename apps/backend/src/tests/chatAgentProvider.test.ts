import { afterEach, describe, expect, it, vi } from "vitest";
import {
  RemoteChatAgentProvider,
  type OpenRouterProviderRouting,
} from "../agent/chatAgentProvider.js";

describe("RemoteChatAgentProvider", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it("sends low-latency provider routing preferences to OpenRouter", async () => {
    let requestBody: Record<string, unknown> | undefined;
    const routing: OpenRouterProviderRouting = {
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

    globalThis.fetch = vi.fn(
      async (_url: string | URL | Request, init?: RequestInit) => {
        requestBody = JSON.parse(String(init?.body ?? "{}")) as Record<
          string,
          unknown
        >;
        return new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(
                new TextEncoder().encode(
                  [
                    'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"propose_meal_log","arguments":"{\\"text\\":\\"bread\\"}"}}]}}]}',
                    "data: [DONE]",
                    "",
                  ].join("\n\n"),
                ),
              );
              controller.close();
            },
          }),
          { status: 200 },
        );
      },
    ) as typeof fetch;

    const provider = new RemoteChatAgentProvider(
      "test-key",
      "https://openrouter.example.test",
      10000,
      routing,
    );

    const decision = await provider.runWithTools({
      model: "deepseek/deepseek-v4-flash:nitro",
      traceId: "trace-test",
      messages: [{ role: "user", content: "bread" }],
      tools: [
        {
          type: "function",
          function: {
            name: "propose_meal_log",
            description: "Propose meal",
            parameters: { type: "object" },
          },
        },
      ],
    });

    expect(requestBody).toEqual(
      expect.objectContaining({
        model: "deepseek/deepseek-v4-flash:nitro",
        tool_choice: "auto",
        max_tokens: 2048,
        stream: true,
        stream_options: { include_usage: true },
        provider: routing,
      }),
    );
    expect(decision.providerRouting).toEqual(routing);
    expect(decision.rawResponse).toEqual(
      expect.objectContaining({ providerRouting: routing }),
    );
  });

  it("times out when the provider stream does not finish", async () => {
    globalThis.fetch = vi.fn(
      async () =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(
                new TextEncoder().encode(
                  'data: {"choices":[{"delta":{"content":"thinking"}}]}\n\n',
                ),
              );
            },
          }),
          { status: 200 },
        ),
    ) as typeof fetch;

    const provider = new RemoteChatAgentProvider(
      "test-key",
      "https://openrouter.example.test",
      10,
    );

    await expect(
      provider.runWithTools({
        model: "deepseek/deepseek-v4-flash:nitro",
        traceId: "trace-test",
        messages: [{ role: "user", content: "bread" }],
        tools: [
          {
            type: "function",
            function: {
              name: "propose_meal_log",
              description: "Propose meal",
              parameters: { type: "object" },
            },
          },
        ],
      }),
    ).rejects.toThrow("LLM provider timed out after 10ms");
  });
});
