import type { MacroGoalMetadata, MacroMode, MacroPreset, MacroSource, NutritionSnapshot } from "@cal-tracker/contracts";

export const PROTEIN_KCAL_PER_GRAM = 4;
export const CARBS_KCAL_PER_GRAM = 4;
export const FAT_KCAL_PER_GRAM = 9;
export const MAX_MACRO_GRAMS = 2000;
export const BLOCKING_MACRO_CALORIE_DELTA_KCAL = 25;

export type MacroPercentages = {
  proteinPct: number;
  carbsPct: number;
  fatPct: number;
};

export type MacroGrams = {
  proteinGrams: number;
  carbsGrams: number;
  fatGrams: number;
};

export type MacroGoalUpdateInput = {
  macroMode?: MacroMode;
  macroSource?: MacroSource;
  macroPreset?: MacroPreset | null;
  proteinPct?: number;
  carbsPct?: number;
  fatPct?: number;
  proteinGrams?: number;
  carbsGrams?: number;
  fatGrams?: number;
  macroCalories?: number;
  calorieDeltaKcal?: number;
};

export const macroPresets: Record<MacroPreset, MacroPercentages> = {
  balanced: { proteinPct: 30, carbsPct: 40, fatPct: 30 },
  high_protein: { proteinPct: 35, carbsPct: 35, fatPct: 30 },
  lower_carb: { proteinPct: 35, carbsPct: 25, fatPct: 40 }
};

export function gramsFromPercentages(calories: number, percentages: MacroPercentages): MacroGrams {
  return {
    proteinGrams: Math.round((calories * percentages.proteinPct / 100) / PROTEIN_KCAL_PER_GRAM),
    carbsGrams: Math.round((calories * percentages.carbsPct / 100) / CARBS_KCAL_PER_GRAM),
    fatGrams: Math.round((calories * percentages.fatPct / 100) / FAT_KCAL_PER_GRAM)
  };
}

export function macroCaloriesFromGrams(grams: MacroGrams): number {
  return Math.round(
    grams.proteinGrams * PROTEIN_KCAL_PER_GRAM +
    grams.carbsGrams * CARBS_KCAL_PER_GRAM +
    grams.fatGrams * FAT_KCAL_PER_GRAM
  );
}

export function nutritionWithMacroGrams(calories: number, grams: MacroGrams): NutritionSnapshot {
  return {
    calories,
    proteinGrams: grams.proteinGrams,
    carbsGrams: grams.carbsGrams,
    fatGrams: grams.fatGrams
  };
}

export function calorieDeltaKcal(calories: number, grams: MacroGrams): number {
  return macroCaloriesFromGrams(grams) - calories;
}

export function validateMacroGoalUpdate(
  input: MacroGoalUpdateInput,
  nextCalories: number
): string | null {
  if (input.macroMode === undefined) return null;
  if (input.macroMode === "percentage") {
    const total = (input.proteinPct ?? 0) + (input.carbsPct ?? 0) + (input.fatPct ?? 0);
    return total === 100 ? null : "macro percentages must total 100";
  }

  const grams = {
    proteinGrams: input.proteinGrams ?? 0,
    carbsGrams: input.carbsGrams ?? 0,
    fatGrams: input.fatGrams ?? 0
  };
  if (
    grams.proteinGrams > MAX_MACRO_GRAMS ||
    grams.carbsGrams > MAX_MACRO_GRAMS ||
    grams.fatGrams > MAX_MACRO_GRAMS
  ) {
    return "macro grams must be 2000 g or less";
  }
  const macroCalories = macroCaloriesFromGrams(grams);
  const delta = macroCalories - nextCalories;
  if (Math.abs(delta) > BLOCKING_MACRO_CALORIE_DELTA_KCAL) {
    return "macro grams must match the calorie target within 25 kcal";
  }
  if (input.macroCalories !== undefined && input.macroCalories !== macroCalories) {
    return "macroCalories does not match macro grams";
  }
  if (input.calorieDeltaKcal !== undefined && input.calorieDeltaKcal !== delta) {
    return "calorieDeltaKcal does not match macro grams";
  }
  return null;
}

export function applyMacroGoalUpdate(
  currentTarget: NutritionSnapshot,
  currentMetadata: MacroGoalMetadata,
  input: MacroGoalUpdateInput,
  nextCalories: number
): { target: NutritionSnapshot; metadata: MacroGoalMetadata } {
  if (input.macroMode === undefined) {
    if (
      nextCalories !== currentTarget.calories &&
      currentMetadata.macroMode === "percentage" &&
      currentMetadata.proteinPct != null &&
      currentMetadata.carbsPct != null &&
      currentMetadata.fatPct != null
    ) {
      return percentageMacroGoal(nextCalories, {
        proteinPct: currentMetadata.proteinPct,
        carbsPct: currentMetadata.carbsPct,
        fatPct: currentMetadata.fatPct
      }, {
        macroSource: currentMetadata.macroSource ?? "custom",
        macroPreset: currentMetadata.macroPreset ?? null
      });
    }
    return {
      target: { ...currentTarget, calories: nextCalories },
      metadata: currentMetadata
    };
  }

  if (input.macroMode === "percentage") {
    return percentageMacroGoal(nextCalories, {
      proteinPct: input.proteinPct ?? 0,
      carbsPct: input.carbsPct ?? 0,
      fatPct: input.fatPct ?? 0
    }, {
      macroSource: input.macroSource ?? (input.macroPreset ? "preset" : "custom"),
      macroPreset: input.macroPreset ?? null
    });
  }

  const grams = {
    proteinGrams: input.proteinGrams ?? currentTarget.proteinGrams,
    carbsGrams: input.carbsGrams ?? currentTarget.carbsGrams,
    fatGrams: input.fatGrams ?? currentTarget.fatGrams
  };
  const macroCalories = macroCaloriesFromGrams(grams);
  return {
    target: nutritionWithMacroGrams(nextCalories, grams),
    metadata: {
      macroMode: "grams",
      macroSource: input.macroSource ?? "custom",
      macroPreset: input.macroPreset ?? null,
      proteinPct: input.proteinPct ?? null,
      carbsPct: input.carbsPct ?? null,
      fatPct: input.fatPct ?? null,
      macroCalories,
      calorieDeltaKcal: macroCalories - nextCalories
    }
  };
}

function percentageMacroGoal(
  calories: number,
  percentages: MacroPercentages,
  identity: { macroSource: MacroSource; macroPreset: MacroPreset | null }
): { target: NutritionSnapshot; metadata: MacroGoalMetadata } {
  const grams = gramsFromPercentages(calories, percentages);
  const macroCalories = macroCaloriesFromGrams(grams);
  return {
    target: nutritionWithMacroGrams(calories, grams),
    metadata: {
      macroMode: "percentage",
      macroSource: identity.macroSource,
      macroPreset: identity.macroPreset,
      proteinPct: percentages.proteinPct,
      carbsPct: percentages.carbsPct,
      fatPct: percentages.fatPct,
      macroCalories,
      calorieDeltaKcal: macroCalories - calories
    }
  };
}
