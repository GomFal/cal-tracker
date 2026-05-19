ALTER TABLE nutrition_targets
  ADD COLUMN IF NOT EXISTS macro_mode text,
  ADD COLUMN IF NOT EXISTS macro_source text,
  ADD COLUMN IF NOT EXISTS macro_preset text,
  ADD COLUMN IF NOT EXISTS protein_pct integer,
  ADD COLUMN IF NOT EXISTS carbs_pct integer,
  ADD COLUMN IF NOT EXISTS fat_pct integer,
  ADD COLUMN IF NOT EXISTS macro_calories integer,
  ADD COLUMN IF NOT EXISTS calorie_delta_kcal integer;

ALTER TABLE daily_goal_snapshots
  ADD COLUMN IF NOT EXISTS macro_mode text,
  ADD COLUMN IF NOT EXISTS macro_source text,
  ADD COLUMN IF NOT EXISTS macro_preset text,
  ADD COLUMN IF NOT EXISTS protein_pct integer,
  ADD COLUMN IF NOT EXISTS carbs_pct integer,
  ADD COLUMN IF NOT EXISTS fat_pct integer,
  ADD COLUMN IF NOT EXISTS macro_calories integer,
  ADD COLUMN IF NOT EXISTS calorie_delta_kcal integer;
