#!/usr/bin/env bash
set -Eeuo pipefail

output=${1:-}
recipient=${2:-}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ -z ${output} || -z ${recipient} ]]; then
  echo "Usage: $0 OUTPUT.tar.age AGE_RECIPIENT" >&2
  exit 1
fi

for command in age tar; do
  command -v "${command}" >/dev/null || {
    echo "Missing required command: ${command}" >&2
    exit 1
  }
done

state_paths=(
  home/ashton/.config/homeoss
  home/ashton/.config/syncthing
  home/ashton/.local/state/syncthing
  opt/immich/.env
  opt/openlist/.env
  opt/openlist/data
  opt/kopia/config
  opt/healthchecks/data
  var/lib/immich-postgres
  etc/wpa_supplicant/wpa_supplicant-wlo2.conf
  var/lib/samba/private/passdb.tdb
)

existing=()
for path in "${state_paths[@]}"; do
  [[ -e /${path} ]] && existing+=("${path}")
done

if ((${#existing[@]} == 0)); then
  echo "No HomeOSS runtime state was found." >&2
  exit 1
fi

umask 077
install -d -m 0700 "$(dirname -- "${output}")"

running_containers=()
if command -v docker >/dev/null; then
  for container in \
    immich_server immich_machine_learning immich_postgres immich_redis \
    openlist kopia healthchecks
  do
    if [[ $(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null) == true ]]; then
      running_containers+=("${container}")
    fi
  done
fi

restart_containers() {
  if ((${#running_containers[@]} > 0)); then
    docker start "${running_containers[@]}" >/dev/null
  fi
}
trap restart_containers EXIT

if ((${#running_containers[@]} > 0)); then
  echo "Temporarily stopping HomeOSS containers for a consistent backup."
  docker stop "${running_containers[@]}" >/dev/null
fi

tar --acls --xattrs --numeric-owner -C / -cf - "${existing[@]}" |
  age --encrypt --recipient "${recipient}" --output "${output}"

restart_containers
running_containers=()
trap - EXIT

echo "Encrypted runtime state written to ${output}."
echo "Keep the matching Age identity somewhere separate and private."
