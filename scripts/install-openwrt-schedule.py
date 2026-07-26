#!/usr/bin/env python3
import datetime
import pathlib
import shlex
import subprocess
from zoneinfo import ZoneInfo

REPO_DIR = pathlib.Path(__file__).resolve().parent.parent
CONFIG = REPO_DIR / "config" / "schedules.env"
SERVER = "ashton@192.168.30.136"
ROUTER = "root@192.168.30.1"
SSH = [
    "ssh",
    "-F",
    "/dev/null",
    "-o",
    "UserKnownHostsFile=/tmp/homeoss-known-hosts",
    "-o",
    "StrictHostKeyChecking=accept-new",
]


def load_env(path: pathlib.Path) -> dict[str, str]:
    result = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, value = line.split("=", 1)
        result[key] = value
    return result


def run_ssh(host: str, command: str, *, input_text: str | None = None) -> str:
    completed = subprocess.run(
        [*SSH, host, command],
        input=input_text,
        text=True,
        check=True,
        capture_output=True,
    )
    return completed.stdout


config = load_env(CONFIG)
ping_url = run_ssh(
    SERVER,
    "source /home/ashton/.config/homeoss/healthchecks-pings.env; "
    'printf %s "$HEALTHCHECK_OPENWRT_SCHEDULED_JOB_URL"',
)

weekday_numbers = {
    "Mon": 0,
    "Tue": 1,
    "Wed": 2,
    "Thu": 3,
    "Fri": 4,
    "Sat": 5,
    "Sun": 6,
}
utc_schedules = []
hour, minute = map(int, config["OPENWRT_REBOOT_TIME"].split(":"))
local_tz = ZoneInfo(config["SCHEDULE_TIMEZONE"])

for name in config["OPENWRT_REBOOT_DAYS"].split(","):
    anchor = datetime.date(2026, 7, 27) + datetime.timedelta(
        days=weekday_numbers[name]
    )
    local = datetime.datetime.combine(
        anchor, datetime.time(hour, minute), tzinfo=local_tz
    )
    utc = local.astimezone(datetime.timezone.utc)
    utc_schedules.append(((utc.weekday() + 1) % 7, utc.hour, utc.minute))

current = run_ssh(ROUTER, "cat /etc/crontabs/root")
preserved = [
    line
    for line in current.splitlines()
    if "weekly scheduled reboot" not in line
]

managed = [
    (
        "# weekly scheduled reboot: "
        f"{config['OPENWRT_REBOOT_DAYS']} at "
        f"{config['OPENWRT_REBOOT_TIME']} {config['SCHEDULE_TIMEZONE']} "
        "(router clock is UTC)"
    )
]
for local_day, (utc_day, utc_hour, utc_minute) in zip(
    config["OPENWRT_REBOOT_DAYS"].split(","), utc_schedules
):
    managed.append(
        f"{utc_minute} {utc_hour} * * {utc_day} "
        f"/usr/bin/wget -qO /dev/null {shlex.quote(ping_url)}; "
        f"/sbin/reboot # weekly scheduled reboot, {local_day} "
        f"{config['OPENWRT_REBOOT_TIME']}"
    )

new_crontab = "\n".join([*preserved, *managed]).strip() + "\n"
run_ssh(ROUTER, "cat >/tmp/homeoss-root.cron", input_text=new_crontab)
run_ssh(
    ROUTER,
    "cp /etc/crontabs/root "
    "/etc/crontabs/root.bak.schedule-config && "
    "cp /tmp/homeoss-root.cron /etc/crontabs/root && "
    "chmod 0600 /etc/crontabs/root && "
    "/etc/init.d/cron restart",
)
print("OpenWrt schedule installed from config/schedules.env.")
