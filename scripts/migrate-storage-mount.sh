#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly old_mount=/srv/immich-data
source "${repo_dir}/config/storage.env"
readonly new_mount=${STORAGE_ROOT}
readonly disk_uuid=8551ca9f-2f26-4af4-8802-8628e5e0a7e8
readonly kopia_secret=/home/ashton/.config/homeoss/kopia.env

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if systemctl is-active --quiet immich-cloud-backup.service; then
  echo "Refusing to migrate while an Immich cloud backup is running." >&2
  exit 1
fi

device=$(findmnt -no SOURCE --mountpoint "${old_mount}" 2>/dev/null || true)
if [[ -n ${device} ]]; then
  mounted_uuid=$(blkid -s UUID -o value "${device}")
  if [[ ${mounted_uuid} != "${disk_uuid}" ]]; then
    echo "Refusing to migrate unexpected filesystem ${device} (${mounted_uuid})." >&2
    exit 1
  fi
fi

if [[ ! -d ${new_mount} ]]; then
  install -d -m 0755 "${new_mount}"
elif ! findmnt --mountpoint "${new_mount}" >/dev/null &&
  find "${new_mount}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  echo "Refusing to cover non-empty ${new_mount} with a mount." >&2
  exit 1
fi

docker stop immich_server kopia >/dev/null 2>&1 || true

if findmnt --mountpoint "${old_mount}" >/dev/null; then
  old_automount=$(systemd-escape --path --suffix=automount "${old_mount}")
  systemctl stop "${old_automount}" 2>/dev/null || true
  umount "${old_mount}"
fi

cp --archive /etc/fstab "/etc/fstab.pre-storage-migration.$(date +%Y%m%d-%H%M%S)"
sed -i "s#${old_mount}#${new_mount}#g" /etc/fstab
systemctl daemon-reload
mount "${new_mount}"

actual_uuid=$(findmnt -no UUID --mountpoint "${new_mount}")
if [[ ${actual_uuid} != "${disk_uuid}" ]]; then
  echo "Mounted UUID ${actual_uuid} does not match ${disk_uuid}." >&2
  exit 1
fi

getent group familyshare >/dev/null || groupadd --system familyshare
usermod -aG familyshare ashton
usermod -aG familyshare www-data
install -d -m 2770 -o ashton -g familyshare "${new_mount}/file-backup"
install -d -m 0700 -o ashton -g ashton "${new_mount}/kopia-repository"
install -d -m 0700 "${new_mount}/.backup-work"

if [[ -f /opt/immich/.env ]]; then
  sed -i "s#${old_mount}/immich#${new_mount}/immich#g" /opt/immich/.env
fi

install -m 0644 "${repo_dir}/services/kopia/docker-compose.yml" \
  /opt/kopia/docker-compose.yml
install -m 0644 "${repo_dir}/services/immich/docker-compose.yml" \
  /opt/immich/docker-compose.yml
install -m 0750 "${repo_dir}/scripts/immich-disk-hotplug.sh" \
  /usr/local/sbin/immich-disk-hotplug
install -m 0750 "${repo_dir}/scripts/immich-cloud-backup.sh" \
  /usr/local/sbin/immich-cloud-backup

install -d -m 0755 /etc/homeoss
install -m 0644 "${repo_dir}/config/storage.env" /etc/homeoss/storage.env
sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/samba/family-share.conf" >/etc/samba/smb.conf
sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/nfs/family-share.exports" \
  >/etc/exports.d/family-share.exports
sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/apache/family-webdav.conf" \
  >/etc/apache2/sites-available/family-webdav.conf
chmod 0644 /etc/samba/smb.conf /etc/exports.d/family-share.exports \
  /etc/apache2/sites-available/family-webdav.conf

docker compose -f /opt/immich/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file /opt/immich/.env \
  config --quiet
docker compose -f /opt/kopia/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file "${kopia_secret}" \
  config --quiet
testparm -s >/dev/null
apache2ctl configtest

exportfs -ra
systemctl restart smbd nmbd nfs-server apache2
docker compose -f /opt/immich/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file /opt/immich/.env up -d
docker compose -f /opt/kopia/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file "${kopia_secret}" up -d

findmnt "${new_mount}"
docker compose -f /opt/immich/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file /opt/immich/.env ps
docker compose -f /opt/kopia/docker-compose.yml \
  --env-file /etc/homeoss/storage.env --env-file "${kopia_secret}" ps
