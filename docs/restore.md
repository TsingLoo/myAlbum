# Restore procedure

## 1. Rebuild the host

Install Debian 13, clone this repository, run the bootstrap script, and mount
the existing ext4 media disk. Confirm the mount before starting Immich:

```bash
findmnt /srv/immich-data
```

Never allow Immich to write into an unmounted `/srv/immich-data` directory.

## 2. Deploy containers

Create `services/immich/.env` from the example, retaining the database
credentials stored with the encrypted backup. Run:

```bash
sudo ./scripts/deploy.sh
```

## 3. Restore Immich

Restore these folders to `/srv/immich-data/immich`:

- `upload`
- `library`
- `profile`
- `backups`

`thumbs` and `encoded-video` are optional and can be regenerated.

Use Immich's supported restore workflow to restore the matching `.sql.gz`
database dump. The filesystem and database must come from the same backup
generation. Restore the files first, then the database. The database also
restores Immich administrator settings, job state, face assignments, OCR
results, smart-search embeddings, albums, users, and asset metadata.

Machine-learning model files are a disposable Docker cache and are not included
in the cloud archive. The pinned models in the Compose file are downloaded
again automatically. See `docs/immich-ai.md`.

## 4. Restore OpenList

OpenList's `data.db` contains configuration and cloud authorization, so it is
excluded from Git. Either restore its separately encrypted configuration or
open `http://SERVER_IP:5244`, create a new administrator password, and
authorize China Mobile Cloud again.

## 5. Verify

```bash
cd /opt/immich && docker compose ps
cd /opt/openlist && docker compose ps
findmnt /srv/immich-data
```

Then inspect several old photos and videos in Immich before enabling scheduled
cloud backups.
