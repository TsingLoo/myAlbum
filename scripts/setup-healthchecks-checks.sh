#!/usr/bin/env bash
set -Eeuo pipefail

readonly healthchecks_secret=/home/ashton/.config/homeoss/healthchecks.env
readonly ping_secret=/home/ashton/.config/homeoss/healthchecks-pings.env
readonly compose_file=/opt/healthchecks/docker-compose.yml
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/config/schedules.env"

cron_days() {
  local value=$1
  value=${value//Sun/0}
  value=${value//Mon/1}
  value=${value//Tue/2}
  value=${value//Wed/3}
  value=${value//Thu/4}
  value=${value//Fri/5}
  value=${value//Sat/6}
  printf '%s' "${value}"
}

immich_cron="$(printf '%s %s * * %s' \
  "${IMMICH_BACKUP_TIME#*:}" "${IMMICH_BACKUP_TIME%:*}" \
  "$(cron_days "${IMMICH_BACKUP_DAYS}")")"
kopia_local_cron="$(printf '%s %s * * *' \
  "${KOPIA_LOCAL_HEALTHCHECK_TIME#*:}" \
  "${KOPIA_LOCAL_HEALTHCHECK_TIME%:*}")"
kopia_cloud_cron="$(printf '%s %s * * %s' \
  "${KOPIA_CLOUD_SYNC_TIME#*:}" "${KOPIA_CLOUD_SYNC_TIME%:*}" \
  "$(cron_days "${KOPIA_CLOUD_SYNC_DAYS}")")"
openwrt_cron="$(printf '%s %s * * %s' \
  "${OPENWRT_REBOOT_TIME#*:}" "${OPENWRT_REBOOT_TIME%:*}" \
  "$(cron_days "${OPENWRT_REBOOT_DAYS}")")"

set -a
# shellcheck disable=SC1090
source "${healthchecks_secret}"
set +a

compose=(docker compose -f "${compose_file}"
  --env-file "${healthchecks_secret}")

python_code=$(
  printf '%s' \
    'from datetime import timedelta;' \
    'from django.contrib.auth import get_user_model;' \
    'from hc.accounts.models import Project;' \
    'from hc.api.models import Check;' \
    'u=get_user_model().objects.get(email="'"${HEALTHCHECKS_ADMIN_EMAIL}"'");' \
    'p,_=Project.objects.get_or_create(owner=u,name="HomeOSS Tasks");' \
    'specs=[' \
    '("immich_cloud_backup","Immich cloud backup",1296000,172800),' \
    '("kopia_local_snapshot","Kopia local snapshot",97200,10800),' \
    '("kopia_cloud_sync","Kopia cloud sync",97200,10800),' \
    '("openwrt_scheduled_job","OpenWrt scheduled job",97200,10800)' \
    '];' \
    'checks=[Check.objects.update_or_create(project=p,slug=slug,defaults={"name":name,"kind":"simple","timeout":timedelta(seconds=timeout),"grace":timedelta(seconds=grace)})[0] for slug,name,timeout,grace in specs];' \
    'i=next(c for c in checks if c.slug=="immich_cloud_backup");' \
    'i.kind="cron";i.schedule="'"${immich_cron}"'";i.tz="'"${SCHEDULE_TIMEZONE}"'";i.grace=timedelta(hours='"${IMMICH_HEALTHCHECK_GRACE_HOURS}"');i.save();' \
    'l=next(c for c in checks if c.slug=="kopia_local_snapshot");' \
    'l.kind="cron";l.schedule="'"${kopia_local_cron}"'";l.tz="'"${SCHEDULE_TIMEZONE}"'";l.grace=timedelta(minutes='"${KOPIA_LOCAL_HEALTHCHECK_GRACE_MINUTES}"');l.save();' \
    'k=next(c for c in checks if c.slug=="kopia_cloud_sync");' \
    'k.kind="cron";k.schedule="'"${kopia_cloud_cron}"'";k.tz="'"${SCHEDULE_TIMEZONE}"'";k.grace=timedelta(hours='"${KOPIA_CLOUD_HEALTHCHECK_GRACE_HOURS}"');k.save();' \
    'r=next(c for c in checks if c.slug=="openwrt_scheduled_job");' \
    'r.kind="cron";r.schedule="'"${openwrt_cron}"'";r.tz="'"${SCHEDULE_TIMEZONE}"'";r.grace=timedelta(minutes='"${OPENWRT_HEALTHCHECK_GRACE_MINUTES}"');r.save();' \
    'print("\n".join("HEALTHCHECK_"+c.slug.upper()+"_URL=http://192.168.30.136:8000/ping/"+str(c.code) for c in checks))'
)

umask 077
"${compose[@]}" exec -T healthchecks \
  ./manage.py shell --no-imports -c "${python_code}" >"${ping_secret}"
chmod 0600 "${ping_secret}"
chown ashton:ashton "${ping_secret}"

echo "Healthchecks checks created."
echo "Ping URLs saved to ${ping_secret}."
