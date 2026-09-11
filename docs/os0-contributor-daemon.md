# OS.0 Contributor Daemon MVP

CursiveOS OS.0 starts with a small nervous-system loop:

1. CursiveRoot stores explicit `measurement_requests` (**privileged insert**).
2. A Linux bare-metal host runs `tools/contributor_daemon.py`.
3. The daemon reports `machine_capabilities` (hardware, not occupancy), claims one request, runs `seed_organism.py screen-variant --execute`, uploads the resulting seed bundle, and writes a `measurement_jobs` record.
4. While a screen runs it writes **local** progress for the Desktop window (`docs/os0-client-window.md`). That status is not uploaded.
5. CursiveRoot reads queue/job/capability tables alongside `runs`, `seed_bundles`, and simulated payouts.

This is alpha infrastructure. It is **not payout eligible** and it is **Linux-first**.
Windows/WSL probes may test protocol plumbing later, but they must not enter Linux selection truth.

## Files

- `tools/contributor_daemon.py` — capability probe, claim, execute, upload
- `tools/cursive_status.py` — local busy/progress JSON
- `tools/cursive_panel.py` — optional Desktop face
- `supabase/migrations/20260701000000_os0_measurement_queue.sql` plus later RLS tightening (`measurement_requests` anon INSERT revoked)

## Local dry-run

From the repo root:

```bash
python tools/contributor_daemon.py capabilities --json
python tools/contributor_daemon.py write-sample-request --out .cursiveos/contributor-daemon/sample-request.json
python tools/contributor_daemon.py --state-dir .cursiveos/contributor-daemon run-once --request-json .cursiveos/contributor-daemon/sample-request.json --dry-run
```

On Windows this should normally report the sample request as ineligible.
On Linux, the same dry-run should produce a planned `seed_organism.py screen-variant --execute` command.

## Live daemon

```bash
python3 tools/contributor_daemon.py capabilities --register
python3 tools/contributor_daemon.py --state-dir ~/.cursiveos/contributor-daemon daemon --interval 300
```

For a single claim/run cycle:

```bash
python3 tools/contributor_daemon.py --state-dir ~/.cursiveos/contributor-daemon daemon --once
```

Sit at the machine: open the CursiveOS window so Stop is one click. The daemon can run headless; the window is optional.

## Safety rails

- Every executable request must name both parent and candidate variant files.
- `candidate_variant_id` cannot equal `parent_variant_id`.
- `trust_scope` must be `simulated_not_payout_eligible` or `observe_only_not_payout_eligible`.
- `selection_scope` must remain Linux-scoped.
- The daemon refuses non-Linux/non-bare-metal selection-truth requests.
- **Anon cannot inject work.** `measurement_requests` insert is privileged. Do not re-open that from a cloud agent.
- **Do not publish occupancy.** Heartbeats may include hardware capability. They must not include "this PC is busy."
- Tighten remaining `USING(true)` update policies on capabilities/jobs before a public tester blast (G4).
