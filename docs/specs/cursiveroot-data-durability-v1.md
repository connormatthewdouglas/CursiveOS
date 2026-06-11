# CursiveRoot Data Durability v1

Date: 2026-06-10 (corrected same day — see Addendum)
Status: Active
Scope: CursiveRoot Supabase project (`iovvktpuoinmjdgfxgvm`), free plan

> **ADDENDUM (2026-06-10, ~2h later): the data came back.** Roughly 1–2 hours
> after the project resumed, all 77 runs, 5 machines, the genesis seed bundle,
> and the Layer 5 rows were visible again. The restore after unpausing is
> evidently **asynchronous**: the project reports `ACTIVE_HEALTHY` and serves
> queries while tables are still empty (confirmed via `pg_stat_user_tables`
> showing zero inserts and zero live tuples ~10 minutes after resume), and the
> data lands later. Revised lessons:
>
> 1. **An empty database right after unpausing is not proof of data loss.**
>    Wait 1–2 hours and re-check before concluding anything.
> 2. **Do not write to or "repair" the database during that window** — writes
>    could collide with the late-arriving restore. (Our re-seeded parameter
>    rows used `on conflict do nothing`, so no harm was done.)
> 3. **Everything else below still stands.** The free tier has no PITR and no
>    user-accessible backups; the auto-pause → restore path is still the
>    biggest data risk, and the daily backup + keep-alive job remains the
>    protection. The original analysis is preserved below as written, with
>    the loss conclusion corrected by this addendum.

## Why this document exists

On **2026-06-10** CursiveRoot was found with its full schema intact but **every
table empty** immediately after resuming from a free-tier auto-pause (the data
reappeared 1–2 hours later — see Addendum). Root cause was identified from the
Postgres logs and project metadata.

## What happened (root cause)

CursiveRoot runs on the **free** Supabase plan. Free projects **auto-pause after
7 days of inactivity**. CursiveRoot was last active at **2026-06-07 20:17:56 UTC**,
auto-paused, and was resumed on 2026-06-10.

The resume did **not** roll the database forward to the moment it paused. The
Postgres logs show a snapshot restore that stopped at the *earliest* consistent
point of a base backup:

```
database system was interrupted; last known up at 2026-06-07 20:17:56 UTC
starting backup recovery with redo LSN 2/52000028 ... on timeline ID 3
starting point-in-time recovery to earliest consistent point
recovery stopping after reaching consistency
selected new timeline ID: 4
```

The restored snapshot contained the table **structure** but not the **rows**.
Confirmed via `pg_stat_user_tables`: every public table showed
`n_tup_ins = 0` / `n_live_tup = 0` after the restore — Postgres had no record of
any insert since recovery.

Contributing factors, all of which meant there was nothing to recover from:
- **No PITR** — point-in-time recovery is not available on the free plan.
- **No independent backups** — no `pg_dump` was being taken anywhere.
- **No migration tracking** — `supabase_migrations.schema_migrations` did not
  exist, so even the schema was only reproducible by luck (it happened to be in
  the restored snapshot, and as SQL in `references/SUPABASE-MIGRATION-*.sql`).

## Decision

Treat CursiveRoot data as **operationally required**, but **stay on the free
plan**. The durability strategy must therefore work entirely within free-tier
limits. We do **not** upgrade to Pro and do **not** rely on Supabase PITR.

The chosen approach attacks both the trigger and the blast radius:

1. **Prevent the pause (removes the trigger).** A daily GitHub Actions job
   connects to the database. That activity resets the 7-day idle timer, so the
   project never auto-pauses and never enters the lossy snapshot-restore path.
2. **Keep independent encrypted backups (removes the blast radius).** The same
   job runs `pg_dump` of the `public` schema, encrypts it (AES256), and commits
   it to git history. If a pause ever slips through anyway, data is recoverable.

One job covers both because the backup's database connection *is* the keep-alive.

### Why these choices

- **GitHub Actions, not an external cron host** — free, already where the code
  lives, no extra infrastructure to keep running.
- **Encrypted backups committed to the repo** — both Cursive repos are public, so
  raw operational data (e.g. `l5_accounts`, `l5_wallet_identities`) must never be
  committed in the clear. Encryption makes git itself the durable, versioned,
  zero-cost backup store. (Plain GitHub artifacts were rejected: on a public repo
  they are broadly downloadable and expire.)
- **Session pooler connection** — free-tier direct connections are IPv6-only and
  GitHub runners have no IPv6; the IPv4 session pooler is the supported path and
  works with `pg_dump`.
- **Schema-only snapshot kept unencrypted** (`supabase/schema.sql`) — structure
  is not sensitive and a readable, diffable schema is useful.

## Implementation

- Workflow: [`.github/workflows/db-backup.yml`](../../.github/workflows/db-backup.yml)
- Tooling + setup + restore steps: [`supabase/README.md`](../../supabase/README.md)
- Restore script: [`supabase/restore.sh`](../../supabase/restore.sh)

Required repository secrets: `SUPABASE_DB_URL` (session pooler string incl.
password) and `BACKUP_PASSPHRASE` (encryption passphrase — store it outside the
repo; backups are unrecoverable without it).

## Residual risk

- Recovery granularity is the **last daily backup**: a worst-case incident could
  lose up to ~24h of data. Acceptable under the free-only constraint; tighten by
  increasing the cron frequency if needed.
- `auth.*` and `storage.*` are Supabase-managed and not in scope here; only the
  `public` schema is backed up.
- Scheduled workflows are disabled after 60 days of **no repo activity**. Active
  development prevents this; re-enable in the Actions tab if the repo goes idle.

## If data loss recurs

1. Do **not** write to the database — avoid colliding with a possibly
   still-running restore.
2. **Wait 1–2 hours and re-check** (`pg_stat_user_tables`, row counts). The
   post-unpause restore is asynchronous and the database can look empty while
   it is still in flight.
3. Only if the data has not returned: restore the newest backup into a
   **scratch** database and verify (`supabase/restore.sh`), then promote.
4. Check the Postgres logs (look for "recovery to earliest consistent point")
   to confirm whether a pause/restore was the cause, then verify the daily
   workflow is still green.
