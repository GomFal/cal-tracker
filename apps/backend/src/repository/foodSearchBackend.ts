import type { FoodHybridSearchInput, FoodSearchCandidate } from "./types.js";

export interface FoodSearchBackend {
  searchFoodsHybrid(
    userId: string,
    input: FoodHybridSearchInput,
  ): Promise<FoodSearchCandidate[]>;
}
