#!/usr/bin/env bash
set -euo pipefail

APK_PATH="${1:-}"
EXPECTED_PACKAGE="${2:-}"
EXPECTED_VERSION_CODE="${3:-}"
APKANALYZER_BIN="${APKANALYZER_BIN:-apkanalyzer}"

fail() {
  echo "Android APK update metadata verification failed: $*" >&2
  exit 1
}

[[ -n "$APK_PATH" && -f "$APK_PATH" ]] || fail "APK path is missing"
[[ "$EXPECTED_PACKAGE" =~ ^app\.bettercalories(\.dev)?$ ]] \
  || fail "expected package is not an approved update package"
[[ "$EXPECTED_VERSION_CODE" =~ ^[1-9][0-9]*$ ]] \
  || fail "expected versionCode must be a positive integer"
command -v "$APKANALYZER_BIN" >/dev/null 2>&1 \
  || fail "apkanalyzer is required to inspect the APK"

actual_package="$($APKANALYZER_BIN manifest application-id "$APK_PATH")" \
  || fail "could not read the APK package"
actual_version_code="$($APKANALYZER_BIN manifest version-code "$APK_PATH")" \
  || fail "could not read the APK versionCode"

[[ "$actual_package" == "$EXPECTED_PACKAGE" ]] \
  || fail "APK package does not match the publication channel"
[[ "$actual_version_code" == "$EXPECTED_VERSION_CODE" ]] \
  || fail "APK versionCode does not match the publication manifest"

echo "Android APK package and versionCode verified for update publication."
