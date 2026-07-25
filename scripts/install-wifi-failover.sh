#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ ! -s /etc/wpa_supplicant/wpa_supplicant-wlo2.conf ]]; then
  echo "Create /etc/wpa_supplicant/wpa_supplicant-wlo2.conf first." >&2
  exit 1
fi

install -m 0644 "${repo_dir}/network/interfaces.d/wlo2" \
  /etc/network/interfaces.d/wlo2
install -m 0750 "${repo_dir}/scripts/wired-wifi-failover.sh" \
  /usr/local/sbin/wired-wifi-failover
install -m 0644 "${repo_dir}/systemd/wired-wifi-failover.service" \
  /etc/systemd/system/wired-wifi-failover.service

systemctl daemon-reload
systemctl enable --now wired-wifi-failover.service
