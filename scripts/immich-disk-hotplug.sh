#!/usr/bin/env bash
set -Eeuo pipefail

readonly mountpoint=/srv/immich-data
readonly media_root="${mountpoint}/immich"
readonly disk_uuid=8551ca9f-2f26-4af4-8802-8628e5e0a7e8
readonly markers=(backups encoded-video library profile thumbs upload)

log() {
  systemd-cat -t immich-disk-hotplug echo "$*"
}

for _ in {1..20}; do
  if [[ -e "/dev/disk/by-uuid/${disk_uuid}" ]]; then
    break
  fi
  sleep 1
done

if [[ ! -e "/dev/disk/by-uuid/${disk_uuid}" ]]; then
  log "Disk UUID ${disk_uuid} did not appear"
  exit 1
fi

if ! findmnt --mountpoint "${mountpoint}" >/dev/null; then
  mount "${mountpoint}"
fi

for directory in "${markers[@]}"; do
  if [[ ! -f "${media_root}/${directory}/.immich" ]]; then
    log "Refusing to start Immich: missing ${media_root}/${directory}/.immich"
    exit 1
  fi
done

if docker container inspect immich_server >/dev/null 2>&1; then
  docker restart immich_server >/dev/null
  log "Disk mounted and Immich restarted"
fi
