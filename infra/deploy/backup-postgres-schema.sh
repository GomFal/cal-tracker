#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?Usage: backup-postgres-schema.sh <dev|pro>}"

case "$ENVIRONMENT" in
  dev) SCHEMA="cal_tracker_dev" ;;
  pro) SCHEMA="cal_tracker_pro" ;;
  *) echo "Unknown environment: $ENVIRONMENT" >&2; exit 2 ;;
esac

BACKUP_DIR="/srv/cal-tracker/backups"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d -m 0750 "$BACKUP_DIR"
docker exec cal-tracker-postgres pg_dump -U cal_tracker -d cal_tracker --schema="$SCHEMA" --format=custom > "$BACKUP_DIR/${SCHEMA}_${TIMESTAMP}.dump"
# Keep a database-independent copy of every known suppression. A restore still
# performs a fresh export after stopping both backend slots.
"$SCRIPT_DIR/privacy-ledger-overlay.sh" export "$ENVIRONMENT" >/dev/null
# Deleted chat content expires from backup media through this fixed rotation.
# Keep the just-created backup even if the host clock changes unexpectedly.
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${SCHEMA}_*.dump" -mmin +43199 -delete
echo "$BACKUP_DIR/${SCHEMA}_${TIMESTAMP}.dump"
