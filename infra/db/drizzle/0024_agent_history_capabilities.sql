ALTER TABLE "agent_direct_actions" DROP CONSTRAINT "agent_direct_actions_action_id_check";--> statement-breakpoint
DROP INDEX "agent_direct_actions_user_proposal_unique";--> statement-breakpoint
ALTER TABLE "agent_direct_actions" ALTER COLUMN "proposal_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "daily_goal_snapshots" ALTER COLUMN "water_consumed_liters" SET DATA TYPE numeric(6, 3);--> statement-breakpoint
ALTER TABLE "daily_goal_snapshots" ALTER COLUMN "water_consumed_liters" SET DEFAULT '0';--> statement-breakpoint
ALTER TABLE "action_calls" ADD COLUMN "internal_metadata_json" jsonb;--> statement-breakpoint
CREATE UNIQUE INDEX "agent_direct_actions_user_action_proposal_unique" ON "agent_direct_actions" USING btree ("user_id","action_id","proposal_id") WHERE "agent_direct_actions"."proposal_id" IS NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "agent_direct_actions_user_action_source_unique" ON "agent_direct_actions" USING btree ("user_id","action_id","source_tool_call_id");--> statement-breakpoint
ALTER TABLE "agent_direct_actions" ADD CONSTRAINT "agent_direct_actions_action_id_check" CHECK ("agent_direct_actions"."action_id" IN ('commit_meal','correct_meal'));