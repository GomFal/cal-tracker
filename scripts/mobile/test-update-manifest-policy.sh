#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/mobile/validate-update-manifest.py"
APK_METADATA_VALIDATOR="$ROOT_DIR/scripts/mobile/verify-update-apk-metadata.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

write_manifest() {
  local path="$1"
  local channel="$2"
  local package_name="$3"
  local version_code="$4"
  local apk_url="$5"
  cat > "$path" <<JSON
{
  "channel": "$channel",
  "packageName": "$package_name",
  "versionName": "1.2.3",
  "versionCode": $version_code,
  "apkUrl": "$apk_url",
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "sizeBytes": 42,
  "publishedAt": "2026-07-16T12:00:00Z",
  "futureField": "decoy \"versionCode\": 999"
}
JSON
}

expect_rejected() {
  if "$@" >/dev/null 2>&1; then
    echo "Expected update manifest policy rejection: $*" >&2
    exit 1
  fi
}

dev_manifest="$TMP_DIR/dev.json"
prod_manifest="$TMP_DIR/prod.json"
write_manifest \
  "$dev_manifest" dev app.bettercalories.dev 23 \
  https://dev-api.bettercalories.app/apk/bettercalories-dev.apk
write_manifest \
  "$prod_manifest" prod app.bettercalories 23 \
  https://api.bettercalories.app/apk/bettercalories-prod.apk

python3 "$VALIDATOR" "$dev_manifest" --channel dev \
  --minimum-version-code 22 --expected-version-code 23
python3 "$VALIDATOR" "$prod_manifest" --channel prod \
  --minimum-version-code 22 --expected-version-code 23
[[ "$(python3 "$VALIDATOR" "$dev_manifest" --channel dev --print-version-code)" == "23" ]] \
  || { echo "Structured manifest versionCode output was ambiguous." >&2; exit 1; }

expect_rejected python3 "$VALIDATOR" "$dev_manifest" --channel prod
expect_rejected python3 "$VALIDATOR" "$dev_manifest" --channel dev \
  --minimum-version-code 23

for untrusted_url in \
  http://dev-api.bettercalories.app/apk/app.apk \
  https://api.bettercalories.app/apk/app.apk \
  https://dev-api.bettercalories.app:443/apk/app.apk \
  https://dev-api.bettercalories.app/apk/nested/app.apk
do
  untrusted_manifest="$TMP_DIR/untrusted.json"
  write_manifest \
    "$untrusted_manifest" dev app.bettercalories.dev 23 "$untrusted_url"
  expect_rejected python3 "$VALIDATOR" "$untrusted_manifest" --channel dev
done

printf '{"channel":"dev"}\n' > "$TMP_DIR/manipulated.json"
expect_rejected python3 "$VALIDATOR" "$TMP_DIR/manipulated.json" --channel dev

cp "$dev_manifest" "$TMP_DIR/missing-integrity.json"
python3 - "$TMP_DIR/missing-integrity.json" <<'PY'
import json
import sys

path = sys.argv[1]
manifest = json.loads(open(path, encoding="utf-8").read())
manifest.pop("sha256")
open(path, "w", encoding="utf-8").write(json.dumps(manifest))
PY
expect_rejected python3 "$VALIDATOR" "$TMP_DIR/missing-integrity.json" --channel dev

touch "$TMP_DIR/app.apk"
cat > "$TMP_DIR/apkanalyzer" <<'SCRIPT'
#!/usr/bin/env bash
case "$2" in
  application-id) printf '%s\n' "${FAKE_APK_PACKAGE:?}" ;;
  version-code) printf '%s\n' "${FAKE_APK_VERSION_CODE:?}" ;;
  *) exit 1 ;;
esac
SCRIPT
chmod +x "$TMP_DIR/apkanalyzer"

APKANALYZER_BIN="$TMP_DIR/apkanalyzer" \
FAKE_APK_PACKAGE=app.bettercalories.dev \
FAKE_APK_VERSION_CODE=23 \
  "$APK_METADATA_VALIDATOR" "$TMP_DIR/app.apk" app.bettercalories.dev 23
expect_rejected env \
  APKANALYZER_BIN="$TMP_DIR/apkanalyzer" \
  FAKE_APK_PACKAGE=app.bettercalories \
  FAKE_APK_VERSION_CODE=23 \
  "$APK_METADATA_VALIDATOR" "$TMP_DIR/app.apk" app.bettercalories.dev 23
expect_rejected env \
  APKANALYZER_BIN="$TMP_DIR/apkanalyzer" \
  FAKE_APK_PACKAGE=app.bettercalories.dev \
  FAKE_APK_VERSION_CODE=22 \
  "$APK_METADATA_VALIDATOR" "$TMP_DIR/app.apk" app.bettercalories.dev 23

if rg -q 'allow_non_incremental_version|ALLOW_NON_INCREMENTAL_APK_VERSION' \
  "$ROOT_DIR/.github/workflows/mobile-apk-deploy.yml" \
  "$ROOT_DIR/scripts/mobile/deploy-server-apks.sh"; then
  echo "Non-incremental APK publication override is still enabled." >&2
  exit 1
fi

echo "Trusted mobile update manifest policy tests passed."
