#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:?Usage: privacy-ledger-overlay.sh <export|validate|import> <dev|pro>}"
ENVIRONMENT="${2:?Usage: privacy-ledger-overlay.sh <export|validate|import> <dev|pro>}"

case "$ENVIRONMENT" in
  dev) DEFAULT_SCHEMA="cal_tracker_dev" ;;
  pro) DEFAULT_SCHEMA="cal_tracker_pro" ;;
  *) echo "Unknown environment: $ENVIRONMENT" >&2; exit 2 ;;
esac

SCHEMA="${PRIVACY_LEDGER_SCHEMA:-$DEFAULT_SCHEMA}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-cal-tracker-postgres}"
POSTGRES_USER="${POSTGRES_USER:-cal_tracker}"
POSTGRES_DATABASE="${POSTGRES_DATABASE:-cal_tracker}"
OVERLAY_DIR="${CAL_TRACKER_PRIVACY_LEDGER_DIR:-/srv/cal-tracker/privacy-ledger-overlays}"
OVERLAY_FILE="$OVERLAY_DIR/${SCHEMA}.csv"
EXPECTED_HEADER='id,subject_user_id,conversation_id,requested_at,purge_due_at,status,purged_at,last_attempt_at,attempt_count,result_code'

if [[ ! "$SCHEMA" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Invalid privacy ledger schema: $SCHEMA" >&2
  exit 2
fi

install -d -m 0700 "$OVERLAY_DIR"

export_overlay() {
  local temporary_file
  temporary_file="$(mktemp "$OVERLAY_DIR/.${SCHEMA}.XXXXXX")"
  trap 'rm -f "$temporary_file"' EXIT

  docker exec "$POSTGRES_CONTAINER" psql \
    --no-psqlrc --quiet --set=ON_ERROR_STOP=1 \
    -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" \
    --command="COPY (
      SELECT id, subject_user_id, conversation_id, requested_at, purge_due_at,
             status, purged_at, last_attempt_at, attempt_count, result_code
      FROM \"$SCHEMA\".privacy_deletion_requests
      ORDER BY requested_at, id
    ) TO STDOUT WITH (FORMAT csv, HEADER true)" > "$temporary_file"

  if [[ "$(head -n 1 "$temporary_file")" != "$EXPECTED_HEADER" ]]; then
    echo "Privacy ledger export is missing or malformed for $SCHEMA" >&2
    exit 1
  fi

  chmod 0600 "$temporary_file"
  mv -f "$temporary_file" "$OVERLAY_FILE"
  trap - EXIT
  echo "$OVERLAY_FILE"
}

validate_overlay() {
  if [[ ! -f "$OVERLAY_FILE" ]] || [[ ! -r "$OVERLAY_FILE" ]]; then
    echo "Privacy ledger overlay unavailable for $SCHEMA: $OVERLAY_FILE" >&2
    exit 1
  fi
  if [[ "$(head -n 1 "$OVERLAY_FILE")" != "$EXPECTED_HEADER" ]]; then
    echo "Privacy ledger overlay is malformed for $SCHEMA: $OVERLAY_FILE" >&2
    exit 1
  fi
}

import_overlay() {
  validate_overlay

  {
    cat <<SQL
BEGIN;
CREATE TEMP TABLE privacy_deletion_overlay (
  id uuid NOT NULL,
  subject_user_id uuid NOT NULL,
  conversation_id uuid NOT NULL,
  requested_at timestamptz NOT NULL,
  purge_due_at timestamptz NOT NULL,
  status text NOT NULL,
  purged_at timestamptz,
  last_attempt_at timestamptz,
  attempt_count integer NOT NULL,
  result_code text
) ON COMMIT DROP;
COPY privacy_deletion_overlay (
  id, subject_user_id, conversation_id, requested_at, purge_due_at, status,
  purged_at, last_attempt_at, attempt_count, result_code
) FROM STDIN WITH (FORMAT csv, HEADER true);
SQL
    cat "$OVERLAY_FILE"
    cat <<SQL
\.
INSERT INTO "$SCHEMA".privacy_deletion_requests (
  id, subject_user_id, conversation_id, requested_at, purge_due_at, status,
  purged_at, last_attempt_at, attempt_count, result_code
)
SELECT id, subject_user_id, conversation_id, requested_at, purge_due_at, status,
       purged_at, last_attempt_at, attempt_count, result_code
FROM privacy_deletion_overlay
ON CONFLICT (conversation_id) DO NOTHING;
COMMIT;
SQL
  } | docker exec -i "$POSTGRES_CONTAINER" psql \
    --no-psqlrc --quiet --set=ON_ERROR_STOP=1 \
    -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE"

  echo "$OVERLAY_FILE"
}

case "$ACTION" in
  export) export_overlay ;;
  validate) validate_overlay ;;
  import) import_overlay ;;
  *) echo "Unknown action: $ACTION" >&2; exit 2 ;;
esac
