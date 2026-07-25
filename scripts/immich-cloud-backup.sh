#!/usr/bin/env bash
set -Eeuo pipefail

readonly media_root=/srv/immich-data/immich
readonly immich_config=/opt/immich
readonly secret_file=/home/ashton/.config/homeoss/openlist-backup.env
readonly age_identity=/home/ashton/.config/homeoss/backup-age-key.txt
readonly age_recipient=/home/ashton/.config/homeoss/backup-age-recipient.txt
readonly report_sender=/usr/local/sbin/send-backup-report
readonly work_root=/var/backups/immich-cloud
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

if ! findmnt --mountpoint /srv/immich-data >/dev/null; then
  echo "/srv/immich-data is not mounted; refusing to back up." >&2
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
  srv/immich-data/immich/library \
  srv/immich-data/immich/upload \
  srv/immich-data/immich/profile \
  srv/immich-data/immich/backups \
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
log "Backup ${generation} completed successfully"
