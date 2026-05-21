#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOBILE_DIR="$ROOT_DIR/apps/mobile"
DIST_DIR="$ROOT_DIR/dist/mobile/android"
REMOTE_HOST="${BETTERCALORIES_APK_SSH_HOST:-root@bettercalories.app}"
ENVIRONMENT="${1:-all}"
ALLOW_NON_INCREMENTAL_VERSION="${ALLOW_NON_INCREMENTAL_APK_VERSION:-0}"

DEV_PUBLIC_BASE_URL="${DEV_PUBLIC_BASE_URL:-https://dev-api.bettercalories.app}"
PROD_PUBLIC_BASE_URL="${PROD_PUBLIC_BASE_URL:-https://api.bettercalories.app}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/mobile/deploy-server-apks.sh dev
  scripts/mobile/deploy-server-apks.sh prod
  scripts/mobile/deploy-server-apks.sh all

Environment variables:
  BETTERCALORIES_APK_SSH_HOST        Defaults to root@bettercalories.app
  DEV_PUBLIC_BASE_URL                Defaults to https://dev-api.bettercalories.app
  PROD_PUBLIC_BASE_URL               Defaults to https://api.bettercalories.app
  ALLOW_NON_INCREMENTAL_APK_VERSION  Set to 1 to republish the same/lower versionCode
USAGE
}

case "$ENVIRONMENT" in
  dev|prod|all) ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

extract_json_number() {
  local key="$1"
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/p" | head -n 1
}

extract_json_string() {
  local key="$1"
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\\1/p" | head -n 1
}

version_line="$(sed -n 's/^version:[[:space:]]*//p' "$MOBILE_DIR/pubspec.yaml" | head -n 1)"
version_name="${version_line%%+*}"
version_code="${version_line##*+}"
if [[ -z "$version_name" || -z "$version_code" || "$version_name" == "$version_code" ]]; then
  echo "Could not infer versionName/versionCode from apps/mobile/pubspec.yaml" >&2
  exit 1
fi

for command in flutter ssh scp sha256sum stat curl sed find awk date; do
  require_command "$command"
done

publish_flavor() {
  local flavor="$1"
  local public_base_url="$2"
  local remote_dir="$3"
  local local_manifest
  local apk_name
  local source_apk
  local sha256
  local size_bytes
  local published_at
  local previous_version_code

  previous_version_code="$(
    curl -fsS "$public_base_url/apk/latest.json" 2>/dev/null | extract_json_number versionCode || true
  )"
  if [[ -n "$previous_version_code" && "$version_code" -le "$previous_version_code" && "$ALLOW_NON_INCREMENTAL_VERSION" != "1" ]]; then
    echo "Refusing to publish $flavor $version_name+$version_code over published versionCode $previous_version_code." >&2
    echo "Increment apps/mobile/pubspec.yaml or set ALLOW_NON_INCREMENTAL_APK_VERSION=1." >&2
    exit 1
  fi

  ALLOW_DEBUG_SIGNING=1 "$ROOT_DIR/scripts/mobile/build-android.sh" "$flavor"

  source_apk="$(find "$DIST_DIR" -maxdepth 1 -type f -name "bettercalories-$flavor-${version_name}-${version_code}-*.apk" | sort | tail -n 1)"
  if [[ -z "$source_apk" || ! -f "$source_apk" ]]; then
    echo "Could not find built APK for $flavor in $DIST_DIR." >&2
    exit 1
  fi

  apk_name="$(basename "$source_apk")"
  sha256="$(sha256sum "$source_apk" | awk '{print $1}')"
  size_bytes="$(stat -c%s "$source_apk")"
  published_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local_manifest="$(mktemp)"

  cat > "$local_manifest" <<JSON
{
  "versionName": "$version_name",
  "versionCode": $version_code,
  "apkUrl": "$public_base_url/apk/$apk_name",
  "sha256": "$sha256",
  "sizeBytes": $size_bytes,
  "publishedAt": "$published_at"
}
JSON

  echo "Uploading $flavor APK to $REMOTE_HOST:$remote_dir"
  ssh "$REMOTE_HOST" "install -d -m 0755 '$remote_dir'"
  scp "$source_apk" "$REMOTE_HOST:/tmp/$apk_name"
  scp "$local_manifest" "$REMOTE_HOST:/tmp/bettercalories-$flavor-latest.json"
  ssh "$REMOTE_HOST" "mv '/tmp/$apk_name' '$remote_dir/$apk_name' && mv '/tmp/bettercalories-$flavor-latest.json' '$remote_dir/latest.json' && chmod 0644 '$remote_dir/$apk_name' '$remote_dir/latest.json'"
  rm -f "$local_manifest"
}

publish_nginx_config() {
  scp "$ROOT_DIR/infra/deploy/nginx/api.bettercalories.app.conf" "$REMOTE_HOST:/tmp/api.bettercalories.app.conf"
  ssh "$REMOTE_HOST" "cp /tmp/api.bettercalories.app.conf /etc/nginx/sites-available/api.bettercalories.app && nginx -t && systemctl reload nginx && rm -f /tmp/api.bettercalories.app.conf"
}

validate_public_download() {
  local public_base_url="$1"
  local manifest
  local apk_url

  manifest="$(curl -fsS "$public_base_url/apk/latest.json")"
  apk_url="$(printf '%s\n' "$manifest" | extract_json_string apkUrl)"
  if [[ -z "$apk_url" ]]; then
    echo "Could not read apkUrl from $public_base_url/apk/latest.json" >&2
    exit 1
  fi
  curl -fsSI "$apk_url" >/dev/null
}

case "$ENVIRONMENT" in
  dev)
    publish_flavor dev "$DEV_PUBLIC_BASE_URL" /srv/cal-tracker/mobile/dev
    ;;
  prod)
    publish_flavor prod "$PROD_PUBLIC_BASE_URL" /srv/cal-tracker/mobile/prod
    ;;
  all)
    publish_flavor dev "$DEV_PUBLIC_BASE_URL" /srv/cal-tracker/mobile/dev
    publish_flavor prod "$PROD_PUBLIC_BASE_URL" /srv/cal-tracker/mobile/prod
    ;;
esac

publish_nginx_config

if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "all" ]]; then
  validate_public_download "$DEV_PUBLIC_BASE_URL"
fi

if [[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "all" ]]; then
  validate_public_download "$PROD_PUBLIC_BASE_URL"
fi

echo "Published BetterCalories Android APKs for $ENVIRONMENT."
