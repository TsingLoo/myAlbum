#!/usr/bin/env bash
set -uo pipefail

readonly wired_interface=eno1
readonly wifi_interface=wlo2
readonly poll_seconds=5

log() {
  logger -t wired-wifi-failover -- "$*"
}

wifi_is_configured() {
  ifquery --state "${wifi_interface}" >/dev/null 2>&1
}

disable_wifi() {
  if wifi_is_configured; then
    log "Wired carrier detected; disabling ${wifi_interface}"
    ifdown --force "${wifi_interface}" || true
  else
    ip link set "${wifi_interface}" down 2>/dev/null || true
  fi
}

enable_wifi() {
  if ! wifi_is_configured; then
    log "No wired carrier; enabling ${wifi_interface}"
    rfkill unblock wifi
    ifup "${wifi_interface}" || {
      log "Failed to enable ${wifi_interface}; will retry"
      ifdown --force "${wifi_interface}" 2>/dev/null || true
    }
  fi
}

trap disable_wifi EXIT

while true; do
  if [[ $(cat "/sys/class/net/${wired_interface}/carrier" 2>/dev/null) == 1 ]]; then
    disable_wifi
  else
    enable_wifi
  fi
  sleep "${poll_seconds}"
done
