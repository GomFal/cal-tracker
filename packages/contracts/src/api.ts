import { z } from "zod";
import {
  calorieTargetSourceSchema,
  dailyGoalsSchema,
  dailySummarySchema,
  foodCandidateSchema,
  macroModeSchema,
  macroPresetSchema,
  macroSourceSchema,
  mealItemSchema,
  mealProposalSchema,
  mealSchema,
  mealTemplateSchema,
  nutritionSnapshotSchema,
  quarterLiterSchema,
  uuidSchema
} from "./common.js";

export const errorResponseSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    traceId: z.string().optional(),
    details: z.unknown().optional()
  })
});

export const executeActionRequestSchema = z.object({
  input: z.unknown().default({}),
  source: z.enum(["flutter", "internal_agent", "android_appfunctions", "ios_appintents", "rest"]).default("rest")
});

export const executeActionResponseSchema = z.object({
  actionCallId: uuidSchema,
  confirmationRequired: z.boolean(),
  output: z.unknown()
});

export const agentRunRequestSchema = z.object({
  text: z.string().min(1),
  source: z.enum(["flutter", "ios_appintents", "android_appfunctions"]).default("flutter"),
  activeProposalId: uuidSchema.optional()
});

export const agentRunResponseSchema = z.object({
  kind: z.enum([
    "proposal",
    "meal_committed",
    "meal_corrected",
    "summary",
    "remaining_targets",
    "history",
    "food_memory",
    "nutrition_search",
    "templates",
    "template_saved",
    "template_deleted",
    "confirmation_required",
    "meal_deleted",
    "clarification_required"
  ]),
  message: z.string(),
  proposal: mealProposalSchema.optional(),
  meal: mealSchema.optional(),
  summary: dailySummarySchema.optional(),
  remaining: nutritionSnapshotSchema.optional(),
  meals: z.array(mealSchema).optional(),
  items: z.array(mealItemSchema).optional(),
  templates: z.array(mealTemplateSchema).optional(),
  template: mealTemplateSchema.optional(),
  matches: z.array(z.unknown()).optional(),
  deleted: z.boolean().optional(),
  actionId: z.string().optional(),
  input: z.unknown().optional(),
  options: z.array(z.union([foodCandidateSchema, z.unknown()])).optional(),
  candidateGroups: z
    .array(z.union([foodCandidateSchema, z.unknown()]))
    .optional()
});

export const transcriptionResponseSchema = z.object({
  transcript: z.string(),
  provider: z.string(),
  model: z.string(),
  traceId: z.string()
});

export const voiceMealRunResponseSchema = z.object({
  transcript: z.string(),
  provider: z.string(),
  model: z.string(),
  traceId: z.string(),
  result: agentRunResponseSchema
});

export const foodSearchRequestSchema = z.object({
  query: z.string().trim().min(1),
  barcode: z.string().trim().min(1).optional(),
  limit: z.number().int().min(1).max(25).default(10)
});

export const foodSearchResponseSchema = z.object({
  items: z.array(mealItemSchema),
  candidateGroups: z.array(foodCandidateSchema).optional()
});

export const settingsUpdateSchema = z.object({
  trustedModeEnabled: z.boolean().optional()
});

export const goalsUpdateSchema = z.object({
  date: z.string().optional(),
  calories: z.number().int().min(800).max(10000).optional(),
  hydrationGoalLiters: quarterLiterSchema.optional(),
  calorieTargetSource: calorieTargetSourceSchema.optional(),
  macroMode: macroModeSchema.optional(),
  macroSource: macroSourceSchema.optional(),
  macroPreset: macroPresetSchema.nullable().optional(),
  proteinPct: z.number().int().min(0).max(100).optional(),
  carbsPct: z.number().int().min(0).max(100).optional(),
  fatPct: z.number().int().min(0).max(100).optional(),
  proteinGrams: z.number().nonnegative().max(2000).optional(),
  carbsGrams: z.number().nonnegative().max(2000).optional(),
  fatGrams: z.number().nonnegative().max(2000).optional(),
  macroCalories: z.number().int().nonnegative().optional(),
  calorieDeltaKcal: z.number().int().optional()
}).superRefine((value, ctx) => {
  const hasMacroField = value.macroMode !== undefined ||
    value.macroSource !== undefined ||
    value.macroPreset !== undefined ||
    value.proteinPct !== undefined ||
    value.carbsPct !== undefined ||
    value.fatPct !== undefined ||
    value.proteinGrams !== undefined ||
    value.carbsGrams !== undefined ||
    value.fatGrams !== undefined ||
    value.macroCalories !== undefined ||
    value.calorieDeltaKcal !== undefined;
  if (value.calories === undefined && value.hydrationGoalLiters === undefined && !hasMacroField) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "calories, hydrationGoalLiters, or macro fields are required"
    });
  }
  if (!hasMacroField) return;
  if (value.macroMode === undefined) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["macroMode"],
      message: "macroMode is required when macro fields are provided"
    });
    return;
  }
  if (value.macroMode === "percentage") {
    if (value.proteinPct === undefined || value.carbsPct === undefined || value.fatPct === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["proteinPct"],
        message: "proteinPct, carbsPct, and fatPct are required in percentage mode"
      });
      return;
    }
    const total = value.proteinPct + value.carbsPct + value.fatPct;
    if (total !== 100) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["proteinPct"],
        message: "macro percentages must total 100"
      });
    }
  }
  if (value.macroMode === "grams") {
    if (value.proteinGrams === undefined || value.carbsGrams === undefined || value.fatGrams === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["proteinGrams"],
        message: "proteinGrams, carbsGrams, and fatGrams are required in grams mode"
      });
    }
  }
});

export const dailyHydrationUpdateSchema = z.object({
  date: z.string().optional(),
  waterConsumedLiters: quarterLiterSchema
});

export const dailyHydrationResponseSchema = z.object({
  summary: dailySummarySchema
});

export const calorieEstimateRequestSchema = z.object({
  age: z.number().int().min(18).max(100),
  sex: z.enum(["male", "female"]),
  heightCm: z.number().min(120).max(230),
  weightKg: z.number().min(35).max(250),
  activityLevel: z.enum(["sedentary", "lightly_active", "moderately_active", "very_active", "extra_active"]),
  goal: z.enum(["lose_fat", "maintain", "gain_muscle"]),
  pace: z.enum(["slow", "moderate", "aggressive", "lean", "standard"]).optional()
});

export const calorieEstimateResponseSchema = z.object({
  bmr: z.number().int().positive(),
  maintenanceCalories: z.number().int().positive(),
  targetCalories: z.number().int().min(800).max(10000),
  recommendedRange: z.object({
    min: z.number().int().min(800).max(10000),
    max: z.number().int().min(800).max(10000)
  }),
  activityFactor: z.number().positive(),
  adjustmentCalories: z.number().int(),
  warnings: z.array(z.string()),
  explanation: z.string()
});

export const goalsResponseSchema = z.object({
  goals: dailyGoalsSchema,
  summary: dailySummarySchema.optional()
});

export type CalorieEstimateRequest = z.infer<typeof calorieEstimateRequestSchema>;
export type CalorieEstimateResponse = z.infer<typeof calorieEstimateResponseSchema>;

export const dashboardResponseSchema = z.object({
  summary: dailySummarySchema
});

export const mealHistoryResponseSchema = z.object({
  meals: z.array(mealSchema)
});

export const templatesResponseSchema = z.object({
  templates: z.array(mealTemplateSchema)
});
