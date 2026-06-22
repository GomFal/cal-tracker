CREATE TABLE IF NOT EXISTS agent_candidate_registries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES agent_conversations(id) ON DELETE CASCADE,
  message_id uuid REFERENCES agent_messages(id) ON DELETE SET NULL,
  trace_id text,
  turn_id uuid,
  action_call_id uuid,
  search_ref text NOT NULL,
  action_id text NOT NULL,
  candidate_count integer NOT NULL,
  group_count integer NOT NULL,
  threshold numeric,
  registry_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS agent_candidate_registries_user_search_ref_unique
  ON agent_candidate_registries(user_id, search_ref);

CREATE INDEX IF NOT EXISTS agent_candidate_registries_conversation_created_idx
  ON agent_candidate_registries(conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS agent_candidate_registries_turn_id_idx
  ON agent_candidate_registries(turn_id);

CREATE INDEX IF NOT EXISTS agent_candidate_registries_trace_id_idx
  ON agent_candidate_registries(trace_id);
