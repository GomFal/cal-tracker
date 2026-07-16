#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

fail() {
  echo "Supply-chain policy violation: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "required file is missing: ${1#"$ROOT_DIR"/}"
}

validate_concrete_image() {
  local image="$1"
  local source="$2"
  local name_and_tag tag

  if [[ "$image" == *'${'* ]]; then
    fail "$source uses a variable base image ($image); production bases must be reviewable in the repository"
  fi

  if [[ "$image" =~ @sha256:[a-f0-9]{64}$ ]]; then
    return
  fi

  name_and_tag="${image##*/}"
  [[ "$name_and_tag" == *:* ]] || fail "$source uses an untagged image: $image"
  tag="${name_and_tag##*:}"
  [[ "$tag" != "latest" ]] || fail "$source uses latest: $image"

  # Concrete MVP tags start with at least major.minor. This rejects mutable
  # major-only aliases such as oven/bun:1 and pgvector/pgvector:pg16 while
  # accepting reviewed tags such as 1.3.13 and 0.8.2-pg16-bookworm.
  [[ "$tag" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([._-][A-Za-z0-9][A-Za-z0-9._-]*)?$ ]] \
    || fail "$source does not use a concrete version tag: $image"
}

MISE_FILE="$ROOT_DIR/.mise.toml"
PACKAGE_FILE="$ROOT_DIR/package.json"
DOCKERFILE="$ROOT_DIR/apps/backend/Dockerfile"
DEPLOY_COMPOSE="$ROOT_DIR/infra/deploy/compose.yml"
MOBILE_BUILD="$ROOT_DIR/scripts/mobile/build-android.sh"
RUNTIME_SMOKE="$ROOT_DIR/scripts/deploy/smoke-container-runtime-hardening.sh"
BACKEND_WORKFLOWS=(
  "$ROOT_DIR/.github/workflows/backend-ci.yml"
  "$ROOT_DIR/.github/workflows/backend-deploy.yml"
)

for required in \
  "$MISE_FILE" \
  "$PACKAGE_FILE" \
  "$DOCKERFILE" \
  "$DEPLOY_COMPOSE" \
  "$MOBILE_BUILD" \
  "$RUNTIME_SMOKE" \
  "${BACKEND_WORKFLOWS[@]}"; do
  require_file "$required"
done

bun_version="$(awk -F '"' '/^[[:space:]]*bun[[:space:]]*=[[:space:]]*"/ { print $2; exit }' "$MISE_FILE")"
[[ "$bun_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail ".mise.toml must pin Bun to an exact major.minor.patch version"
grep -Fq "\"packageManager\": \"bun@$bun_version\"" "$PACKAGE_FILE" \
  || fail "package.json packageManager must match Bun $bun_version from .mise.toml"

for workflow in "${BACKEND_WORKFLOWS[@]}"; do
  setup_count="$(grep -Ec 'uses:[[:space:]]*oven-sh/setup-bun@v[0-9]+' "$workflow" || true)"
  [[ "$setup_count" -gt 0 ]] || fail "${workflow#"$ROOT_DIR"/} does not configure Bun"

  mapfile -t configured_versions < <(
    sed -nE "s/^[[:space:]]*bun-version:[[:space:]]*['\"]?([^'\"[:space:]#]+)['\"]?([[:space:]]*#.*)?$/\\1/p" "$workflow"
  )
  [[ "${#configured_versions[@]}" -eq "$setup_count" ]] \
    || fail "${workflow#"$ROOT_DIR"/} must provide one bun-version for every setup-bun step"
  for configured in "${configured_versions[@]}"; do
    [[ "$configured" == "$bun_version" ]] \
      || fail "${workflow#"$ROOT_DIR"/} uses Bun $configured instead of $bun_version"
  done

  grep -Fq 'bun install --frozen-lockfile' "$workflow" \
    || fail "${workflow#"$ROOT_DIR"/} must install with --frozen-lockfile"
done

while IFS= read -r from_line; do
  from_line="${from_line%%[[:space:]]AS[[:space:]]*}"
  image="$(awk '{ for (field = 2; field <= NF; field++) if ($field !~ /^--/) { print $field; exit } }' <<< "$from_line")"
  [[ -n "$image" ]] || fail "could not read a base image from $DOCKERFILE"
  validate_concrete_image "$image" "${DOCKERFILE#"$ROOT_DIR"/}"
done < <(grep -Ei '^[[:space:]]*FROM[[:space:]]+' "$DOCKERFILE")

docker_from_count="$(grep -Eic '^[[:space:]]*FROM[[:space:]]+' "$DOCKERFILE")"
matching_bun_bases="$(grep -Eic "^[[:space:]]*FROM[[:space:]]+oven/bun:${bun_version}([[:space:]]|$)" "$DOCKERFILE" || true)"
[[ "$matching_bun_bases" -eq "$docker_from_count" ]] \
  || fail "every backend Docker stage must use the canonical oven/bun:$bun_version base"

postgres_image=""
while IFS= read -r image; do
  image="${image%%[[:space:]#]*}"
  [[ "$image" == *'${'* ]] && continue
  validate_concrete_image "$image" "${DEPLOY_COMPOSE#"$ROOT_DIR"/}"
  [[ "$image" == pgvector/pgvector:* ]] && postgres_image="$image"
done < <(sed -nE 's/^[[:space:]]*image:[[:space:]]*["'\'']?([^"'\''[:space:]#]+).*/\1/p' "$DEPLOY_COMPOSE")
[[ -n "$postgres_image" ]] || fail "infra/deploy/compose.yml must declare a concrete pgvector image"
grep -Fq "$postgres_image" "$RUNTIME_SMOKE" \
  || fail "runtime smoke test must use the production pgvector image $postgres_image"

grep -Fq 'bun install --frozen-lockfile' "$DOCKERFILE" \
  || fail "apps/backend/Dockerfile must install with --frozen-lockfile"
grep -Fq 'flutter pub get --enforce-lockfile' "$MOBILE_BUILD" \
  || fail "scripts/mobile/build-android.sh must enforce pubspec.lock"
grep -Fq 'run = "bun install --frozen-lockfile"' "$MISE_FILE" \
  || fail ".mise.toml install task must use Bun with --frozen-lockfile"
grep -Fq 'flutter pub get --enforce-lockfile' "$MISE_FILE" \
  || fail ".mise.toml Flutter install task must enforce pubspec.lock"

echo "software supply-chain policy passed (Bun $bun_version)."
