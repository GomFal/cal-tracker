-- A direct client commit has one authoritative meal and one persisted timeline
-- entry. The proposal lock in PostgresRepository serializes concurrent requests;
-- these constraints preserve that invariant across retries and process restarts.
CREATE UNIQUE INDEX IF NOT EXISTS meals_proposal_id_unique
  ON meals (proposal_id)
  WHERE proposal_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS agent_direct_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action_id text NOT NULL CHECK (action_id = 'commit_meal'),
  conversation_id uuid NOT NULL REFERENCES agent_conversations(id) ON DELETE CASCADE,
  proposal_id uuid NOT NULL REFERENCES meal_proposals(id) ON DELETE CASCADE,
  source_tool_call_id text NOT NULL,
  client_mutation_id uuid NOT NULL,
  meal_id uuid NOT NULL REFERENCES meals(id) ON DELETE RESTRICT,
  message_id uuid NOT NULL REFERENCES agent_messages(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, action_id, client_mutation_id),
  UNIQUE (user_id, proposal_id)
);

CREATE INDEX IF NOT EXISTS agent_direct_actions_conversation_idx
  ON agent_direct_actions (user_id, conversation_id, created_at);
