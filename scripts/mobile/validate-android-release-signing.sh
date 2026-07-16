#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ANDROID_DIR="${MOBILE_ANDROID_DIR:-$ROOT_DIR/apps/mobile/android}"
KEY_PROPERTIES="$ANDROID_DIR/key.properties"

fail() {
  echo "Android production signing configuration error: $*" >&2
  exit 1
}

if [[ -n "${ALLOW_DEBUG_SIGNING:-}" ]]; then
  fail "ALLOW_DEBUG_SIGNING is not supported"
fi

fingerprint="${ANDROID_RELEASE_CERT_SHA256:-}"
normalized_fingerprint="$(printf '%s' "$fingerprint" | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')"
[[ "$normalized_fingerprint" =~ ^[0-9A-F]{64}$ ]] \
  || fail "ANDROID_RELEASE_CERT_SHA256 must contain one SHA-256 certificate fingerprint"

environment_fields=(
  ANDROID_RELEASE_STORE_FILE
  ANDROID_RELEASE_STORE_PASSWORD
  ANDROID_RELEASE_KEY_ALIAS
  ANDROID_RELEASE_KEY_PASSWORD
)
environment_field_count=0
for field in "${environment_fields[@]}"; do
  [[ -n "${!field:-}" ]] && environment_field_count=$((environment_field_count + 1))
done

if [[ "$environment_field_count" -gt 0 ]]; then
  [[ "$environment_field_count" -eq "${#environment_fields[@]}" ]] \
    || fail "all ANDROID_RELEASE_* signing variables are required together"
  [[ -f "$ANDROID_RELEASE_STORE_FILE" ]] \
    || fail "ANDROID_RELEASE_STORE_FILE does not reference a file"
  exit 0
fi

[[ -f "$KEY_PROPERTIES" ]] \
  || fail "missing apps/mobile/android/key.properties and ANDROID_RELEASE_* signing variables"

for property in storeFile storePassword keyAlias keyPassword; do
  value="$(sed -nE "s/^[[:space:]]*${property}[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$KEY_PROPERTIES" | tail -n 1)"
  [[ -n "$value" ]] || fail "key.properties is missing $property"
  [[ "$value" != "change-me" ]] || fail "key.properties still contains a placeholder for $property"
  if [[ "$property" == "storeFile" ]]; then
    if [[ "$value" == /* ]]; then
      store_file="$value"
    else
      store_file="$ANDROID_DIR/$value"
    fi
    [[ -f "$store_file" ]] || fail "key.properties storeFile does not reference a file"
  fi
done
