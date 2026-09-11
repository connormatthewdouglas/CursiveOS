# OS.0 Autonomous Proposer (G3)

`tools/organism_proposer.py` is the "self" in self-improvement: it selects the next
experiment from a measured history and materializes a real, runnable, reversible
candidate that a contributor daemon can screen through the normal acceptance loop.
**It proposes; the sensors decide.** No probabilistic judgment enters selection.

**Enqueue is still privileged.** The proposer writes files. It does not insert
`measurement_requests`. Anon INSERT is denied. That is the remaining founder-shaped hole
in the loop, by design, until a signed proposer identity exists.

## What it does

1. **Selects** the next candidate from an audited library of reversible `sysctl` knobs
   (`KNOB_LIBRARY`), in priority order, skipping any candidate that already has a
   variant file. Memory-channel first, because that is where the lineage's last measured
   win came from (v0.11 zram+swappiness).
2. **Materializes** two real files:
   - `references/seed-organism/variant.<id>.json`
   - `presets/cursiveos-presets-<id>.sh` — parent-delegating, one sysctl, undo restores
     the prior value.
3. **Prints privileged enqueue SQL** for a human / service role. Do not paste that SQL
   from a cloud agent into live CursiveRoot.

`tools/closed_loop.py` is the founder-rig runner: leftover propose → screen → upload →
stack only if kept. Cycle 7 (2026-09-11) ran four leftovers this way; all rejected.

## Safety model (load-bearing)

- **Audited knobs only.** Never free-form shell.
- **Reversible by construction.**
- **Simulated + Linux-scoped.** `simulated_not_payout_eligible`, `linux_bare_metal`.
- **Enqueue is privileged.**
- **Do not mine** `pagecluster0` or `vfscache50`. Both already returned honest nulls.

## Usage

```bash
python tools/organism_proposer.py list-knobs
python tools/organism_proposer.py propose
python tools/organism_proposer.py propose --materialize
```

Then commit the two files so daemons can `git pull` them (Desktop window → Update from
GitHub). A privileged identity still has to enqueue. A daemon claims, screens, sensors
decide.

## Screened so far (do not re-run)

| Candidate | Cycle | Verdict |
| --- | --- | --- |
| v0.13-pagecluster0 | 5 | honest null |
| v0.13-vfscache50 | 6 | honest null |
| v0.13-watermark200 | 7 | rejected |
| v0.13-dirtyexpire1500 | 7 | rejected |
| v0.13-migcost5ms | 7 | rejected |
| v0.13-notsentlowat16k | 7 | rejected |

## Next (not yet built)

- Ground selection in the **live QD archive** (`tools/qd_organism.py`) from real
  CursiveRoot fitness — explore under-covered cells, mutate real elites.
- **Gated auto-enqueue** via a dedicated signed proposer identity (G4). Real reward
  stays hard-gated.
