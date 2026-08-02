#!/usr/bin/env bash
set -Eeuo pipefail

readonly ping_secret=/home/ashton/.config/homeoss/healthchecks-pings.env
readonly kopia_secret=/home/ashton/.config/homeoss/kopia.env
readonly storage_config=/etc/homeoss/storage.env
readonly compose_file=/opt/kopia/docker-compose.yml
readonly ping_helper=/usr/local/lib/homeoss/healthchecks-ping.sh
readonly backup_logger=/usr/local/sbin/append-backup-log

source "${ping_secret}"
source "${ping_helper}"

healthchecks_ping "${HEALTHCHECK_KOPIA_LOCAL_SNAPSHOT_URL}" /start

if docker compose -f "${compose_file}" \
  --env-file "${storage_config}" --env-file "${kopia_secret}" \
  exec -T kopia kopia snapshot list /data --json |
  python3 -c '
import datetime
import json
import sys

snapshots = json.load(sys.stdin)
if not snapshots:
    raise SystemExit("no Kopia snapshots found")
latest = max(datetime.datetime.fromisoformat(s["startTime"]) for s in snapshots)
now = datetime.datetime.now(datetime.timezone.utc)
if now - latest > datetime.timedelta(hours=36):
    raise SystemExit(f"latest Kopia snapshot is too old: {latest.isoformat()}")
'
then
  if [[ -x ${backup_logger} ]]; then
    "${backup_logger}" filebackup-kopia-snapshot SUCCESS \
      "latest snapshot is fresh" || true
  fi
  healthchecks_ping "${HEALTHCHECK_KOPIA_LOCAL_SNAPSHOT_URL}"
else
  if [[ -x ${backup_logger} ]]; then
    "${backup_logger}" filebackup-kopia-snapshot FAILED \
      "latest snapshot is missing or stale" || true
  fi
  healthchecks_ping "${HEALTHCHECK_KOPIA_LOCAL_SNAPSHOT_URL}" /fail
  exit 1
fi
