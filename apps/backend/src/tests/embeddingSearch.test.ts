import { describe, expect, it } from "vitest";
import { InMemoryRepository } from "../repository/inMemory.js";

describe("embedding food search", () => {
  it("uses a single global embedding space without embedding model ids", async () => {
    const repository = InMemoryRepository.seeded();
    const rice = await repository.upsertFoodItem({
      name: "Rice",
      normalizedName: "rice",
      canonicalName: "rice",
      source: "test",
      servingGrams: 100,
      calories: 130,
      proteinGrams: 2.7,
      carbsGrams: 28,
      fatGrams: 0.3,
    });
    const beef = await repository.upsertFoodItem({
      name: "Beef",
      normalizedName: "beef",
      canonicalName: "beef",
      source: "test",
      servingGrams: 100,
      calories: 250,
      proteinGrams: 26,
      carbsGrams: 0,
      fatGrams: 15,
    });
    const riceVector = vector(1);
    const beefVector = vector(0);
    beefVector[1] = 1;
    await repository.upsertFoodItemEmbedding({
      foodItemId: rice.id,
      embeddedText: "rice",
      embeddedTextHash: "rice-hash",
      embedding: riceVector,
    });
    await repository.upsertFoodItemEmbedding({
      foodItemId: beef.id,
      embeddedText: "beef",
      embeddedTextHash: "beef-hash",
      embedding: beefVector,
    });

    const results = await repository.searchFoodsHybrid("user-1", {
      query: "unknown query",
      embedding: riceVector,
    });

    expect(results[0]).toEqual(expect.objectContaining({ id: rice.id, vectorScore: 1 }));
  });
});

function vector(firstValue: number): number[] {
  const values = Array.from({ length: 1024 }, () => 0);
  values[0] = firstValue;
  return values;
}
