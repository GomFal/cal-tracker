CREATE TABLE IF NOT EXISTS agent_tool_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES agent_conversations(id) ON DELETE CASCADE,
  assistant_message_id uuid NOT NULL REFERENCES agent_messages(id) ON DELETE CASCADE,
  turn_id uuid NOT NULL,
  tool_call_id text NOT NULL,
  action_id text NOT NULL,
  iteration integer NOT NULL,
  tool_call_index integer NOT NULL,
  status text NOT NULL,
  snapshot_json jsonb NOT NULL,
  started_at timestamptz NOT NULL,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT agent_tool_executions_status_check
    CHECK (status IN ('started', 'completed', 'failed', 'interrupted')),
  CONSTRAINT agent_tool_executions_snapshot_status_check
    CHECK (snapshot_json ->> 'status' = status),
  CONSTRAINT agent_tool_executions_terminal_timestamp_check
    CHECK (
      (status = 'started' AND completed_at IS NULL
        AND NOT (snapshot_json ? 'completedAt'))
      OR
      (status IN ('completed', 'failed', 'interrupted')
        AND completed_at IS NOT NULL
        AND snapshot_json ? 'completedAt')
    ),
  CONSTRAINT agent_tool_executions_conversation_call_unique
    UNIQUE (conversation_id, tool_call_id)
);

CREATE INDEX IF NOT EXISTS agent_tool_executions_conversation_order_idx
  ON agent_tool_executions(conversation_id, turn_id, iteration, tool_call_index);
CREATE INDEX IF NOT EXISTS agent_tool_executions_user_created_idx
  ON agent_tool_executions(user_id, created_at);

DROP TRIGGER IF EXISTS agent_tool_executions_reject_suppressed ON agent_tool_executions;
CREATE TRIGGER agent_tool_executions_reject_suppressed BEFORE INSERT ON agent_tool_executions
FOR EACH ROW EXECUTE FUNCTION reject_suppressed_conversation_write();
