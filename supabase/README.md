# CursiveRoot — Database Backups & Durability

CursiveRoot is the project's Supabase Postgres database (project ref
`iovvktpuoinmjdgfxgvm`). It is the system of record for run telemetry, the Layer 5
ledger, accounts, and governance state.

It runs on the **free** Supabase plan. This directory holds the tooling that keeps
free-tier data from being lost. Background and the full rationale:
[../docs/specs/cursiveroot-data-durability-v1.md](../docs/specs/cursiveroot-data-durability-v1.md).

## What's here

| Path | Purpose |
|------|---------|
| `backups/cursiveroot-*.dump.gpg` | Daily **encrypted** `pg_dump` (custom format) of the `public` schema, committed to git. |
| `backups/LATEST` | Filename of the most recent backup. |
| `schema.sql` | Human-readable **schema-only** snapshot (no data). Regenerated each run. |
| `restore.sh` | Decrypt + `pg_restore` a backup into a target database. |

Backups are encrypted with AES256 (`gpg --symmetric`) **before** being committed,
because both Cursive repos are public. Never commit a raw `pg_dump` here.

## How it works

`.github/workflows/db-backup.yml` runs **daily at 09:00 UTC** (and on manual
`workflow_dispatch`). Each run:

1. Connects to CursiveRoot via the IPv4 **session pooler** and runs `pg_dump`.
   The connection itself is activity that **resets the 7-day auto-pause timer**,
   so the project never pauses → never hits the lossy snapshot-restore path.
2. Encrypts the dump and commits it to `backups/`, keeping the last 30 in the
   working tree (older ones stay in git history).
3. Refreshes `schema.sql`.

## One-time setup (required)

The workflow needs two repository secrets
(**Settings → Secrets and variables → Actions → New repository secret**):

| Secret | Value |
|--------|-------|
| `SUPABASE_DB_URL` | The **Session pooler** connection string from Supabase → Project Settings → Database → Connection string → *Session pooler*, with the database password filled in. (Session pooler is IPv4 and works from GitHub runners; the direct connection is IPv6-only on free tier.) |
| `BACKUP_PASSPHRASE` | A strong passphrase used to encrypt/decrypt backups. **Store it somewhere safe outside this repo** — without it the backups are unrecoverable. |

Then trigger a first run: **Actions → CursiveRoot DB Backup → Run workflow**.

## Restoring

```bash
export BACKUP_PASSPHRASE='...'                 # the passphrase used for backups
export SUPABASE_DB_URL='postgresql://...'       # TARGET db (use a scratch db first!)
./supabase/restore.sh                           # newest backup, or pass a specific file
```

`restore.sh` decrypts the chosen backup and runs `pg_restore --clean --if-exists`
against the `public` schema. **Always restore into a scratch/branch database and
verify before pointing it at production.**

## Limits to be aware of

- Free tier has **no PITR** (point-in-time recovery). Recovery granularity is
  "last daily backup," so up to ~24h of data could be lost in a worst case.
- `auth.*` / `storage.*` are Supabase-managed and are **not** included here; only
  the `public` schema (the operational data) is backed up.
- GitHub disables scheduled workflows after 60 days of **no repo activity**.
  Normal development keeps it alive; if the repo ever goes idle that long,
  re-enable the workflow in the Actions tab.
