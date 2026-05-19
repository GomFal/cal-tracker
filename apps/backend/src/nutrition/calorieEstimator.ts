import type { CalorieEstimateRequest, CalorieEstimateResponse } from "@cal-tracker/contracts";

const ACTIVITY_FACTORS: Record<CalorieEstimateRequest["activityLevel"], number> = {
  sedentary: 1.2,
  lightly_active: 1.375,
  moderately_active: 1.55,
  very_active: 1.725,
  extra_active: 1.9
};

type PaceRule = {
  percent: number;
  min: number;
  max: number;
};

const FAT_LOSS_RULES: Record<"slow" | "moderate" | "aggressive", PaceRule> = {
  slow: { percent: 0.1, min: 250, max: 500 },
  moderate: { percent: 0.15, min: 300, max: 750 },
  aggressive: { percent: 0.25, min: 500, max: 1000 }
};

const GAIN_RULES: Record<"lean" | "standard" | "aggressive", PaceRule> = {
  lean: { percent: 0.05, min: 100, max: 200 },
  standard: { percent: 0.1, min: 200, max: 350 },
  aggressive: { percent: 0.15, min: 350, max: 500 }
};

export function estimateCalories(input: CalorieEstimateRequest): CalorieEstimateResponse {
  const bmrRaw = input.sex === "male"
    ? 10 * input.weightKg + 6.25 * input.heightCm - 5 * input.age + 5
    : 10 * input.weightKg + 6.25 * input.heightCm - 5 * input.age - 161;
  const activityFactor = ACTIVITY_FACTORS[input.activityLevel];
  const maintenanceRaw = bmrRaw * activityFactor;
  const warnings: string[] = [];

  if (input.activityLevel === "extra_active") {
    warnings.push("Extra active is only for unusually high physical workloads. If unsure, choose Very active or Moderately active.");
  }

  let targetRaw = maintenanceRaw;
  let adjustmentCalories = 0;
  if (input.goal === "lose_fat") {
    const pace = isFatLossPace(input.pace) ? input.pace : "moderate";
    const rule = FAT_LOSS_RULES[pace];
    adjustmentCalories = roundToNearest10(clamp(maintenanceRaw * rule.percent, rule.min, rule.max));
    targetRaw = maintenanceRaw - adjustmentCalories;
  } else if (input.goal === "gain_muscle") {
    const pace = isGainPace(input.pace) ? input.pace : "standard";
    const rule = GAIN_RULES[pace];
    adjustmentCalories = roundToNearest10(clamp(maintenanceRaw * rule.percent, rule.min, rule.max));
    targetRaw = maintenanceRaw + adjustmentCalories;
  }

  const sexGuardrail = input.sex === "female" ? 1200 : 1500;
  if (targetRaw < sexGuardrail) {
    warnings.push(`This estimate is below the common ${sexGuardrail} kcal guardrail for this equation. Consider a less aggressive goal or professional guidance.`);
  }
  if (targetRaw < 800) {
    warnings.push("The formula produced a target below the app minimum, so the returned target was raised to 800 kcal.");
    targetRaw = 800;
  }

  const targetCalories = roundToNearest10(targetRaw);
  const maintenanceCalories = roundToNearest10(maintenanceRaw);
  const rangePadding = input.goal === "maintain" ? 150 : 100;
  const rangeMin = Math.max(800, roundToNearest10(targetCalories - rangePadding));
  const rangeMax = Math.min(10000, roundToNearest10(targetCalories + rangePadding));

  return {
    bmr: Math.round(bmrRaw),
    maintenanceCalories,
    targetCalories,
    recommendedRange: {
      min: rangeMin,
      max: rangeMax
    },
    activityFactor,
    adjustmentCalories,
    warnings,
    explanation: "This is a starting estimate based on Mifflin-St Jeor, an activity factor, and your goal. Track your trend for 2-4 weeks and adjust if needed."
  };
}

function isFatLossPace(value: unknown): value is "slow" | "moderate" | "aggressive" {
  return value === "slow" || value === "moderate" || value === "aggressive";
}

function isGainPace(value: unknown): value is "lean" | "standard" | "aggressive" {
  return value === "lean" || value === "standard" || value === "aggressive";
}

function roundToNearest10(value: number): number {
  return Math.round(value / 10) * 10;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
