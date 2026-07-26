# Scheduled-task monitoring

Healthchecks provides a local dashboard at `http://myhome.server:8000`.
It monitors distributed jobs without replacing their native schedulers:

- OpenWrt cron
- Immich cloud backup systemd timer
- Kopia local snapshots
- Kopia cloud repository synchronization

Runtime administrator credentials are stored in
`/home/ashton/.config/homeoss/healthchecks.env` with mode `0600`.
Private ping URLs are stored separately in
`/home/ashton/.config/homeoss/healthchecks-pings.env`.

Healthchecks uses SQLite at `/opt/healthchecks/data/hc.sqlite`. The dashboard is
available only on the home LAN and therefore cannot alert when the entire home
server or network is offline.

`config/schedules.env` is the single source of truth for task times, random
delays, and Healthchecks grace periods. Server installers render systemd timer
files and Healthchecks schedules from it. `scripts/install-openwrt-schedule.py`
converts the configured Hong Kong schedule to the router's UTC cron.
