#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

touch "$tmp_dir/cal_tracker_pro_fresh.dump"
touch "$tmp_dir/cal_tracker_pro_under_limit.dump"
touch "$tmp_dir/cal_tracker_pro_at_limit.dump"
touch "$tmp_dir/cal_tracker_dev_at_limit.dump"
touch -d '43198 minutes ago' "$tmp_dir/cal_tracker_pro_under_limit.dump"
touch -d '43200 minutes ago' "$tmp_dir/cal_tracker_pro_at_limit.dump"
touch -d '43200 minutes ago' "$tmp_dir/cal_tracker_dev_at_limit.dump"

find "$tmp_dir" -maxdepth 1 -type f -name 'cal_tracker_pro_*.dump' -mmin +43199 -delete

test -f "$tmp_dir/cal_tracker_pro_fresh.dump"
test -f "$tmp_dir/cal_tracker_pro_under_limit.dump"
test ! -e "$tmp_dir/cal_tracker_pro_at_limit.dump"
test -f "$tmp_dir/cal_tracker_dev_at_limit.dump"
