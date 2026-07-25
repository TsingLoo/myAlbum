#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

install -m 0750 "${repo_dir}/scripts/immich-disk-hotplug.sh" \
  /usr/local/sbin/immich-disk-hotplug
install -m 0644 "${repo_dir}/systemd/immich-disk-hotplug.service" \
  /etc/systemd/system/immich-disk-hotplug.service
install -m 0644 "${repo_dir}/udev/99-immich-data-disk.rules" \
  /etc/udev/rules.d/99-immich-data-disk.rules

systemctl daemon-reload
udevadm control --reload-rules
