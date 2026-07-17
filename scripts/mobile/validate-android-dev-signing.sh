#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Android development signing configuration error: $*" >&2
  exit 1
}

fingerprint="${ANDROID_DEV_CERT_SHA256:-}"
normalized_fingerprint="$(printf '%s' "$fingerprint" | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')"
[[ "$normalized_fingerprint" =~ ^[0-9A-F]{64}$ ]] \
  || fail "ANDROID_DEV_CERT_SHA256 must contain one SHA-256 certificate fingerprint"

required_fields=(
  ANDROID_DEV_STORE_FILE
  ANDROID_DEV_STORE_PASSWORD
  ANDROID_DEV_KEY_ALIAS
  ANDROID_DEV_KEY_PASSWORD
)
for field in "${required_fields[@]}"; do
  [[ -n "${!field:-}" ]] || fail "$field is required"
done

[[ -f "$ANDROID_DEV_STORE_FILE" ]] \
  || fail "ANDROID_DEV_STORE_FILE does not reference a file"
