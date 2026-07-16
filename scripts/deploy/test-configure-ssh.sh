#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/deploy/configure-ssh.sh"
TEST_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

ssh-keygen -q -t ed25519 -N '' -f "$TEST_ROOT/host-key"
host_public_key="$(cut -d' ' -f1-2 "$TEST_ROOT/host-key.pub")"
fingerprint="$(ssh-keygen -lf "$TEST_ROOT/host-key.pub" | awk '{ print $2 }')"
known_hosts="deploy.example.test $host_public_key"

run_configure() {
  SSH_DIR="$1" \
  VPS_HOST="${2:-deploy.example.test}" \
  VPS_SSH_PRIVATE_KEY="$(cat "$TEST_ROOT/host-key")" \
  VPS_SSH_KNOWN_HOSTS="$known_hosts" \
  VPS_SSH_HOST_KEY_FINGERPRINTS="${3:-$fingerprint}" \
    "$SCRIPT"
}

run_configure "$TEST_ROOT/success" >/dev/null
[[ "$(stat -c '%a' "$TEST_ROOT/success/id_ed25519")" == "600" ]]
[[ "$(stat -c '%a' "$TEST_ROOT/success/known_hosts")" == "600" ]]
grep -q '^  StrictHostKeyChecking yes$' "$TEST_ROOT/success/config"

if run_configure "$TEST_ROOT/wrong-fingerprint" deploy.example.test SHA256:not-the-key >/dev/null 2>&1; then
  echo "Expected a mismatched fingerprint to be rejected." >&2
  exit 1
fi

if run_configure "$TEST_ROOT/wrong-host" another.example.test "$fingerprint" >/dev/null 2>&1; then
  echo "Expected missing host data to be rejected." >&2
  exit 1
fi

echo "configure-ssh tests passed."
