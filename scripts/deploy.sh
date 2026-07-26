#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/storage.env"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if ! findmnt --mountpoint "${STORAGE_ROOT}" >/dev/null; then
  echo "Refusing to deploy: ${STORAGE_ROOT} is not mounted." >&2
  exit 1
fi

install -d -m 0755 /etc/homeoss /opt/immich /opt/openlist
install -m 0644 "${repo_dir}/config/storage.env" /etc/homeoss/storage.env
install -m 0644 "${repo_dir}/config/schedules.env" /etc/homeoss/schedules.env
install -d -m 0755 "${STORAGE_ROOT}/immich"
install -d -m 0700 "${STORAGE_ROOT}/.backup-work"
getent group familyshare >/dev/null || groupadd --system familyshare
getent passwd ashton >/dev/null && usermod -aG familyshare ashton
if [[ -d /srv/family-share && ! -e /srv/lan-share ]]; then
  mv /srv/family-share /srv/lan-share
fi
install -d -m 2770 -o root -g familyshare /srv/lan-share
install -d -m 2770 -o ashton -g familyshare "${STORAGE_ROOT}/file-backup"
install -d -m 0700 /var/lib/immich-postgres

install -m 0644 "${repo_dir}/services/immich/docker-compose.yml" \
  /opt/immich/docker-compose.yml
if [[ -s ${repo_dir}/services/immich/.env ]]; then
  install -m 0600 "${repo_dir}/services/immich/.env" /opt/immich/.env
elif [[ ! -s /opt/immich/.env ]]; then
  echo "Restore /opt/immich/.env or create services/immich/.env." >&2
  exit 1
fi

install -m 0644 "${repo_dir}/services/openlist/docker-compose.yml" \
  /opt/openlist/docker-compose.yml
if [[ -f ${repo_dir}/services/openlist/.env ]]; then
  install -m 0600 "${repo_dir}/services/openlist/.env" /opt/openlist/.env
elif [[ ! -f /opt/openlist/.env ]]; then
  install -m 0600 "${repo_dir}/services/openlist/.env.example" \
    /opt/openlist/.env
fi
install -d -m 0700 /opt/openlist/data
openlist_uid=$(awk -F= '$1 == "OPENLIST_UID" {print $2}' /opt/openlist/.env)
openlist_gid=$(awk -F= '$1 == "OPENLIST_GID" {print $2}' /opt/openlist/.env)
chown -R "${openlist_uid}:${openlist_gid}" /opt/openlist/data

docker compose -f /opt/immich/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file /opt/immich/.env \
  config --quiet
docker compose -f /opt/openlist/docker-compose.yml \
  --env-file /opt/openlist/.env config --quiet

docker compose -f /opt/immich/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file /opt/immich/.env pull
docker compose -f /opt/immich/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file /opt/immich/.env up -d

docker compose -f /opt/openlist/docker-compose.yml \
  --env-file /opt/openlist/.env pull
docker compose -f /opt/openlist/docker-compose.yml \
  --env-file /opt/openlist/.env up -d

docker compose -f /opt/immich/docker-compose.yml ps
docker compose -f /opt/openlist/docker-compose.yml ps
