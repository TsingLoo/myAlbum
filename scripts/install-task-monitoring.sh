#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/schedules.env"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

"${repo_dir}/scripts/setup-healthchecks-checks.sh"

install -d -m 0755 /etc/homeoss
install -m 0644 "${repo_dir}/config/storage.env" \
  /etc/homeoss/storage.env
install -m 0644 "${repo_dir}/config/kopia-cloud-sync.env" \
  /etc/homeoss/kopia-cloud-sync.env
install -m 0644 "${repo_dir}/config/schedules.env" \
  /etc/homeoss/schedules.env
install -d -m 0755 /usr/local/lib/homeoss
install -m 0644 "${repo_dir}/scripts/healthchecks-ping.sh" \
  /usr/local/lib/homeoss/healthchecks-ping.sh
install -m 0750 "${repo_dir}/scripts/kopia-snapshot-healthcheck.sh" \
  /usr/local/sbin/kopia-snapshot-healthcheck
install -m 0750 "${repo_dir}/scripts/immich-cloud-backup.sh" \
  /usr/local/sbin/immich-cloud-backup
install -m 0750 "${repo_dir}/scripts/kopia-cloud-sync.sh" \
  /usr/local/sbin/kopia-cloud-sync
install -m 0644 "${repo_dir}/systemd/kopia-snapshot-healthcheck.service" \
  /etc/systemd/system/kopia-snapshot-healthcheck.service
sed \
  -e "s#@KOPIA_LOCAL_HEALTHCHECK_TIME@#${KOPIA_LOCAL_HEALTHCHECK_TIME}#g" \
  -e "s#@KOPIA_LOCAL_HEALTHCHECK_RANDOM_DELAY@#${KOPIA_LOCAL_HEALTHCHECK_RANDOM_DELAY}#g" \
  -e "s#@SCHEDULE_TIMEZONE@#${SCHEDULE_TIMEZONE}#g" \
  "${repo_dir}/systemd/kopia-snapshot-healthcheck.timer" \
  >/etc/systemd/system/kopia-snapshot-healthcheck.timer
install -m 0644 "${repo_dir}/systemd/kopia-cloud-sync.service" \
  /etc/systemd/system/kopia-cloud-sync.service
sed \
  -e "s#@KOPIA_CLOUD_SYNC_DAYS@#${KOPIA_CLOUD_SYNC_DAYS}#g" \
  -e "s#@KOPIA_CLOUD_SYNC_TIME@#${KOPIA_CLOUD_SYNC_TIME}#g" \
  -e "s#@KOPIA_CLOUD_SYNC_RANDOM_DELAY@#${KOPIA_CLOUD_SYNC_RANDOM_DELAY}#g" \
  -e "s#@SCHEDULE_TIMEZONE@#${SCHEDULE_TIMEZONE}#g" \
  "${repo_dir}/systemd/kopia-cloud-sync.timer" \
  >/etc/systemd/system/kopia-cloud-sync.timer
install -m 0644 "${repo_dir}/systemd/immich-cloud-backup.service" \
  /etc/systemd/system/immich-cloud-backup.service
sed \
  -e "s#@IMMICH_BACKUP_DAYS@#${IMMICH_BACKUP_DAYS}#g" \
  -e "s#@IMMICH_BACKUP_TIME@#${IMMICH_BACKUP_TIME}#g" \
  -e "s#@IMMICH_BACKUP_RANDOM_DELAY@#${IMMICH_BACKUP_RANDOM_DELAY}#g" \
  -e "s#@SCHEDULE_TIMEZONE@#${SCHEDULE_TIMEZONE}#g" \
  "${repo_dir}/systemd/immich-cloud-backup.timer" \
  >/etc/systemd/system/immich-cloud-backup.timer
chmod 0644 \
  /etc/systemd/system/kopia-snapshot-healthcheck.timer \
  /etc/systemd/system/kopia-cloud-sync.timer \
  /etc/systemd/system/immich-cloud-backup.timer

systemctl daemon-reload
systemctl disable --now immich-backup-healthcheck.timer 2>/dev/null || true
systemctl enable --now kopia-snapshot-healthcheck.timer
systemctl enable --now kopia-cloud-sync.timer
systemctl restart immich-cloud-backup.timer kopia-cloud-sync.timer
systemctl start kopia-snapshot-healthcheck.service
systemctl list-timers kopia-snapshot-healthcheck.timer \
  kopia-cloud-sync.timer --no-pager
