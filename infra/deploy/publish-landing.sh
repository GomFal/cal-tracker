#!/usr/bin/env bash
set -euo pipefail

archive="${1:?archive is required}"
release_id="${2:?release id is required}"
remote_root="${3:?remote root is required}"
remote_state="${4:?remote state is required}"
release_dir="$remote_state/releases/$release_id"
backup_dir="$remote_state/backups/$release_id"

if tar -tzf "$archive" | awk -F/ '$1 == ".." || $0 ~ /^\// || $0 ~ /(^|\/)\.\.(\/|$)/ { bad=1 } END { exit bad ? 0 : 1 }'; then
  echo "Landing archive contains an unsafe path." >&2
  exit 1
fi
if tar -tvzf "$archive" | awk 'substr($1, 1, 1) !~ /^[-d]$/ { bad=1 } END { exit bad ? 0 : 1 }'; then
  echo "Landing archive contains links or special files." >&2
  exit 1
fi

install -d -m 0755 "$release_dir" "$backup_dir"
tar -xzf "$archive" -C "$release_dir"
find "$release_dir" -type d -exec chmod 0755 {} +
find "$release_dir" -type f -exec chmod 0644 {} +

if [[ -d "$remote_root" ]]; then
  install -d -m 0755 "$backup_dir/html"
  rsync -a "$remote_root"/ "$backup_dir/html"/
else
  install -d -m 0755 "$remote_root"
fi

rsync -a --delete "$release_dir"/ "$remote_root"/
find "$remote_root" -type d -exec chmod 0755 {} +
find "$remote_root" -type f -exec chmod 0644 {} +
printf '%s\n' "$release_dir" > "$remote_state/current"
rm -f -- "$archive"
