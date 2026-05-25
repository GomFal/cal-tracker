#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANDING_DIR="$ROOT_DIR/apps/landing"
NGINX_CONF="$ROOT_DIR/infra/deploy/nginx/bettercalories.app.conf"

REMOTE_HOST="${BETTERCALORIES_LANDING_SSH_HOST:-root@bettercalories.app}"
REMOTE_ROOT="${BETTERCALORIES_LANDING_REMOTE_ROOT:-/var/www/bettercalories.app/html}"
REMOTE_STATE_DIR="${BETTERCALORIES_LANDING_STATE_DIR:-/srv/cal-tracker/landing}"
REMOTE_NGINX_CONF="${BETTERCALORIES_LANDING_NGINX_CONF:-/etc/nginx/sites-available/bettercalories.app}"
REMOTE_NGINX_ENABLED="${BETTERCALORIES_LANDING_NGINX_ENABLED:-/etc/nginx/sites-enabled/bettercalories.app}"
PUBLIC_BASE_URL="${BETTERCALORIES_LANDING_PUBLIC_BASE_URL:-https://bettercalories.app}"
WWW_BASE_URL="${BETTERCALORIES_LANDING_WWW_BASE_URL:-https://www.bettercalories.app}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy-landing.sh

Environment variables:
  BETTERCALORIES_LANDING_SSH_HOST          Defaults to root@bettercalories.app
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

if [[ ! -f "$NGINX_CONF" ]]; then
  echo "Missing NGINX config: $NGINX_CONF" >&2
  exit 1
fi

echo "Validating landing..."
(cd "$ROOT_DIR" && bun run landing:validate)

timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
release_dir="$REMOTE_STATE_DIR/releases/$timestamp"
backup_dir="$REMOTE_STATE_DIR/backups/$timestamp"
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

remote_archive="/tmp/bettercalories-landing-$timestamp.tar.gz"
remote_nginx_tmp="/tmp/bettercalories.app.$timestamp.conf"

echo "Checking remote host..."
ssh "$REMOTE_HOST" "for command in tar rsync nginx install curl date find; do command -v \"\$command\" >/dev/null || { echo \"Missing required remote command: \$command\" >&2; exit 1; }; done"

echo "Uploading release to $REMOTE_HOST..."
scp "$archive" "$REMOTE_HOST:$remote_archive"
scp "$NGINX_CONF" "$REMOTE_HOST:$remote_nginx_tmp"

echo "Installing landing on $REMOTE_HOST..."
ssh "$REMOTE_HOST" bash -s -- \
  "$remote_archive" \
  "$remote_nginx_tmp" \
  "$release_dir" \
  "$backup_dir" \
  "$REMOTE_ROOT" \
  "$REMOTE_NGINX_CONF" \
  "$REMOTE_NGINX_ENABLED" <<'REMOTE_SCRIPT'
set -euo pipefail

remote_archive="$1"
remote_nginx_tmp="$2"
release_dir="$3"
backup_dir="$4"
remote_root="$5"
remote_nginx_conf="$6"
remote_nginx_enabled="$7"

previous_nginx_backup=""
restore_nginx() {
  if [[ -n "$previous_nginx_backup" && -f "$previous_nginx_backup" ]]; then
    cp "$previous_nginx_backup" "$remote_nginx_conf"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi
}

install -d -m 0755 "$release_dir" "$backup_dir"
tar -xzf "$remote_archive" -C "$release_dir"
find "$release_dir" -type d -exec chmod 0755 {} +
find "$release_dir" -type f -exec chmod 0644 {} +

if [[ -d "$remote_root" ]]; then
  install -d -m 0755 "$backup_dir/html"
  rsync -a "$remote_root"/ "$backup_dir/html"/
else
  install -d -m 0755 "$remote_root"
fi

if [[ -f "$remote_nginx_conf" ]]; then
  previous_nginx_backup="$backup_dir/bettercalories.app.conf"
  cp "$remote_nginx_conf" "$previous_nginx_backup"
fi

cp "$remote_nginx_tmp" "$remote_nginx_conf"
ln -sfn "$remote_nginx_conf" "$remote_nginx_enabled"
if ! nginx -t; then
  echo "nginx -t failed. Restoring previous NGINX config." >&2
  restore_nginx
  exit 1
fi

rsync -a --delete "$release_dir"/ "$remote_root"/
find "$remote_root" -type d -exec chmod 0755 {} +
find "$remote_root" -type f -exec chmod 0644 {} +

nginx -t
systemctl reload nginx

rm -f "$remote_archive" "$remote_nginx_tmp"
echo "$release_dir" > "$(dirname "$backup_dir")/../current"
REMOTE_SCRIPT

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
