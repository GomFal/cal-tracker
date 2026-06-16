CREATE TABLE IF NOT EXISTS "telemetry_events" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "trace_id" text NOT NULL,
  "user_id" uuid REFERENCES users(id) ON DELETE SET NULL,
  "session_id" text,
  "event_type" text NOT NULL,
  "flow" text,
  "surface" text NOT NULL,
  "severity" text NOT NULL,
  "status" text,
  "route" text,
  "method" text,
  "action_id" text,
  "duration_ms" integer,
  "error_code" text,
  "error_message" text,
  "app_version" text,
  "app_build" text,
  "platform" text,
  "locale" text,
  "metadata_json" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz NOT NULL DEFAULT now()
);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "telemetry_events_created_at_idx" ON "telemetry_events" ("created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "telemetry_events_trace_id_idx" ON "telemetry_events" ("trace_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "telemetry_events_user_id_created_at_idx" ON "telemetry_events" ("user_id","created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "telemetry_events_event_type_created_at_idx" ON "telemetry_events" ("event_type","created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "telemetry_events_severity_created_at_idx" ON "telemetry_events" ("severity","created_at" DESC);--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "llm_runs" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "trace_id" text NOT NULL,
  "user_id" uuid REFERENCES users(id) ON DELETE SET NULL,
  "source" text,
  "locale" text,
  "timezone" text,
  "model" text NOT NULL,
  "input_mode" text,
  "active_proposal_id" uuid,
  "decision_source" text,
  "selected_tool" text,
  "executed_tool" text,
  "result_kind" text,
  "action_call_id" uuid,
  "prompt_chars" integer,
  "tools_json_chars" integer,
  "messages_json_chars" integer,
  "request_payload_chars" integer,
  "prompt_tokens" integer,
  "completion_tokens" integer,
  "total_tokens" integer,
  "reasoning_tokens" integer,
  "first_byte_ms" integer,
  "first_tool_call_ms" integer,
  "largest_stream_gap_ms" integer,
  "llm_ms" integer,
  "action_ms" integer,
  "total_ms" integer,
  "empty_tool_call" boolean NOT NULL DEFAULT false,
  "invalid_tool_arguments" boolean NOT NULL DEFAULT false,
  "provider_error" boolean NOT NULL DEFAULT false,
  "metadata_json" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz NOT NULL DEFAULT now()
);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "llm_runs_created_at_idx" ON "llm_runs" ("created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "llm_runs_trace_id_idx" ON "llm_runs" ("trace_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "llm_runs_user_id_created_at_idx" ON "llm_runs" ("user_id","created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "llm_runs_result_kind_created_at_idx" ON "llm_runs" ("result_kind","created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "llm_runs_selected_tool_created_at_idx" ON "llm_runs" ("selected_tool","created_at" DESC);--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "food_search_events" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "trace_id" text NOT NULL,
  "user_id" uuid REFERENCES users(id) ON DELETE SET NULL,
  "query_text" text,
  "query_hash" text,
  "query_length" integer NOT NULL DEFAULT 0,
  "locale" text,
  "barcode_present" boolean NOT NULL DEFAULT false,
  "normalized_search_enabled" boolean,
  "normalized_scope" text,
  "path" text,
  "result_count" integer NOT NULL DEFAULT 0,
  "candidate_group_count" integer,
  "top_score" numeric(8, 4),
  "top_external_source" text,
  "top_result_type" text,
  "zero_results" boolean NOT NULL DEFAULT false,
  "low_confidence" boolean NOT NULL DEFAULT false,
  "selected_rank" integer,
  "duration_ms" integer,
  "metadata_json" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz NOT NULL DEFAULT now()
);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "food_search_events_created_at_idx" ON "food_search_events" ("created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "food_search_events_trace_id_idx" ON "food_search_events" ("trace_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "food_search_events_user_id_created_at_idx" ON "food_search_events" ("user_id","created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "food_search_events_zero_results_created_at_idx" ON "food_search_events" ("zero_results","created_at" DESC);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "food_search_events_low_confidence_created_at_idx" ON "food_search_events" ("low_confidence","created_at" DESC);
