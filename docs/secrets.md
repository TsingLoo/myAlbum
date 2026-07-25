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

The encrypted cloud backup should include a copy of the exact Immich `.env`
used for that backup generation. Git should only contain `.env.example`.
## Outlook backup reports

Copy `config/outlook-graph.env.example` to
`/home/ashton/.config/homeoss/outlook-graph.env`, add the Microsoft application
client ID, and set mode `0600`. Run
`sudo /usr/local/sbin/send-backup-report --authorize` once to grant delegated
`Mail.Send` access. The resulting refresh token is stored at
`/home/ashton/.config/homeoss/outlook-graph-token.json` with mode `0600`.
Never commit either live file.
