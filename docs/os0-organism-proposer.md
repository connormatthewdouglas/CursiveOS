# OS.0 Autonomous Proposer (G3)

`tools/organism_proposer.py` is the "self" in self-improvement: it selects the next
experiment from a measured history and materializes a real, runnable, reversible
candidate that a contributor daemon can screen through the normal acceptance loop.
**It proposes; the sensors decide.** No probabilistic judgment enters selection.

## What it does

1. **Selects** the next candidate from an audited library of reversible `sysctl` knobs
   (`KNOB_LIBRARY`), in priority order, skipping any candidate that already has a
   variant file. Priority favors the memory channel first, because that is where the
   lineage's most recent measured win came from (v0.11 zram+swappiness, +75.4%).
2. **Materializes** two real files that mirror the existing lineage exactly:
   - `references/seed-organism/variant.<id>.json` — a `candidate_screen`, fitness-eligible
     variant with a pre-registered hypothesis and a rollback method.
   - `presets/cursiveos-presets-<id>.sh` — delegates apply/undo to the parent preset and
     adds exactly one sysctl, capturing the prior value on apply and restoring it on undo.
3. **Prints a privileged enqueue SQL** for the founder / service role to run.

## Safety model (load-bearing)

- **Audited knobs only.** The proposer composes solely from `KNOB_LIBRARY` — plain,
  reversible `sysctl` keys. It never generates free-form shell. This preserves the
  mutation-safety and reversibility invariants, and keeps the daemon's containment
  guarantee intact (it still only runs repo-contained, existing variant paths).
- **Reversible by construction.** Every generated preset restores the prior sysctl value
  before delegating the rest of the revert to the parent.
- **Simulated + Linux-scoped.** Materialized candidates are `simulated_not_payout_eligible`
  and `linux_bare_metal`.
- **Enqueue is privileged.** Because `measurement_requests` is privileged-authored
  (anon INSERT revoked in migration `20260702000000`), the proposer does **not** insert a
  request with the public key. It prints SQL for a human/service-role to run. During
  bootstrap this keeps a founder in the loop on exactly what daemons execute with sudo,
  while the *proposal* is automated.

## Usage

```bash
python tools/organism_proposer.py list-knobs                 # show the library + what's proposed
python tools/organism_proposer.py propose                    # dry run: show the next candidate
python tools/organism_proposer.py propose --materialize      # write variant.json + preset.sh + print enqueue SQL
```

Then (privileged): review + commit the two files so daemons can pull them, and run the
printed `insert into public.measurement_requests ...` via the service role (or a
migration / the Supabase SQL editor). A daemon claims it, screens it, and the sensors
decide — exactly as for a hand-authored candidate.

## First autonomous candidate

`v0.13-pagecluster0` — `vm.page-cluster=0` on top of v0.12. This is the standard
companion tuning for a zram swap device (fault a single page per swap-in instead of an
8-page cluster), which v0.12 does not yet set, targeting the memory-pressure channel.

## Next (not yet built)

- Ground selection in the **live QD archive** (`tools/qd_organism.py`) driven by real
  fitness pulled from CursiveRoot, rather than a static priority-ordered library —
  explore under-covered behavioral cells and mutate the best real elites.
- Optional **gated auto-enqueue** via a dedicated authenticated proposer identity once
  the signed-identity write path (G4) exists, so the loop can close without the manual
  SQL step — still with real reward hard-gated.
