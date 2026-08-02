#!/usr/bin/env bash
set -Eeuo pipefail

readonly storage_config=${HOMEOSS_STORAGE_CONFIG:-/etc/homeoss/storage.env}
readonly immich_config=/opt/immich
readonly kopia_secret=/home/ashton/.config/homeoss/kopia-immich.env
readonly compose_file=/opt/kopia-immich/docker-compose.yml
readonly report_sender=/usr/local/sbin/send-backup-report
readonly backup_logger=/usr/local/sbin/append-backup-log
readonly ping_secret=/home/ashton/.config/homeoss/healthchecks-pings.env
readonly ping_helper=/usr/local/lib/homeoss/healthchecks-ping.sh

source "${storage_config}"
readonly media_root=${STORAGE_ROOT}/immich
readonly work_root=${STORAGE_ROOT}/.backup-work
readonly work_dir=${work_root}/immich-kopia
readonly dump_target=${media_root}/backups/homeoss-kopia-database.sql.gz
readonly info_target=${media_root}/backups/homeoss-kopia-backup-info.txt

server_stopped=0
stage=initialization
start_epoch=$(date +%s)

if [[ -r ${ping_secret} && -r ${ping_helper} ]]; then
  source "${ping_secret}"
  source "${ping_helper}"
  healthchecks_ping "${HEALTHCHECK_IMMICH_KOPIA_SNAPSHOT_URL:-}" /start
fi

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"
}

restart_immich() {
  if [[ ${server_stopped} -eq 1 ]]; then
    docker start immich_server >/dev/null
    server_stopped=0
    log "Immich server restarted"
  fi
}

finish() {
  local result=$?
  local status=FAILED
  trap - EXIT
  restart_immich
  [[ ${result} -eq 0 ]] && status=SUCCESS

  if [[ -x ${backup_logger} ]]; then
    "${backup_logger}" immich-kopia-backup "${status}" \
      "stage=${stage} duration_seconds=$(($(date +%s) - start_epoch))" || true
  fi

  if declare -F healthchecks_ping >/dev/null; then
    healthchecks_ping "${HEALTHCHECK_IMMICH_KOPIA_SNAPSHOT_URL:-}" \
      "/${result}"
  fi

  if [[ -x ${report_sender} ]]; then
    "${report_sender}" "[Immich Kopia backup] ${status}" <<EOF || true
Immich incremental backup report

Status: ${status}
Host: $(hostname)
Finished stage: ${stage}
Exit code: ${result}
Duration seconds: $(($(date +%s) - start_epoch))
Completed at: $(date --iso-8601=seconds)
EOF
  fi
  exit "${result}"
}
trap finish EXIT

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

exec 9>/run/lock/homeoss-immich-backup.lock
if ! flock --nonblock 9; then
  echo "Another Immich backup is already running." >&2
  exit 1
fi

for path in "${media_root}" "${immich_config}/.env" "${kopia_secret}" \
  "${compose_file}"; do
  if [[ ! -e ${path} ]]; then
    echo "Required path is missing: ${path}" >&2
    exit 1
  fi
done

if ! findmnt --mountpoint "${STORAGE_ROOT}" >/dev/null; then
  echo "${STORAGE_ROOT} is not mounted; refusing to back up." >&2
  exit 1
fi

install -d -m 0700 "${work_dir}"
install -d -m 0755 "${media_root}/backups"

set -a
# shellcheck disable=SC1090
source "${immich_config}/.env"
set +a

stage=database-dump
log "Stopping Immich writes for a consistent database dump"
docker stop immich_server >/dev/null
server_stopped=1

docker exec immich_postgres pg_dump \
  --clean --if-exists \
  --username="${DB_USERNAME}" \
  --dbname="${DB_DATABASE_NAME}" |
  gzip -1 >"${work_dir}/database.sql.gz"

{
  printf 'created=%s\n' "$(date --iso-8601=seconds)"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'immich_version=%s\n' "${IMMICH_VERSION}"
  printf 'backup_method=kopia\n'
  printf 'kopia_source=/immich\n'
} >"${work_dir}/backup-info.txt"

mv -f "${work_dir}/database.sql.gz" "${dump_target}"
mv -f "${work_dir}/backup-info.txt" "${info_target}"
restart_immich

stage=kopia-snapshot
log "Creating the incremental Kopia snapshot"
docker compose -f "${compose_file}" \
  --env-file "${storage_config}" --env-file "${kopia_secret}" \
  exec -T kopia-immich kopia snapshot create /immich

stage=complete
log "Immich Kopia backup completed successfully"
