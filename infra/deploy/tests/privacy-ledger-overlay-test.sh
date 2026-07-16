#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
overlay_dir="$test_root/overlays"
fake_bin="$test_root/bin"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$fake_bin"

cat > "$fake_bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAKE_DOCKER_FAIL:-0}" == "1" ]]; then
  exit 1
fi
cat <<'CSV'
id,subject_user_id,conversation_id,requested_at,purge_due_at,status,purged_at,last_attempt_at,attempt_count,result_code
00000000-0000-0000-0000-000000000001,00000000-0000-0000-0000-000000000002,00000000-0000-0000-0000-000000000003,2026-01-01T00:00:00Z,2026-01-02T00:00:00Z,purged,2026-01-01T00:00:01Z,2026-01-01T00:00:01Z,1,purged
CSV
SH
chmod +x "$fake_bin/docker"

env PATH="$fake_bin:$PATH" CAL_TRACKER_PRIVACY_LEDGER_DIR="$overlay_dir" \
  "$script_dir/privacy-ledger-overlay.sh" export dev >/dev/null
overlay_file="$overlay_dir/cal_tracker_dev.csv"
test "$(stat -c '%a' "$overlay_dir")" = "700"
test "$(stat -c '%a' "$overlay_file")" = "600"
before_failure="$(sha256sum "$overlay_file")"

# A failed live export must fail closed and preserve the last atomic file; the
# restore orchestrator still aborts and never treats that old file as complete.
if env PATH="$fake_bin:$PATH" FAKE_DOCKER_FAIL=1 \
  CAL_TRACKER_PRIVACY_LEDGER_DIR="$overlay_dir" \
  "$script_dir/privacy-ledger-overlay.sh" export dev >/dev/null 2>&1; then
  echo "expected live overlay export to fail" >&2
  exit 1
fi
test "$(sha256sum "$overlay_file")" = "$before_failure"

rm "$overlay_file"
if env PATH="$fake_bin:$PATH" CAL_TRACKER_PRIVACY_LEDGER_DIR="$overlay_dir" \
  "$script_dir/privacy-ledger-overlay.sh" import dev >/dev/null 2>&1; then
  echo "expected missing overlay import to fail" >&2
  exit 1
fi
