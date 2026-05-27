import type {
  FoodCandidateGroup,
  FoodMention,
  MealItem,
} from "@cal-tracker/contracts";
import type { FoodResolutionResult, FoodResolver } from "./foodResolver.js";

export type NutritionSearchResult = {
  items: MealItem[];
  candidates?: FoodCandidateGroup[];
  candidateGroups?: FoodCandidateGroup[];
};

export interface NutritionProvider {
  search(
    userId: string,
    query: string,
    barcode?: string,
    locale?: string,
  ): Promise<MealItem[] | NutritionSearchResult>;
}

export interface MealMentionResolutionProvider extends NutritionProvider {
  resolveMealMentions(
    userId: string,
    mentions: FoodMention[],
    locale?: string,
  ): Promise<FoodResolutionResult>;
}

export class ResolverNutritionProvider implements MealMentionResolutionProvider {
  constructor(private readonly resolver: FoodResolver) {}

  search(
    userId: string,
    query: string,
    barcode?: string,
    locale?: string,
  ): Promise<NutritionSearchResult> {
    return this.resolver.search(userId, query, barcode, locale);
  }

  resolveMealMentions(
    userId: string,
    mentions: FoodMention[],
    locale?: string,
  ): Promise<FoodResolutionResult> {
    return this.resolver.resolveMealMentions(userId, mentions, locale);
  }
}
