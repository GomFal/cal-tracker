UPDATE nutrition_targets
SET
  protein_grams = 0,
  carbs_grams = 0,
  fat_grams = 0,
  macro_source = NULL,
  macro_preset = NULL,
  protein_pct = NULL,
  carbs_pct = NULL,
  fat_pct = NULL,
  macro_calories = NULL,
  calorie_delta_kcal = NULL
WHERE macro_mode IS NULL;

UPDATE daily_goal_snapshots
SET
  protein_grams = 0,
  carbs_grams = 0,
  fat_grams = 0,
  macro_source = NULL,
  macro_preset = NULL,
  protein_pct = NULL,
  carbs_pct = NULL,
  fat_pct = NULL,
  macro_calories = NULL,
  calorie_delta_kcal = NULL
WHERE macro_mode IS NULL;
