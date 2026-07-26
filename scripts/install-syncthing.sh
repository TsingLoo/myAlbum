#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

apt-get update
apt-get install -y syncthing openssl

sync_root=/home/ashton/Sync
install -d -m 0750 -o ashton -g ashton "${sync_root}"
install -d -m 0700 -o ashton -g ashton /home/ashton/.config/homeoss

credentials=/home/ashton/.config/homeoss/syncthing.env
if [[ ! -s ${credentials} ]]; then
  umask 077
  gui_password=$(openssl rand -base64 24)
  {
    printf 'SYNCTHING_GUI_USER=%q\n' "ashton"
    printf 'SYNCTHING_GUI_PASSWORD=%q\n' "${gui_password}"
  } >"${credentials}"
  chown ashton:ashton "${credentials}"
fi

systemctl enable --now syncthing@ashton.service

for _ in {1..30}; do
  if runuser -u ashton -- syncthing cli show system >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# shellcheck disable=SC1090
source "${credentials}"
runuser -u ashton -- syncthing cli config gui user set \
  "${SYNCTHING_GUI_USER}"
runuser -u ashton -- syncthing cli config gui password set \
  "${SYNCTHING_GUI_PASSWORD}"
runuser -u ashton -- syncthing cli config gui raw-address set \
  "0.0.0.0:8384"

systemctl restart syncthing@ashton.service
systemctl --no-pager --full status syncthing@ashton.service

echo
echo "Syncthing is available at http://myhome.server:8384"
echo "Credentials are stored in ${credentials}."
echo "The data directory is ${sync_root} on the internal SSD."
