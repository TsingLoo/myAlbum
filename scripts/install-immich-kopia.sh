#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/storage.env"
secret_dir=/home/ashton/.config/homeoss
secret_file=${secret_dir}/kopia-immich.env
compose_dir=/opt/kopia-immich
compose_file=${compose_dir}/docker-compose.yml

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if ! findmnt --mountpoint "${STORAGE_ROOT}" >/dev/null; then
  echo "Refusing to install: ${STORAGE_ROOT} is not mounted." >&2
  exit 1
fi

install -d -m 0755 /etc/homeoss "${compose_dir}"
install -m 0644 "${repo_dir}/config/storage.env" /etc/homeoss/storage.env
install -d -m 0700 -o ashton -g ashton \
  "${compose_dir}/config" "${compose_dir}/cache" "${compose_dir}/logs"
install -d -m 0700 -o ashton -g ashton \
  "${STORAGE_ROOT}/kopia-immich-repository" "${secret_dir}"

if [[ ! -s ${secret_file} ]]; then
  repository_password=$(openssl rand -hex 32)
  server_password=$(openssl rand -hex 24)
  {
    echo "KOPIA_PASSWORD=${repository_password}"
    echo "KOPIA_SERVER_USERNAME=ashton"
    echo "KOPIA_SERVER_PASSWORD=${server_password}"
  } >"${secret_file}"
  chown ashton:ashton "${secret_file}"
  chmod 0600 "${secret_file}"
fi

install -m 0644 \
  "${repo_dir}/services/kopia-immich/docker-compose.yml" "${compose_file}"
install -m 0644 "${repo_dir}/services/kopia-common.yml" /opt/kopia-common.yml
compose=(docker compose -f "${compose_file}"
  --env-file /etc/homeoss/storage.env --env-file "${secret_file}")
"${compose[@]}" config --quiet
"${compose[@]}" pull

if [[ ! -s ${compose_dir}/config/repository.config ]]; then
  "${compose[@]}" run --rm --no-deps kopia-immich \
    repository create filesystem --path=/repository
fi

"${compose[@]}" run --rm --no-deps kopia-immich policy set /immich \
  --compression=zstd \
  --keep-latest=10 \
  --keep-daily=7 \
  --keep-weekly=8 \
  --keep-monthly=12 \
  --keep-annual=3 \
  --add-ignore=data/thumbs \
  --add-ignore=data/encoded-video \
  --manual

"${compose[@]}" up -d
"${compose[@]}" ps
