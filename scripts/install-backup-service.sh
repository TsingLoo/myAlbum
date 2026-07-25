#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

install -m 0750 "${repo_dir}/scripts/immich-cloud-backup.sh" \
  /usr/local/sbin/immich-cloud-backup
install -m 0644 "${repo_dir}/systemd/immich-cloud-backup.service" \
  /etc/systemd/system/immich-cloud-backup.service
install -m 0644 "${repo_dir}/systemd/immich-cloud-backup.timer" \
  /etc/systemd/system/immich-cloud-backup.timer

systemctl daemon-reload
rm -f /usr/local/sbin/immich-backup-due
systemctl enable --now immich-cloud-backup.timer
systemctl list-timers immich-cloud-backup.timer --no-pager
