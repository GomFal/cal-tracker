ALTER TABLE agent_conversations
  ADD COLUMN IF NOT EXISTS hidden_from_user_at timestamptz;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS agent_conversations_user_visible_updated_idx
  ON agent_conversations(user_id, hidden_from_user_at, updated_at);
--> statement-breakpoint
ALTER TABLE agent_messages
  ADD COLUMN IF NOT EXISTS trace_id text,
  ADD COLUMN IF NOT EXISTS turn_id uuid,
  ADD COLUMN IF NOT EXISTS input_mode text,
  ADD COLUMN IF NOT EXISTS source text,
  ADD COLUMN IF NOT EXISTS active_proposal_id uuid;
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS agent_messages_trace_id_idx
  ON agent_messages(trace_id);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS agent_messages_turn_id_idx
  ON agent_messages(turn_id);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS agent_messages_conversation_turn_idx
  ON agent_messages(conversation_id, turn_id, created_at);
