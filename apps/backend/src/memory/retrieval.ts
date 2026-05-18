import type { MemoryMatch, AppRepository } from "../repository/types.js";
import { normalizeText } from "../utils/normalize.js";
import type { EmbeddingProvider } from "../embeddings/provider.js";

export class MemoryRetrievalService {
  constructor(
    private readonly repository: AppRepository,
    private readonly embeddingProvider?: EmbeddingProvider
  ) {}

  async query(userId: string, text: string): Promise<{ matches: MemoryMatch[]; vectorUnavailable: boolean }> {
    const normalized = normalizeText(text);
    const exactAndFuzzy = await this.repository.queryMemory(userId, normalized);
    if (exactAndFuzzy.length > 0) {
      return { matches: exactAndFuzzy, vectorUnavailable: false };
    }

    if (!this.embeddingProvider) {
      return { matches: [], vectorUnavailable: true };
    }

    try {
      await this.embeddingProvider.embed([normalized]);
    } catch {
      return { matches: [], vectorUnavailable: true };
    }
    return { matches: [], vectorUnavailable: true };
  }
}
