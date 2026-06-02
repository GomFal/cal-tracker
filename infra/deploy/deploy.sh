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

export BACKEND_IMAGE="$REQUESTED_BACKEND_IMAGE"

docker compose --env-file "$SECRETS_FILE" -f "$COMPOSE_FILE" pull postgres
if [[ "${SKIP_BACKEND_PULL:-false}" == "true" ]]; then
  echo "Skipping backend image pull for $NEXT_SERVICE; using local image $BACKEND_IMAGE"
else
  docker compose --env-file "$SECRETS_FILE" -f "$COMPOSE_FILE" pull "$NEXT_SERVICE"
fi
docker compose --env-file "$SECRETS_FILE" -f "$COMPOSE_FILE" up -d postgres

for _ in {1..60}; do
  if docker exec cal-tracker-postgres pg_isready -U cal_tracker -d "$DATABASE_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

docker exec cal-tracker-postgres pg_isready -U cal_tracker -d "$DATABASE_NAME"

docker run --rm \
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
