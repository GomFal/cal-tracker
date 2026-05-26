import { afterEach, describe, expect, it, vi } from "vitest";
import { OpenRouterEmbeddingProvider } from "../embeddings/provider.js";

describe("OpenRouterEmbeddingProvider", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it("sends embedding requests to OpenRouter and validates vector dimensions", async () => {
    let requestUrl = "";
    let requestBody: Record<string, unknown> | undefined;
    globalThis.fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      requestUrl = String(url);
      requestBody = JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>;
      return Response.json({
        model: "baai/bge-m3",
        data: [{ embedding: [0.1, 0.2, 0.3] }],
      });
    }) as typeof fetch;

    const provider = new OpenRouterEmbeddingProvider(
      "test-key",
      "baai/bge-m3",
      3,
      "https://openrouter.example.test/api/v1",
    );

    const result = await provider.embed(["arroz"]);

    expect(requestUrl).toBe("https://openrouter.example.test/api/v1/embeddings");
    expect(requestBody).toEqual({
      model: "baai/bge-m3",
      input: ["arroz"],
      encoding_format: "float",
    });
    expect(result).toEqual({
      model: "baai/bge-m3",
      dimensions: 3,
      data: [{ embedding: [0.1, 0.2, 0.3] }],
    });
  });

  it("throws when OpenRouter returns the wrong vector dimensions", async () => {
    globalThis.fetch = vi.fn(async () => Response.json({
      data: [{ embedding: [0.1, 0.2] }],
    })) as typeof fetch;

    const provider = new OpenRouterEmbeddingProvider(
      "test-key",
      "baai/bge-m3",
      3,
      "https://openrouter.example.test/api/v1",
    );

    await expect(provider.embed(["arroz"])).rejects.toThrow("Embedding vector length mismatch");
  });

  it("throws on HTTP errors", async () => {
    globalThis.fetch = vi.fn(async () => new Response("no credits", { status: 402 })) as typeof fetch;

    const provider = new OpenRouterEmbeddingProvider(
      "test-key",
      "baai/bge-m3",
      3,
      "https://openrouter.example.test/api/v1",
    );

    await expect(provider.embed(["arroz"])).rejects.toThrow("Embedding provider failed: 402 no credits");
  });
});
