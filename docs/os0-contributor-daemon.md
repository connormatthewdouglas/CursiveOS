# OS.0 Contributor Daemon MVP

CursiveOS OS.0 starts with a small nervous-system loop:

1. CursiveRoot stores explicit `measurement_requests`.
2. A Linux bare-metal host runs `tools/contributor_daemon.py`.
3. The daemon reports `machine_capabilities`, claims one request, runs `seed_organism.py screen-variant --execute`, uploads the resulting seed bundle, and writes a `measurement_jobs` record.
4. The dashboard reads the queue/job/capability tables alongside the existing `runs`, `seed_bundles`, and simulated payout tables.

This is alpha infrastructure. It is **not payout eligible** and it is **Linux-first**.
Windows/WSL probes may test protocol plumbing later, but they must not enter Linux selection truth.

## Files

- `supabase/migrations/20260701000000_os0_measurement_queue.sql`
  - `machine_capabilities`
  - `measurement_requests`
  - `measurement_jobs`
  - public alpha RLS policies for daemon bootstrap
  - one seeded request: `v0.12` parent vs `v0.12b-swappiness` candidate
- `tools/contributor_daemon.py`
  - capability probe
  - request validation
  - dry-run planning
  - local request execution
  - CursiveRoot poll/claim/report path
- `references/seed-organism/variant.v0.12b-swappiness.json`
  - explicit candidate metadata for the first OS.0 queue seed
- `dashboard/index.html`
  - polished static dashboard with OS.0 queue, jobs, heartbeats, evidence, fleet, and simulated reward sections

## Local dry-run

From the repo root:

```bash
python tools/contributor_daemon.py capabilities --json
python tools/contributor_daemon.py write-sample-request --out .cursiveos/contributor-daemon/sample-request.json
python tools/contributor_daemon.py --state-dir .cursiveos/contributor-daemon run-once --request-json .cursiveos/contributor-daemon/sample-request.json --dry-run
```

On Windows this should normally report the sample request as ineligible, because OS.0 selection truth is Linux bare-metal only.
On the Linux laptop, the same dry-run should produce a planned `seed_organism.py screen-variant --execute` command.

## Live daemon once the migration is applied

```bash
python3 tools/contributor_daemon.py capabilities --register
python3 tools/contributor_daemon.py --state-dir ~/.cursiveos/contributor-daemon daemon --interval 300
```

For a single claim/run cycle:

```bash
python3 tools/contributor_daemon.py --state-dir ~/.cursiveos/contributor-daemon daemon --once
```

## Safety rails

- Every executable request must name both parent and candidate variant files.
- `candidate_variant_id` cannot equal `parent_variant_id`.
- `trust_scope` must be `simulated_not_payout_eligible` or `observe_only_not_payout_eligible`.
- `selection_scope` must remain Linux-scoped.
- The daemon refuses non-Linux/non-bare-metal selection-truth requests.
- The SQL migration keeps public alpha writes for convenience; tighten RLS before opening the fleet beyond founder-controlled machines.
