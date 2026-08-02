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
install -m 0644 "${repo_dir}/config/immich-kopia-cloud-sync.env" \
  /etc/homeoss/immich-kopia-cloud-sync.env

install -m 0750 "${repo_dir}/scripts/immich-cloud-backup.sh" \
  /usr/local/sbin/immich-cloud-backup
install -m 0750 "${repo_dir}/scripts/immich-kopia-backup.sh" \
  /usr/local/sbin/immich-kopia-backup
install -m 0750 "${repo_dir}/scripts/kopia-cloud-sync.sh" \
  /usr/local/sbin/kopia-cloud-sync
install -m 0750 "${repo_dir}/scripts/append-backup-log.sh" \
  /usr/local/sbin/append-backup-log
install -m 0755 "${repo_dir}/scripts/immich-backup-due.sh" \
  /usr/local/sbin/immich-backup-due
install -m 0750 "${repo_dir}/scripts/send-backup-report.py" \
  /usr/local/sbin/send-backup-report
install -m 0644 "${repo_dir}/systemd/immich-cloud-backup.service" \
  /etc/systemd/system/immich-cloud-backup.service
install -m 0644 "${repo_dir}/systemd/immich-kopia-backup.service" \
  /etc/systemd/system/immich-kopia-backup.service
install -m 0644 "${repo_dir}/systemd/immich-kopia-cloud-sync.service" \
  /etc/systemd/system/immich-kopia-cloud-sync.service
sed \
  -e "s#@IMMICH_BACKUP_TIME@#${IMMICH_BACKUP_TIME}#g" \
  -e "s#@IMMICH_BACKUP_RANDOM_DELAY@#${IMMICH_BACKUP_RANDOM_DELAY}#g" \
  -e "s#@SCHEDULE_TIMEZONE@#${SCHEDULE_TIMEZONE}#g" \
  "${repo_dir}/systemd/immich-kopia-backup.timer" \
  >/etc/systemd/system/immich-kopia-backup.timer
sed \
  -e "s#@IMMICH_KOPIA_CLOUD_SYNC_TIME@#${IMMICH_KOPIA_CLOUD_SYNC_TIME}#g" \
  -e "s#@IMMICH_KOPIA_CLOUD_SYNC_RANDOM_DELAY@#${IMMICH_KOPIA_CLOUD_SYNC_RANDOM_DELAY}#g" \
  -e "s#@SCHEDULE_TIMEZONE@#${SCHEDULE_TIMEZONE}#g" \
  "${repo_dir}/systemd/immich-kopia-cloud-sync.timer" \
  >/etc/systemd/system/immich-kopia-cloud-sync.timer
sed \
  -e "s#@IMMICH_FULL_BACKUP_TIME@#${IMMICH_FULL_BACKUP_TIME}#g" \
  -e "s#@IMMICH_FULL_BACKUP_RANDOM_DELAY@#${IMMICH_FULL_BACKUP_RANDOM_DELAY}#g" \
  -e "s#@SCHEDULE_TIMEZONE@#${SCHEDULE_TIMEZONE}#g" \
  "${repo_dir}/systemd/immich-cloud-backup.timer" \
  >/etc/systemd/system/immich-cloud-backup.timer
chmod 0644 /etc/systemd/system/immich-cloud-backup.timer \
  /etc/systemd/system/immich-kopia-backup.timer \
  /etc/systemd/system/immich-kopia-cloud-sync.timer

systemctl daemon-reload
systemctl enable --now immich-cloud-backup.timer immich-kopia-backup.timer \
  immich-kopia-cloud-sync.timer
systemctl restart immich-cloud-backup.timer immich-kopia-backup.timer \
  immich-kopia-cloud-sync.timer
systemctl list-timers immich-cloud-backup.timer \
  immich-kopia-backup.timer immich-kopia-cloud-sync.timer --no-pager
