ALTER TABLE llm_runs
  ADD COLUMN IF NOT EXISTS conversation_id uuid,
  ADD COLUMN IF NOT EXISTS turn_id uuid,
  ADD COLUMN IF NOT EXISTS provider text,
  ADD COLUMN IF NOT EXISTS provider_request_id text,
  ADD COLUMN IF NOT EXISTS provider_generation_id text,
  ADD COLUMN IF NOT EXISTS provider_cost_amount numeric(12, 6),
  ADD COLUMN IF NOT EXISTS estimated_cost_amount numeric(12, 6),
  ADD COLUMN IF NOT EXISTS cost_currency text,
  ADD COLUMN IF NOT EXISTS cost_source text,
  ADD COLUMN IF NOT EXISTS pricing_snapshot_json jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS llm_runs_conversation_created_at_idx
  ON llm_runs(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS llm_runs_turn_id_idx
  ON llm_runs(turn_id);

CREATE TABLE IF NOT EXISTS agent_turn_telemetry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid REFERENCES agent_conversations(id) ON DELETE SET NULL,
  trace_id text NOT NULL,
  turn_id uuid NOT NULL,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  input_mode text,
  source text,
  active_proposal_id uuid,
  model text,
  input_text text,
  assistant_text text,
  result_kind text,
  stop_reason text,
  iteration_count integer NOT NULL DEFAULT 0,
  tool_call_count integer NOT NULL DEFAULT 0,
  prompt_chars integer,
  messages_json_chars integer,
  tools_json_chars integer,
  request_payload_chars integer,
  prompt_tokens integer,
  completion_tokens integer,
  total_tokens integer,
  reasoning_tokens integer,
  provider_cost_amount numeric(12, 6),
  estimated_cost_amount numeric(12, 6),
  cost_currency text,
  cost_source text,
  pricing_snapshot_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  first_byte_ms integer,
  first_tool_call_ms integer,
  largest_stream_gap_ms integer,
  llm_ms integer,
  action_ms integer,
  total_ms integer,
  status text NOT NULL DEFAULT 'success',
  error_code text,
  error_message text,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS agent_turn_telemetry_turn_id_unique
  ON agent_turn_telemetry(turn_id);
CREATE INDEX IF NOT EXISTS agent_turn_telemetry_created_at_idx
  ON agent_turn_telemetry(created_at DESC);
CREATE INDEX IF NOT EXISTS agent_turn_telemetry_trace_id_idx
  ON agent_turn_telemetry(trace_id);
CREATE INDEX IF NOT EXISTS agent_turn_telemetry_user_created_at_idx
  ON agent_turn_telemetry(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS agent_turn_telemetry_conversation_created_at_idx
  ON agent_turn_telemetry(conversation_id, created_at DESC);

CREATE TABLE IF NOT EXISTS agent_tool_call_telemetry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_turn_id uuid REFERENCES agent_turn_telemetry(id) ON DELETE SET NULL,
  conversation_id uuid REFERENCES agent_conversations(id) ON DELETE SET NULL,
  trace_id text NOT NULL,
  turn_id uuid,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  tool_call_id text,
  action_call_id uuid,
  action_id text NOT NULL,
  arguments_json jsonb,
  result_summary_json jsonb,
  status text NOT NULL,
  error_message text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  duration_ms integer,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS agent_tool_call_telemetry_created_at_idx
  ON agent_tool_call_telemetry(created_at DESC);
CREATE INDEX IF NOT EXISTS agent_tool_call_telemetry_trace_id_idx
  ON agent_tool_call_telemetry(trace_id);
CREATE INDEX IF NOT EXISTS agent_tool_call_telemetry_turn_id_idx
  ON agent_tool_call_telemetry(turn_id);
CREATE INDEX IF NOT EXISTS agent_tool_call_telemetry_action_call_id_idx
  ON agent_tool_call_telemetry(action_call_id);
CREATE INDEX IF NOT EXISTS agent_tool_call_telemetry_user_created_at_idx
  ON agent_tool_call_telemetry(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS llm_provider_calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trace_id text NOT NULL,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  conversation_id uuid REFERENCES agent_conversations(id) ON DELETE SET NULL,
  agent_turn_id uuid REFERENCES agent_turn_telemetry(id) ON DELETE SET NULL,
  turn_id uuid,
  action_call_id uuid,
  feature_surface text NOT NULL,
  provider text NOT NULL,
  provider_request_id text,
  provider_generation_id text,
  requested_model text NOT NULL,
  served_model text,
  routing_json jsonb,
  input_mode text,
  prompt_tokens integer,
  completion_tokens integer,
  total_tokens integer,
  reasoning_tokens integer,
  cached_input_tokens integer,
  audio_tokens integer,
  image_tokens integer,
  provider_cost_amount numeric(12, 6),
  estimated_cost_amount numeric(12, 6),
  cost_currency text,
  cost_source text NOT NULL DEFAULT 'unknown',
  input_token_unit_price numeric(12, 8),
  output_token_unit_price numeric(12, 8),
  reasoning_token_unit_price numeric(12, 8),
  cached_input_token_unit_price numeric(12, 8),
  audio_token_unit_price numeric(12, 8),
  image_token_unit_price numeric(12, 8),
  pricing_source text,
  pricing_version text,
  pricing_effective_at timestamptz,
  status text NOT NULL,
  error_code text,
  error_message text,
  duration_ms integer,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS llm_provider_calls_created_at_idx
  ON llm_provider_calls(created_at DESC);
CREATE INDEX IF NOT EXISTS llm_provider_calls_trace_id_idx
  ON llm_provider_calls(trace_id);
CREATE INDEX IF NOT EXISTS llm_provider_calls_user_created_at_idx
  ON llm_provider_calls(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS llm_provider_calls_conversation_created_at_idx
  ON llm_provider_calls(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS llm_provider_calls_turn_id_idx
  ON llm_provider_calls(turn_id);
CREATE INDEX IF NOT EXISTS llm_provider_calls_model_created_at_idx
  ON llm_provider_calls(requested_model, created_at DESC);

CREATE TABLE IF NOT EXISTS transcription_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trace_id text NOT NULL,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  conversation_id uuid REFERENCES agent_conversations(id) ON DELETE SET NULL,
  turn_id uuid,
  surface text NOT NULL,
  provider text,
  model text,
  language text,
  audio_mime_type text,
  audio_bytes integer,
  audio_duration_ms integer,
  transcript_text text,
  transcript_length integer NOT NULL DEFAULT 0,
  duration_ms integer,
  status text NOT NULL,
  error_code text,
  error_message text,
  downstream_result_kind text,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS transcription_records_created_at_idx
  ON transcription_records(created_at DESC);
CREATE INDEX IF NOT EXISTS transcription_records_trace_id_idx
  ON transcription_records(trace_id);
CREATE INDEX IF NOT EXISTS transcription_records_user_created_at_idx
  ON transcription_records(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS transcription_records_conversation_created_at_idx
  ON transcription_records(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS transcription_records_turn_id_idx
  ON transcription_records(turn_id);
