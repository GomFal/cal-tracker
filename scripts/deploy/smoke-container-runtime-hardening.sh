#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?Usage: smoke-container-runtime-hardening.sh <backend-image>}"
CPU_LIMIT="${BACKEND_CPU_LIMIT:-1.0}"
MEMORY_LIMIT="${BACKEND_MEMORY_LIMIT:-768m}"
RUN_ID="runtime-hardening-$PPID-$$"
NETWORK="$RUN_ID"
POSTGRES="${RUN_ID}-postgres"
BACKEND="${RUN_ID}-backend"
STRESS="${RUN_ID}-stress"
BACKUP_FILE="$(mktemp)"

cleanup() {
  docker rm -f "$STRESS" "$BACKEND" "$POSTGRES" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -f "$BACKUP_FILE"
}
trap cleanup EXIT

runtime_policy=(
  --security-opt no-new-privileges:true
  --cap-drop ALL
  --cpus "$CPU_LIMIT"
  --memory "$MEMORY_LIMIT"
)
test_environment=(
  -e NODE_ENV=test
  -e DATABASE_URL="postgres://cal_tracker:cal_tracker@$POSTGRES:5432/cal_tracker"
  -e PORT=3000
)

docker network create "$NETWORK" >/dev/null
docker run -d \
  --name "$POSTGRES" \
  --network "$NETWORK" \
  -e POSTGRES_DB=cal_tracker \
  -e POSTGRES_USER=cal_tracker \
  -e POSTGRES_PASSWORD=cal_tracker \
  pgvector/pgvector:0.8.2-pg16-bookworm >/dev/null

for _ in {1..60}; do
  if docker exec "$POSTGRES" pg_isready -U cal_tracker -d cal_tracker >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "$POSTGRES" pg_isready -U cal_tracker -d cal_tracker >/dev/null

docker run --rm \
  "${runtime_policy[@]}" \
  --network "$NETWORK" \
  "${test_environment[@]}" \
  "$IMAGE" \
  bun dist/scripts/migrate.js >/dev/null

docker run -d \
  --name "$BACKEND" \
  "${runtime_policy[@]}" \
  --network "$NETWORK" \
  "${test_environment[@]}" \
  "$IMAGE" >/dev/null

for _ in {1..40}; do
  if docker exec "$BACKEND" bun -e \
    "fetch('http://127.0.0.1:3000/v1/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"; then
    break
  fi
  sleep 1
done
docker exec "$BACKEND" bun -e \
  "fetch('http://127.0.0.1:3000/v1/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

docker exec "$BACKEND" bun -e '
  const status = await Bun.file("/proc/self/status").text();
  if (process.getuid() !== 1000) throw new Error(`unexpected uid ${process.getuid()}`);
  if (!/^NoNewPrivs:\s+1$/m.test(status)) throw new Error("no-new-privileges is not active");
  if (!/^CapEff:\s+0+$/m.test(status)) throw new Error("effective capabilities are not empty");
  try {
    process.setuid(0);
    throw new Error("unexpectedly changed uid to root");
  } catch (error) {
    if (process.getuid() === 0) throw error;
  }
'

[[ "$(docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$BACKEND")" == *'no-new-privileges:true'* ]]
[[ "$(docker inspect -f '{{json .HostConfig.CapDrop}}' "$BACKEND")" == '["ALL"]' ]]
[[ "$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$BACKEND")" -gt 0 ]]
[[ "$(docker inspect -f '{{.HostConfig.Memory}}' "$BACKEND")" -gt 0 ]]

docker exec "$POSTGRES" pg_dump -U cal_tracker -d cal_tracker --format=custom > "$BACKUP_FILE"
docker exec "$POSTGRES" createdb -U cal_tracker cal_tracker_restore
docker exec -i "$POSTGRES" pg_restore -U cal_tracker -d cal_tracker_restore < "$BACKUP_FILE"
docker exec "$POSTGRES" psql -U cal_tracker -d cal_tracker_restore -Atqc \
  'select count(*) > 0 from schema_migrations' | grep -Fxq t

docker run -d \
  --name "$STRESS" \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cpus 1.0 \
  --memory 128m \
  --memory-swap 128m \
  "$IMAGE" \
  bun -e 'const chunks=[]; while (true) { const chunk=new Uint8Array(16*1024*1024); for (let i=0;i<chunk.length;i+=4096) chunk[i]=1; chunks.push(chunk); }' \
  >/dev/null

docker wait "$STRESS" >/dev/null || true
[[ "$(docker inspect -f '{{.State.OOMKilled}}' "$STRESS")" == "true" ]]
docker exec "$POSTGRES" pg_isready -U cal_tracker -d cal_tracker >/dev/null
docker exec "$BACKEND" bun -e \
  "fetch('http://127.0.0.1:3000/v1/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

echo "container runtime hardening smoke passed."
