#!/usr/bin/env bash
set -Eeuo pipefail

readonly storage_config=${HOMEOSS_STORAGE_CONFIG:-/etc/homeoss/storage.env}
source "${storage_config}"
readonly media_root=${STORAGE_ROOT}/immich
readonly media_archive_root=${media_root#/}
readonly immich_config=/opt/immich
readonly secret_file=/home/ashton/.config/homeoss/openlist-backup.env
readonly age_identity=/home/ashton/.config/homeoss/backup-age-key.txt
readonly age_recipient=/home/ashton/.config/homeoss/backup-age-recipient.txt
readonly report_sender=/usr/local/sbin/send-backup-report
readonly backup_logger=/usr/local/sbin/append-backup-log
readonly ping_secret=/home/ashton/.config/homeoss/healthchecks-pings.env
readonly ping_helper=/usr/local/lib/homeoss/healthchecks-ping.sh
# Keep large transient archives off the internal system SSD.
readonly work_root=${STORAGE_ROOT}/.backup-work
readonly success_state=/var/lib/homeoss/immich-cloud-backup.last-success
readonly generation="immich-$(date +%Y-%m-%dT%H%M%S)"
readonly work_dir="${work_root}/${generation}"
readonly parts_dir="${work_dir}/parts"

server_stopped=0
stage=initialization
start_epoch=$(date +%s)
upload_start_epoch=0
upload_end_epoch=0
photo_count=0
video_count=0
source_bytes=0
archive_bytes=0

exec 9>/run/lock/homeoss-immich-backup.lock
if ! flock --nonblock 9; then
  echo "Another Immich backup is already running." >&2
  exit 1
fi

if [[ -r ${ping_secret} && -r ${ping_helper} ]]; then
  source "${ping_secret}"
  source "${ping_helper}"
  healthchecks_ping "${HEALTHCHECK_IMMICH_FULL_CLOUD_BACKUP_URL:-}" /start
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

format_duration() {
  local seconds=$1
  printf '%02d:%02d:%02d' \
    "$((seconds / 3600))" "$(((seconds % 3600) / 60))" "$((seconds % 60))"
}

finish() {
  local result=$?
  local end_epoch
  local status
  local upload_seconds=0

  trap - EXIT
  restart_immich
  end_epoch=$(date +%s)
  if [[ ${upload_start_epoch} -gt 0 ]]; then
    if [[ ${upload_end_epoch} -eq 0 ]]; then
      upload_end_epoch=${end_epoch}
    fi
    upload_seconds=$((upload_end_epoch - upload_start_epoch))
  fi

  if [[ ${result} -eq 0 ]]; then
    status=SUCCESS
  else
    status=FAILED
  fi

  if [[ -x ${backup_logger} ]]; then
    "${backup_logger}" immich-full-cloud-backup "${status}" \
      "generation=${generation} stage=${stage}" || true
  fi

  if declare -F healthchecks_ping >/dev/null; then
    healthchecks_ping "${HEALTHCHECK_IMMICH_FULL_CLOUD_BACKUP_URL:-}" \
      "/${result}"
  fi

  if [[ -x ${report_sender} ]]; then
    if ! "${report_sender}" "[Immich backup] ${status} - ${generation}" <<EOF
Immich cloud backup report

Status: ${status}
Generation: ${generation}
Host: $(hostname)
Finished stage: ${stage}
Exit code: ${result}
Photos: ${photo_count}
Videos: ${video_count}
Source size: $(numfmt --to=iec-i --suffix=B "${source_bytes}")
Encrypted upload size: $(numfmt --to=iec-i --suffix=B "${archive_bytes}")
Upload duration: $(format_duration "${upload_seconds}")
Total duration: $(format_duration "$((end_epoch - start_epoch))")
Completed at: $(date --iso-8601=seconds)
EOF
    then
      log "Warning: failed to send Outlook report"
    fi
  else
    log "Warning: report sender is not installed"
  fi
  exit "${result}"
}

trap finish EXIT

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

for path in "${media_root}" "${immich_config}/.env" "${secret_file}" \
  "${age_identity}" "${age_recipient}"; do
  if [[ ! -e ${path} ]]; then
    echo "Required path is missing: ${path}" >&2
    exit 1
  fi
done

if ! findmnt --mountpoint "${STORAGE_ROOT}" >/dev/null; then
  echo "${STORAGE_ROOT} is not mounted; refusing to back up." >&2
  exit 1
fi

install -d -m 0700 "${parts_dir}"

stage=collecting-statistics
photo_count=$(find \
  "${media_root}/library" "${media_root}/upload" \
  -type f \( \
    -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o \
    -iname '*.heic' -o -iname '*.heif' -o -iname '*.webp' -o \
    -iname '*.gif' -o -iname '*.tif' -o -iname '*.tiff' -o \
    -iname '*.dng' -o -iname '*.raw' -o -iname '*.cr2' -o \
    -iname '*.cr3' -o -iname '*.nef' -o -iname '*.arw' \
  \) -printf . | wc -c)
video_count=$(find \
  "${media_root}/library" "${media_root}/upload" \
  -type f \( \
    -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' -o \
    -iname '*.avi' -o -iname '*.mkv' -o -iname '*.webm' -o \
    -iname '*.3gp' -o -iname '*.mts' -o -iname '*.m2ts' -o \
    -iname '*.mpg' -o -iname '*.mpeg' \
  \) -printf . | wc -c)
source_bytes=$(du -sb \
  "${media_root}/library" "${media_root}/upload" "${media_root}/profile" |
  awk '{total += $1} END {print total + 0}')

set -a
# shellcheck disable=SC1090
source "${immich_config}/.env"
# shellcheck disable=SC1090
source "${secret_file}"
set +a

login_payload=$(python3 -c \
  'import json,os; print(json.dumps({"username":os.environ["OPENLIST_USERNAME"],"password":os.environ["OPENLIST_PASSWORD"]}))')
token=$(curl -fsS "${OPENLIST_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  --data "${login_payload}" |
  python3 -c \
    'import json,sys; d=json.load(sys.stdin); assert d["code"]==200,d; print(d["data"]["token"])')

stage=database-dump
log "Stopping Immich writes for a consistent snapshot"
docker stop immich_server >/dev/null
server_stopped=1

log "Creating PostgreSQL dump"
docker exec immich_postgres pg_dump \
  --clean --if-exists \
  --username="${DB_USERNAME}" \
  --dbname="${DB_DATABASE_NAME}" |
  gzip -1 >"${work_dir}/database.sql.gz"

restart_immich

{
  printf 'generation=%s\n' "${generation}"
  printf 'created=%s\n' "$(date --iso-8601=seconds)"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'immich_version=%s\n' "${IMMICH_VERSION}"
  printf 'age_recipient=%s\n' "$(cat "${age_recipient}")"
} >"${work_dir}/backup-info.txt"

stage=archive
log "Archiving originals, database, and deployment configuration while Immich is online"
tar \
  -c \
  --numeric-owner \
  --warning=no-file-changed \
  -C / \
  "${media_archive_root}/library" \
  "${media_archive_root}/upload" \
  "${media_archive_root}/profile" \
  "${media_archive_root}/backups" \
  opt/immich \
  etc/fstab \
  -C "${work_dir}" \
  database.sql.gz \
  backup-info.txt |
  zstd -1 -T0 |
  age -R "${age_recipient}" |
  split -b 1G -d -a 3 - \
    "${parts_dir}/${generation}.tar.zst.age.part-"

restart_immich

(cd "${parts_dir}" && sha256sum ./* >SHA256SUMS)
cp "${work_dir}/backup-info.txt" "${parts_dir}/"
archive_bytes=$(find "${parts_dir}" -type f -name '*.part-*' -printf '%s\n' |
  awk '{total += $1} END {print total + 0}')

stage=creating-cloud-directory
cloud_dir="/${generation}"
mkdir_payload=$(python3 -c \
  'import json,sys; print(json.dumps({"path":sys.argv[1]}))' "${cloud_dir}")
curl -fsS "${OPENLIST_URL}/api/fs/mkdir" \
  -H "Authorization: ${token}" \
  -H "Content-Type: application/json" \
  --data "${mkdir_payload}" |
  python3 -c \
    'import json,sys; d=json.load(sys.stdin); assert d["code"]==200,d'

upload_file() {
  local source=$1
  local destination="${cloud_dir}/$(basename "${source}")"
  local encoded
  encoded=$(python3 -c \
    'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1],safe="/"))' \
    "${destination}")
  log "Uploading $(basename "${source}")"
  curl -fsS --retry 8 --retry-all-errors \
    -X PUT "${OPENLIST_URL}/api/fs/put" \
    -H "Authorization: ${token}" \
    -H "File-Path: ${encoded}" \
    -H "As-Task: false" \
    -H "Expect:" \
    --data-binary "@${source}" |
    python3 -c \
      'import json,sys; d=json.load(sys.stdin); assert d["code"]==200,d'
}

stage=upload
upload_start_epoch=$(date +%s)
for part in "${parts_dir}"/*.part-*; do
  upload_file "${part}"
done
upload_file "${parts_dir}/SHA256SUMS"
upload_file "${parts_dir}/backup-info.txt"
upload_end_epoch=$(date +%s)

stage=remote-verification
log "Upload completed; verifying remote file sizes"
list_payload=$(python3 -c \
  'import json,sys; print(json.dumps({"path":sys.argv[1],"page":1,"per_page":1000,"refresh":True}))' \
  "${cloud_dir}")
remote_json=$(curl -fsS "${OPENLIST_URL}/api/fs/list" \
  -H "Authorization: ${token}" \
  -H "Content-Type: application/json" \
  --data "${list_payload}")
python3 - "${parts_dir}" "${remote_json}" <<'PY'
import json
import pathlib
import sys

local_dir = pathlib.Path(sys.argv[1])
response = json.loads(sys.argv[2])
assert response["code"] == 200, response
remote = {item["name"]: item["size"] for item in response["data"]["content"]}
for path in local_dir.iterdir():
    if path.is_file():
        assert remote.get(path.name) == path.stat().st_size, (
            path.name,
            path.stat().st_size,
            remote.get(path.name),
        )
PY

log "Remote size verification passed"
stage=cleanup
rm -rf -- "${work_dir}"
stage=complete
install -d -m 0755 "$(dirname "${success_state}")"
touch "${success_state}"
log "Backup ${generation} completed successfully"
