#!/usr/bin/env bash
set -euo pipefail

flavor="${1:-}"
api_base_url="${2:-}"
build_mode="${3:-release}"

if [[ -z "$flavor" || -z "$api_base_url" ]]; then
  echo "Usage: validate-api-base-url.sh <dev|prod|local> <api-base-url> <debug|release>" >&2
  exit 2
fi

FLAVOR="$flavor" API_BASE_URL="$api_base_url" BUILD_MODE="$build_mode" python3 - <<'PY'
import os
import sys
from urllib.parse import urlsplit

flavor = os.environ["FLAVOR"]
raw_url = os.environ["API_BASE_URL"]
build_mode = os.environ["BUILD_MODE"]

if build_mode not in {"debug", "release"}:
    print("Unsupported mobile build mode.", file=sys.stderr)
    raise SystemExit(2)

try:
    parsed = urlsplit(raw_url)
    parsed.port
except ValueError:
    print("Invalid mobile API base URL.", file=sys.stderr)
    raise SystemExit(1)

if (
    not parsed.scheme
    or not parsed.hostname
    or parsed.username is not None
    or parsed.password is not None
    or parsed.query
    or parsed.fragment
    or parsed.path
):
    print("Invalid mobile API base URL.", file=sys.stderr)
    raise SystemExit(1)

secure_origins = {
    "dev": "https://dev-api.bettercalories.app",
    "prod": "https://api.bettercalories.app",
}
local_debug_origins = {
    "http://10.0.2.2:3000",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
}

allowed = False
if flavor in secure_origins:
    allowed = raw_url == secure_origins[flavor]
    if not allowed and flavor == "dev" and build_mode == "debug":
        allowed = raw_url in local_debug_origins
elif flavor in {"local", "local1", "local2"} and build_mode == "debug":
    allowed = raw_url in local_debug_origins

if not allowed:
    print(
        f"Refusing unapproved API origin for {flavor} {build_mode} build.",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
