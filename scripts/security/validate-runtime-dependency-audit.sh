#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MISE_FILE="$ROOT_DIR/.mise.toml"
AUDIT_FILE="$(mktemp)"
trap 'rm -f "$AUDIT_FILE"' EXIT

expected_bun="$(awk -F '"' '/^[[:space:]]*bun[[:space:]]*=[[:space:]]*"/ { print $2; exit }' "$MISE_FILE")"
actual_bun="$(bun --version)"

if [[ -z "$expected_bun" || "$actual_bun" != "$expected_bun" ]]; then
  echo "Runtime dependency audit requires Bun $expected_bun; found $actual_bun." >&2
  exit 1
fi

# `bun audit` exits non-zero for any finding, including accepted lower-severity
# development-only advisories. Preserve its JSON and apply the MVP high gate.
(cd "$ROOT_DIR" && bun audit --json >"$AUDIT_FILE") || true

bun - "$AUDIT_FILE" <<'BUN'
const auditPath = Bun.argv[2];
const raw = await Bun.file(auditPath).text();
if (!raw.trim()) {
  console.error("bun audit returned no JSON evidence");
  process.exit(1);
}

let report;
try {
  report = JSON.parse(raw);
} catch {
  console.error("bun audit returned invalid JSON evidence");
  process.exit(1);
}

const findings = Object.entries(report).flatMap(([packageName, advisories]) =>
  advisories.map((advisory) => ({ packageName, ...advisory })),
);
const blocking = findings.filter((finding) =>
  finding.severity === "high" || finding.severity === "critical",
);

if (blocking.length > 0) {
  for (const finding of blocking) {
    console.error(`${finding.severity}: ${finding.packageName} ${finding.id} ${finding.title}`);
  }
  process.exit(1);
}

const counts = findings.reduce((result, finding) => {
  result[finding.severity] = (result[finding.severity] ?? 0) + 1;
  return result;
}, {});
console.log(
  `runtime dependency audit passed: 0 high/critical; ${counts.moderate ?? 0} moderate; ${counts.low ?? 0} low`,
);
BUN
