#!/usr/bin/env bash
set -Eeuo pipefail

readonly secret_dir=/home/ashton/.config/homeoss
readonly secret_file=${secret_dir}/openlist-admin.env

if ! docker container inspect openlist >/dev/null 2>&1; then
  echo "The OpenList container is not running." >&2
  exit 1
fi

admin_password=$(openssl rand -hex 24)
docker exec openlist ./openlist admin set "${admin_password}" >/dev/null

install -d -m 0700 "${secret_dir}"
umask 077
{
  echo "OPENLIST_ADMIN_USERNAME=admin"
  echo "OPENLIST_ADMIN_PASSWORD=${admin_password}"
} >"${secret_file}"
chmod 0600 "${secret_file}"

echo "OpenList administrator password reset."
echo "Credentials saved to ${secret_file}."
