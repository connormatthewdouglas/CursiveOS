# Changelog - Decision-Grade Sensor Loop v2.5

**Date:** 2026-05-31

v2.5 turns the Phase 0 benchmark corpus into an operator-readable sensor report and prepares CursiveRoot for richer, auditable measurement detail. The goal is not to accept mutations faster. The goal is to make the organism harder to fool by separating characterization, screening, and inheritance evidence.

## Strategic Change

The next organism phase is now defined as a measurement-quality pass:

1. Preserve detailed benchmark evidence instead of compressing runs down to headline deltas.
2. Analyze live CursiveRoot data in terms of selection readiness.
3. Keep single parent/candidate screens below acceptance confidence.
4. Identify data hygiene issues before external testers depend on the database.

## Implemented

- Added `tools/cursiveroot_analyze.py`, a live CursiveRoot analyzer that reports:
  - total visible runs, machine rows, canonical machines, seed bundles, and detail bundles
  - latest run summary
  - v0.8 cohort medians, means, ranges, and stability counts
  - organism state: accepted mutations, candidate screens, measured baselines
  - decision notes for network, cold-start, sustained inference, idle power, and seed acceptance readiness
  - data hygiene warnings for machine-id aliases and incomplete machine rows
  - optional JSON output for future Hub/API use

- Replaced `scripts/cursiveroot-status.sh` with a thin wrapper around the analyzer. Existing operator muscle memory still works:

```bash
./scripts/cursiveroot-status.sh
```

- Extended `tools/seed_organism.py` so full-test ingestion extracts structured telemetry from detail logs when those logs are available:
  - network per-pass throughput, retransmits, RTT, average, and range
  - cold-start per-call GPU-before frequency, load time, TTFT, cold total, token rate, averages, and ranges
  - sustained inference per-pass token rate, TTFT, processor classification, averages, and ranges
  - idle-power sample arrays already present in the full-test JSON

- Added measurement-quality flags to seed metrics:
  - missing detail logs
  - too few idle-power samples
  - CPU-bound sustained inference
  - failed full-test stability flag

- Preserved the important confidence boundary: internal benchmark passes are kept for audit detail, but they do **not** automatically count as independent selection confirmations. A single parent/candidate screen remains diagnostic only.

- Added optional upload support for `run_detail_bundles`. If the new table exists, recovered full-test results can upload structured telemetry keyed by source JSON hash. If the table has not been migrated yet, regular benchmark upload continues without failing.

- Added `references/SUPABASE-MIGRATION-decision-grade-sensors-v0.2.sql` for the new `run_detail_bundles` table.

- Added a unit test proving that full-test detail logs are extracted while `sample_counts` remain unchanged for selection confidence.

## Live CursiveRoot Reading

The new analyzer currently sees:

- `74` benchmark run rows
- `5` machine rows
- `1` seed bundle
- `0` accepted seed mutations
- `0` candidate screen bundles
- `0` uploaded run detail bundles, because the new migration has not been applied to live CursiveRoot yet

Current v0.8 cohort signal from live rows:

- Network gain: strong under canonical loopback WAN simulation.
- Cold-start: promising in places, but hardware-dependent and not clean enough to drive inheritance alone.
- Sustained inference: too small/noisy to drive inheritance.
- Idle power: material cost, still an active penalty.

## Data Hygiene Found

- Many historical run rows use human-readable machine ids while their notes contain the newer hardware fingerprint id.
- At least one machine row is missing `os` and `kernel`.
- These do not invalidate the old results, but they should be cleaned or canonicalized before external tester rollout.

## Files Changed

- `tools/cursiveroot_analyze.py`
- `tools/seed_organism.py`
- `scripts/cursiveroot-status.sh`
- `references/SUPABASE-MIGRATION-decision-grade-sensors-v0.2.sql`
- `tests/test_seed_organism.py`
- `docs/specs/seed-organism-runbook-v0.1.md`
- `docs/action-plan.md`
- `README.md`

## Verification

```bash
python3 -m py_compile tools/seed_organism.py tools/cursiveroot_analyze.py
python3 -m unittest tests/test_seed_organism.py
./scripts/cursiveroot-status.sh --limit 120 --latest 5
```

## Next Build Step

Apply the v0.2 Supabase migration, then run the v0.8 versus v0.9-network-efficient screen in counterbalanced order on at least two machines. Only after repeated paired evidence exists should the seed organism consider inheritance.
