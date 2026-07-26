#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y age ca-certificates curl gnupg openssl rclone rsync zstd

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

install -d -m 0755 /etc/homeoss /opt/immich /opt/openlist
install -m 0644 "${repo_dir}/config/storage.env" /etc/homeoss/storage.env
install -m 0644 "${repo_dir}/config/schedules.env" /etc/homeoss/schedules.env
install -d -m 0700 /var/lib/immich-postgres
getent group familyshare >/dev/null || groupadd --system familyshare
getent passwd ashton >/dev/null && usermod -aG familyshare ashton
if [[ -d /srv/family-share && ! -e /srv/lan-share ]]; then
  mv /srv/family-share /srv/lan-share
fi
install -d -m 2770 -o root -g familyshare /srv/lan-share

echo "Docker installation complete."
