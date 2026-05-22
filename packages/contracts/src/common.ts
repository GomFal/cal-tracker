import { z } from "zod";

export const isoDateTimeSchema = z.string().datetime();
export const uuidSchema = z.string().uuid();

export const nutritionSnapshotSchema = z.object({
  calories: z.number().int().nonnegative(),
  proteinGrams: z.number().nonnegative(),
  carbsGrams: z.number().nonnegative(),
  fatGrams: z.number().nonnegative()
});

export const calorieTargetSourceSchema = z.enum(["manual", "calculator", "default"]);
export const macroModeSchema = z.enum(["percentage", "grams"]);
export const macroSourceSchema = z.enum(["preset", "custom"]);
export const macroPresetSchema = z.enum(["balanced", "high_protein", "lower_carb"]);

export const macroGoalMetadataSchema = z.object({
  macroMode: macroModeSchema.nullable().optional(),
  macroSource: macroSourceSchema.nullable().optional(),
  macroPreset: macroPresetSchema.nullable().optional(),
  proteinPct: z.number().int().min(0).max(100).nullable().optional(),
  carbsPct: z.number().int().min(0).max(100).nullable().optional(),
  fatPct: z.number().int().min(0).max(100).nullable().optional(),
  macroCalories: z.number().int().nonnegative().nullable().optional(),
  calorieDeltaKcal: z.number().int().nullable().optional()
});

export const quarterLiterSchema = z.number().min(0).max(10).refine(
  (value) => Math.abs(value * 4 - Math.round(value * 4)) < 1e-9,
  "must be in 0.25 L increments"
);

export const dailyGoalsSchema = z.object({
  date: z.string(),
  target: nutritionSnapshotSchema,
  hydrationGoalLiters: quarterLiterSchema,
  calorieTargetConfigured: z.boolean(),
  calorieTargetSource: calorieTargetSourceSchema,
  ...macroGoalMetadataSchema.shape
});

export const foodResolutionProvenanceSchema = z.object({
  originalText: z.string().optional(),
  canonicalName: z.string().optional(),
  externalSource: z.string().optional(),
  externalId: z.string().optional(),
  sourceUrl: z.string().url().optional(),
  license: z.string().optional(),
  confidence: z.number().min(0).max(1).optional(),
  needsReview: z.boolean().optional()
});

export const foodPortionChoiceSchema = z.object({
  label: z.string().min(1),
  quantity: z.number().positive(),
  unit: z.string().min(1),
  gramWeight: z.number().positive().optional(),
  totalGrams: z.number().positive().optional(),
  kind: z.enum(["count_size", "whole_item", "household", "piece_shape", "serving", "metric"]).optional(),
  portionDescriptor: z.string().optional(),
  canonicalFoodName: z.string().optional(),
  sourceDescription: z.string().optional(),
  externalSource: z.string().optional(),
  externalFoodId: z.string().optional(),
  actionText: z.string().optional()
});

export const mealItemSchema = z.object({
  id: uuidSchema.optional(),
  name: z.string().min(1),
  quantity: z.number().positive(),
  unit: z.string().min(1),
  calories: z.number().int().nonnegative(),
  proteinGrams: z.number().nonnegative(),
  carbsGrams: z.number().nonnegative(),
  fatGrams: z.number().nonnegative(),
  source: z.string().default("backend_estimate"),
  originalText: foodResolutionProvenanceSchema.shape.originalText,
  canonicalName: foodResolutionProvenanceSchema.shape.canonicalName,
  externalSource: foodResolutionProvenanceSchema.shape.externalSource,
  externalId: foodResolutionProvenanceSchema.shape.externalId,
  sourceUrl: foodResolutionProvenanceSchema.shape.sourceUrl,
  license: foodResolutionProvenanceSchema.shape.license,
  confidence: foodResolutionProvenanceSchema.shape.confidence,
  needsReview: foodResolutionProvenanceSchema.shape.needsReview,
  resolvedGrams: z.number().positive().optional(),
  portionDescription: z.string().optional(),
  rank: z.number().int().positive().optional(),
  matchScore: z.number().min(0).max(1).optional(),
  lexicalScore: z.number().min(0).max(1).optional(),
  vectorScore: z.number().min(0).max(1).optional(),
  preferenceScore: z.number().min(0).max(1).optional(),
  matchReason: z.string().optional()
});

export const foodMentionSchema = z.object({
  originalText: z.string().min(1),
  canonicalName: z.string().min(1).optional(),
  canonicalEnglishName: z.string().min(1).optional(),
  language: z.string().min(2).max(16).optional(),
  quantity: z.number().positive(),
  unit: z.string().min(1),
  rawUnitText: z.string().min(1).optional(),
  unitKind: z.enum(["metric", "household", "implicit_count", "unknown"]).optional(),
  portionDescriptorRaw: z.string().min(1).optional(),
  portionDescriptor: z.string().min(1).optional(),
  brand: z.string().optional(),
  barcode: z.string().optional(),
  confidence: z.number().min(0).max(1),
  marketProduct: z.boolean().default(false)
}).superRefine((mention, ctx) => {
  if (!mention.canonicalName && !mention.canonicalEnglishName) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: "canonicalName or canonicalEnglishName is required",
      path: ["canonicalName"]
    });
  }
});

export const foodCandidateSchema = z.object({
  mention: foodMentionSchema,
  candidates: z.array(mealItemSchema),
  reason: z.string().optional(),
  portionOptions: z.array(foodPortionChoiceSchema).optional()
});

export const mealLabelTypeSchema = z.enum([
  "breakfast",
  "lunch",
  "dinner",
  "snack",
  "pre_workout",
  "post_workout",
  "other"
]);

export const mealLabelSchema = z.object({
  type: mealLabelTypeSchema,
  label: z.string().trim().min(1).max(40)
});

export const mealProposalSchema = z.object({
  id: uuidSchema,
  phrase: z.string(),
  title: z.string(),
  status: z.enum(["pending", "committed", "rejected", "corrected"]),
  confidence: z.number().min(0).max(1),
  requiresConfirmation: z.boolean(),
  trustedAutoCommitEligible: z.boolean(),
  source: z.string(),
  nutrition: nutritionSnapshotSchema,
  items: z.array(mealItemSchema),
  createdAt: isoDateTimeSchema
});

export const mealSchema = z.object({
  id: uuidSchema,
  title: z.string(),
  occurredAt: isoDateTimeSchema,
  mealLabel: mealLabelSchema.nullable().optional(),
  nutrition: nutritionSnapshotSchema,
  items: z.array(mealItemSchema),
  createdAt: isoDateTimeSchema,
  deletedAt: isoDateTimeSchema.nullable().optional()
});

export const dailySummarySchema = z.object({
  date: z.string(),
  consumed: nutritionSnapshotSchema,
  target: nutritionSnapshotSchema,
  remaining: nutritionSnapshotSchema,
  hydrationGoalLiters: quarterLiterSchema,
  waterConsumedLiters: quarterLiterSchema,
  calorieTargetConfigured: z.boolean(),
  calorieTargetSource: calorieTargetSourceSchema,
  ...macroGoalMetadataSchema.shape,
  meals: z.array(mealSchema)
});

export const mealTemplateSchema = z.object({
  id: uuidSchema,
  title: z.string(),
  trustedAutoCommitEnabled: z.boolean(),
  nutrition: nutritionSnapshotSchema,
  items: z.array(mealItemSchema),
  aliases: z.array(z.string()).default([])
});

export type NutritionSnapshot = z.infer<typeof nutritionSnapshotSchema>;
export type CalorieTargetSource = z.infer<typeof calorieTargetSourceSchema>;
export type MacroMode = z.infer<typeof macroModeSchema>;
export type MacroSource = z.infer<typeof macroSourceSchema>;
export type MacroPreset = z.infer<typeof macroPresetSchema>;
export type MacroGoalMetadata = z.infer<typeof macroGoalMetadataSchema>;
export type DailyGoals = z.infer<typeof dailyGoalsSchema>;
export type FoodResolutionProvenance = z.infer<typeof foodResolutionProvenanceSchema>;
export type FoodPortionChoice = z.infer<typeof foodPortionChoiceSchema>;
export type MealItem = z.infer<typeof mealItemSchema>;
export type FoodMention = z.infer<typeof foodMentionSchema>;
export type FoodCandidateGroup = z.infer<typeof foodCandidateSchema>;
export type MealLabelType = z.infer<typeof mealLabelTypeSchema>;
export type MealLabel = z.infer<typeof mealLabelSchema>;
export type MealProposal = z.infer<typeof mealProposalSchema>;
export type Meal = z.infer<typeof mealSchema>;
export type DailySummary = z.infer<typeof dailySummarySchema>;
export type MealTemplate = z.infer<typeof mealTemplateSchema>;
