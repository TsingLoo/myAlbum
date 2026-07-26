#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/storage.env"
source "${repo_dir}/config/schedules.env"
secret_dir=/home/ashton/.config/homeoss
secret_file=${secret_dir}/kopia.env
compose_file=/opt/kopia/docker-compose.yml

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if ! findmnt --mountpoint "${STORAGE_ROOT}" >/dev/null; then
  echo "Refusing to install: ${STORAGE_ROOT} is not mounted." >&2
  exit 1
fi

getent group familyshare >/dev/null || groupadd --system familyshare
getent passwd ashton >/dev/null || {
  echo "The ashton account does not exist." >&2
  exit 1
}
usermod -aG familyshare ashton

install -d -m 2770 -o ashton -g familyshare "${STORAGE_ROOT}/file-backup"
install -d -m 0755 /etc/homeoss /opt/kopia
install -m 0644 "${repo_dir}/config/storage.env" /etc/homeoss/storage.env
install -d -m 0700 -o ashton -g ashton \
  /opt/kopia/config /opt/kopia/cache /opt/kopia/logs
install -d -m 0700 -o ashton -g ashton "${STORAGE_ROOT}/kopia-repository"
install -d -m 0700 -o ashton -g ashton "${secret_dir}"

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
  echo "Generated Kopia credentials in ${secret_file}."
fi

install -m 0644 "${repo_dir}/services/kopia/docker-compose.yml" "${compose_file}"

compose=(docker compose -f "${compose_file}"
  --env-file /etc/homeoss/storage.env --env-file "${secret_file}")
"${compose[@]}" config --quiet
"${compose[@]}" pull

if [[ ! -s /opt/kopia/config/repository.config ]]; then
  "${compose[@]}" run --rm --no-deps kopia \
    repository create filesystem --path=/repository
fi

"${compose[@]}" run --rm --no-deps kopia policy set /data \
  --compression=zstd \
  --keep-latest=10 \
  --keep-daily=7 \
  --keep-weekly=8 \
  --keep-monthly=12 \
  --keep-annual=3 \
  --snapshot-time="${KOPIA_LOCAL_SNAPSHOT_TIME}" \
  --run-missed=true

"${compose[@]}" up -d

# Create the first snapshot even when the upload directory is still empty.
"${compose[@]}" exec -T kopia kopia snapshot create /data

"${compose[@]}" ps
echo "Kopia UI: http://myhome.server:51515"
echo "Username: ashton"
echo "Password file: ${secret_file}"
