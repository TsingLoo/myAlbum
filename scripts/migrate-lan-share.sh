#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/storage.env"
old_path=/srv/family-share
new_path=/srv/lan-share

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ -e ${old_path} && -e ${new_path} ]]; then
  echo "Refusing to merge two existing directories:" >&2
  echo "  ${old_path}" >&2
  echo "  ${new_path}" >&2
  exit 1
fi

if [[ -d ${old_path} ]]; then
  mv "${old_path}" "${new_path}"
fi
install -d -m 2770 -o root -g familyshare "${new_path}"

sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/samba/family-share.conf" >/etc/samba/smb.conf
install -d -m 0755 /etc/exports.d
sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/nfs/family-share.exports" \
  >/etc/exports.d/family-share.exports
sed "s#@STORAGE_ROOT@#${STORAGE_ROOT}#g" \
  "${repo_dir}/sharing/apache/family-webdav.conf" \
  >/etc/apache2/sites-available/family-webdav.conf
chmod 0644 /etc/samba/smb.conf \
  /etc/exports.d/family-share.exports \
  /etc/apache2/sites-available/family-webdav.conf

testparm -s
exportfs -ra
apache2ctl configtest
systemctl restart smbd nmbd nfs-server apache2

echo "LAN share migrated to ${new_path}."
echo "SMB path: \\\\myhome.server\\LanShare"
