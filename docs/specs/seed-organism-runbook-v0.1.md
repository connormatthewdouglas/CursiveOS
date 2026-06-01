# Seed Organism Runbook v0.1

This runbook is the first executable path for the Phase 0 seed organism described in `docs/specs/seed-organism-v0.1.md`.

## Local mac fixture loop

Use this path while developing on macOS. It proves scoring, gating, bundle writing, ledger append, and fake payout without touching host tuning.

In Phase 0, a fake revenue cycle is simulated accounting only. It does not move BTC, create a claim, or promise compensation. It proves that accepted fitness entries can be converted into a payout report using the Layer 5 current-cycle and lifetime split.

A payout report is the audit artifact from that simulation. It shows which contributor identities would receive simulated sats if the same ledger state were settled for real. For a single accepted benchmark/variant run, the simulated payee is the `contributor_id` on the accepted variant ledger entry, currently `local-founder` in the bootstrap examples. A machine tester is not paid merely for running a benchmark unless they are also the contributor for an accepted variant.

```bash
python3 tools/seed_organism.py init
python3 tools/seed_organism.py run-variant \
  --variant references/seed-organism/variant.example.json \
  --metrics references/seed-organism/metrics-positive.example.json \
  --cycle-id 1
python3 tools/seed_organism.py close-cycle --cycle-id 1 --revenue-sats 100000
python3 tools/seed_organism.py status
python3 tools/seed_organism.py upload
python3 tools/seed_organism.py remote-status
./scripts/cursiveroot-status.sh
```

Local state is written under `.cursiveos/seed/` and is intentionally ignored by git.

## Linux test-host loop

Use this path on a Linux machine that can safely run the existing CursiveOS full-test harness. This is the intended non-technical tester path: open Terminal, paste one command, and let the local runner clone/update the repo before running the seed organism.

```bash
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y curl; }; (curl -fsSL https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-organism-linux-test.sh || wget -qO- https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-organism-linux-test.sh) | bash
```

The command above runs the bootstrap script at `seed-organism-linux-test.sh`. For development, the same flow can be run from an existing checkout:

```bash
python3 tools/seed_organism.py init
python3 tools/seed_organism.py run-variant \
  --variant references/seed-organism/variant.example.json \
  --execute \
  --cycle-id 1
```

The `--execute` mode is Linux-only. It runs `cursiveos-full-test-v1.4.sh` with the canonical genesis preset path and turns the result into the same seed organism sensor bundle used by fixture mode. A first real v0.8 run is baseline characterization (`genesis-baseline-v0.8`), not a contributed mutation and not payout-eligible.

### First candidate screen

After a host has a genesis baseline, the next real test compares the current parent (`v0.8`) to a narrow candidate (`v0.9-network-efficient`). The candidate keeps only network tuning and avoids v0.8's always-on CPU/GPU power-state tuning. This screen runs two full tests back-to-back on one machine:

```bash
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y curl; }; (curl -fsSL https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-mutation-linux-test.sh || wget -qO- https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-mutation-linux-test.sh) | bash
```

One screen can reveal whether the hypothesis is worth repeating. It cannot accept a mutation or produce a payout: acceptance requires repeated, counterbalanced parent/candidate sessions so that thermal drift and run order do not masquerade as fitness.

If Ollama is installed but not running, the harness now tries to start it automatically before pulling or validating a model. If Ollama still cannot become ready, the run continues with inference metrics marked `N/A`; the seed organism should then emit an invalid or inconclusive bundle rather than losing the whole audit trail.

If a completed benchmark wrote a JSON result but CursiveRoot was temporarily unavailable during upload, do not rerun the benchmark. On that Linux machine, update the repo and recover the saved JSON:

```bash
cd ~/CursiveOS && git pull --ff-only origin main && python3 tools/seed_organism.py recover-result --result-json logs/cursiveos-full-test-YYYYMMDD-HHMMSS.json
```

## Artifact Contract

Each evaluated variant writes an audit bundle:

- `variant.json`
- `metrics.json`
- `sensor-result.json`
- `regression-result.json`
- `bundle-manifest.json`

Accepted variants append to `.cursiveos/seed/ledger/ledger.jsonl`. All variants append sensor and regression results whether accepted, rejected, invalid, or inconclusive.

## Sensor Direction

Genesis performance scoring treats:

- higher network throughput as positive
- lower cold-start latency as positive
- higher sustained tokens/sec as positive
- higher idle power as a reported cost and optional penalty

The regression gate is separate from scoring. A variant with good performance is still rejected if the full-test, reversibility, or host-safety gate fails.

The full-test JSON records the actual selected preset version and stores idle-power medians with the underlying sample list (up to five readings per condition). The seed organism now also extracts structured telemetry from the detailed network and inference logs when those logs are available:

- network per-pass throughput, retransmits, RTT, average, and range
- cold-start per-call GPU-before frequency, load duration, TTFT, cold total, and range
- sustained inference per-pass token rate, TTFT, processor classification, average, and range

These details are audit evidence. They do not automatically become independent selection confirmations. A single parent/candidate session still remains below acceptance confidence even if its internal benchmark had five passes.

## CursiveRoot Analysis

Use the decision-grade analyzer for the live operator view:

```bash
./scripts/cursiveroot-status.sh --limit 120 --latest 8
python3 tools/cursiveroot_analyze.py --json
```

The analyzer reports cohort medians/ranges, organism state, seed-bundle readiness, and data hygiene warnings. Its current purpose is to tell the operator whether data is characterization, screening evidence, or ready for repeated confirmation.

If the optional v0.2 migration is applied, recovered full-test results can also upload structured detail bundles:

```bash
psql "$CURSIVEROOT_DATABASE_URL" -f references/SUPABASE-MIGRATION-decision-grade-sensors-v0.2.sql
python3 tools/seed_organism.py recover-result --result-json logs/cursiveos-full-test-YYYYMMDD-HHMMSS.json
```

`run_detail_bundles` is keyed by the source full-test JSON hash. If that table is not present yet, normal `runs` and `seed_bundles` upload still continues.

## CursiveRoot Boundary

The local implementation writes audit artifacts first, then uploads copies to CursiveRoot with `python3 tools/seed_organism.py upload`. Upload failure does not delete local artifacts.

From the development Mac, use `python3 tools/seed_organism.py remote-status` to confirm that Linux seed uploads reached CursiveRoot.

Phase 0 upload uses the same public-key pattern as benchmark submissions: anonymous clients can insert and read seed artifacts, but cannot update or delete them. This is acceptable for controlled founder-rig testing and should be tightened before broad external tester rollout.

Do not forget this before external rollout: public insert/read is a bootstrap convenience, not the final trust model. The next hardening pass should add authenticated machine/tester identity, server-side validation, and narrower read/write policies.
