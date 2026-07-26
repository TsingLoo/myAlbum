#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
secret_dir=/home/ashton/.config/homeoss
secret_file=${secret_dir}/healthchecks.env
compose_file=/opt/healthchecks/docker-compose.yml

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

install -d -m 0755 /opt/healthchecks
install -d -m 0700 -o 999 -g 999 /opt/healthchecks/data
install -d -m 0700 -o ashton -g ashton "${secret_dir}"

if [[ ! -s ${secret_file} ]]; then
  secret_key=$(openssl rand -hex 32)
  admin_password=$(openssl rand -hex 24)
  {
    echo "HEALTHCHECKS_SECRET_KEY=${secret_key}"
    echo "HEALTHCHECKS_ADMIN_EMAIL=ashton@myhome.server"
    echo "HEALTHCHECKS_ADMIN_PASSWORD=${admin_password}"
  } >"${secret_file}"
  chown ashton:ashton "${secret_file}"
  chmod 0600 "${secret_file}"
fi

install -m 0644 "${repo_dir}/services/healthchecks/docker-compose.yml" \
  "${compose_file}"

compose=(docker compose -f "${compose_file}" --env-file "${secret_file}")
"${compose[@]}" config --quiet
"${compose[@]}" pull
"${compose[@]}" up -d
"${compose[@]}" exec -T healthchecks ./manage.py migrate --noinput
"${compose[@]}" restart healthchecks

set -a
# shellcheck disable=SC1090
source "${secret_file}"
set +a

for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:8000/api/v3/status/ >/dev/null; then
    break
  fi
  sleep 2
done

if ! curl -fsS http://127.0.0.1:8000/api/v3/status/ >/dev/null; then
  echo "Healthchecks did not become ready." >&2
  exit 1
fi

if ! "${compose[@]}" exec -T healthchecks \
  ./manage.py shell -c \
  "from django.contrib.auth import get_user_model; raise SystemExit(0 if get_user_model().objects.filter(email='${HEALTHCHECKS_ADMIN_EMAIL}').exists() else 1)"
then
  "${compose[@]}" exec -T healthchecks ./manage.py createsuperuser \
    --email "${HEALTHCHECKS_ADMIN_EMAIL}" \
    --password "${HEALTHCHECKS_ADMIN_PASSWORD}"
fi

"${compose[@]}" ps
echo "Healthchecks: http://myhome.server:8000"
echo "Credentials: ${secret_file}"
