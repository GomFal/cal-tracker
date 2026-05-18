import { z } from "zod";
import {
  calorieTargetSourceSchema,
  dailyGoalsSchema,
  dailySummarySchema,
  foodCandidateSchema,
  mealItemSchema,
  mealProposalSchema,
  mealSchema,
  mealTemplateSchema,
  nutritionSnapshotSchema,
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
  activeProposalId: uuidSchema.optional(),
  source: z.enum(["flutter", "ios_appintents", "android_appfunctions"]).default("flutter")
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
  options: z.array(z.union([foodCandidateSchema, z.unknown()])).optional()
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

export const settingsUpdateSchema = z.object({
  trustedModeEnabled: z.boolean().optional()
});

export const goalsUpdateSchema = z.object({
  date: z.string().optional(),
  calories: z.number().int().min(800).max(10000).optional(),
  hydrationGoalGlasses: z.number().int().min(1).max(40).optional(),
  calorieTargetSource: calorieTargetSourceSchema.optional()
}).refine(
  (value) => value.calories !== undefined || value.hydrationGoalGlasses !== undefined,
  "calories or hydrationGoalGlasses is required"
);

export const calorieEstimateRequestSchema = z.object({
  age: z.number().int().min(18).max(100),
  sex: z.enum(["male", "female"]),
  heightCm: z.number().min(120).max(230),
  weightKg: z.number().min(35).max(250),
  activityLevel: z.enum(["sedentary", "lightly_active", "moderately_active", "very_active", "extra_active"]),
  goal: z.enum(["lose_fat", "maintain", "gain_muscle", "recomposition"]),
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
