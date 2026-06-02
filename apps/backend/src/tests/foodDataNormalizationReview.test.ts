import { describe, expect, it } from "vitest";
import {
  evaluateNormalizationReview,
  nutritionDiverges,
  percentileThresholdsFromMetrics,
} from "../foodData/normalizationReview.js";
import type { NormalizedFoodSearchDocumentInput } from "../foodData/normalization.js";

describe("food data normalization review", () => {
  it("marks missing normalized docs as failed", () => {
    const review = evaluateNormalizationReview({
      foodId: "food-1",
      rawName: "   ",
    });

    expect(review.reviewStatus).toBe("failed");
    expect(review.severity).toBe("error");
    expect(review.issueCodes).toContain("normalizer_returned_no_doc");
  });

  it("marks empty normalized fields as failed", () => {
    const review = evaluateNormalizationReview({
      foodId: "food-1",
      rawName: "Food",
      doc: doc({
        displayName: "",
        baseName: "",
        primaryEntityName: "",
        searchText: "",
      }),
    });

    expect(review.reviewStatus).toBe("failed");
    expect(review.issueCodes).toEqual(expect.arrayContaining([
      "empty_display_name",
      "empty_base_name",
      "empty_primary_entity",
      "empty_search_text",
    ]));
  });

  it("marks generic outliers as needing review", () => {
    const review = evaluateNormalizationReview({
      foodId: "food-1",
      rawName: "Food, one, two, three, four, five, six, seven",
      doc: doc({
        resultType: "generic_food",
        displayName: "Food",
        baseName: "Food",
        searchText: "food one two three four five six seven",
        metadata: {
          hiddenDescriptors: ["one", "two", "three", "four"],
          retainedDescriptors: ["five"],
        },
      }),
    });

    expect(review.reviewStatus).toBe("needs_review");
    expect(review.severity).toBe("warning");
    expect(review.issueCodes).toEqual(expect.arrayContaining([
      "display_too_short",
      "overcollapsed_display",
      "excessive_descriptor_loss",
    ]));
  });

  it("keeps duplicated brand displays as a non-blocking observability signal", () => {
    const review = evaluateNormalizationReview({
      foodId: "food-1",
      rawName: "Goya Arroz",
      rawBrand: "Goya",
      doc: doc({
        resultType: "product",
        displayName: "Goya Arroz - Goya",
        baseName: "Goya Arroz",
        brandDisplay: "Goya",
        primaryEntityName: "Goya Arroz",
      }),
    });

    expect(review.reviewStatus).toBe("valid");
    expect(review.issueCodes).not.toContain("product_brand_duplicated");
    expect(review.observabilityIssueCodes).toContain("product_brand_duplicated");
  });

  it("keeps brand-only product display as a non-blocking observability signal", () => {
    const review = evaluateNormalizationReview({
      foodId: "food-1",
      rawName: "Brand",
      rawBrand: "Brand",
      doc: doc({
        resultType: "product",
        displayName: "Brand",
        baseName: "Brand",
        brandDisplay: "Brand",
        primaryEntityName: "Brand",
      }),
    });

    expect(review.reviewStatus).toBe("valid");
    expect(review.issueCodes).not.toContain("product_brand_only_display");
    expect(review.observabilityIssueCodes).toContain("product_brand_only_display");
  });

  it("does not mark one-token product names as overcollapsed because of brand metadata", () => {
    const review = evaluateNormalizationReview({
      foodId: "food-1",
      rawName: "Tubetti",
      rawBrand: "F.lli De Cecco di Filippo Fara San Martino SpA",
      doc: doc({
        resultType: "product",
        displayName: "Tubetti - F.lli De Cecco",
        baseName: "Tubetti",
        brandDisplay: "F.lli De Cecco",
        primaryEntityName: "Tubetti",
        searchText: "tubetti f lli de cecco",
      }),
    });

    expect(review.issueCodes).not.toContain("display_too_short");
    expect(review.issueCodes).not.toContain("overcollapsed_display");
    expect(review.reviewStatus).toBe("valid");
  });

  it("keeps standalone overcollapsed display as non-blocking observability", () => {
    const review = evaluateNormalizationReview({
      foodId: "food-1",
      rawName: "Applesauce, canned, unsweetened, with long source detail, extra, words, from, imported, shelf stable, pantry pack",
      doc: doc({
        resultType: "generic_food",
        displayName: "Applesauce Unsweetened, Canned",
        baseName: "Applesauce Unsweetened",
        primaryEntityName: "Applesauce",
        searchText: "applesauce unsweetened canned",
        metadata: {
          hiddenDescriptors: ["long source detail"],
          retainedDescriptors: ["unsweetened", "canned"],
        },
      }),
    });

    expect(review.reviewStatus).toBe("valid");
    expect(review.issueCodes).not.toContain("overcollapsed_display");
    expect(review.observabilityIssueCodes).toContain("overcollapsed_display");
  });

  it("keeps no-effect generic compaction as a non-blocking observability signal", () => {
    const review = evaluateNormalizationReview({
      foodId: "food-1",
      rawName: "Abiyuch, Raw",
      doc: doc({
        resultType: "generic_food",
        displayName: "Abiyuch, Raw",
        baseName: "Abiyuch, Raw",
        primaryEntityName: "Abiyuch",
        searchText: "abiyuch raw",
        metadata: {
          retainedDescriptors: ["raw"],
          hiddenDescriptors: [],
        },
      }),
    });

    expect(review.reviewStatus).toBe("valid");
    expect(review.issueCodes).not.toContain("no_effect_generic_compaction");
    expect(review.observabilityIssueCodes).toContain("no_effect_generic_compaction");
  });

  it("computes percentile thresholds from metrics", () => {
    const thresholds = percentileThresholdsFromMetrics([
      reviewMetric({ displayTokenCount: 1, searchTextTokenCount: 10 }),
      reviewMetric({ displayTokenCount: 2, searchTextTokenCount: 20 }),
      reviewMetric({ displayTokenCount: 10, searchTextTokenCount: 100 }),
    ]);

    expect(thresholds).toEqual({
      p99DisplayTokenCount: 10,
      p99SearchTextTokenCount: 100,
    });
  });

  it("detects materially divergent nutrition", () => {
    expect(nutritionDiverges([
      { calories: 130, proteinGrams: 2, carbsGrams: 28, fatGrams: 0 },
      { calories: 360, proteinGrams: 7, carbsGrams: 78, fatGrams: 1 },
    ])).toBe(true);

    expect(nutritionDiverges([
      { calories: 130, proteinGrams: 2, carbsGrams: 28, fatGrams: 0 },
      { calories: 140, proteinGrams: 2.2, carbsGrams: 29, fatGrams: 0.1 },
    ])).toBe(false);
  });
});

function doc(overrides: Partial<NormalizedFoodSearchDocumentInput>): NormalizedFoodSearchDocumentInput {
  return {
    foodItemId: "food-1",
    locale: "en",
    resultType: "generic_food",
    displayName: "Food",
    baseName: "Food",
    primaryEntityName: "Food",
    primaryEntityAliases: ["food"],
    secondaryEntityAliases: [],
    identityTokenKeys: [],
    primaryEntityCategoryCoherence: 0,
    primaryEntityRepresentativeness: 0,
    searchText: "food",
    searchAliases: [],
    rankBucket: 1,
    normalizationVersion: "food-normalization-v1",
    normalizationSource: "deterministic",
    normalizationConfidence: 0.82,
    qualityFlags: [],
    metadata: {},
    ...overrides,
  };
}

function reviewMetric(overrides: { displayTokenCount: number; searchTextTokenCount: number }) {
  return {
    rawTokenCount: 1,
    displayTokenCount: overrides.displayTokenCount,
    rawCharLength: 1,
    displayCharLength: 1,
    searchTextTokenCount: overrides.searchTextTokenCount,
    hiddenDescriptorCount: 0,
    retainedDescriptorCount: 0,
    compressionRatio: 1,
    charCompressionRatio: 1,
    descriptorLossRatio: 0,
    normalizationConfidence: 0.82,
  };
}
