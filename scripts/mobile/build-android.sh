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
  ANDROID_RELEASE_CERT_SHA256  Approved production certificate SHA-256

Production signing can be provided by apps/mobile/android/key.properties or by
ANDROID_RELEASE_STORE_FILE, ANDROID_RELEASE_STORE_PASSWORD,
ANDROID_RELEASE_KEY_ALIAS, and ANDROID_RELEASE_KEY_PASSWORD.
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

if [[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "all" ]]; then
  "$ROOT_DIR/scripts/mobile/validate-android-release-signing.sh"
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
  local define_file="$MOBILE_CONFIG_DIR/$flavor.json"
  if [[ ! -f "$define_file" ]]; then
    echo "Missing Flutter dart-define file: $define_file" >&2
    exit 1
  fi

  echo "Building Android APK: $flavor ($api_base_url)"
  (
    cd "$MOBILE_DIR"
    flutter pub get --enforce-lockfile
    flutter build apk \
      --release \
      --flavor "$flavor" \
      --dart-define-from-file="$define_file" \
      --dart-define="API_BASE_URL=$api_base_url"
  )

  local source_apk="$MOBILE_DIR/build/app/outputs/flutter-apk/app-$flavor-release.apk"
  local output_apk="$DIST_DIR/bettercalories-$flavor-$version-$short_sha.apk"

  if [[ "$flavor" == "prod" ]]; then
    "$ROOT_DIR/scripts/mobile/verify-apk-signing.sh" \
      "$source_apk" \
      "${ANDROID_RELEASE_CERT_SHA256:-}"
  fi

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
