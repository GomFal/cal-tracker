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

set -a
source "$SECRETS_FILE"
set +a

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
  --network cal-tracker-internal \
  --env-file "$ENV_DIR/${ENVIRONMENT}.env" \
  -e "DATABASE_SCHEMA=$SCHEMA" \
  -e "DATABASE_URL=postgres://cal_tracker:${POSTGRES_PASSWORD}@cal-tracker-postgres:5432/${DATABASE_NAME}" \
  "$BACKEND_IMAGE" \
  bun dist/scripts/migrate.js

"$DEPLOY_DIR/privacy-ledger-overlay.sh" import "$ENVIRONMENT"

docker run --rm \
  --network cal-tracker-internal \
  --env-file "$ENV_DIR/${ENVIRONMENT}.env" \
  -e "DATABASE_SCHEMA=$SCHEMA" \
  -e "DATABASE_URL=postgres://cal_tracker:${POSTGRES_PASSWORD}@cal-tracker-postgres:5432/${DATABASE_NAME}" \
  "$BACKEND_IMAGE" \
  bun dist/scripts/apply-privacy-suppressions.js

rm -f "$PENDING_MARKER"
echo "Restore suppression checks passed for $ENVIRONMENT; run deploy.sh to reopen service"
