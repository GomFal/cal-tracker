#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/deploy/validate-supply-chain-policy.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p \
  "$FIXTURE/.github/workflows" \
  "$FIXTURE/apps/backend" \
  "$FIXTURE/infra/deploy" \
  "$FIXTURE/scripts/deploy" \
  "$FIXTURE/scripts/mobile"

write_valid_fixture() {
  cat > "$FIXTURE/.mise.toml" <<'EOF'
[tools]
bun = "1.3.13"

[tasks.install]
run = "bun install --frozen-lockfile"

[tasks.flutter-pub-get]
run = "flutter pub get --enforce-lockfile"
EOF
  cat > "$FIXTURE/package.json" <<'EOF'
{"packageManager": "bun@1.3.13"}
EOF
  for workflow in backend-ci backend-deploy; do
    cat > "$FIXTURE/.github/workflows/$workflow.yml" <<'EOF'
steps:
  - uses: oven-sh/setup-bun@v2
    with:
      bun-version: "1.3.13"
  - run: bun install --frozen-lockfile
EOF
  done
  cat > "$FIXTURE/apps/backend/Dockerfile" <<'EOF'
FROM oven/bun:1.3.13 AS build
RUN bun install --frozen-lockfile
FROM oven/bun:1.3.13 AS runtime
EOF
  cat > "$FIXTURE/infra/deploy/compose.yml" <<'EOF'
services:
  postgres:
    image: pgvector/pgvector:0.8.2-pg16-bookworm
  backend:
    image: ${BACKEND_IMAGE:?BACKEND_IMAGE is required}
EOF
  cat > "$FIXTURE/scripts/mobile/build-android.sh" <<'EOF'
flutter pub get --enforce-lockfile
EOF
  cat > "$FIXTURE/scripts/deploy/smoke-container-runtime-hardening.sh" <<'EOF'
docker run pgvector/pgvector:0.8.2-pg16-bookworm
EOF

  # These deliberately mutable references are outside production policy
  # surfaces and must not create false positives.
  cat > "$FIXTURE/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: pgvector/pgvector:pg16
EOF
  printf '%s\n' 'example text: FROM oven/bun:latest' > "$FIXTURE/notes.md"
}

expect_failure() {
  local description="$1"
  if "$VALIDATOR" "$FIXTURE" >/dev/null 2>&1; then
    echo "Expected policy failure: $description" >&2
    exit 1
  fi
}

"$VALIDATOR" "$ROOT_DIR"
write_valid_fixture
"$VALIDATOR" "$FIXTURE" >/dev/null

sed -i 's/bun-version: "1.3.13"/bun-version: latest/' "$FIXTURE/.github/workflows/backend-ci.yml"
expect_failure "Bun latest in production CI"
write_valid_fixture

sed -i 's/oven\/bun:1.3.13/oven\/bun:1/g' "$FIXTURE/apps/backend/Dockerfile"
expect_failure "major-only backend base image"
write_valid_fixture

sed -i '0,/oven\/bun:1.3.13/s//oven\/bun:1.3.12/' "$FIXTURE/apps/backend/Dockerfile"
expect_failure "backend base does not match the canonical Bun version"
write_valid_fixture

sed -i 's/0.8.2-pg16-bookworm/pg16/' "$FIXTURE/infra/deploy/compose.yml"
expect_failure "major-only PostgreSQL image"
write_valid_fixture

sed -i 's/ --frozen-lockfile//' "$FIXTURE/.github/workflows/backend-deploy.yml"
expect_failure "unfrozen backend dependency install"

echo "software supply-chain policy tests passed."
