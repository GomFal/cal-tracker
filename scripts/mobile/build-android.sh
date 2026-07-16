#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOBILE_DIR="$ROOT_DIR/apps/mobile"
DIST_DIR="$ROOT_DIR/dist/mobile/android"
MOBILE_CONFIG_DIR="${MOBILE_CONFIG_DIR:-$MOBILE_DIR/config}"

ENVIRONMENT="${1:-all}"
BUILD_MODE="${BUILD_MODE:-release}"
DEV_API_BASE_URL="${DEV_API_BASE_URL:-https://dev-api.bettercalories.app}"
PROD_API_BASE_URL="${PROD_API_BASE_URL:-https://api.bettercalories.app}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/mobile/build-android.sh dev
  scripts/mobile/build-android.sh prod
  scripts/mobile/build-android.sh all

Environment variables:
  DEV_API_BASE_URL       Defaults to https://dev-api.bettercalories.app
  PROD_API_BASE_URL      Defaults to https://api.bettercalories.app
  MOBILE_CONFIG_DIR      Defaults to apps/mobile/config
  BUILD_MODE             Defaults to release
  ALLOW_DEBUG_SIGNING=1  Allows prod release builds without android/key.properties
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

if [[ "$BUILD_MODE" != "release" ]]; then
  echo "Only BUILD_MODE=release is supported for distributable Android APKs." >&2
  exit 1
fi

version="$(sed -n 's/^version:[[:space:]]*//p' "$MOBILE_DIR/pubspec.yaml" | head -n 1 | tr '+' '-')"
short_sha="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'local')"
mkdir -p "$DIST_DIR"

stale_registrant="$MOBILE_DIR/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
if [[ -f "$stale_registrant" ]] && grep -q "Generated file. Do not edit." "$stale_registrant"; then
  rm -f "$stale_registrant"
fi

build_flavor() {
  local flavor="$1"
  local api_base_url="$2"

  "$ROOT_DIR/scripts/mobile/validate-api-base-url.sh" \
    "$flavor" "$api_base_url" "$BUILD_MODE"

  if [[ "$flavor" == "prod" && ! -f "$MOBILE_DIR/android/key.properties" && "${ALLOW_DEBUG_SIGNING:-}" != "1" ]]; then
    cat >&2 <<'MESSAGE'
Refusing to build prod with the debug signing key.

Create apps/mobile/android/key.properties from key.properties.example and point it
to a local .jks/.keystore file, or set ALLOW_DEBUG_SIGNING=1 for a local-only
test artifact.
MESSAGE
    exit 1
  fi

  local define_file="$MOBILE_CONFIG_DIR/$flavor.json"
  if [[ ! -f "$define_file" ]]; then
    echo "Missing Flutter dart-define file: $define_file" >&2
    exit 1
  fi

  echo "Building Android APK: $flavor ($api_base_url)"
  (
    cd "$MOBILE_DIR"
    flutter pub get
    flutter build apk \
      --release \
      --flavor "$flavor" \
      --dart-define-from-file="$define_file" \
      --dart-define="API_BASE_URL=$api_base_url"
  )

  local source_apk="$MOBILE_DIR/build/app/outputs/flutter-apk/app-$flavor-release.apk"
  local output_apk="$DIST_DIR/bettercalories-$flavor-$version-$short_sha.apk"

  cp "$source_apk" "$output_apk"
  sha256sum "$output_apk" > "$output_apk.sha256"
  echo "Wrote $output_apk"
}

if [[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "all" ]]; then
  build_flavor "dev" "$DEV_API_BASE_URL"
fi

if [[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "all" ]]; then
  build_flavor "prod" "$PROD_API_BASE_URL"
fi
