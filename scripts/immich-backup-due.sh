#!/usr/bin/env bash
set -Eeuo pipefail

readonly state_file=/var/lib/homeoss/immich-cloud-backup.last-success
readonly minimum_interval_seconds=$((13 * 24 * 60 * 60))

# No successful backup yet: allow the one-time first run or the next retry.
[[ -e ${state_file} ]] || exit 0

last_success=$(stat -c %Y "${state_file}")
now=$(date +%s)
((now - last_success >= minimum_interval_seconds))
