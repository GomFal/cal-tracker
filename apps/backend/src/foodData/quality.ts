export type FoodQualityStatus = "valid" | "duplicate" | "suspicious" | "quarantined";

export type FoodQualityClassification = {
  qualityStatus: FoodQualityStatus;
  isSearchEligible: boolean;
  qualityFlags: string[];
  qualityScore: number;
};

export type FoodQualityInput = {
  userId?: string | null;
  name: string;
  servingGrams: number;
  calories: number;
  proteinGrams: number;
  carbsGrams: number;
  fatGrams: number;
  brand?: string | null;
  barcode?: string | null;
  foodCategory?: string | null;
  ingredients?: string | null;
  isProduct?: boolean;
  sameNameNoBrandProductCount?: number;
};

const QUARANTINE_PENALTY = 0.4;
const SUSPICIOUS_PENALTY = 0.15;

export function classifyFoodQuality(input: FoodQualityInput): FoodQualityClassification {
  const imported = !input.userId;
  const quarantineFlags = quarantineFlagsForFood(input, imported);
  const suspiciousFlags = suspiciousFlagsForFood(input);
  const qualityFlags = [...quarantineFlags, ...suspiciousFlags];
  const qualityStatus: FoodQualityStatus =
    quarantineFlags.length > 0
      ? "quarantined"
      : suspiciousFlags.length > 0
        ? "suspicious"
        : "valid";
  return {
    qualityStatus,
    isSearchEligible: qualityStatus === "valid",
    qualityFlags,
    qualityScore: qualityScore(qualityStatus, quarantineFlags.length, suspiciousFlags.length),
  };
}

function quarantineFlagsForFood(input: FoodQualityInput, imported: boolean): string[] {
  const flags: string[] = [];
  const macroSum = input.proteinGrams + input.carbsGrams + input.fatGrams;

  if (input.name.trim().length === 0) flags.push("missing_name");
  if (input.calories < 0 || input.proteinGrams < 0 || input.carbsGrams < 0 || input.fatGrams < 0) {
    flags.push("negative_nutrition");
  }
  if (imported && input.calories === 0 && input.proteinGrams === 0 && input.carbsGrams === 0 && input.fatGrams === 0) {
    flags.push("zero_nutrition");
  }
  if (imported && input.calories === 0 && (input.proteinGrams > 0 || input.carbsGrams > 0 || input.fatGrams > 0)) {
    flags.push("zero_calories_with_macros");
  }
  if (input.calories > 1000) flags.push("impossible_calories");
  if (input.proteinGrams > 120 || input.carbsGrams > 120 || input.fatGrams > 120 || macroSum > 130) {
    flags.push("impossible_macros");
  }

  return flags;
}

function suspiciousFlagsForFood(input: FoodQualityInput): string[] {
  const flags: string[] = [];
  const macroCalories = input.proteinGrams * 4 + input.carbsGrams * 4 + input.fatGrams * 9;
  const macroDelta = Math.abs(macroCalories - input.calories);
  const macroThreshold = Math.max(75, input.calories * 0.5);

  if (input.calories > 0 && macroCalories > 0 && macroDelta > macroThreshold) {
    flags.push("macro_energy_mismatch");
  }

  const isProduct = Boolean(input.isProduct);
  const hasBrand = Boolean(input.brand?.trim());
  if (isProduct && !hasBrand && (input.sameNameNoBrandProductCount ?? 0) > 20) {
    flags.push("missing_brand_for_product");
  }
  if (
    isProduct &&
    !hasBrand &&
    !input.foodCategory?.trim() &&
    !input.ingredients?.trim()
  ) {
    flags.push("low_metadata");
  }

  return flags;
}

function qualityScore(status: FoodQualityStatus, quarantineCount: number, suspiciousCount: number): number {
  if (status === "duplicate") return 0;
  const score = 1 - quarantineCount * QUARANTINE_PENALTY - suspiciousCount * SUSPICIOUS_PENALTY;
  return Math.max(0, Math.min(1, Math.round(score * 10000) / 10000));
}
