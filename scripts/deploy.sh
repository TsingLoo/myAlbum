#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if ! findmnt --mountpoint /srv/immich-data >/dev/null; then
  echo "Refusing to deploy: /srv/immich-data is not mounted." >&2
  exit 1
fi

if [[ ! -f ${repo_dir}/services/immich/.env ]]; then
  echo "Create services/immich/.env from .env.example first." >&2
  exit 1
fi

install -d -m 0755 /opt/immich /opt/openlist
install -d -m 0755 /srv/immich-data/immich
install -d -m 0700 /var/lib/immich-postgres

install -m 0644 "${repo_dir}/services/immich/docker-compose.yml" \
  /opt/immich/docker-compose.yml
install -m 0600 "${repo_dir}/services/immich/.env" /opt/immich/.env

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
  --env-file /opt/immich/.env config --quiet
docker compose -f /opt/openlist/docker-compose.yml \
  --env-file /opt/openlist/.env config --quiet

docker compose -f /opt/immich/docker-compose.yml \
  --env-file /opt/immich/.env pull
docker compose -f /opt/immich/docker-compose.yml \
  --env-file /opt/immich/.env up -d

docker compose -f /opt/openlist/docker-compose.yml \
  --env-file /opt/openlist/.env pull
docker compose -f /opt/openlist/docker-compose.yml \
  --env-file /opt/openlist/.env up -d

docker compose -f /opt/immich/docker-compose.yml ps
docker compose -f /opt/openlist/docker-compose.yml ps
