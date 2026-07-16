#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_USER="bettercalories-deploy"
PUBLIC_KEY_FILE=""
# Empty in production. The executable provisioning test overrides this only
# after sourcing the script so all privileged paths stay inside its fixture.
PROVISION_ROOT=""

usage() {
  cat <<'EOF'
Usage:
  sudo ./provision-deploy-user.sh --public-key-file <path> [--user <name>]

Creates a dedicated, passwordless SSH account whose only sudo permission is
the BetterCalories deployment dispatcher. It does not change sshd policy.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

root_path() {
  printf '%s%s' "$PROVISION_ROOT" "$1"
}

provision_deploy_user() {
  local home_dir primary_group sudoers_file

  if ! getent passwd "$DEPLOY_USER" >/dev/null; then
    adduser --disabled-password --gecos '' "$DEPLOY_USER"
  fi
  passwd -l "$DEPLOY_USER" >/dev/null

  home_dir="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
  [[ -n "$home_dir" ]] || die "Could not determine the deployment user's home directory."
  primary_group="$(id -gn "$DEPLOY_USER")" \
    || die "Could not determine the deployment user's primary group."
  [[ -n "$primary_group" ]] || die "The deployment user's primary group is empty."

  chown root:root "$home_dir"
  chmod 0755 "$home_dir"
  install -d -o root -g root -m 0755 "$home_dir/.ssh"
  {
    printf 'no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc,no-pty '
    awk 'NF && $1 !~ /^#/ { print; exit }' "$PUBLIC_KEY_FILE"
  } > "$home_dir/.ssh/authorized_keys"
  chown root:root "$home_dir/.ssh/authorized_keys"
  chmod 0644 "$home_dir/.ssh/authorized_keys"

  install -d -o "$DEPLOY_USER" -g "$primary_group" -m 0700 "$(root_path /srv/cal-tracker/incoming)"
  install -d -m 0755 \
    "$(root_path /srv/cal-tracker/deploy)" \
    "$(root_path /srv/cal-tracker/state)" \
    "$(root_path /srv/cal-tracker/mobile/dev)" \
    "$(root_path /srv/cal-tracker/mobile/prod)"
  install -d -m 0700 "$(root_path /srv/cal-tracker/env)"
  install -o root -g root -m 0755 \
    "$SCRIPT_DIR/bettercalories-deploy" \
    "$(root_path /usr/local/sbin/bettercalories-deploy)"
  printf '%s\n' "$DEPLOY_USER" > "$(root_path /etc/bettercalories-deploy-user)"
  chmod 0644 "$(root_path /etc/bettercalories-deploy-user)"

  sudoers_file="$(root_path /etc/sudoers.d/91-bettercalories-deploy)"
  printf '%s ALL=(root) NOPASSWD: /usr/local/sbin/bettercalories-deploy\n' "$DEPLOY_USER" > "$sudoers_file"
  chmod 0440 "$sudoers_file"
  visudo -cf "$sudoers_file" >/dev/null

  # Infrastructure files are installed only from this explicitly elevated,
  # operator-controlled provisioning step. Routine CI cannot replace scripts
  # that the dispatcher later executes as root.
  bash "$SCRIPT_DIR/bootstrap-server.sh"
}

main() {
  while (($#)); do
    case "$1" in
      --public-key-file) PUBLIC_KEY_FILE="${2:-}"; shift 2 ;;
      --user) DEPLOY_USER="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) usage; die "Unknown argument: $1" ;;
    esac
  done

  [[ "${EUID}" -eq 0 ]] || die "Run this script through sudo or as root."
  [[ "$DEPLOY_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$DEPLOY_USER" != root ]] \
    || die "Invalid deployment user."
  [[ -f "$PUBLIC_KEY_FILE" ]] || die "A public key file is required."
  [[ "$(awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' "$PUBLIC_KEY_FILE")" -eq 1 ]] \
    || die "The public key file must contain exactly one key."
  ssh-keygen -l -f "$PUBLIC_KEY_FILE" >/dev/null || die "The public key is invalid."

  provision_deploy_user

  echo "Provisioned the limited deployment account '$DEPLOY_USER'. SSH policy was not changed."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
