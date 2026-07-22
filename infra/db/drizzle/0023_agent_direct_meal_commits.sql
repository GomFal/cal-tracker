-- A direct client commit has one authoritative meal and one persisted timeline
-- entry. The proposal lock in PostgresRepository serializes concurrent requests;
-- these constraints preserve that invariant across retries and process restarts.
CREATE UNIQUE INDEX IF NOT EXISTS meals_proposal_id_unique
  ON meals (proposal_id)
  WHERE proposal_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS agent_direct_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  action_id text NOT NULL,
  conversation_id uuid NOT NULL,
  proposal_id uuid NOT NULL,
  source_tool_call_id text NOT NULL,
  client_mutation_id uuid NOT NULL,
  meal_id uuid NOT NULL,
  message_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT agent_direct_actions_action_id_check CHECK (action_id = 'commit_meal')
);

ALTER TABLE agent_direct_actions ADD CONSTRAINT agent_direct_actions_user_id_users_id_fk
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE agent_direct_actions ADD CONSTRAINT agent_direct_actions_conversation_id_agent_conversations_id_fk
  FOREIGN KEY (conversation_id) REFERENCES agent_conversations(id) ON DELETE CASCADE;
ALTER TABLE agent_direct_actions ADD CONSTRAINT agent_direct_actions_proposal_id_meal_proposals_id_fk
  FOREIGN KEY (proposal_id) REFERENCES meal_proposals(id) ON DELETE CASCADE;
ALTER TABLE agent_direct_actions ADD CONSTRAINT agent_direct_actions_meal_id_meals_id_fk
  FOREIGN KEY (meal_id) REFERENCES meals(id) ON DELETE RESTRICT;
ALTER TABLE agent_direct_actions ADD CONSTRAINT agent_direct_actions_message_id_agent_messages_id_fk
  FOREIGN KEY (message_id) REFERENCES agent_messages(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS agent_direct_actions_user_mutation_unique
  ON agent_direct_actions (user_id, action_id, client_mutation_id);
CREATE UNIQUE INDEX IF NOT EXISTS agent_direct_actions_user_proposal_unique
  ON agent_direct_actions (user_id, proposal_id);
CREATE INDEX IF NOT EXISTS agent_direct_actions_conversation_idx
  ON agent_direct_actions (user_id, conversation_id, created_at);
