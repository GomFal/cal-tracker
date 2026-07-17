#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORKFLOW="$ROOT_DIR/.github/workflows/mobile-apk-deploy.yml"
GRADLE_BUILD="$ROOT_DIR/apps/mobile/android/app/build.gradle.kts"
BUILD_SCRIPT="$ROOT_DIR/scripts/mobile/build-android.sh"
DEPLOY_SCRIPT="$ROOT_DIR/scripts/mobile/deploy-server-apks.sh"
CONFIG_VALIDATOR="$ROOT_DIR/scripts/mobile/validate-android-release-signing.sh"
DEV_CONFIG_VALIDATOR="$ROOT_DIR/scripts/mobile/validate-android-dev-signing.sh"
APK_VERIFIER="$ROOT_DIR/scripts/mobile/verify-apk-signing.sh"

fail() {
  echo "Android APK signing policy violation: $*" >&2
  exit 1
}

for required in \
  "$WORKFLOW" \
  "$GRADLE_BUILD" \
  "$BUILD_SCRIPT" \
  "$DEPLOY_SCRIPT" \
  "$CONFIG_VALIDATOR" \
  "$DEV_CONFIG_VALIDATOR" \
  "$APK_VERIFIER"; do
  [[ -f "$required" ]] || fail "required file is missing: ${required#"$ROOT_DIR"/}"
done

if grep -Eq 'ALLOW_DEBUG_SIGNING[[:space:]]*=' \
  "$WORKFLOW" "$GRADLE_BUILD" "$BUILD_SCRIPT" "$DEPLOY_SCRIPT"; then
  fail "a production build or publication route enables debug signing"
fi

grep -Fq 'ANDROID_RELEASE_KEYSTORE_BASE64' "$WORKFLOW" \
  || fail "the mobile workflow does not reconstruct the protected release keystore"
grep -Fq 'ANDROID_DEV_KEYSTORE_BASE64' "$WORKFLOW" \
  || fail "the mobile workflow does not reconstruct the protected development keystore"
for secret in \
  ANDROID_DEV_STORE_PASSWORD \
  ANDROID_DEV_KEY_ALIAS \
  ANDROID_DEV_KEY_PASSWORD \
  ANDROID_DEV_CERT_SHA256; do
  grep -Fq "secrets.$secret" "$WORKFLOW" \
    || fail "the mobile workflow does not consume the protected $secret secret"
done
for secret in \
  ANDROID_RELEASE_STORE_PASSWORD \
  ANDROID_RELEASE_KEY_ALIAS \
  ANDROID_RELEASE_KEY_PASSWORD \
  ANDROID_RELEASE_CERT_SHA256; do
  grep -Fq "secrets.$secret" "$WORKFLOW" \
    || fail "the mobile workflow does not consume the protected $secret secret"
done
grep -Fq 'scripts/mobile/verify-apk-signing.sh' "$WORKFLOW" \
  || fail "the mobile workflow does not verify APK certificates"
grep -Fq 'bettercalories-dev-*.apk' "$WORKFLOW" \
  || fail "the mobile workflow does not verify the development APK certificate"
grep -Fq 'rm -rf "$RUNNER_TEMP/android-production-signing"' "$WORKFLOW" \
  || fail "the mobile workflow does not remove temporary signing material"
grep -Fq 'rm -rf "$RUNNER_TEMP/android-development-signing"' "$WORKFLOW" \
  || fail "the mobile workflow does not remove temporary development signing material"

grep -Fq 'validate-android-dev-signing.sh' "$BUILD_SCRIPT" \
  || fail "the Android build does not validate stable signing before dev release"
grep -Fq 'validate-android-release-signing.sh' "$BUILD_SCRIPT" \
  || fail "the Android build does not validate release signing before prod"
grep -Fq 'verify-apk-signing.sh' "$BUILD_SCRIPT" \
  || fail "the Android build does not verify APK certificates"
grep -Fq '${ANDROID_DEV_CERT_SHA256:-}' "$BUILD_SCRIPT" \
  || fail "the Android build does not verify the approved dev certificate"
grep -Fq 'verify-apk-signing.sh' "$DEPLOY_SCRIPT" \
  || fail "prebuilt APKs are not verified before publication"
grep -Fq '${ANDROID_DEV_CERT_SHA256:-}' "$DEPLOY_SCRIPT" \
  || fail "prebuilt dev APKs are not verified before publication"

grep -Fq 'signingConfigs.findByName("devRelease")?.let { signingConfig = it }' "$GRADLE_BUILD" \
  || fail "the dev flavor is not bound to the stable development signing config"
grep -Fq 'buildsDevRelease && !hasCompleteDevSigning' "$GRADLE_BUILD" \
  || fail "direct devRelease Gradle builds do not fail closed"
grep -Fq 'signingConfigs.findByName("release")?.let { signingConfig = it }' "$GRADLE_BUILD" \
  || fail "the prod flavor is not bound to the release signing config"
grep -Fq 'buildsProdRelease && !hasCompleteReleaseSigning' "$GRADLE_BUILD" \
  || fail "direct prodRelease Gradle builds do not fail closed"
if grep -Eq 'findByName\("release"\).*(\?:|getByName\("debug"\))' "$GRADLE_BUILD"; then
  fail "Gradle falls back from release signing to the debug key"
fi

echo "Android APK signing policy passed."
