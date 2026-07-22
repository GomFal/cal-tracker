import { createHash } from "node:crypto";
import type { Meal, MealItem } from "@cal-tracker/contracts";

/**
 * Fingerprints the complete mutable meal snapshot with a deliberately ordered
 * representation. Meal has no updatedAt, so commit-time optimistic concurrency
 * must compare the data that can actually change.
 */
export function mealFingerprint(meal: Meal): string {
  return createHash("sha256")
    .update(JSON.stringify(canonicalMeal(meal)))
    .digest("hex");
}

function canonicalMeal(meal: Meal) {
  return {
    id: meal.id,
    title: meal.title,
    occurredAt: new Date(meal.occurredAt).toISOString(),
    mealLabel: meal.mealLabel
      ? { type: meal.mealLabel.type, label: meal.mealLabel.label }
      : null,
    nutrition: {
      calories: meal.nutrition.calories,
      proteinGrams: meal.nutrition.proteinGrams,
      carbsGrams: meal.nutrition.carbsGrams,
      fatGrams: meal.nutrition.fatGrams,
    },
    items: meal.items.map(canonicalMealItem),
    createdAt: new Date(meal.createdAt).toISOString(),
    deletedAt: meal.deletedAt
      ? new Date(meal.deletedAt).toISOString()
      : null,
  };
}

function canonicalMealItem(item: MealItem) {
  return {
    id: item.id ?? null,
    name: item.name,
    quantity: item.quantity,
    unit: item.unit,
    calories: item.calories,
    proteinGrams: item.proteinGrams,
    carbsGrams: item.carbsGrams,
    fatGrams: item.fatGrams,
    source: item.source,
    originalText: item.originalText ?? null,
    canonicalName: item.canonicalName ?? null,
    language: item.language ?? null,
    externalSource: item.externalSource ?? null,
    externalId: item.externalId ?? null,
    sourceUrl: item.sourceUrl ?? null,
    license: item.license ?? null,
    confidence: item.confidence ?? null,
    needsReview: item.needsReview ?? null,
    resolvedGrams: item.resolvedGrams ?? null,
    portionDescription: item.portionDescription ?? null,
    displayDetails: item.displayDetails ?? null,
  };
}
