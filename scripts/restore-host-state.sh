#!/usr/bin/env bash
set -Eeuo pipefail

bundle=${1:-}
identity=${2:-}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ ! -s ${bundle} || ! -s ${identity} ]]; then
  echo "Usage: $0 STATE.tar.age AGE_IDENTITY_FILE" >&2
  exit 1
fi

age --decrypt --identity "${identity}" "${bundle}" |
  tar --acls --xattrs --numeric-owner -C / -xf -

echo "HomeOSS runtime state restored."
