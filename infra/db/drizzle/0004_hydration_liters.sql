ALTER TABLE "daily_goal_snapshots" ALTER COLUMN "hydration_goal_glasses" SET DEFAULT 0;--> statement-breakpoint
ALTER TABLE "nutrition_targets" ALTER COLUMN "hydration_goal_glasses" SET DEFAULT 0;--> statement-breakpoint
ALTER TABLE "daily_goal_snapshots" ADD COLUMN "hydration_goal_liters" numeric(5, 2) DEFAULT '0' NOT NULL;--> statement-breakpoint
ALTER TABLE "daily_goal_snapshots" ADD COLUMN "water_consumed_liters" numeric(5, 2) DEFAULT '0' NOT NULL;--> statement-breakpoint
ALTER TABLE "nutrition_targets" ADD COLUMN "hydration_goal_liters" numeric(5, 2) DEFAULT '0' NOT NULL;--> statement-breakpoint
UPDATE "daily_goal_snapshots"
SET
  "hydration_goal_glasses" = 0,
  "hydration_goal_liters" = 0,
  "water_consumed_liters" = 0;--> statement-breakpoint
UPDATE "nutrition_targets"
SET
  "hydration_goal_glasses" = 0,
  "hydration_goal_liters" = 0;
