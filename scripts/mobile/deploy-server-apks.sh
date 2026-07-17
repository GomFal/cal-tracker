#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOBILE_DIR="$ROOT_DIR/apps/mobile"
DIST_DIR="$ROOT_DIR/dist/mobile/android"
REMOTE_HOST="${BETTERCALORIES_APK_SSH_HOST:-bettercalories-deploy@bettercalories.app}"
ENVIRONMENT="${1:-all}"
SKIP_ANDROID_BUILD="${SKIP_ANDROID_BUILD:-0}"

DEV_PUBLIC_BASE_URL="https://dev-api.bettercalories.app"
PROD_PUBLIC_BASE_URL="https://api.bettercalories.app"
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
  SKIP_ANDROID_BUILD=1               Publish an already-built APK from dist/mobile/android
  ANDROID_DEV_CERT_SHA256            Approved development certificate SHA-256
  ANDROID_RELEASE_CERT_SHA256        Approved production certificate SHA-256

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

for command in ssh scp sha256sum stat curl sed find awk date python3; do
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
  local expected_package
  local previous_manifest
  local previous_status
  local -a manifest_validation_args

  case "$flavor" in
    dev) expected_package="app.bettercalories.dev" ;;
    prod) expected_package="app.bettercalories" ;;
    *) echo "Unsupported APK channel: $flavor" >&2; exit 1 ;;
  esac

  previous_manifest="$(mktemp)"
  if ! previous_status="$(
    curl --silent --show-error \
      --proto '=https' --tlsv1.2 --location --max-redirs 0 \
      --output "$previous_manifest" --write-out '%{http_code}' \
      "$public_base_url/apk/latest.json"
  )"; then
    rm -f "$previous_manifest"
    echo "Refusing to publish because the existing manifest request redirected or failed." >&2
    exit 1
  fi
  case "$previous_status" in
    200)
      previous_version_code="$(
        python3 "$ROOT_DIR/scripts/mobile/validate-update-manifest.py" \
          "$previous_manifest" --channel "$flavor" --print-version-code
      )"
      ;;
    404)
      previous_version_code=""
      ;;
    *)
      rm -f "$previous_manifest"
      echo "Refusing to publish after update manifest HTTP $previous_status." >&2
      exit 1
      ;;
  esac
  rm -f "$previous_manifest"

  if [[ -n "$previous_version_code" && "$version_code" -le "$previous_version_code" ]]; then
    echo "Refusing to publish $flavor $version_name+$version_code over published versionCode $previous_version_code." >&2
    echo "Increment apps/mobile/pubspec.yaml before publishing." >&2
    exit 1
  fi

  if [[ "$SKIP_ANDROID_BUILD" == "1" ]]; then
    echo "Using prebuilt Android APKs from $DIST_DIR"
  else
    "$ROOT_DIR/scripts/mobile/build-android.sh" "$flavor"
  fi

  source_apk="$(find "$DIST_DIR" -maxdepth 1 -type f -name "bettercalories-$flavor-${version_name}-${version_code}-*.apk" | sort | tail -n 1)"
  if [[ -z "$source_apk" || ! -f "$source_apk" ]]; then
    echo "Could not find built APK for $flavor in $DIST_DIR." >&2
    exit 1
  fi

  if [[ "$flavor" == "dev" ]]; then
    "$ROOT_DIR/scripts/mobile/verify-apk-signing.sh" \
      "$source_apk" \
      "${ANDROID_DEV_CERT_SHA256:-}"
  elif [[ "$flavor" == "prod" ]]; then
    "$ROOT_DIR/scripts/mobile/verify-apk-signing.sh" \
      "$source_apk" \
      "${ANDROID_RELEASE_CERT_SHA256:-}"
  fi

  "$ROOT_DIR/scripts/mobile/verify-update-apk-metadata.sh" \
    "$source_apk" "$expected_package" "$version_code"

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
  "channel": "$flavor",
  "packageName": "$expected_package",
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

  manifest_validation_args=(
    "$local_manifest"
    --channel "$flavor"
    --expected-version-code "$version_code"
  )
  if [[ -n "$previous_version_code" ]]; then
    manifest_validation_args+=(--minimum-version-code "$previous_version_code")
  fi
  python3 "$ROOT_DIR/scripts/mobile/validate-update-manifest.py" \
    "${manifest_validation_args[@]}"

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
  local flavor="$1"
  local public_base_url="$2"
  local manifest
  local apk_url

  manifest="$(mktemp)"
  curl --fail --silent --show-error \
    --proto '=https' --tlsv1.2 --location --max-redirs 0 \
    --output "$manifest" "$public_base_url/apk/latest.json"
  apk_url="$(
    python3 "$ROOT_DIR/scripts/mobile/validate-update-manifest.py" \
      "$manifest" --channel "$flavor" \
      --expected-version-code "$version_code" --print-apk-url
  )"
  rm -f "$manifest"
  curl --fail --silent --show-error --head \
    --proto '=https' --tlsv1.2 --location --max-redirs 0 \
    "$apk_url" >/dev/null
  curl --fail --silent --show-error --head \
    --proto '=https' --tlsv1.2 --location --max-redirs 0 \
    "$public_base_url/apk/latest.apk" >/dev/null
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
  validate_public_download dev "$DEV_PUBLIC_BASE_URL"
fi

if [[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "all" ]]; then
  validate_public_download prod "$PROD_PUBLIC_BASE_URL"
fi

echo "Published BetterCalories Android APKs for $ENVIRONMENT."
