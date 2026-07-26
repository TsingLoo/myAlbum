# Secrets and state

Git contains templates, not live credentials.

## Never commit

- `services/immich/.env`
- `services/openlist/.env`
- OpenList `data.db` and `config.json`
- China Mobile Cloud `Authorization`
- database dumps
- encryption identities or private keys
- photo and video archives

The repository `.gitignore` blocks the common forms, but always inspect
`git status` before committing.

## Required secret inventory

Store these in a password manager and in an offline recovery record:

- Debian administrator credentials
- Immich administrator credentials
- Immich `DB_PASSWORD`
- OpenList administrator credentials
- China Mobile Cloud account recovery details
- backup encryption private key
- `/home/ashton/.config/homeoss/kopia.env` (repository and web UI passwords)
- Wi-Fi PSKs in `/etc/wpa_supplicant/wpa_supplicant-wlo2.conf`
- Samba account database and the WebDAV htpasswd file

The encrypted cloud backup should include a copy of the exact Immich `.env`
used for that backup generation. Git should only contain `.env.example`.
## Tencent SES backup reports

The backup report sender reads Tencent CAM credentials from
`/home/ashton/.config/homeoss/tencent-ses.env`. Keep this file mode `0600` and
never commit it. The CAM user needs only permission to call `ses:SendEmail`.
# Secret and runtime-state recovery

Git contains only reproducible, non-secret configuration. The following state
must stay encrypted outside the repository:

- Immich database password and service environment
- Immich PostgreSQL data from the internal system disk
- OpenList database, users, mounts, and cloud authorization
- Kopia repository password and local repository connection configuration
- Healthchecks secret, administrator password, database, and ping URLs
- WebDAV and Samba password databases
- Optional Wi-Fi credentials and cloud-backup API credentials

Create an encrypted bundle before replacing or reinstalling the host:

```bash
age-keygen -o homeoss-recovery.identity
sudo ./scripts/backup-host-state.sh \
  /path/to/homeoss-state.tar.age \
  "$(age-keygen -y homeoss-recovery.identity)"
```

The command briefly stops the HomeOSS containers to produce a consistent
PostgreSQL and SQLite copy, then starts the containers that were running.

Do not store the identity beside the encrypted bundle. Restore both through
`scripts/install-all.sh`, as documented in the README.
