#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOBILE_DIR="$ROOT_DIR/apps/mobile"
DIST_DIR="$ROOT_DIR/dist/mobile/android"
REMOTE_HOST="${BETTERCALORIES_APK_SSH_HOST:-bettercalories-deploy@bettercalories.app}"
ENVIRONMENT="${1:-all}"
ALLOW_NON_INCREMENTAL_VERSION="${ALLOW_NON_INCREMENTAL_APK_VERSION:-0}"
SKIP_ANDROID_BUILD="${SKIP_ANDROID_BUILD:-0}"

DEV_PUBLIC_BASE_URL="${DEV_PUBLIC_BASE_URL:-https://dev-api.bettercalories.app}"
PROD_PUBLIC_BASE_URL="${PROD_PUBLIC_BASE_URL:-https://api.bettercalories.app}"
DEPLOY_SOURCE_COMMIT="${BETTERCALORIES_DEPLOY_SOURCE_COMMIT:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
DEPLOY_RUN_ID="${BETTERCALORIES_DEPLOY_RUN_ID:-$(date -u +%s)}"
DEPLOY_ACTOR="${BETTERCALORIES_DEPLOY_ACTOR:-$(id -un)}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/mobile/deploy-server-apks.sh dev
  scripts/mobile/deploy-server-apks.sh prod
  scripts/mobile/deploy-server-apks.sh all

Environment variables:
  BETTERCALORIES_APK_SSH_HOST        Defaults to bettercalories-deploy@bettercalories.app
  BETTERCALORIES_DEPLOY_SOURCE_COMMIT  Source Git commit (defaults to HEAD)
  BETTERCALORIES_DEPLOY_RUN_ID         Numeric deployment/run identifier
  BETTERCALORIES_DEPLOY_ACTOR          Account initiating the deployment
  DEV_PUBLIC_BASE_URL                Defaults to https://dev-api.bettercalories.app
  PROD_PUBLIC_BASE_URL               Defaults to https://api.bettercalories.app
  ALLOW_NON_INCREMENTAL_APK_VERSION  Set to 1 to republish the same/lower versionCode
  SKIP_ANDROID_BUILD=1               Publish an already-built APK from dist/mobile/android

Important:
  The in-app updater only prompts users when latest.json has a greater
  versionCode than the installed app. Before publishing a dev/prod APK meant
  to trigger automatic updates, increment apps/mobile/pubspec.yaml (the +N
  build number). Rebuilding/reuploading the same versionCode will not trigger
  the updater unless users install it manually.
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

[[ "$DEPLOY_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid BETTERCALORIES_DEPLOY_SOURCE_COMMIT." >&2
  exit 1
}
[[ "$DEPLOY_RUN_ID" =~ ^[0-9]+(-[0-9]+)?$ ]] || {
  echo "Invalid BETTERCALORIES_DEPLOY_RUN_ID." >&2
  exit 1
}
[[ "$DEPLOY_ACTOR" =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || {
  echo "Invalid BETTERCALORIES_DEPLOY_ACTOR." >&2
  exit 1
}

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

# The mobile auto-updater compares the published manifest versionCode against
# the installed app versionCode. Bump apps/mobile/pubspec.yaml's +N build number
# before publishing any APK that should trigger an automatic update prompt.

for command in ssh scp sha256sum stat curl sed find awk date; do
  require_command "$command"
done

if [[ "$SKIP_ANDROID_BUILD" != "1" ]]; then
  require_command flutter
fi

publish_flavor() {
  local flavor="$1"
  local public_base_url="$2"
  local local_manifest
  local apk_name
  local source_apk
  local sha256
  local size_bytes
  local published_at
  local previous_version_code
  local remote_stage

  previous_version_code="$(
    curl -fsS "$public_base_url/apk/latest.json" 2>/dev/null | extract_json_number versionCode || true
  )"
  if [[ -n "$previous_version_code" && "$version_code" -le "$previous_version_code" && "$ALLOW_NON_INCREMENTAL_VERSION" != "1" ]]; then
    echo "Refusing to publish $flavor $version_name+$version_code over published versionCode $previous_version_code." >&2
    echo "Increment apps/mobile/pubspec.yaml or set ALLOW_NON_INCREMENTAL_APK_VERSION=1." >&2
    exit 1
  fi

  if [[ "$SKIP_ANDROID_BUILD" == "1" ]]; then
    echo "Using prebuilt Android APKs from $DIST_DIR"
  else
    ALLOW_DEBUG_SIGNING=1 "$ROOT_DIR/scripts/mobile/build-android.sh" "$flavor"
  fi

  source_apk="$(find "$DIST_DIR" -maxdepth 1 -type f -name "bettercalories-$flavor-${version_name}-${version_code}-*.apk" | sort | tail -n 1)"
  if [[ -z "$source_apk" || ! -f "$source_apk" ]]; then
    echo "Could not find built APK for $flavor in $DIST_DIR." >&2
    exit 1
  fi

  apk_name="$(basename "$source_apk")"
  [[ "$apk_name" =~ ^bettercalories-(dev|prod)-[A-Za-z0-9._-]+\.apk$ ]] || {
    echo "Unsafe APK file name: $apk_name" >&2
    exit 1
  }
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
  "publishedAt": "$published_at",
  "sourceCommit": "$DEPLOY_SOURCE_COMMIT",
  "deploymentRunId": "$DEPLOY_RUN_ID",
  "deploymentActor": "$DEPLOY_ACTOR"
}
JSON

  remote_stage="/srv/cal-tracker/incoming/mobile-$DEPLOY_RUN_ID-$flavor"
  echo "Uploading $flavor APK to the restricted staging area on $REMOTE_HOST"
  ssh "$REMOTE_HOST" "rm -rf '$remote_stage' && install -d -m 0700 '$remote_stage'"
  scp "$source_apk" "$REMOTE_HOST:$remote_stage/$apk_name"
  scp "$local_manifest" "$REMOTE_HOST:$remote_stage/latest.json"
  ssh "$REMOTE_HOST" sudo -n /usr/local/sbin/bettercalories-deploy publish-apk \
    "$flavor" "$remote_stage/$apk_name" "$remote_stage/latest.json" "$sha256" \
    "$DEPLOY_SOURCE_COMMIT" "$DEPLOY_RUN_ID" "$DEPLOY_ACTOR"
  rm -f "$local_manifest"
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
  curl -fsSI "$public_base_url/apk/latest.apk" >/dev/null
}

case "$ENVIRONMENT" in
  dev)
    publish_flavor dev "$DEV_PUBLIC_BASE_URL"
    ;;
  prod)
    publish_flavor prod "$PROD_PUBLIC_BASE_URL"
    ;;
  all)
    publish_flavor dev "$DEV_PUBLIC_BASE_URL"
    publish_flavor prod "$PROD_PUBLIC_BASE_URL"
    ;;
esac

if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "all" ]]; then
  validate_public_download "$DEV_PUBLIC_BASE_URL"
fi

if [[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "all" ]]; then
  validate_public_download "$PROD_PUBLIC_BASE_URL"
fi

echo "Published BetterCalories Android APKs for $ENVIRONMENT."
