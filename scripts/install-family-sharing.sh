#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/storage.env"
webdav_secret=/home/ashton/.config/homeoss/family-webdav.htpasswd

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

apt-get update
apt-get install -y samba nfs-kernel-server apache2 apache2-utils

if [[ ! -s ${webdav_secret} ]]; then
  echo "Missing ${webdav_secret}; create it with htpasswd first." >&2
  exit 1
fi

getent group familyshare >/dev/null || groupadd --system familyshare
getent passwd ashton >/dev/null && usermod -aG familyshare ashton
usermod -aG familyshare www-data
install -d -m 2770 -o root -g familyshare /srv/family-share
if ! findmnt --mountpoint "${STORAGE_ROOT}" >/dev/null; then
  echo "Refusing to share files: ${STORAGE_ROOT} is not mounted." >&2
  exit 1
fi
install -d -m 2770 -o ashton -g familyshare "${STORAGE_ROOT}/file-backup"
install -d -m 0755 /etc/homeoss
install -m 0644 "${repo_dir}/config/storage.env" /etc/homeoss/storage.env

sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/samba/family-share.conf" >/etc/samba/smb.conf
chmod 0644 /etc/samba/smb.conf
install -d -m 0755 /etc/exports.d
sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/nfs/family-share.exports" \
  >/etc/exports.d/family-share.exports
chmod 0644 /etc/exports.d/family-share.exports
install -m 0644 "${repo_dir}/sharing/apache/ports.conf" \
  /etc/apache2/ports.conf
sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/apache/family-webdav.conf" \
  >/etc/apache2/sites-available/family-webdav.conf
chmod 0644 /etc/apache2/sites-available/family-webdav.conf
install -m 0640 -o root -g www-data "${webdav_secret}" \
  /etc/apache2/family-webdav.htpasswd

a2enmod dav dav_fs auth_basic alias
a2dissite 000-default
a2ensite family-webdav

testparm -s
exportfs -ra
apache2ctl configtest
systemctl disable --now samba-ad-dc.service 2>/dev/null || true
systemctl enable --now smbd nmbd nfs-server apache2
systemctl restart smbd nmbd nfs-server apache2
