#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY_VALIDATOR="$ROOT_DIR/scripts/deploy/validate-apk-signing-policy.sh"
CONFIG_VALIDATOR="$ROOT_DIR/scripts/mobile/validate-android-release-signing.sh"
DEV_CONFIG_VALIDATOR="$ROOT_DIR/scripts/mobile/validate-android-dev-signing.sh"
APK_VERIFIER="$ROOT_DIR/scripts/mobile/verify-apk-signing.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

expect_failure() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "Expected Android signing policy failure: $description" >&2
    exit 1
  fi
}

copy_policy_fixture() {
  rm -rf "$FIXTURE/policy"
  mkdir -p \
    "$FIXTURE/policy/.github/workflows" \
    "$FIXTURE/policy/apps/mobile/android/app" \
    "$FIXTURE/policy/scripts/mobile"
  cp "$ROOT_DIR/.github/workflows/mobile-apk-deploy.yml" "$FIXTURE/policy/.github/workflows/"
  cp "$ROOT_DIR/apps/mobile/android/app/build.gradle.kts" "$FIXTURE/policy/apps/mobile/android/app/"
  cp "$ROOT_DIR/scripts/mobile/build-android.sh" "$FIXTURE/policy/scripts/mobile/"
  cp "$ROOT_DIR/scripts/mobile/deploy-server-apks.sh" "$FIXTURE/policy/scripts/mobile/"
  cp "$CONFIG_VALIDATOR" "$FIXTURE/policy/scripts/mobile/"
  cp "$DEV_CONFIG_VALIDATOR" "$FIXTURE/policy/scripts/mobile/"
  cp "$APK_VERIFIER" "$FIXTURE/policy/scripts/mobile/"
}

"$POLICY_VALIDATOR" "$ROOT_DIR" >/dev/null
copy_policy_fixture
"$POLICY_VALIDATOR" "$FIXTURE/policy" >/dev/null

sed -i '/scripts\/mobile\/build-android.sh/i\          ALLOW_DEBUG_SIGNING=1' \
  "$FIXTURE/policy/.github/workflows/mobile-apk-deploy.yml"
expect_failure "workflow debug-signing escape" "$POLICY_VALIDATOR" "$FIXTURE/policy"
copy_policy_fixture

sed -i '/scripts\/mobile\/verify-apk-signing.sh/d' \
  "$FIXTURE/policy/.github/workflows/mobile-apk-deploy.yml"
expect_failure "missing CI certificate verification" "$POLICY_VALIDATOR" "$FIXTURE/policy"
copy_policy_fixture

sed -i 's/bettercalories-dev-\*\.apk/bettercalories-unverified-dev-*.apk/' \
  "$FIXTURE/policy/.github/workflows/mobile-apk-deploy.yml"
expect_failure "missing CI development certificate verification" "$POLICY_VALIDATOR" "$FIXTURE/policy"
copy_policy_fixture

sed -i '/rm -rf.*android-production-signing/d' \
  "$FIXTURE/policy/.github/workflows/mobile-apk-deploy.yml"
expect_failure "missing temporary key cleanup" "$POLICY_VALIDATOR" "$FIXTURE/policy"
copy_policy_fixture

sed -i '/rm -rf.*android-development-signing/d' \
  "$FIXTURE/policy/.github/workflows/mobile-apk-deploy.yml"
expect_failure "missing temporary development key cleanup" "$POLICY_VALIDATOR" "$FIXTURE/policy"
copy_policy_fixture

sed -i 's/signingConfigs.findByName("release")?.let { signingConfig = it }/signingConfig = signingConfigs.getByName("debug")/' \
  "$FIXTURE/policy/apps/mobile/android/app/build.gradle.kts"
expect_failure "prod debug signing config" "$POLICY_VALIDATOR" "$FIXTURE/policy"
copy_policy_fixture

sed -i 's/signingConfigs.findByName("devRelease")?.let { signingConfig = it }/signingConfig = signingConfigs.getByName("debug")/' \
  "$FIXTURE/policy/apps/mobile/android/app/build.gradle.kts"
expect_failure "dev debug signing config" "$POLICY_VALIDATOR" "$FIXTURE/policy"

android_fixture="$FIXTURE/android"
mkdir -p "$android_fixture"
fingerprint="$(printf 'A%.0s' {1..64})"
unset \
  ALLOW_DEBUG_SIGNING \
  ANDROID_RELEASE_STORE_FILE \
  ANDROID_RELEASE_STORE_PASSWORD \
  ANDROID_RELEASE_KEY_ALIAS \
  ANDROID_RELEASE_KEY_PASSWORD \
  ANDROID_RELEASE_CERT_SHA256
export MOBILE_ANDROID_DIR="$android_fixture"
export ANDROID_RELEASE_CERT_SHA256="$fingerprint"

expect_failure "missing release key" "$CONFIG_VALIDATOR"
touch "$FIXTURE/release.jks"
export ANDROID_RELEASE_STORE_FILE="$FIXTURE/release.jks"
export ANDROID_RELEASE_STORE_PASSWORD="test-only"
expect_failure "partial release-key configuration" "$CONFIG_VALIDATOR"
export ANDROID_RELEASE_KEY_ALIAS="release"
export ANDROID_RELEASE_KEY_PASSWORD="test-only"
"$CONFIG_VALIDATOR" >/dev/null
export ALLOW_DEBUG_SIGNING=1
expect_failure "removed debug-signing escape" "$CONFIG_VALIDATOR"
unset ALLOW_DEBUG_SIGNING

unset \
  ANDROID_DEV_STORE_FILE \
  ANDROID_DEV_STORE_PASSWORD \
  ANDROID_DEV_KEY_ALIAS \
  ANDROID_DEV_KEY_PASSWORD \
  ANDROID_DEV_CERT_SHA256
export ANDROID_DEV_CERT_SHA256="$fingerprint"
expect_failure "missing development key" "$DEV_CONFIG_VALIDATOR"
export ANDROID_DEV_STORE_FILE="$FIXTURE/release.jks"
export ANDROID_DEV_STORE_PASSWORD="test-only"
expect_failure "partial development-key configuration" "$DEV_CONFIG_VALIDATOR"
export ANDROID_DEV_KEY_ALIAS="development"
export ANDROID_DEV_KEY_PASSWORD="test-only"
"$DEV_CONFIG_VALIDATOR" >/dev/null

fake_bin="$FIXTURE/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/apksigner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${APKSIGNER_FAIL:-0}" != "1" ]] || exit 1
printf '%s\n' "$APKSIGNER_REPORT"
EOF
chmod +x "$fake_bin/apksigner"
touch "$FIXTURE/app.apk"
release_report="Signer #1 certificate DN: CN=BetterCalories Release, O=BetterCalories, C=ES
Signer #1 certificate SHA-256 digest: $fingerprint"
debug_report="Signer #1 certificate DN: CN=Android Debug, O=Android, C=US
Signer #1 certificate SHA-256 digest: $fingerprint"

APKSIGNER_BIN="$fake_bin/apksigner" APKSIGNER_REPORT="$release_report" \
  "$APK_VERIFIER" "$FIXTURE/app.apk" "$fingerprint" >/dev/null
expect_failure "missing approved fingerprint" \
  env -u ANDROID_RELEASE_CERT_SHA256 \
  APKSIGNER_BIN="$fake_bin/apksigner" APKSIGNER_REPORT="$release_report" \
  "$APK_VERIFIER" "$FIXTURE/app.apk"
expect_failure "certificate fingerprint mismatch" \
  env APKSIGNER_BIN="$fake_bin/apksigner" APKSIGNER_REPORT="$release_report" \
  "$APK_VERIFIER" "$FIXTURE/app.apk" "$(printf 'B%.0s' {1..64})"
expect_failure "Android Debug certificate" \
  env APKSIGNER_BIN="$fake_bin/apksigner" APKSIGNER_REPORT="$debug_report" \
  "$APK_VERIFIER" "$FIXTURE/app.apk" "$fingerprint"
expect_failure "invalid APK signature" \
  env APKSIGNER_BIN="$fake_bin/apksigner" APKSIGNER_REPORT="$release_report" APKSIGNER_FAIL=1 \
  "$APK_VERIFIER" "$FIXTURE/app.apk" "$fingerprint"

if [[ "${RUN_REAL_APK_SIGNING_TESTS:-0}" == "1" ]]; then
  real_apksigner="$(command -v apksigner || true)"
  android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -z "$android_sdk_root" && -d /home/antonio/Android/Sdk ]]; then
    android_sdk_root=/home/antonio/Android/Sdk
  fi
  if [[ -z "$real_apksigner" && -n "$android_sdk_root" && -d "$android_sdk_root/build-tools" ]]; then
    real_apksigner="$(find "$android_sdk_root/build-tools" -path '*/apksigner' -type f | sort -V | tail -n 1)"
  fi
  [[ -n "$real_apksigner" ]] || { echo "Real apksigner test requested but apksigner is unavailable." >&2; exit 1; }
  command -v keytool >/dev/null 2>&1 || { echo "Real apksigner test requested but keytool is unavailable." >&2; exit 1; }
  command -v jar >/dev/null 2>&1 || { echo "Real apksigner test requested but jar is unavailable." >&2; exit 1; }

  real_dir="$FIXTURE/real"
  mkdir -p "$real_dir/payload"
  printf '<manifest package="app.bettercalories.signingtest" />\n' > "$real_dir/payload/AndroidManifest.xml"
  (cd "$real_dir/payload" && jar --create --file "$real_dir/unsigned.apk" AndroidManifest.xml)
  keytool -genkeypair -noprompt \
    -keystore "$real_dir/release.p12" \
    -storetype PKCS12 \
    -storepass test-only-password \
    -keypass test-only-password \
    -alias release \
    -keyalg RSA \
    -keysize 2048 \
    -validity 30 \
    -dname "CN=BetterCalories Test Release,O=BetterCalories,C=ES" >/dev/null 2>&1
  cp "$real_dir/unsigned.apk" "$real_dir/release.apk"
  "$real_apksigner" sign \
    --min-sdk-version 29 \
    --ks "$real_dir/release.p12" \
    --ks-type PKCS12 \
    --ks-pass pass:test-only-password \
    --key-pass pass:test-only-password \
    --ks-key-alias release \
    "$real_dir/release.apk"
  real_fingerprint="$(
    LANG=C keytool -list -v \
      -keystore "$real_dir/release.p12" \
      -storetype PKCS12 \
      -storepass test-only-password \
      -alias release 2>/dev/null \
      | sed -nE 's/^[[:space:]]*SHA256:[[:space:]]*([0-9A-F:]+)$/\1/p' \
      | head -n 1
  )"
  cat > "$real_dir/apksigner-test-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command_name="$1"
shift
if [[ "$command_name" == "verify" ]]; then
  exec "$REAL_APKSIGNER" verify --min-sdk-version 29 "$@"
fi
exec "$REAL_APKSIGNER" "$command_name" "$@"
EOF
  chmod +x "$real_dir/apksigner-test-wrapper"
  REAL_APKSIGNER="$real_apksigner" APKSIGNER_BIN="$real_dir/apksigner-test-wrapper" \
    "$APK_VERIFIER" "$real_dir/release.apk" "$real_fingerprint" >/dev/null
fi

echo "Android APK signing policy tests passed."
