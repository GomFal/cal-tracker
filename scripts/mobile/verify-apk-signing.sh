#!/usr/bin/env bash
set -euo pipefail

APK_PATH="${1:-}"
EXPECTED_FINGERPRINT="${2:-${ANDROID_RELEASE_CERT_SHA256:-}}"

fail() {
  echo "Android APK signing verification failed: $*" >&2
  exit 1
}

[[ -n "$APK_PATH" && -f "$APK_PATH" ]] || fail "APK file is required"

resolve_apksigner() {
  local configured_bin="${APKSIGNER_BIN:-}"
  local resolved_bin=""

  if [[ -n "$configured_bin" ]]; then
    resolved_bin="$(command -v "$configured_bin" 2>/dev/null || true)"
    [[ -n "$resolved_bin" ]] || fail "configured apksigner is not available"
    printf '%s\n' "$resolved_bin"
    return
  fi

  resolved_bin="$(command -v apksigner 2>/dev/null || true)"
  if [[ -z "$resolved_bin" ]]; then
    local android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    if [[ -n "$android_sdk_root" && -d "$android_sdk_root/build-tools" ]]; then
      resolved_bin="$(
        find "$android_sdk_root/build-tools" \
          -path '*/apksigner' \
          -type f \
          -perm -u+x \
          | sort -V \
          | tail -n 1
      )"
    fi
  fi

  [[ -n "$resolved_bin" ]] || fail "apksigner is not available"
  printf '%s\n' "$resolved_bin"
}

APKSIGNER_BIN="$(resolve_apksigner)"

expected="$(printf '%s' "$EXPECTED_FINGERPRINT" | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')"
[[ "$expected" =~ ^[0-9A-F]{64}$ ]] \
  || fail "the approved SHA-256 certificate fingerprint is missing or invalid"

certificate_report="$("$APKSIGNER_BIN" verify --verbose --print-certs "$APK_PATH")" \
  || fail "apksigner rejected the APK"

if grep -Eiq 'certificate DN:.*CN=Android Debug([,]|$)' <<< "$certificate_report"; then
  fail "the APK is signed with an Android Debug certificate"
fi

mapfile -t actual_fingerprints < <(
  sed -nE '/certificate SHA-256 digest:/ {
    s/.*certificate SHA-256 digest:[[:space:]]*//
    s/[^0-9a-fA-F:].*$//
    /^[0-9a-fA-F:]+$/p
  }' <<< "$certificate_report" \
    | tr -d ':' \
    | tr '[:lower:]' '[:upper:]' \
    | sort -u
)

[[ "${#actual_fingerprints[@]}" -eq 1 ]] \
  || fail "expected exactly one current signer certificate (found ${#actual_fingerprints[@]})"
[[ "${actual_fingerprints[0]}" == "$expected" ]] \
  || fail "the signer certificate does not match the approved fingerprint"

echo "Android APK signature verified against the approved certificate."
