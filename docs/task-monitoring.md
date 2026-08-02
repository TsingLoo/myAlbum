# Scheduled-task monitoring

Healthchecks provides a local dashboard at `http://myhome.server:8000`.
It monitors distributed jobs without replacing their native schedulers:

- OpenWrt cron
- Immich incremental Kopia backup systemd timer
- Immich Kopia cloud-replication systemd timer
- Immich monthly full-archive systemd timer
- Kopia local snapshots
- Kopia cloud repository synchronization

Runtime administrator credentials are stored in
`/home/ashton/.config/homeoss/healthchecks.env` with mode `0600`.
Private ping URLs are stored separately in
`/home/ashton/.config/homeoss/healthchecks-pings.env`.

Every monitored backup outcome is also appended to
`/var/lib/homeoss/backuplog.txt` and uploaded to `/backuplog.txt` at the
OpenList backup root. If OpenList is unavailable, the local entry remains and
the complete accumulated log is uploaded by the next backup event that can
reach OpenList.

Healthchecks uses SQLite at `/opt/healthchecks/data/hc.sqlite`. The dashboard is
available only on the home LAN and therefore cannot alert when the entire home
server or network is offline.

`config/schedules.env` is the single source of truth for task times, random
delays, and Healthchecks grace periods. Server installers render systemd timer
files and Healthchecks schedules from it. `scripts/install-openwrt-schedule.py`
converts the configured Hong Kong schedule to the router's UTC cron.
