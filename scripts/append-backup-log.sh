#!/usr/bin/env bash
set -Eeuo pipefail

readonly secret_file=/home/ashton/.config/homeoss/openlist-backup.env
readonly state_dir=/var/lib/homeoss
readonly log_file=${state_dir}/backuplog.txt
readonly raw_job=${1:?usage: append-backup-log JOB STATUS [DETAIL]}
readonly status=${2:?usage: append-backup-log JOB STATUS [DETAIL]}
detail=${3:-}
detail=${detail//$'\n'/ }
detail=${detail//$'\t'/ }

case ${raw_job} in
  Immich | Immich-Kopia-cloud-sync)
    readonly job=immich-kopia-cloud-sync
    ;;
  Kopia-cloud-sync)
    readonly job=filebackup-kopia-cloud-sync
    ;;
  *)
    readonly job=${raw_job}
    ;;
esac

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

exec 9>/run/lock/homeoss-backup-log.lock
flock 9

install -d -m 0755 "${state_dir}"
temp_log=$(mktemp "${state_dir}/backuplog.XXXXXX")
trap 'rm -f "${temp_log}"' EXIT

{
  printf '%-25s | %-7s | %-32s | %-16s | %s\n' \
    Timestamp Status Job Host Details
  printf '%-25s-+-%-7s-+-%-32s-+-%-16s-+-%s\n' \
    ------------------------- ------- -------------------------------- \
    ---------------- ----------------
  printf '%-25s | %-7s | %-32s | %-16s | %s\n' \
    "$(date --iso-8601=seconds)" "${status}" "${job}" "$(hostname)" \
    "${detail}"
  if [[ -s ${log_file} ]]; then
    if head -n 1 "${log_file}" | grep -q '^Timestamp .* | Status '; then
      tail -n +3 "${log_file}"
    else
      tac "${log_file}" |
        awk -F '\t' '
          BEGIN { OFS = "" }
          {
            job = $3
            if (job == "Immich") job = "immich-kopia-cloud-sync"
            if (job == "Immich-Kopia-cloud-sync")
              job = "immich-kopia-cloud-sync"
            if (job == "Kopia-cloud-sync")
              job = "filebackup-kopia-cloud-sync"
            host = $4
            sub(/^host=/, "", host)
            printf "%-25s | %-7s | %-32s | %-16s | %s\n",
              $1, $2, job, host, $5
          }
        '
    fi
  fi
} >"${temp_log}"

chmod 0644 "${temp_log}"
mv -f "${temp_log}" "${log_file}"
trap - EXIT

if [[ ! -r ${secret_file} ]]; then
  echo "Recorded locally; OpenList credentials are unavailable." >&2
  exit 1
fi

set -a
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

encoded_path=$(python3 -c \
  'import urllib.parse; print(urllib.parse.quote("/backuplog.txt",safe="/"))')
curl -fsS --retry 3 --retry-all-errors \
  -X PUT "${OPENLIST_URL}/api/fs/put" \
  -H "Authorization: ${token}" \
  -H "File-Path: ${encoded_path}" \
  -H "As-Task: false" \
  -H "Overwrite: true" \
  -H "Expect:" \
  --data-binary "@${log_file}" |
  python3 -c \
    'import json,sys; d=json.load(sys.stdin); assert d["code"]==200,d'

# Some storage drivers preserve the replaced object by appending four random
# characters to its name even when OpenList requests an overwrite. Remove only
# those driver-created copies after the new canonical file is safely uploaded.
list_response=$(curl -fsS --retry 3 --retry-all-errors \
  "${OPENLIST_URL}/api/fs/list" \
  -H "Authorization: ${token}" \
  -H "Content-Type: application/json" \
  --data '{"path":"/","password":"","page":1,"per_page":200,"refresh":true}')
remove_payload=$(python3 -c \
  'import json,re,sys
d=json.load(sys.stdin)
assert d["code"]==200,d
names=[x["name"] for x in (d.get("data") or {}).get("content",[])
       if re.fullmatch(r"backuplog[.]txt[A-Za-z0-9]{4}",x.get("name",""))]
print(json.dumps({"dir":"/","names":names}) if names else "")' \
  <<<"${list_response}")

if [[ -n ${remove_payload} ]]; then
  curl -fsS --retry 3 --retry-all-errors \
    "${OPENLIST_URL}/api/fs/remove" \
    -H "Authorization: ${token}" \
    -H "Content-Type: application/json" \
    --data "${remove_payload}" |
    python3 -c \
      'import json,sys; d=json.load(sys.stdin); assert d["code"]==200,d'
fi
