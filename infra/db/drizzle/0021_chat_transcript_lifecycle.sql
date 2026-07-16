CREATE TABLE IF NOT EXISTS privacy_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_user_id uuid NOT NULL,
  conversation_id uuid NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  purge_due_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  purged_at timestamptz,
  last_attempt_at timestamptz,
  attempt_count integer NOT NULL DEFAULT 0,
  result_code text,
  CONSTRAINT privacy_deletion_requests_status_check
    CHECK (status IN ('pending', 'purged', 'failed'))
);

CREATE UNIQUE INDEX IF NOT EXISTS privacy_deletion_requests_conversation_unique
  ON privacy_deletion_requests(conversation_id);
CREATE INDEX IF NOT EXISTS privacy_deletion_requests_status_requested_idx
  ON privacy_deletion_requests(status, requested_at);
CREATE INDEX IF NOT EXISTS privacy_deletion_requests_subject_idx
  ON privacy_deletion_requests(subject_user_id);

CREATE OR REPLACE FUNCTION reject_suppressed_conversation_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;
  -- Serialize the final write decision with the DELETE request. If DELETE got
  -- the lock first, this statement sees its committed tombstone after waiting;
  -- if the write got it first, DELETE waits and its later purge includes it.
  PERFORM pg_advisory_xact_lock(hashtext(NEW.conversation_id::text));
  IF EXISTS (
    SELECT 1 FROM privacy_deletion_requests
    WHERE conversation_id = NEW.conversation_id
  ) THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS agent_messages_reject_suppressed ON agent_messages;
CREATE TRIGGER agent_messages_reject_suppressed BEFORE INSERT ON agent_messages
FOR EACH ROW EXECUTE FUNCTION reject_suppressed_conversation_write();
DROP TRIGGER IF EXISTS agent_candidate_registries_reject_suppressed ON agent_candidate_registries;
CREATE TRIGGER agent_candidate_registries_reject_suppressed BEFORE INSERT ON agent_candidate_registries
FOR EACH ROW EXECUTE FUNCTION reject_suppressed_conversation_write();
DROP TRIGGER IF EXISTS agent_turn_telemetry_reject_suppressed ON agent_turn_telemetry;
CREATE TRIGGER agent_turn_telemetry_reject_suppressed BEFORE INSERT ON agent_turn_telemetry
FOR EACH ROW EXECUTE FUNCTION reject_suppressed_conversation_write();
DROP TRIGGER IF EXISTS agent_tool_call_telemetry_reject_suppressed ON agent_tool_call_telemetry;
CREATE TRIGGER agent_tool_call_telemetry_reject_suppressed BEFORE INSERT ON agent_tool_call_telemetry
FOR EACH ROW EXECUTE FUNCTION reject_suppressed_conversation_write();
DROP TRIGGER IF EXISTS llm_provider_calls_reject_suppressed ON llm_provider_calls;
CREATE TRIGGER llm_provider_calls_reject_suppressed BEFORE INSERT ON llm_provider_calls
FOR EACH ROW EXECUTE FUNCTION reject_suppressed_conversation_write();
DROP TRIGGER IF EXISTS transcription_records_reject_suppressed ON transcription_records;
CREATE TRIGGER transcription_records_reject_suppressed BEFORE INSERT ON transcription_records
FOR EACH ROW EXECUTE FUNCTION reject_suppressed_conversation_write();
DROP TRIGGER IF EXISTS llm_runs_reject_suppressed ON llm_runs;
CREATE TRIGGER llm_runs_reject_suppressed BEFORE INSERT ON llm_runs
FOR EACH ROW EXECUTE FUNCTION reject_suppressed_conversation_write();

-- Capture suppression before account cascades remove the conversation. The
-- ledger intentionally has no FK: restored backups must still know which IDs
-- may not be made visible again.
CREATE OR REPLACE FUNCTION capture_account_privacy_suppressions()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO privacy_deletion_requests (
    subject_user_id, conversation_id, requested_at, purge_due_at, status,
    purged_at, last_attempt_at, attempt_count, result_code
  )
  SELECT OLD.id, conversation.id, now(), now(), 'purged', now(), now(), 1,
         'account_deleted_cascade'
  FROM agent_conversations conversation
  WHERE conversation.user_id = OLD.id
  ON CONFLICT (conversation_id) DO UPDATE SET
    status = 'purged',
    purged_at = now(),
    last_attempt_at = now(),
    attempt_count = privacy_deletion_requests.attempt_count + 1,
    result_code = 'account_deleted_cascade';

  -- Rows using ON DELETE SET NULL would otherwise remain identifiable after
  -- account deletion. Remove them before the user row cascades.
  DELETE FROM action_calls WHERE user_id = OLD.id;
  DELETE FROM telemetry_events WHERE user_id = OLD.id;
  DELETE FROM llm_runs WHERE user_id = OLD.id;
  DELETE FROM food_search_events WHERE user_id = OLD.id;
  DELETE FROM agent_tool_call_telemetry WHERE user_id = OLD.id;
  DELETE FROM llm_provider_calls WHERE user_id = OLD.id;
  DELETE FROM agent_turn_telemetry WHERE user_id = OLD.id;
  DELETE FROM transcription_records WHERE user_id = OLD.id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS users_capture_privacy_suppressions ON users;
CREATE TRIGGER users_capture_privacy_suppressions
BEFORE DELETE ON users
FOR EACH ROW
EXECUTE FUNCTION capture_account_privacy_suppressions();
