#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?Usage: restore-postgres-schema.sh <dev|pro> <dump> <backend-image>}"
DUMP_FILE="${2:?Usage: restore-postgres-schema.sh <dev|pro> <dump> <backend-image>}"
BACKEND_IMAGE="${3:?Usage: restore-postgres-schema.sh <dev|pro> <dump> <backend-image>}"

case "$ENVIRONMENT" in
  dev) SCHEMA="cal_tracker_dev" ;;
  pro) SCHEMA="cal_tracker_pro" ;;
  *) echo "Unknown environment: $ENVIRONMENT" >&2; exit 2 ;;
esac

DEPLOY_DIR="/srv/cal-tracker/deploy"
ENV_DIR="/srv/cal-tracker/env"
STATE_DIR="/srv/cal-tracker/state"
COMPOSE_FILE="$DEPLOY_DIR/compose.yml"
SECRETS_FILE="$ENV_DIR/deploy.env"
PENDING_MARKER="$STATE_DIR/${ENVIRONMENT}.privacy-restore-pending"

if [[ ! -r "$DUMP_FILE" ]]; then
  echo "Restore dump is unavailable: $DUMP_FILE" >&2
  exit 1
fi

read_env_value() {
  local key="$1"
  awk -v key="$key" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); found=1; exit } END { if (!found) exit 1 }' "$SECRETS_FILE"
}

# Restore inputs are data for Docker and must never be evaluated as shell code.
POSTGRES_PASSWORD="$(read_env_value POSTGRES_PASSWORD)" \
  || { echo "POSTGRES_PASSWORD is missing from deploy.env" >&2; exit 2; }
DEV_DATABASE_NAME="$(read_env_value DEV_DATABASE_NAME 2>/dev/null || true)"
PRO_DATABASE_NAME="$(read_env_value PRO_DATABASE_NAME 2>/dev/null || true)"
BACKEND_CPU_LIMIT="$(read_env_value BACKEND_CPU_LIMIT 2>/dev/null || printf '1.0\n')"
BACKEND_MEMORY_LIMIT="$(read_env_value BACKEND_MEMORY_LIMIT 2>/dev/null || printf '768m\n')"

if [[ ! "$BACKEND_CPU_LIMIT" =~ ^([1-9][0-9]*([.][0-9]+)?|0[.][0-9]*[1-9][0-9]*)$ ]]; then
  echo "Invalid BACKEND_CPU_LIMIT: expected a positive CPU count" >&2
  exit 2
fi

if [[ ! "$BACKEND_MEMORY_LIMIT" =~ ^[1-9][0-9]*(b|k|kb|m|mb|g|gb)$ ]]; then
  echo "Invalid BACKEND_MEMORY_LIMIT: expected a positive Docker memory value such as 768m" >&2
  exit 2
fi

case "$ENVIRONMENT" in
  dev) DATABASE_NAME="${DEV_DATABASE_NAME:-cal_tracker}" ;;
  pro) DATABASE_NAME="${PRO_DATABASE_NAME:-cal_tracker}" ;;
esac

if [[ ! "$DATABASE_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Invalid database name for $ENVIRONMENT: $DATABASE_NAME" >&2
  exit 2
fi

install -d -m 0750 "$STATE_DIR"
touch "$PENDING_MARKER"

cd "$DEPLOY_DIR"
docker compose --env-file "$SECRETS_FILE" -f "$COMPOSE_FILE" stop \
  "backend-${ENVIRONMENT}-blue" "backend-${ENVIRONMENT}-green"

# This file lives outside PostgreSQL and outside the rotating schema dumps.
# Any failure from this point leaves the pending marker in place, so deploy.sh
# refuses to make the restored schema reachable.
"$DEPLOY_DIR/privacy-ledger-overlay.sh" export "$ENVIRONMENT"

docker exec -i cal-tracker-postgres pg_restore \
  -U cal_tracker -d "$DATABASE_NAME" --schema="$SCHEMA" \
  --clean --if-exists --no-owner --no-privileges < "$DUMP_FILE"

docker run --rm \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cpus "$BACKEND_CPU_LIMIT" \
  --memory "$BACKEND_MEMORY_LIMIT" \
  --network cal-tracker-internal \
  --env-file "$ENV_DIR/${ENVIRONMENT}.env" \
  -e "DATABASE_SCHEMA=$SCHEMA" \
  -e "DATABASE_URL=postgres://cal_tracker:${POSTGRES_PASSWORD}@cal-tracker-postgres:5432/${DATABASE_NAME}" \
  "$BACKEND_IMAGE" \
  bun dist/scripts/migrate.js

"$DEPLOY_DIR/privacy-ledger-overlay.sh" import "$ENVIRONMENT"

docker run --rm \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cpus "$BACKEND_CPU_LIMIT" \
  --memory "$BACKEND_MEMORY_LIMIT" \
  --network cal-tracker-internal \
  --env-file "$ENV_DIR/${ENVIRONMENT}.env" \
  -e "DATABASE_SCHEMA=$SCHEMA" \
  -e "DATABASE_URL=postgres://cal_tracker:${POSTGRES_PASSWORD}@cal-tracker-postgres:5432/${DATABASE_NAME}" \
  "$BACKEND_IMAGE" \
  bun dist/scripts/apply-privacy-suppressions.js

rm -f "$PENDING_MARKER"
echo "Restore suppression checks passed for $ENVIRONMENT; run deploy.sh to reopen service"
