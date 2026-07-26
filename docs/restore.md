# Restore procedure

## 1. Rebuild the host

Install Debian 13, clone this repository, attach the existing ext4 media disk,
and restore the encrypted runtime-state bundle with the all-in-one installer:

```bash
sudo ./scripts/install-all.sh /dev/sdb1 \
  /path/to/homeoss-state.tar.age \
  /path/to/homeoss-recovery.identity
```

The installer refuses to deploy before `/srv/hdd_storage` is mounted and never
formats the disk.

## 2. Deploy containers

The all-in-one installer restores the original service environments, OpenList
state, Kopia configuration, Healthchecks database, and PostgreSQL data before
deploying the containers.

## 3. Restore Immich

Restore these folders to `/srv/hdd_storage/immich`:

- `upload`
- `library`
- `profile`
- `backups`

`thumbs` and `encoded-video` are optional and can be regenerated.

The encrypted host-state bundle includes the consistent PostgreSQL directory.
If it is unavailable, use Immich's supported restore workflow with the matching
`.sql.gz` cloud backup. The filesystem and database must come from the same
backup generation.

Machine-learning model files are a disposable Docker cache and are not included
in the cloud archive. The pinned models in the Compose file are downloaded
again automatically. See `docs/immich-ai.md`.

## 4. Restore OpenList

OpenList's `data.db` contains configuration and cloud authorization. It is
restored from the encrypted host-state bundle. If that bundle is unavailable,
open `http://SERVER_IP:5244`, create a new administrator password, and
authorize China Mobile Cloud again.

## 5. Verify

```bash
cd /opt/immich && docker compose ps
cd /opt/openlist && docker compose ps
findmnt /srv/hdd_storage
```

Then inspect several old photos and videos in Immich before enabling scheduled
cloud backups.
