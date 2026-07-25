# homeOSS

Reproducible configuration for the Debian home photo server at
`192.168.30.136`.

## Services

- Debian 13 on the internal SSD
- Docker Engine and Docker Compose
- Immich on port `2283`
- OpenList on port `5244`
- Immich media on an ext4 USB disk mounted at `/srv/immich-data`
- UUID-based systemd automount and udev recovery after USB disk reinsertion
- PostgreSQL data on the internal SSD at `/var/lib/immich-postgres`

No passwords, cloud tokens, databases, photos, or generated backups belong in
this repository.

## Cloud backup

`scripts/immich-cloud-backup.sh` creates a consistent PostgreSQL dump, archives
the critical Immich originals and configuration, encrypts the stream with Age,
splits it into 1 GiB parts, and uploads through the OpenList HTTP API.

Install the systemd timer with:

```bash
sudo ./scripts/install-backup-service.sh
```

The timer runs every Tuesday at 03:00 with a random delay of up to 30 minutes.

## Fresh-machine recovery

1. Install Debian 13 with the SSH server and standard system utilities.
2. Clone this repository.
3. Run `sudo ./scripts/bootstrap-debian.sh`.
4. Attach the media disk and run:

   ```bash
   sudo ./scripts/mount-data-disk.sh /dev/sdb1
   ```

   This script only mounts an existing ext4 filesystem; it does not format it.
5. Copy the secret templates and fill them locally:

   ```bash
   cp services/immich/.env.example services/immich/.env
   ```

6. Run `sudo ./scripts/deploy.sh`.
7. Restore the Immich media folders and a matching database dump.
8. Log in to OpenList and authorize China Mobile Cloud again, or restore an
   encrypted OpenList configuration backup outside Git.

See [docs/restore.md](docs/restore.md) for the full restore order.

## Updating the live server

Configuration in Git is the source of truth. After reviewing changes:

```bash
sudo ./scripts/deploy.sh
```

Do not edit files inside Immich's media directories. Manage assets only through
Immich.
