#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_BIN="$TMP_DIR/bin"
mkdir -p "$MOCK_BIN" "$TMP_DIR/root/etc/sudoers.d" "$TMP_DIR/home"

cat > "$MOCK_BIN/getent" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == passwd && "$2" == "$MOCK_DEPLOY_USER" ]]
[[ -f "$MOCK_ACCOUNT_STATE" ]] || exit 2
printf '%s:x:1500:1600::%s:/usr/sbin/nologin\n' "$MOCK_DEPLOY_USER" "$MOCK_HOME"
EOF

cat > "$MOCK_BIN/adduser" <<'EOF'
#!/bin/bash
set -euo pipefail
touch "$MOCK_ACCOUNT_STATE"
EOF

cat > "$MOCK_BIN/id" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == -gn && "$2" == "$MOCK_DEPLOY_USER" ]]
printf '%s\n' "$MOCK_PRIMARY_GROUP"
EOF

cat > "$MOCK_BIN/install" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%q ' "$@" >> "$MOCK_INSTALL_LOG"
printf '\n' >> "$MOCK_INSTALL_LOG"
if [[ " $* " == *" -d "* ]]; then
  mkdir -p "${@: -1}"
else
  mkdir -p "$(dirname "${@: -1}")"
  : > "${@: -1}"
fi
EOF

for command in passwd chown chmod visudo ssh-keygen; do
  cat > "$MOCK_BIN/$command" <<'EOF'
#!/bin/bash
exit 0
EOF
done
chmod +x "$MOCK_BIN"/*

export MOCK_DEPLOY_USER="bettercalories-deploy"
export MOCK_PRIMARY_GROUP="bettercalories-primary"
export MOCK_ACCOUNT_STATE="$TMP_DIR/account-created"
export MOCK_HOME="$TMP_DIR/home"
export MOCK_INSTALL_LOG="$TMP_DIR/install.log"
export PATH="$MOCK_BIN:$PATH"

# shellcheck source=../../infra/deploy/provision-deploy-user.sh
source "$ROOT_DIR/infra/deploy/provision-deploy-user.sh"

DEPLOY_USER="$MOCK_DEPLOY_USER"
PUBLIC_KEY_FILE="$TMP_DIR/deploy.pub"
PROVISION_ROOT="$TMP_DIR/root"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest deployment@test\n' > "$PUBLIC_KEY_FILE"

# Avoid running the privileged bootstrap while keeping the production call in
# the exercised provisioning path.
bash() {
  [[ "$1" == "$ROOT_DIR/infra/deploy/bootstrap-server.sh" ]]
}

provision_deploy_user

[[ -f "$MOCK_ACCOUNT_STATE" ]]
[[ -f "$MOCK_HOME/.ssh/authorized_keys" ]]
grep -Fq 'no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc,no-pty ssh-ed25519' \
  "$MOCK_HOME/.ssh/authorized_keys"
grep -Fq -- "-o $MOCK_DEPLOY_USER -g $MOCK_PRIMARY_GROUP -m 0700 $TMP_DIR/root/srv/cal-tracker/incoming" \
  "$MOCK_INSTALL_LOG"
grep -Fq "$MOCK_DEPLOY_USER ALL=(root) NOPASSWD: /usr/local/sbin/bettercalories-deploy" \
  "$TMP_DIR/root/etc/sudoers.d/91-bettercalories-deploy"

echo "deployment user provisioning test passed."
