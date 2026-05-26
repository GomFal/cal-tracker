export type EmbeddingInput = {
  model: string;
  input: string[];
};

export type EmbeddingResult = {
  model: string;
  dimensions: number;
  data: Array<{ embedding: number[] }>;
};

export interface EmbeddingProvider {
  embed(input: string[]): Promise<EmbeddingResult>;
}

export class OpenRouterEmbeddingProvider implements EmbeddingProvider {
  constructor(
    private readonly apiKey: string,
    private readonly model: string,
    private readonly dimensions: number,
    private readonly baseUrl: string = "https://openrouter.ai/api/v1",
    private readonly timeoutMs = 10000,
  ) {}

  async embed(input: string[]): Promise<EmbeddingResult> {
    const response = await fetch(`${this.baseUrl}/embeddings`, {
      method: "POST",
      signal: timeoutSignal(this.timeoutMs),
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": process.env.APP_BASE_URL ?? "",
        "X-Title": "Cal Tracker Embeddings",
      },
      body: JSON.stringify({
        model: this.model,
        input,
        encoding_format: "float",
      } satisfies EmbeddingInput & { encoding_format: "float" }),
    });
    if (!response.ok) {
      throw new Error(`Embedding provider failed: ${response.status} ${await response.text()}`);
    }

    const result = await response.json() as {
      model?: string;
      data?: Array<{ embedding?: number[] }>;
    };
    if (!Array.isArray(result.data)) {
      throw new Error("Embedding provider response missing data");
    }
    if (result.data.length !== input.length) {
      throw new Error(`Embedding result count mismatch: expected ${input.length}, got ${result.data.length}`);
    }
    for (const item of result.data) {
      if (!Array.isArray(item.embedding)) {
        throw new Error("Embedding result missing vector");
      }
      if (item.embedding.length !== this.dimensions) {
        throw new Error(`Embedding vector length mismatch: expected ${this.dimensions}, got ${item.embedding.length}`);
      }
    }
    return {
      model: result.model ?? this.model,
      dimensions: this.dimensions,
      data: result.data.map((item) => ({ embedding: item.embedding! })),
    };
  }
}

export class UnavailableEmbeddingProvider implements EmbeddingProvider {
  async embed(): Promise<EmbeddingResult> {
    throw new Error("embedding_provider_unavailable");
  }
}

function timeoutSignal(timeoutMs: number): AbortSignal {
  const controller = new AbortController();
  setTimeout(() => controller.abort(), timeoutMs).unref?.();
  return controller.signal;
}
