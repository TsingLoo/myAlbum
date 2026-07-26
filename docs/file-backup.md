# File backup with Kopia

## Upload folder

Put files to be protected in the dedicated external-disk share:

| Protocol | Address |
|---|---|
| SMB | `\\myhome.server\FileBackup` |
| NFS | `myhome.server:/srv/hdd_storage/file-backup` |
| WebDAV | `http://myhome.server:8080/file-backup/` |
| SFTP | `sftp://ashton@myhome.server/srv/hdd_storage/file-backup` |

The source directory is `/srv/hdd_storage/file-backup` on the external disk. Kopia
can read it but the container mounts it read-only.

## Backup repository

Encrypted snapshots are stored at
`/srv/hdd_storage/kopia-repository` on the external USB disk. The repository is
not a normal file tree; do not edit or delete its contents manually.

Kopia takes a snapshot daily at 03:30 and runs a missed snapshot after downtime.
The policy retains 10 latest, 7 daily, 8 weekly, 12 monthly, and 3 annual
snapshots. Compression and content deduplication are enabled.

Open `http://myhome.server:51515` on the home LAN to inspect snapshots or
restore files. The username is `ashton`. Read the generated UI password with:

```bash
sudo sed -n 's/^KOPIA_SERVER_PASSWORD=//p' \
  /home/ashton/.config/homeoss/kopia.env
```

The same file contains the repository encryption password. Keep an offline
copy in a password manager. Without that password, the repository cannot be
restored.

## Restore

Use the Kopia web interface to select a snapshot and restore individual files
or the entire source. To operate through the container:

```bash
sudo docker compose -f /opt/kopia/docker-compose.yml \
  --env-file /home/ashton/.config/homeoss/kopia.env \
  snapshot list /data
```

The external disk is a separate local copy, but it is still in the same home.
`kopia-cloud-sync.timer` replicates the encrypted repository to
`/kopia-repository` in China Mobile Cloud through OpenList every Sunday,
Monday, Wednesday, and Friday at 03:30, with a random delay of up to 30
minutes. Install it with:

```bash
sudo ./scripts/install-kopia-cloud-sync.sh
```

Synchronization is incremental and intentionally does not delete cloud blobs
that disappeared locally. This uses more cloud capacity over time, but retains
more recovery data if the local repository is damaged or unwanted deletions
are synchronized.
