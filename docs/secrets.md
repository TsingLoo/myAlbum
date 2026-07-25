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
