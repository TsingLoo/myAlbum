#!/usr/bin/env bash
set -Eeuo pipefail

readonly storage_config=${HOMEOSS_STORAGE_CONFIG:-/etc/homeoss/storage.env}
readonly sync_config=${KOPIA_SYNC_CONFIG:-/etc/homeoss/kopia-cloud-sync.env}
readonly openlist_secret=/home/ashton/.config/homeoss/openlist-backup.env
readonly kopia_secret=${KOPIA_SECRET:-/home/ashton/.config/homeoss/kopia.env}
readonly compose_file=${KOPIA_COMPOSE_FILE:-/opt/kopia/docker-compose.yml}
readonly kopia_service=${KOPIA_SERVICE:-kopia}
readonly report_name=${KOPIA_REPORT_NAME:-Kopia cloud sync}
readonly healthcheck_variable=${KOPIA_HEALTHCHECK_VARIABLE:-HEALTHCHECK_KOPIA_CLOUD_SYNC_URL}
readonly report_sender=/usr/local/sbin/send-backup-report
readonly backup_logger=/usr/local/sbin/append-backup-log
readonly ping_secret=/home/ashton/.config/homeoss/healthchecks-pings.env
readonly ping_helper=/usr/local/lib/homeoss/healthchecks-ping.sh
readonly lock_wait_seconds=7200

source "${storage_config}"
source "${sync_config}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

start_epoch=$(date +%s)
status=FAILED

if [[ -r ${ping_secret} && -r ${ping_helper} ]]; then
  source "${ping_secret}"
  source "${ping_helper}"
  healthchecks_ping "${!healthcheck_variable:-}" /start
fi

finish() {
  local result=$?
  local end_epoch
  trap - EXIT
  end_epoch=$(date +%s)
  if [[ ${result} -eq 0 ]]; then
    status=SUCCESS
  fi
  if [[ -x ${backup_logger} ]]; then
    "${backup_logger}" "${report_name// /-}" "${status}" \
      "cloud_path=${KOPIA_CLOUD_PATH} duration_seconds=$((end_epoch - start_epoch))" || true
  fi
  if declare -F healthchecks_ping >/dev/null; then
    healthchecks_ping "${!healthcheck_variable:-}" \
      "/${result}"
  fi
  if [[ -x ${report_sender} ]]; then
    "${report_sender}" "[${report_name}] ${status}" <<EOF || true
Kopia cloud repository synchronization

Status: ${status}
Host: $(hostname)
Cloud path: ${KOPIA_CLOUD_PATH}
Duration seconds: $((end_epoch - start_epoch))
Completed at: $(date --iso-8601=seconds)
EOF
  fi
  exit "${result}"
}
trap finish EXIT

exec 9>/run/lock/homeoss-kopia-cloud-sync.lock
if ! flock --timeout "${lock_wait_seconds}" 9; then
  echo "Timed out waiting for another Kopia cloud synchronization." >&2
  exit 1
fi

for path in "${storage_config}" "${sync_config}" "${openlist_secret}" \
  "${kopia_secret}" "${compose_file}"; do
  if [[ ! -r ${path} ]]; then
    echo "Required file is missing or unreadable: ${path}" >&2
    exit 1
  fi
done

if ! findmnt --mountpoint "${STORAGE_ROOT}" >/dev/null; then
  echo "${STORAGE_ROOT} is not mounted; refusing to synchronize." >&2
  exit 1
fi

if ! docker container inspect "${kopia_service}" >/dev/null 2>&1; then
  echo "The ${kopia_service} container does not exist." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${openlist_secret}"
set +a

webdav_url="${KOPIA_OPENLIST_URL%/}/dav${KOPIA_CLOUD_PATH}"

docker compose -f "${compose_file}" \
  --env-file "${storage_config}" --env-file "${kopia_secret}" \
  exec -T \
  -e KOPIA_SYNC_URL="${webdav_url}" \
  -e KOPIA_SYNC_USERNAME="${OPENLIST_USERNAME}" \
  -e KOPIA_SYNC_PASSWORD="${OPENLIST_PASSWORD}" \
  "${kopia_service}" sh -c '
    kopia repository sync-to webdav \
      --url="${KOPIA_SYNC_URL}" \
      --webdav-username="${KOPIA_SYNC_USERNAME}" \
      --webdav-password="${KOPIA_SYNC_PASSWORD}" \
      --parallel=2 \
      --no-progress
  '
