#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/schedules.env"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

install -d -m 0755 /etc/homeoss
install -m 0644 "${repo_dir}/config/storage.env" /etc/homeoss/storage.env
install -m 0644 "${repo_dir}/config/schedules.env" /etc/homeoss/schedules.env

install -m 0750 "${repo_dir}/scripts/immich-cloud-backup.sh" \
  /usr/local/sbin/immich-cloud-backup
install -m 0755 "${repo_dir}/scripts/immich-backup-due.sh" \
  /usr/local/sbin/immich-backup-due
install -m 0750 "${repo_dir}/scripts/send-backup-report.py" \
  /usr/local/sbin/send-backup-report
install -m 0644 "${repo_dir}/systemd/immich-cloud-backup.service" \
  /etc/systemd/system/immich-cloud-backup.service
sed \
  -e "s#@IMMICH_BACKUP_DAYS@#${IMMICH_BACKUP_DAYS}#g" \
  -e "s#@IMMICH_BACKUP_TIME@#${IMMICH_BACKUP_TIME}#g" \
  -e "s#@IMMICH_BACKUP_RANDOM_DELAY@#${IMMICH_BACKUP_RANDOM_DELAY}#g" \
  -e "s#@SCHEDULE_TIMEZONE@#${SCHEDULE_TIMEZONE}#g" \
  "${repo_dir}/systemd/immich-cloud-backup.timer" \
  >/etc/systemd/system/immich-cloud-backup.timer
chmod 0644 /etc/systemd/system/immich-cloud-backup.timer

systemctl daemon-reload
systemctl enable --now immich-cloud-backup.timer
systemctl list-timers immich-cloud-backup.timer --no-pager
