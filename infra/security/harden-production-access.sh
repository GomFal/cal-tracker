#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly STATE_DIR="${BETTERCALORIES_ACCESS_STATE_DIR:-/var/lib/bettercalories-access-hardening}"
readonly SSH_DROP_IN="/etc/ssh/sshd_config.d/00-bettercalories-hardening.conf"
readonly FAIL2BAN_JAIL="/etc/fail2ban/jail.d/bettercalories-sshd.local"
readonly PROOF_MAX_AGE_SECONDS=3600

usage() {
  cat <<'EOF'
Usage:
  sudo ./harden-production-access.sh prepare --operator <user> --public-key-file <path>
  sudo ./harden-production-access.sh verify --operator <user> --recovery-console-confirmed
  sudo ./harden-production-access.sh enforce --operator <user> --confirm DISABLE_ROOT_AND_PASSWORD
  sudo ./harden-production-access.sh status --operator <user>
  sudo ./harden-production-access.sh rollback-ssh --console-recovery-confirmed

Run prepare from the existing administrative session. Then open a separate SSH
session as the nominal operator with password and keyboard-interactive auth
disabled, and run verify through sudo. Enforce refuses stale or root-created
proofs. Never run enforce until provider-console access has been checked.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[bettercalories-access] %s\n' "$*"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run this command through sudo or as root."
}

validate_operator() {
  local operator="$1"
  [[ "$operator" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid operator account name: $operator"
  [[ "$operator" != "root" ]] || die "The nominal operator cannot be root."
}

parse_operator() {
  local operator=""
  while (($#)); do
    case "$1" in
      --operator)
        (($# >= 2)) || die "--operator requires a value."
        operator="$2"
        shift 2
        ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
  [[ -n "$operator" ]] || die "--operator is required."
  validate_operator "$operator"
  printf '%s\n' "$operator"
}

install_packages() {
  command -v apt-get >/dev/null || die "This procedure currently supports apt-based Ubuntu/Debian hosts only."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends openssh-server sudo fail2ban ufw
}

prepare() {
  local operator="" public_key_file=""
  while (($#)); do
    case "$1" in
      --operator)
        (($# >= 2)) || die "--operator requires a value."
        operator="$2"
        shift 2
        ;;
      --public-key-file)
        (($# >= 2)) || die "--public-key-file requires a value."
        public_key_file="$2"
        shift 2
        ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  [[ -n "$operator" ]] || die "--operator is required."
  [[ -n "$public_key_file" ]] || die "--public-key-file is required."
  validate_operator "$operator"
  [[ -f "$public_key_file" ]] || die "Public key file does not exist: $public_key_file"
  [[ "$(awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' "$public_key_file")" -eq 1 ]] \
    || die "The public key file must contain exactly one non-comment key."
  ssh-keygen -l -f "$public_key_file" >/dev/null || die "ssh-keygen could not parse the public key."

  install_packages
  install -d -m 0700 "$STATE_DIR"

  if ! getent passwd "$operator" >/dev/null; then
    if getent group "$operator" >/dev/null; then
      useradd --create-home --shell /bin/bash "$operator"
    else
      adduser --disabled-password --gecos "" "$operator"
    fi
  fi
  usermod -aG sudo "$operator"

  local home_dir primary_group
  home_dir="$(getent passwd "$operator" | cut -d: -f6)"
  primary_group="$(id -gn "$operator")"
  [[ -n "$home_dir" && -d "$home_dir" ]] || die "Could not resolve the home directory for $operator."
  install -d -o "$operator" -g "$primary_group" -m 0700 "$home_dir/.ssh"
  install -o "$operator" -g "$primary_group" -m 0600 "$public_key_file" "$home_dir/.ssh/authorized_keys"

  printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$operator" > "/etc/sudoers.d/90-bettercalories-${operator}"
  chmod 0440 "/etc/sudoers.d/90-bettercalories-${operator}"
  visudo -cf "/etc/sudoers.d/90-bettercalories-${operator}" >/dev/null

  install -m 0600 "$SCRIPT_DIR/ssh/00-bettercalories-hardening.conf" "$STATE_DIR/00-bettercalories-hardening.conf.staged"
  install -m 0600 "$SCRIPT_DIR/fail2ban/bettercalories-sshd.local" "$STATE_DIR/bettercalories-sshd.local.staged"
  sshd -t -f "$STATE_DIR/00-bettercalories-hardening.conf.staged"

  ssh-keygen -lf "$public_key_file" | awk '{ print $2 }' > "$STATE_DIR/operator-key-fingerprint"
  printf '%s\n' "$operator" > "$STATE_DIR/operator"
  rm -f "$STATE_DIR/operator-verified"

  log "Prepared nominal operator '$operator'; SSH policy has NOT been changed."
  log "Open a second terminal using public-key-only authentication, then run the verify phase there."
}

recent_public_key_login_exists() {
  local operator="$1" source_ip="$2"
  if journalctl --since '-15 minutes' --no-pager -o cat _COMM=sshd 2>/dev/null \
    | grep -F "Accepted publickey for ${operator} from ${source_ip} " >/dev/null; then
    return 0
  fi
  [[ -r /var/log/auth.log ]] \
    && tail -n 1000 /var/log/auth.log \
      | grep -F "Accepted publickey for ${operator} from ${source_ip} " >/dev/null
}

verify() {
  local operator="" recovery_confirmed="false"
  while (($#)); do
    case "$1" in
      --operator)
        (($# >= 2)) || die "--operator requires a value."
        operator="$2"
        shift 2
        ;;
      --recovery-console-confirmed)
        recovery_confirmed="true"
        shift
        ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  [[ -n "$operator" ]] || die "--operator is required."
  validate_operator "$operator"
  [[ "$recovery_confirmed" == "true" ]] || die "Confirm access to the provider recovery console first."
  [[ "${SUDO_USER:-}" == "$operator" ]] || die "Run verify via sudo from the '$operator' account, not from root."
  [[ -n "${SSH_CONNECTION:-}" ]] || die "Verify must run inside an SSH session."
  [[ "$(cat "$STATE_DIR/operator" 2>/dev/null || true)" == "$operator" ]] || die "Operator does not match the prepared account."

  local source_ip current_fingerprint expected_fingerprint
  source_ip="${SSH_CONNECTION%% *}"
  recent_public_key_login_exists "$operator" "$source_ip" \
    || die "No recent public-key login for '$operator' from '$source_ip' was found in the sshd journal."
  current_fingerprint="$(ssh-keygen -lf "$(getent passwd "$operator" | cut -d: -f6)/.ssh/authorized_keys" | awk '{ print $2 }')"
  expected_fingerprint="$(cat "$STATE_DIR/operator-key-fingerprint")"
  [[ "$current_fingerprint" == "$expected_fingerprint" ]] || die "The installed operator key differs from the prepared key."

  runuser -u "$operator" -- sudo -n true \
    || die "The operator cannot use non-interactive sudo elevation."
  sshd -t

  {
    printf 'operator=%s\n' "$operator"
    printf 'source_ip=%s\n' "$source_ip"
    printf 'verified_at=%s\n' "$(date +%s)"
    printf 'key_fingerprint=%s\n' "$current_fingerprint"
    printf 'provider_console_confirmed=true\n'
  } > "$STATE_DIR/operator-verified"
  chmod 0600 "$STATE_DIR/operator-verified"
  logger -t bettercalories-access "Verified public-key SSH and sudo for nominal operator $operator from $source_ip"
  log "Alternative access verified. The proof is valid for ${PROOF_MAX_AGE_SECONDS} seconds."
}

read_proof_value() {
  local key="$1"
  sed -n "s/^${key}=//p" "$STATE_DIR/operator-verified" 2>/dev/null | head -n1
}

check_effective_ssh_policy() {
  local operator="$1" source_ip="${2:-127.0.0.1}" effective test_host
  test_host="$(hostname -f 2>/dev/null || hostname)"
  effective="$(sshd -T -C "user=${operator},host=${test_host},addr=${source_ip}")"
  grep -qx 'pubkeyauthentication yes' <<<"$effective" \
    || { printf 'Effective SSH policy does not enable public keys.\n' >&2; return 1; }
  grep -qx 'passwordauthentication no' <<<"$effective" \
    || { printf 'Effective SSH policy still allows passwords.\n' >&2; return 1; }
  grep -qx 'kbdinteractiveauthentication no' <<<"$effective" \
    || { printf 'Effective SSH policy still allows keyboard-interactive auth.\n' >&2; return 1; }
  grep -qx 'authenticationmethods publickey' <<<"$effective" \
    || { printf 'Effective SSH policy is not public-key-only.\n' >&2; return 1; }

  effective="$(sshd -T -C "user=root,host=${test_host},addr=${source_ip}")"
  grep -qx 'permitrootlogin no' <<<"$effective" \
    || { printf 'Effective SSH policy still allows direct root login.\n' >&2; return 1; }
}

reload_ssh() {
  if systemctl reload ssh; then
    return
  fi
  systemctl reload sshd
}

restore_ssh_backup() {
  if [[ -f "$STATE_DIR/ssh-drop-in.pre-hardening" ]]; then
    install -m 0644 "$STATE_DIR/ssh-drop-in.pre-hardening" "$SSH_DROP_IN"
  else
    rm -f "$SSH_DROP_IN"
  fi
  sshd -t
  reload_ssh
}

enforce() {
  local operator="" confirmation=""
  while (($#)); do
    case "$1" in
      --operator)
        (($# >= 2)) || die "--operator requires a value."
        operator="$2"
        shift 2
        ;;
      --confirm)
        (($# >= 2)) || die "--confirm requires a value."
        confirmation="$2"
        shift 2
        ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  [[ -n "$operator" ]] || die "--operator is required."
  validate_operator "$operator"
  [[ "$confirmation" == "DISABLE_ROOT_AND_PASSWORD" ]] || die "Explicit enforcement confirmation is missing."
  [[ -f "$STATE_DIR/operator-verified" ]] || die "Alternative access has not been verified."
  [[ "$(read_proof_value operator)" == "$operator" ]] || die "Verification proof belongs to another operator."
  [[ "$(read_proof_value provider_console_confirmed)" == "true" ]] || die "Provider-console recovery was not confirmed."

  local verified_at proof_age verified_source_ip
  verified_at="$(read_proof_value verified_at)"
  verified_source_ip="$(read_proof_value source_ip)"
  [[ "$verified_at" =~ ^[0-9]+$ ]] || die "Verification proof timestamp is invalid."
  [[ -n "$verified_source_ip" ]] || die "Verification proof source IP is missing."
  proof_age="$(( $(date +%s) - verified_at ))"
  ((proof_age >= 0 && proof_age <= PROOF_MAX_AGE_SECONDS)) \
    || die "Verification proof is stale; repeat the public-key login and verify phase."

  if [[ -f "$SSH_DROP_IN" && ! -f "$STATE_DIR/ssh-drop-in.pre-hardening" ]]; then
    install -m 0600 "$SSH_DROP_IN" "$STATE_DIR/ssh-drop-in.pre-hardening"
  fi
  (
    local ssh_policy_committed="false"
    # Invoked by the EXIT trap below; ShellCheck cannot infer that call edge.
    # shellcheck disable=SC2317
    rollback_uncommitted_ssh_policy() {
      local exit_status=$?
      if [[ "$ssh_policy_committed" != "true" ]]; then
        log "Enforcement did not commit; restoring the previous SSH policy."
        restore_ssh_backup || true
      fi
      exit "$exit_status"
    }
    trap rollback_uncommitted_ssh_policy EXIT

    install -D -m 0644 "$STATE_DIR/00-bettercalories-hardening.conf.staged" "$SSH_DROP_IN"
    sshd -t
    check_effective_ssh_policy "$operator" "$verified_source_ip"
    reload_ssh
    check_effective_ssh_policy "$operator" "$verified_source_ip"
    ssh_policy_committed="true"
  )

  install -D -m 0644 "$STATE_DIR/bettercalories-sshd.local.staged" "$FAIL2BAN_JAIL"
  fail2ban-client -t
  systemctl enable --now fail2ban
  systemctl restart fail2ban
  fail2ban-client status sshd >/dev/null

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp comment 'SSH public-key access'
  ufw allow 80/tcp comment 'HTTP redirects and ACME'
  ufw allow 443/tcp comment 'HTTPS application traffic'
  ufw logging low
  ufw --force enable

  check_effective_ssh_policy "$operator" "$verified_source_ip" \
    || die "SSH policy changed unexpectedly after enforcement."
  ufw status | grep -q '^Status: active$' || die "UFW did not become active."
  logger -t bettercalories-access "Enforced public-key-only SSH, disabled root login, enabled fail2ban and explicit UFW policy"
  log "Hardening enforced. Keep the current SSH session open while testing a fresh operator login."
}

status() {
  local operator test_host
  operator="$(parse_operator "$@")"
  test_host="$(hostname -f 2>/dev/null || hostname)"
  log "Effective SSH policy:"
  sshd -T -C "user=${operator},host=${test_host},addr=127.0.0.1" \
    | awk '$1 ~ /^(pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|permitrootlogin|maxauthtries|logingracetime)$/ { print }'
  log "Firewall policy:"
  ufw status verbose
  log "Brute-force protection:"
  fail2ban-client status sshd
  log "Recent access-hardening events:"
  journalctl -t bettercalories-access --since '-7 days' --no-pager
}

rollback_ssh() {
  [[ "${1:-}" == "--console-recovery-confirmed" && $# -eq 1 ]] \
    || die "Rollback is reserved for the provider console and requires --console-recovery-confirmed."
  restore_ssh_backup
  logger -t bettercalories-access "Restored the pre-hardening SSH drop-in from the provider console"
  log "Previous SSH drop-in restored. UFW still permits TCP/22."
}

main() {
  local command="${1:-}"
  [[ -n "$command" ]] || { usage; exit 2; }
  shift
  case "$command" in
    help|-h|--help) usage; return ;;
  esac
  require_root
  case "$command" in
    prepare) prepare "$@" ;;
    verify) verify "$@" ;;
    enforce) enforce "$@" ;;
    status) status "$@" ;;
    rollback-ssh) rollback_ssh "$@" ;;
    *) usage; die "Unknown command: $command" ;;
  esac
}

main "$@"
