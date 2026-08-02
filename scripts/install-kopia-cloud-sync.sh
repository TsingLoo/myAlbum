#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/schedules.env"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

install -d -m 0755 /etc/homeoss
install -m 0644 "${repo_dir}/config/storage.env" \
  /etc/homeoss/storage.env
install -m 0644 "${repo_dir}/config/kopia-cloud-sync.env" \
  /etc/homeoss/kopia-cloud-sync.env
install -m 0644 "${repo_dir}/config/schedules.env" \
  /etc/homeoss/schedules.env
install -m 0750 "${repo_dir}/scripts/kopia-cloud-sync.sh" \
  /usr/local/sbin/kopia-cloud-sync
install -m 0750 "${repo_dir}/scripts/append-backup-log.sh" \
  /usr/local/sbin/append-backup-log
install -m 0644 "${repo_dir}/services/kopia/docker-compose.yml" \
  /opt/kopia/docker-compose.yml
install -m 0644 "${repo_dir}/services/kopia-common.yml" /opt/kopia-common.yml
install -m 0644 "${repo_dir}/systemd/kopia-cloud-sync.service" \
  /etc/systemd/system/kopia-cloud-sync.service
sed \
  -e "s#@KOPIA_CLOUD_SYNC_DAYS@#${KOPIA_CLOUD_SYNC_DAYS}#g" \
  -e "s#@KOPIA_CLOUD_SYNC_TIME@#${KOPIA_CLOUD_SYNC_TIME}#g" \
  -e "s#@KOPIA_CLOUD_SYNC_RANDOM_DELAY@#${KOPIA_CLOUD_SYNC_RANDOM_DELAY}#g" \
  -e "s#@SCHEDULE_TIMEZONE@#${SCHEDULE_TIMEZONE}#g" \
  "${repo_dir}/systemd/kopia-cloud-sync.timer" \
  >/etc/systemd/system/kopia-cloud-sync.timer
chmod 0644 /etc/systemd/system/kopia-cloud-sync.timer

systemctl daemon-reload
docker compose -f /opt/kopia/docker-compose.yml \
  --env-file /etc/homeoss/storage.env \
  --env-file /home/ashton/.config/homeoss/kopia.env up -d
systemctl enable --now kopia-cloud-sync.timer
systemctl list-timers kopia-cloud-sync.timer --no-pager
