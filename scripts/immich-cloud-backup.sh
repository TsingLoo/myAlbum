#!/usr/bin/env bash
set -Eeuo pipefail

readonly media_root=/srv/immich-data/immich
readonly immich_config=/opt/immich
readonly secret_file=/home/ashton/.config/homeoss/openlist-backup.env
readonly age_identity=/home/ashton/.config/homeoss/backup-age-key.txt
readonly age_recipient=/home/ashton/.config/homeoss/backup-age-recipient.txt
readonly work_root=/var/backups/immich-cloud
readonly generation="immich-$(date +%Y-%m-%dT%H%M%S)"
readonly work_dir="${work_root}/${generation}"
readonly parts_dir="${work_dir}/parts"

server_stopped=0

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

trap restart_immich EXIT

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
  split -b 3900M -d -a 3 - \
    "${parts_dir}/${generation}.tar.zst.age.part-"

restart_immich

(cd "${parts_dir}" && sha256sum ./* >SHA256SUMS)
cp "${work_dir}/backup-info.txt" "${parts_dir}/"

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

for part in "${parts_dir}"/*.part-*; do
  upload_file "${part}"
done
upload_file "${parts_dir}/SHA256SUMS"
upload_file "${parts_dir}/backup-info.txt"

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
rm -rf -- "${work_dir}"
log "Backup ${generation} completed successfully"
