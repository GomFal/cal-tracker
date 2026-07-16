#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
backend="$ROOT_DIR/.github/workflows/backend-deploy.yml"
mobile="$ROOT_DIR/.github/workflows/mobile-apk-deploy.yml"
policy_ci="$ROOT_DIR/.github/workflows/deployment-policy-ci.yml"

if grep -R -n 'ssh-keyscan' "$backend" "$mobile"; then
  echo "Deployment workflows must not learn host keys at runtime." >&2
  exit 1
fi

for workflow in "$backend" "$mobile"; do
  grep -q 'scripts/deploy/configure-ssh.sh' "$workflow"
  grep -q 'VPS_SSH_KNOWN_HOSTS' "$workflow"
  grep -q 'VPS_SSH_HOST_KEY_FINGERPRINTS' "$workflow"
  grep -q 'VPS_USER.*root' "$workflow"
done

grep -Fq 'steps.build.outputs.digest' "$backend"
grep -Fq 'deploy-backend' "$backend"
grep -Fq 'BETTERCALORIES_DEPLOY_SOURCE_COMMIT' "$mobile"
grep -Fq 'publish-apk' "$ROOT_DIR/scripts/mobile/deploy-server-apks.sh"
grep -Fq 'NOPASSWD: /usr/local/sbin/bettercalories-deploy' "$ROOT_DIR/infra/deploy/provision-deploy-user.sh"
grep -Fq 'test-configure-ssh.sh' "$policy_ci"
grep -Fq 'test-provision-deploy-user.sh' "$policy_ci"
for deploy_script in \
  "$ROOT_DIR/infra/deploy/deploy.sh" \
  "$ROOT_DIR/infra/deploy/restore-postgres-schema.sh"; do
  if grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+.*SECRETS_FILE' "$deploy_script"; then
    echo "Deployment env files must never be executed as shell code: $deploy_script" >&2
    exit 1
  fi
  grep -Fq 'read_env_value()' "$deploy_script"
done

echo "deployment policy tests passed."
