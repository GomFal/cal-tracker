import { z } from "zod";
import {
  dailyGoalsSchema,
  dailySummarySchema,
  mealTemplateSchema,
  mealSchema,
  usualFoodSchema,
} from "./common.js";

/**
 * Server-authoritative cache effects emitted only after a mutation has
 * completed. Clients must ignore domains and versions they do not understand.
 */
export const nutritionDataEffectDomainSchema = z.enum([
  "daily_summary",
  "daily_goals",
  "meals",
  "meal_templates",
  "usual_foods",
]);
export type NutritionDataEffectDomain = z.infer<
  typeof nutritionDataEffectDomainSchema
>;

export const nutritionDataEffectOperationSchema = z.enum([
  "replace",
  "upsert",
  "delete",
  "invalidate",
]);
export type NutritionDataEffectOperation = z.infer<
  typeof nutritionDataEffectOperationSchema
>;

const nutritionDataEffectSnapshotSchema = z.union([
  dailySummarySchema,
  dailyGoalsSchema,
  mealSchema,
  mealTemplateSchema,
  usualFoodSchema,
]);

export const nutritionDataEffectSchema = z.object({
  domain: nutritionDataEffectDomainSchema,
  operation: nutritionDataEffectOperationSchema,
  date: z.string().date().optional(),
  entityId: z.string().uuid().optional(),
  revision: z.string().min(1).max(256).optional(),
  snapshot: nutritionDataEffectSnapshotSchema.optional(),
});
export type NutritionDataEffect = z.infer<typeof nutritionDataEffectSchema>;

export const confirmedNutritionMutationSchema = z.object({
  version: z.literal(1),
  mutationId: z.string().uuid(),
  committedAt: z.string().datetime({ offset: true }),
  effects: z.array(nutritionDataEffectSchema),
});
export type ConfirmedNutritionMutation = z.infer<
  typeof confirmedNutritionMutationSchema
>;
