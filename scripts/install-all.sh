#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
device=${1:-}
state_bundle=${2:-}
age_identity=${3:-}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ -z ${device} ]]; then
  echo "Usage: $0 /dev/disk-partition [STATE.tar.age AGE_IDENTITY_FILE]" >&2
  exit 1
fi

if [[ -n ${state_bundle} || -n ${age_identity} ]]; then
  if [[ -z ${state_bundle} || -z ${age_identity} ]]; then
    echo "Provide both the encrypted state bundle and Age identity." >&2
    exit 1
  fi
fi

run_step() {
  local description=$1
  shift
  printf '\n==> %s\n' "${description}"
  "$@"
}

run_step "Install the Debian and Docker prerequisites" \
  "${repo_dir}/scripts/bootstrap-debian.sh"
run_step "Mount the existing HomeOSS storage disk" \
  "${repo_dir}/scripts/mount-data-disk.sh" "${device}"

if [[ -n ${state_bundle} ]]; then
  run_step "Restore encrypted runtime configuration" \
    "${repo_dir}/scripts/restore-host-state.sh" \
    "${state_bundle}" "${age_identity}"
fi

if [[ ! -s ${repo_dir}/services/immich/.env && ! -s /opt/immich/.env ]]; then
  echo "Missing Immich secrets. Restore a state bundle or create" >&2
  echo "${repo_dir}/services/immich/.env from .env.example." >&2
  exit 1
fi

run_step "Deploy Immich and OpenList" "${repo_dir}/scripts/deploy.sh"
run_step "Install storage hotplug recovery" \
  "${repo_dir}/scripts/install-disk-hotplug.sh"

if [[ -s /home/ashton/.config/homeoss/family-webdav.htpasswd ]]; then
  run_step "Install SMB, NFS, and WebDAV sharing" \
    "${repo_dir}/scripts/install-family-sharing.sh"
else
  echo "Skipping family sharing: WebDAV credentials were not restored."
fi

run_step "Install Kopia and its local snapshot policy" \
  "${repo_dir}/scripts/install-kopia.sh"
run_step "Install Syncthing" \
  "${repo_dir}/scripts/install-syncthing.sh"
run_step "Install Kopia cloud replication" \
  "${repo_dir}/scripts/install-kopia-cloud-sync.sh"
run_step "Install the Immich cloud-backup timer" \
  "${repo_dir}/scripts/install-backup-service.sh"
run_step "Install Healthchecks" \
  "${repo_dir}/scripts/install-healthchecks.sh"
run_step "Create checks and install monitored timers" \
  "${repo_dir}/scripts/install-task-monitoring.sh"

if [[ -s /etc/wpa_supplicant/wpa_supplicant-wlo2.conf ]]; then
  run_step "Install wired/Wi-Fi failover" \
    "${repo_dir}/scripts/install-wifi-failover.sh"
else
  echo "Skipping Wi-Fi failover: its WPA configuration was not restored."
fi

echo
echo "HomeOSS deployment completed."
echo "Apply the router schedule from a trusted workstation with:"
echo "  ./scripts/install-openwrt-schedule.py"
