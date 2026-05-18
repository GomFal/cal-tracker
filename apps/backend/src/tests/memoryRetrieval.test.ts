import { describe, expect, it } from "vitest";
import type { EmbeddingProvider } from "../embeddings/provider.js";
import { MemoryRetrievalService } from "../memory/retrieval.js";
import type { AppRepository } from "../repository/types.js";

describe("MemoryRetrievalService", () => {
  it("treats embedding provider failures as unavailable vector search", async () => {
    const repository = {
      async queryMemory() {
        return [];
      },
    } as unknown as AppRepository;
    const embeddingProvider = {
      async embed() {
        throw new Error("Unable to connect. Is the computer able to access the url?");
      },
    } satisfies EmbeddingProvider;

    const service = new MemoryRetrievalService(repository, embeddingProvider);

    await expect(service.query("user-1", "pollo y pan")).resolves.toEqual({
      matches: [],
      vectorUnavailable: true,
    });
  });
});
