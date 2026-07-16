#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_COMPOSE="$ROOT_DIR/infra/deploy/compose.yml"
LOCAL_COMPOSE="$ROOT_DIR/docker-compose.yml"
DEPLOY_SCRIPT="$ROOT_DIR/infra/deploy/deploy.sh"
RESTORE_SCRIPT="$ROOT_DIR/infra/deploy/restore-postgres-schema.sh"
DOCKERFILE="$ROOT_DIR/apps/backend/Dockerfile"
DEFAULT_CONFIG="$(mktemp)"
OVERRIDE_CONFIG="$(mktemp)"
LOCAL_CONFIG="$(mktemp)"
trap 'rm -f "$DEFAULT_CONFIG" "$OVERRIDE_CONFIG" "$LOCAL_CONFIG"' EXIT

render_deploy_config() {
  BACKEND_IMAGE="example.invalid/backend@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
    POSTGRES_PASSWORD="policy-test-password" \
    docker compose -f "$DEPLOY_COMPOSE" config --format json
}

render_deploy_config > "$DEFAULT_CONFIG"
BACKEND_CPU_LIMIT=1.5 BACKEND_MEMORY_LIMIT=1g render_deploy_config > "$OVERRIDE_CONFIG"
docker compose -f "$LOCAL_COMPOSE" config --format json > "$LOCAL_CONFIG"

python3 - "$DEFAULT_CONFIG" "$OVERRIDE_CONFIG" "$LOCAL_CONFIG" <<'PY'
import json
import sys

default = json.load(open(sys.argv[1], encoding="utf-8"))
override = json.load(open(sys.argv[2], encoding="utf-8"))
local = json.load(open(sys.argv[3], encoding="utf-8"))

backend_names = sorted(name for name in default["services"] if name.startswith("backend-"))
assert backend_names == [
    "backend-dev-blue",
    "backend-dev-green",
    "backend-pro-blue",
    "backend-pro-green",
]

for name in backend_names:
    service = default["services"][name]
    assert service["security_opt"] == ["no-new-privileges:true"], (name, service.get("security_opt"))
    assert service["cap_drop"] == ["ALL"], (name, service.get("cap_drop"))
    assert service["cpus"] == 1, (name, service.get("cpus"))
    assert int(service["mem_limit"]) == 768 * 1024 * 1024, (name, service.get("mem_limit"))
    assert service["restart"] == "unless-stopped"
    assert service.get("healthcheck", {}).get("test")
    assert not service.get("volumes"), f"{name} must not receive host mounts"

    overridden = override["services"][name]
    assert overridden["cpus"] == 1.5
    assert int(overridden["mem_limit"]) == 1024 * 1024 * 1024

postgres = default["services"]["postgres"]
for key in ("security_opt", "cap_drop", "cpus", "mem_limit"):
    assert key not in postgres, f"PostgreSQL hardening is outside the MVP: unexpected {key}"

assert set(local["services"]) == {"postgres"}, "the local Compose has no backend service to harden"
local_postgres = local["services"]["postgres"]
for key in ("security_opt", "cap_drop", "cpus", "mem_limit"):
    assert key not in local_postgres, f"local PostgreSQL is outside the MVP: unexpected {key}"
PY

grep -Eq '^USER[[:space:]]+bun$' "$DOCKERFILE"
for one_off_script in "$DEPLOY_SCRIPT" "$RESTORE_SCRIPT"; do
  run_count="$(grep -c '^docker run --rm' "$one_off_script")"
  for required_flag in \
    '--security-opt no-new-privileges:true' \
    '--cap-drop ALL' \
    '--cpus "$BACKEND_CPU_LIMIT"' \
    '--memory "$BACKEND_MEMORY_LIMIT"'; do
    flag_count="$(grep -Fc -- "$required_flag" "$one_off_script")"
    [[ "$flag_count" -eq "$run_count" ]] || {
      echo "Every one-off container in $one_off_script must use $required_flag" >&2
      exit 1
    }
  done
  grep -Fq 'bun dist/scripts/migrate.js' "$one_off_script"
  grep -Fq 'bun dist/scripts/apply-privacy-suppressions.js' "$one_off_script"
done

if grep -Eq 'docker\.sock|/run/secrets|/var/run' "$DEPLOY_COMPOSE"; then
  echo "Backend deployment Compose must not mount host sockets or new secret paths." >&2
  exit 1
fi

echo "container runtime policy tests passed."
