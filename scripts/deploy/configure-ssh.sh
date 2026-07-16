#!/usr/bin/env bash
set -euo pipefail

SSH_DIR="${SSH_DIR:-${HOME:?HOME is required}/.ssh}"
PRIVATE_KEY="${VPS_SSH_PRIVATE_KEY:?VPS_SSH_PRIVATE_KEY is required}"
KNOWN_HOSTS="${VPS_SSH_KNOWN_HOSTS:?VPS_SSH_KNOWN_HOSTS is required}"
EXPECTED_FINGERPRINTS="${VPS_SSH_HOST_KEY_FINGERPRINTS:?VPS_SSH_HOST_KEY_FINGERPRINTS is required}"
VPS_HOST="${VPS_HOST:?VPS_HOST is required}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "$VPS_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || die "VPS_HOST must be a hostname without a user, port or whitespace."
command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen is required."

install -m 0700 -d "$SSH_DIR"
printf '%s\n' "$PRIVATE_KEY" > "$SSH_DIR/id_ed25519"
printf '%s\n' "$KNOWN_HOSTS" > "$SSH_DIR/known_hosts"
chmod 0600 "$SSH_DIR/id_ed25519" "$SSH_DIR/known_hosts"

host_entries="$(mktemp)"
actual_fingerprints="$(mktemp)"
expected_fingerprints="$(mktemp)"
cleanup() {
  rm -f "$host_entries" "$actual_fingerprints" "$expected_fingerprints"
}
trap cleanup EXIT

ssh-keygen -F "$VPS_HOST" -f "$SSH_DIR/known_hosts" 2>/dev/null \
  | awk 'NF && $1 !~ /^#/' > "$host_entries"
[[ -s "$host_entries" ]] || die "Pinned known_hosts data does not contain VPS_HOST."

ssh-keygen -lf "$host_entries" 2>/dev/null \
  | awk '{ print $2 }' \
  | sort -u > "$actual_fingerprints"
printf '%s\n' "$EXPECTED_FINGERPRINTS" \
  | tr ', ' '\n\n' \
  | awk 'NF { print }' \
  | sort -u > "$expected_fingerprints"

[[ -s "$expected_fingerprints" ]] || die "No expected SSH host fingerprint was provided."
if ! cmp -s "$actual_fingerprints" "$expected_fingerprints"; then
  die "Pinned known_hosts keys do not match the configured SSH host fingerprints."
fi

cat > "$SSH_DIR/config" <<EOF
Host *
  BatchMode yes
  CheckHostIP yes
  IdentitiesOnly yes
  IdentityFile $SSH_DIR/id_ed25519
  KbdInteractiveAuthentication no
  PasswordAuthentication no
  StrictHostKeyChecking yes
  UserKnownHostsFile $SSH_DIR/known_hosts
EOF
chmod 0600 "$SSH_DIR/config"

printf 'SSH configured with a pinned host identity.\n'
