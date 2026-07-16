#!/usr/bin/env bash
set -euo pipefail

APK_PATH="${1:-}"
EXPECTED_FINGERPRINT="${2:-${ANDROID_RELEASE_CERT_SHA256:-}}"
APKSIGNER_BIN="${APKSIGNER_BIN:-apksigner}"

fail() {
  echo "Android APK signing verification failed: $*" >&2
  exit 1
}

[[ -n "$APK_PATH" && -f "$APK_PATH" ]] || fail "APK file is required"
command -v "$APKSIGNER_BIN" >/dev/null 2>&1 || fail "apksigner is not available"

expected="$(printf '%s' "$EXPECTED_FINGERPRINT" | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')"
[[ "$expected" =~ ^[0-9A-F]{64}$ ]] \
  || fail "the approved SHA-256 certificate fingerprint is missing or invalid"

certificate_report="$("$APKSIGNER_BIN" verify --verbose --print-certs "$APK_PATH")" \
  || fail "apksigner rejected the APK"

if grep -Eiq 'certificate DN:.*CN=Android Debug([,]|$)' <<< "$certificate_report"; then
  fail "the APK is signed with an Android Debug certificate"
fi

mapfile -t actual_fingerprints < <(
  sed -nE 's/^Signer #[0-9]+ certificate SHA-256 digest:[[:space:]]*([0-9a-fA-F:]+)[[:space:]]*$/\1/p' \
    <<< "$certificate_report" \
    | tr -d ':' \
    | tr '[:lower:]' '[:upper:]' \
    | sort -u
)

[[ "${#actual_fingerprints[@]}" -eq 1 ]] \
  || fail "expected exactly one current signer certificate"
[[ "${actual_fingerprints[0]}" == "$expected" ]] \
  || fail "the signer certificate does not match the approved fingerprint"

echo "Android APK signature verified against the approved production certificate."
