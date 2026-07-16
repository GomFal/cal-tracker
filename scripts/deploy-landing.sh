#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANDING_DIR="$ROOT_DIR/apps/landing"

REMOTE_HOST="${BETTERCALORIES_LANDING_SSH_HOST:-bettercalories-deploy@bettercalories.app}"
REMOTE_ROOT="${BETTERCALORIES_LANDING_REMOTE_ROOT:-/var/www/bettercalories.app/html}"
REMOTE_STATE_DIR="${BETTERCALORIES_LANDING_STATE_DIR:-/srv/cal-tracker/landing}"
PUBLIC_BASE_URL="${BETTERCALORIES_LANDING_PUBLIC_BASE_URL:-https://bettercalories.app}"
WWW_BASE_URL="${BETTERCALORIES_LANDING_WWW_BASE_URL:-https://www.bettercalories.app}"
DEPLOY_SOURCE_COMMIT="${BETTERCALORIES_DEPLOY_SOURCE_COMMIT:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
DEPLOY_RUN_ID="${BETTERCALORIES_DEPLOY_RUN_ID:-$(date -u +%s)}"
DEPLOY_ACTOR="${BETTERCALORIES_DEPLOY_ACTOR:-$(id -un)}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy-landing.sh

Environment variables:
  BETTERCALORIES_LANDING_SSH_HOST          Defaults to bettercalories-deploy@bettercalories.app
  BETTERCALORIES_LANDING_REMOTE_ROOT       Defaults to /var/www/bettercalories.app/html
  BETTERCALORIES_LANDING_STATE_DIR         Defaults to /srv/cal-tracker/landing
  BETTERCALORIES_LANDING_PUBLIC_BASE_URL   Defaults to https://bettercalories.app
  BETTERCALORIES_LANDING_WWW_BASE_URL      Defaults to https://www.bettercalories.app
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

require_local_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required local command: $1" >&2
    exit 1
  fi
}

for command in bun curl date mktemp scp ssh tar; do
  require_local_command "$command"
done

if [[ ! -d "$LANDING_DIR" ]]; then
  echo "Missing landing directory: $LANDING_DIR" >&2
  exit 1
fi

[[ "$DEPLOY_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid deployment source commit." >&2; exit 1; }
[[ "$DEPLOY_RUN_ID" =~ ^[0-9]+(-[0-9]+)?$ ]] || { echo "Invalid deployment run id." >&2; exit 1; }
[[ "$DEPLOY_ACTOR" =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || { echo "Invalid deployment actor." >&2; exit 1; }

echo "Validating landing..."
(cd "$ROOT_DIR" && bun run landing:validate)

timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
archive="$(mktemp)"
cleanup() {
  rm -f "$archive"
}
trap cleanup EXIT

echo "Packaging landing..."
tar \
  --exclude='./README.md' \
  --exclude='./validate.mjs' \
  -C "$LANDING_DIR" \
  -czf "$archive" \
  .

remote_stage="/srv/cal-tracker/incoming/landing-$DEPLOY_RUN_ID"
remote_archive="$remote_stage/bettercalories-landing-$timestamp.tar.gz"

echo "Checking remote host..."
ssh "$REMOTE_HOST" "rm -rf '$remote_stage' && install -d -m 0700 '$remote_stage'"

echo "Uploading release to $REMOTE_HOST..."
scp "$archive" "$REMOTE_HOST:$remote_archive"

echo "Installing landing on $REMOTE_HOST..."
ssh "$REMOTE_HOST" sudo -n /usr/local/sbin/bettercalories-deploy publish-landing \
  "$remote_archive" "$timestamp" "$REMOTE_ROOT" "$REMOTE_STATE_DIR" \
  "$DEPLOY_SOURCE_COMMIT" "$DEPLOY_RUN_ID" "$DEPLOY_ACTOR" "$PUBLIC_BASE_URL"

echo "Validating public site..."
expect_status() {
  local expected="$1"
  local url="$2"
  local status
  status="$(curl -sS -o /dev/null -w '%{http_code}' -I "$url")"
  if [[ "$status" != "$expected" ]]; then
    echo "Expected HTTP $expected for $url, got $status" >&2
    exit 1
  fi
}

expect_status 200 "$PUBLIC_BASE_URL"
expect_status 200 "$PUBLIC_BASE_URL/sitemap.xml"
expect_status 200 "$PUBLIC_BASE_URL/assets/brand-icon.png"
expect_status 301 "$WWW_BASE_URL"

www_location="$(
  curl -sSI "$WWW_BASE_URL" | awk 'tolower($1) == "location:" { gsub(/\r/, "", $2); print $2; exit }'
)"
if [[ "$www_location" != "$PUBLIC_BASE_URL/" && "$www_location" != "$PUBLIC_BASE_URL" ]]; then
  echo "Unexpected www redirect target: ${www_location:-<missing>}" >&2
  exit 1
fi

echo "Published Better Calories landing to $PUBLIC_BASE_URL."
