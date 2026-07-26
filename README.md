# homeOSS

Reproducible configuration for the Debian home photo server at
`192.168.30.136`.

## Services

- Debian 13 on the internal SSD
- Docker Engine and Docker Compose
- Immich on port `2283`
- OpenList on port `5244`
- Shared storage on an ext4 USB disk mounted at `/srv/hdd_storage`
- UUID-based systemd automount and udev recovery after USB disk reinsertion
- PostgreSQL data on the internal SSD at `/var/lib/immich-postgres`
- Pinned Immich release and machine-learning model selection
- LAN share on the internal SSD at `/srv/lan-share`
- Backup working data on the external disk at `/srv/hdd_storage/.backup-work`
- SMB, NFS, WebDAV, and SFTP access to the family share
- Kopia snapshots of `/srv/hdd_storage/file-backup`
- Healthchecks dashboard for scheduled jobs on port `8000`

No passwords, cloud tokens, databases, photos, or generated backups belong in
this repository.

The external-disk mount point is defined once in `config/storage.env`.
Deployment installs the same configuration at `/etc/homeoss/storage.env`;
scripts and Compose files consume `STORAGE_ROOT` from it.

All scheduled-job times are defined once in `config/schedules.env`. Installers
render systemd timers and Healthchecks Cron expressions from it. Apply the
OpenWrt schedule from the repository workstation with:

```bash
./scripts/install-openwrt-schedule.py
```

## Cloud backup

`scripts/immich-cloud-backup.sh` creates a consistent PostgreSQL dump, archives
the critical Immich originals and configuration, encrypts the stream with Age,
splits it into 1 GiB parts, and uploads through the OpenList HTTP API.

Install the systemd timer with:

```bash
sudo ./scripts/install-backup-service.sh
```

The timer runs every Tuesday at 02:45 with a random delay of up to 30 minutes.

## Fresh-machine recovery

Before replacing the server, create an Age identity and save an encrypted
runtime-state bundle somewhere separate from both the server and Git:

```bash
age-keygen -o homeoss-recovery.identity
sudo ./scripts/backup-host-state.sh \
  /path/to/homeoss-state.tar.age \
  "$(age-keygen -y homeoss-recovery.identity)"
```

The backup briefly stops HomeOSS containers so PostgreSQL and SQLite are
captured consistently. Photos and the Kopia repository remain on the external
data disk and are not duplicated into this bundle.

On a fresh Debian 13 installation, clone this repository, attach the existing
ext4 data disk, copy the encrypted bundle and identity to the machine, then run
one command:

```bash
sudo ./scripts/install-all.sh /dev/sdb1 \
  /path/to/homeoss-state.tar.age \
  /path/to/homeoss-recovery.identity
```

The installer mounts but never formats the disk. It restores private runtime
configuration, deploys Immich and OpenList, and installs sharing, Kopia,
off-site replication, Healthchecks, timers, hotplug recovery, and optional
Wi-Fi failover. Run `scripts/install-openwrt-schedule.py` from a trusted
workstation afterward to apply the router cron configuration.

See [docs/restore.md](docs/restore.md) for the full restore order.
See [docs/immich-ai.md](docs/immich-ai.md) for AI model and state persistence.

## File backup

Files placed in the `FileBackup` share are snapshotted by Kopia every day
at 03:30. Install Kopia and create its encrypted repository with:

```bash
sudo ./scripts/install-kopia.sh
```

The web interface is then available at `http://myhome.server:51515`. Runtime
credentials are generated in `/home/ashton/.config/homeoss/kopia.env` and must
not be committed. See [docs/file-backup.md](docs/file-backup.md).

Replicate the encrypted Kopia repository to China Mobile Cloud through
OpenList with:

```bash
sudo ./scripts/install-kopia-cloud-sync.sh
```

Install the local scheduled-task dashboard with:

```bash
sudo ./scripts/install-healthchecks.sh
```

The dashboard is available at `http://myhome.server:8000`.

## Updating the live server

Configuration in Git is the source of truth. After reviewing changes:

```bash
sudo ./scripts/deploy.sh
```

Do not edit files inside Immich's media directories. Manage assets only through
Immich.
