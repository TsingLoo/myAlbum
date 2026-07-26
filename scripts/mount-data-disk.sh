#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
storage_config=${HOMEOSS_STORAGE_CONFIG:-${repo_dir}/config/storage.env}
source "${storage_config}"

device=${1:-}
mountpoint=${STORAGE_ROOT}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ -z ${device} || ! -b ${device} ]]; then
  echo "Usage: $0 /dev/disk-partition" >&2
  exit 1
fi

fstype=$(blkid -s TYPE -o value "${device}")
if [[ ${fstype} != ext4 ]]; then
  echo "Refusing to mount ${device}: expected ext4, found ${fstype:-unknown}." >&2
  exit 1
fi

uuid=$(blkid -s UUID -o value "${device}")
if [[ -z ${uuid} ]]; then
  echo "Could not determine filesystem UUID." >&2
  exit 1
fi

install -d -m 0755 "${mountpoint}"
entry="UUID=${uuid} ${mountpoint} ext4 defaults,noatime,nofail,x-systemd.automount,x-systemd.device-bound,x-systemd.device-timeout=10s 0 2"

if ! grep -qE "[[:space:]]${mountpoint//\//\\/}[[:space:]]" /etc/fstab; then
  printf '%s\n' "${entry}" >>/etc/fstab
fi

mount "${mountpoint}" 2>/dev/null || mount -a
findmnt "${mountpoint}"
