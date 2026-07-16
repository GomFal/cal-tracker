#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?Usage: deploy.sh <dev|pro> <image>}"
REQUESTED_BACKEND_IMAGE="${2:?Usage: deploy.sh <dev|pro> <image>}"

case "$ENVIRONMENT" in
  dev)
    SCHEMA="cal_tracker_dev"
    STATE_FILE="/srv/cal-tracker/state/dev.active"
    SNIPPET="/etc/nginx/snippets/cal-tracker-dev-proxy.conf"
    BLUE_PORT="3101"
    GREEN_PORT="3102"
    DOMAIN="dev-api.bettercalories.app"
    ;;
  pro)
    SCHEMA="cal_tracker_pro"
    STATE_FILE="/srv/cal-tracker/state/pro.active"
    SNIPPET="/etc/nginx/snippets/cal-tracker-pro-proxy.conf"
    BLUE_PORT="3201"
    GREEN_PORT="3202"
    DOMAIN="api.bettercalories.app"
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT" >&2
    exit 2
    ;;
esac

DEPLOY_DIR="/srv/cal-tracker/deploy"
ENV_DIR="/srv/cal-tracker/env"
COMPOSE_FILE="$DEPLOY_DIR/compose.yml"
SECRETS_FILE="$ENV_DIR/deploy.env"
ACTIVE_SLOT="$(cat "$STATE_FILE" 2>/dev/null || true)"

if [[ "$ACTIVE_SLOT" == "blue" ]]; then
  NEXT_SLOT="green"
  NEXT_PORT="$GREEN_PORT"
  OLD_SERVICE="backend-${ENVIRONMENT}-blue"
elif [[ "$ACTIVE_SLOT" == "green" ]]; then
  NEXT_SLOT="blue"
  NEXT_PORT="$BLUE_PORT"
  OLD_SERVICE="backend-${ENVIRONMENT}-green"
else
  NEXT_SLOT="blue"
  NEXT_PORT="$BLUE_PORT"
  OLD_SERVICE=""
fi

NEXT_SERVICE="backend-${ENVIRONMENT}-${NEXT_SLOT}"

cd "$DEPLOY_DIR"

read_env_value() {
  local key="$1"
  awk -v key="$key" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); found=1; exit } END { if (!found) exit 1 }' "$SECRETS_FILE"
}

# Never source a file writable through the deployment pipeline: dotenv values
# are data for Docker Compose, not shell code executed with dispatcher rights.
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

export BACKEND_IMAGE="$REQUESTED_BACKEND_IMAGE"
export BACKEND_CPU_LIMIT
export BACKEND_MEMORY_LIMIT

docker compose --env-file "$SECRETS_FILE" -f "$COMPOSE_FILE" pull postgres "$NEXT_SERVICE"
docker compose --env-file "$SECRETS_FILE" -f "$COMPOSE_FILE" up -d postgres

for _ in {1..60}; do
  if docker exec cal-tracker-postgres pg_isready -U cal_tracker -d "$DATABASE_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker exec cal-tracker-postgres pg_isready -U cal_tracker -d "$DATABASE_NAME"

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

docker compose --env-file "$SECRETS_FILE" -f "$COMPOSE_FILE" up -d --no-deps --force-recreate "$NEXT_SERVICE"

for _ in {1..40}; do
  if curl -fsS "http://127.0.0.1:${NEXT_PORT}/v1/health" >/dev/null; then
    break
  fi
  sleep 2
done

curl -fsS "http://127.0.0.1:${NEXT_PORT}/v1/health" >/dev/null

cat > "$SNIPPET" <<EOF
include /etc/nginx/snippets/cal-tracker-proxy-common.conf;
proxy_pass http://127.0.0.1:${NEXT_PORT};
EOF

nginx -t
systemctl reload nginx

printf '%s\n' "$NEXT_SLOT" > "$STATE_FILE"

if [[ -n "$OLD_SERVICE" ]]; then
  docker compose --env-file "$SECRETS_FILE" -f "$COMPOSE_FILE" stop "$OLD_SERVICE"
fi

curl -fsS "https://${DOMAIN}/v1/health" >/dev/null
echo "Deployed $ENVIRONMENT to $NEXT_SLOT using $BACKEND_IMAGE"
