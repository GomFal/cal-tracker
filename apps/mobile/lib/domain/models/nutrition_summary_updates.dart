import 'macro_distribution.dart';
import 'nutrition_models.dart';

NutritionSnapshot sumMealItems(Iterable<MealItem> items) {
  var calories = 0;
  var protein = 0.0;
  var carbs = 0.0;
  var fat = 0.0;
  for (final item in items) {
    calories += item.calories;
    protein += item.proteinGrams;
    carbs += item.carbsGrams;
    fat += item.fatGrams;
  }
  return NutritionSnapshot(
    calories: calories,
    proteinGrams: protein,
    carbsGrams: carbs,
    fatGrams: fat,
  );
}

NutritionSnapshot sumMeals(Iterable<Meal> meals) {
  var calories = 0;
  var protein = 0.0;
  var carbs = 0.0;
  var fat = 0.0;
  for (final meal in meals) {
    calories += meal.nutrition.calories;
    protein += meal.nutrition.proteinGrams;
    carbs += meal.nutrition.carbsGrams;
    fat += meal.nutrition.fatGrams;
  }
  return NutritionSnapshot(
    calories: calories,
    proteinGrams: protein,
    carbsGrams: carbs,
    fatGrams: fat,
  );
}

Meal mealWithItems(Meal meal, List<MealItem> items) {
  return Meal(
    id: meal.id,
    title: meal.title,
    occurredAt: meal.occurredAt,
    mealLabel: meal.mealLabel,
    nutrition: sumMealItems(items),
    items: items,
  );
}

MealTemplate mealTemplateWithItems({
  required String id,
  required String title,
  required bool trustedAutoCommitEnabled,
  required List<MealItem> items,
  required List<String> aliases,
}) {
  return MealTemplate(
    id: id,
    title: title,
    trustedAutoCommitEnabled: trustedAutoCommitEnabled,
    nutrition: sumMealItems(items),
    items: items,
    aliases: aliases,
  );
}

DailyGoals goalsFromSummary(DailySummary summary) {
  return DailyGoals(
    date: summary.date,
    target: summary.target,
    hydrationGoalLiters: summary.hydrationGoalLiters,
    calorieTargetConfigured: summary.calorieTargetConfigured,
    calorieTargetSource: summary.calorieTargetSource,
    macroMode: summary.macroMode,
    macroSource: summary.macroSource,
    macroPreset: summary.macroPreset,
    proteinPct: summary.proteinPct,
    carbsPct: summary.carbsPct,
    fatPct: summary.fatPct,
    macroCalories: summary.macroCalories,
    calorieDeltaKcal: summary.calorieDeltaKcal,
  );
}

DailyGoals goalsWithOverrides(
  DailyGoals goals, {
  int? calories,
  double? hydrationGoalLiters,
  String? calorieTargetSource,
  MacroDistributionConfig? macroConfig,
  int? macroCalorieTarget,
}) {
  final target = _targetWithOverrides(
    goals.target,
    calories: calories,
    macroConfig: macroConfig,
    macroCalorieTarget: macroCalorieTarget,
  );
  return DailyGoals(
    date: goals.date,
    target: target,
    hydrationGoalLiters: hydrationGoalLiters ?? goals.hydrationGoalLiters,
    calorieTargetConfigured: calories == null
        ? goals.calorieTargetConfigured
        : true,
    calorieTargetSource: calorieTargetSource ?? goals.calorieTargetSource,
    macroMode: macroConfig?.mode ?? goals.macroMode,
    macroSource: macroConfig?.source ?? goals.macroSource,
    macroPreset: macroConfig?.preset ?? goals.macroPreset,
    proteinPct: macroConfig == null
        ? goals.proteinPct
        : macroConfig.percentages?.proteinPct,
    carbsPct: macroConfig == null
        ? goals.carbsPct
        : macroConfig.percentages?.carbsPct,
    fatPct: macroConfig == null
        ? goals.fatPct
        : macroConfig.percentages?.fatPct,
    macroCalories: macroConfig == null
        ? goals.macroCalories
        : macroCalorieTarget ?? calories ?? goals.target.calories,
    calorieDeltaKcal: macroConfig == null ? goals.calorieDeltaKcal : 0,
  );
}

DailySummary dailySummaryWithMeals(DailySummary summary, List<Meal> meals) {
  final consumed = sumMeals(meals);
  return DailySummary(
    date: summary.date,
    consumed: consumed,
    target: summary.target,
    remaining: _remaining(summary.target, consumed),
    hydrationGoalLiters: summary.hydrationGoalLiters,
    waterConsumedLiters: summary.waterConsumedLiters,
    calorieTargetConfigured: summary.calorieTargetConfigured,
    calorieTargetSource: summary.calorieTargetSource,
    macroMode: summary.macroMode,
    macroSource: summary.macroSource,
    macroPreset: summary.macroPreset,
    proteinPct: summary.proteinPct,
    carbsPct: summary.carbsPct,
    fatPct: summary.fatPct,
    macroCalories: summary.macroCalories,
    calorieDeltaKcal: summary.calorieDeltaKcal,
    meals: meals,
  );
}

DailySummary replaceMealInSummary(DailySummary summary, Meal meal) {
  final meals = summary.meals
      .map((existing) => existing.id == meal.id ? meal : existing)
      .toList();
  return dailySummaryWithMeals(summary, meals);
}

DailySummary removeMealFromSummary(DailySummary summary, String mealId) {
  return dailySummaryWithMeals(
    summary,
    summary.meals.where((meal) => meal.id != mealId).toList(),
  );
}

DailySummary dailySummaryWithWater(
  DailySummary summary,
  double waterConsumedLiters,
) {
  return DailySummary(
    date: summary.date,
    consumed: summary.consumed,
    target: summary.target,
    remaining: summary.remaining,
    hydrationGoalLiters: summary.hydrationGoalLiters,
    waterConsumedLiters: waterConsumedLiters,
    calorieTargetConfigured: summary.calorieTargetConfigured,
    calorieTargetSource: summary.calorieTargetSource,
    macroMode: summary.macroMode,
    macroSource: summary.macroSource,
    macroPreset: summary.macroPreset,
    proteinPct: summary.proteinPct,
    carbsPct: summary.carbsPct,
    fatPct: summary.fatPct,
    macroCalories: summary.macroCalories,
    calorieDeltaKcal: summary.calorieDeltaKcal,
    meals: summary.meals,
  );
}

DailySummary dailySummaryWithGoals(DailySummary summary, DailyGoals goals) {
  return DailySummary(
    date: summary.date,
    consumed: summary.consumed,
    target: goals.target,
    remaining: _remaining(goals.target, summary.consumed),
    hydrationGoalLiters: goals.hydrationGoalLiters,
    waterConsumedLiters: summary.waterConsumedLiters,
    calorieTargetConfigured: goals.calorieTargetConfigured,
    calorieTargetSource: goals.calorieTargetSource,
    macroMode: goals.macroMode,
    macroSource: goals.macroSource,
    macroPreset: goals.macroPreset,
    proteinPct: goals.proteinPct,
    carbsPct: goals.carbsPct,
    fatPct: goals.fatPct,
    macroCalories: goals.macroCalories,
    calorieDeltaKcal: goals.calorieDeltaKcal,
    meals: summary.meals,
  );
}

NutritionSnapshot _targetWithOverrides(
  NutritionSnapshot target, {
  int? calories,
  MacroDistributionConfig? macroConfig,
  int? macroCalorieTarget,
}) {
  if (macroConfig == null) {
    return NutritionSnapshot(
      calories: calories ?? target.calories,
      proteinGrams: target.proteinGrams,
      carbsGrams: target.carbsGrams,
      fatGrams: target.fatGrams,
    );
  }
  final targetCalories = macroCalorieTarget ?? calories ?? target.calories;
  final grams = macroConfig.percentages == null
      ? macroConfig.grams
      : gramsFromPercentages(targetCalories, macroConfig.percentages!);
  return NutritionSnapshot(
    calories: targetCalories,
    proteinGrams: grams?.proteinGrams ?? target.proteinGrams,
    carbsGrams: grams?.carbsGrams ?? target.carbsGrams,
    fatGrams: grams?.fatGrams ?? target.fatGrams,
  );
}

NutritionSnapshot _remaining(NutritionSnapshot target, NutritionSnapshot used) {
  return NutritionSnapshot(
    calories: target.calories - used.calories,
    proteinGrams: target.proteinGrams - used.proteinGrams,
    carbsGrams: target.carbsGrams - used.carbsGrams,
    fatGrams: target.fatGrams - used.fatGrams,
  );
}
