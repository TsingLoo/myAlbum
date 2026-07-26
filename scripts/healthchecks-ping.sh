#!/usr/bin/env bash

healthchecks_ping() {
  local url=${1:-}
  local suffix=${2:-}
  [[ -n ${url} ]] || return 0
  curl -fsS --connect-timeout 3 --max-time 10 \
    "${url}${suffix}" >/dev/null || true
}
