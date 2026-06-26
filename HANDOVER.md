# CursiveOS — Agent Handover (2026-06-26)

Pick-up note for the next agent. Pairs with the auto-memory file
`cursive-work-state.md` (longer history) and `CursiveResearch/VALIDATION.md`
(claim status). This file = the live state of the **memory-pressure sensor sprint**
and exactly how to finish it.

## TL;DR — where the sprint is

The organism gained a **5th measured channel (memory-pressure)** this sprint and it
immediately found a real improvement: **v0.11 (v0.9 + zram + swappiness=60)**.

- 5th channel is fully integrated: scoring (`tools/seed_organism.py`), DB
  (`runs` memory columns, migration `20260625000000`), and the harness
  (**v1.4.5**, `cursiveos-full-test-v1.4.sh`).
- Sensor probe: `benchmarks/benchmark-memory-pressure-v0.2.sh` (cgroup `memory.high`
  refault-time, per-rep timeout, zram engagement proof). Validated on 2 machines.
- **✅ v0.11 ACCEPTED (cycle 3 closed) 2026-06-26.** Three confirming screens all
  positive — Stardust normal +0.0954, **laptop (cross-machine) +0.1004**, Stardust
  reversed +0.0947 — so the accept ran at `--confirmations 3` → confidence **0.875**,
  decision **accepted**, fitness **+0.1004**, anchored on the laptop
  (`42e7c7257af11f46`). Cycle 3 closed (1 contributor, 100k simulated sats). Both
  the accepted bundle and the cycle-3 payout report are in CursiveRoot. This is the
  **2nd accepted variant ever and the FIRST selected by the memory channel.**
- Net: 2 accepted bundles in CursiveRoot (v0.9c cycle 1, v0.11 cycle 3); 2 payout
  reports (cycles 1, 3). Dashboard (https://connormatthewdouglas.github.io/CursiveOS/)
  reads these live.

## Key finding this sprint (don't lose this)

**zram does nothing while `vm.swappiness=0`.** v0.9 pins swappiness=0 to keep model
weights resident. Under cgroup memory pressure, v0.9 AND v0.10-zram both throttle to
the probe's wall-clock cap — zram is touched (ratio ~55x) but the kernel won't swap
to it. So **v0.10-zram is correctly NEUTRAL.** The real win is **v0.11 = v0.9 + zram
+ swappiness=60**: memory refault 45s(capped) → ~11s (>4x), and on the full screen
**cold-start −0.5% / sustained 0.0%** — i.e. re-enabling swap did NOT regress
inference. Also: v0.9 itself *regresses* memory −55% vs untuned (swappiness=0 cost,
previously invisible).

## PICK UP HERE (sprint is complete; these are the next moves)

SSH: `ssh stardust` and `ssh laptop` (config already in `~/.ssh/config`, key
`~/.ssh/cursive_rig`). If sudo is needed, export `TAO_SUDO_PASS` from the local
secure channel/operator context; **do not commit sudo passwords or other secrets
to this repo**. For complex remote bash, base64-encode:
`ssh host "echo <b64> | base64 -d | bash"`.

**First, two loose ends from this sprint:**
- **Rotate the sudo password.** An earlier version of this file (commit `d69487c`,
  on origin) contained the literal sudo password before it was scrubbed at HEAD.
  It is still in git history → treat it as compromised and rotate it on both
  machines. (History rewrite + force-push is possible but disruptive; rotation is
  the real fix.)
- **Promote v0.11 → canonical parent** (mirrors v0.9c→v0.9): create
  `presets/cursiveos-presets-v0.12.sh` (= v0.11 settled) + `variant.v0.12.json`
  (`evaluation_role: parent_baseline`, `fitness_eligible: false`) and point future
  screens at it. The accepted improvement should become the new baseline.
- **Flip the corpus VALIDATION row** for v0.11 from "inconclusive screen" to
  "Validated / accepted" and add a CHANGELOG note that cycle 3 closed.

(For reference, the accept was done with: `seed_organism screen-variant
--confirmations 3 ... --cycle-id 3` then `upload`, then `close-cycle --cycle-id 3
--revenue-sats 100000`, then `upload`, all in state-dir `.cursiveos/seed-mem-c3`
on the laptop.)

## After the sprint — candidate next steps (not started)

- **Tune the swappiness value** (60 vs 100). zram is cheap; higher swappiness may
  help memory more. Screen v0.11 (swappiness 60) vs a v0.11b (swappiness 100).
- **Concurrency inference sensor** — still the other open measurement gap
  (single-stream sustained is below its noise floor; see VALIDATION.md).
- **Auto-count confirmations** from independent CursiveRoot bundles instead of the
  founder-attested `--confirmations N` (pre-external-rollout hardening).
- **v0.2 mm_stat polish** is done; the probe's `capped_reps` is computed from samples.

## Gotchas (carried forward)

- PowerShell here-strings mangle `git commit -m @'...'@` when the body has odd
  chars → use `git commit -F <file>`. Inline python over ssh gets mangled by
  PowerShell → base64 it.
- Both repo origins drift (backup bot + agents) → always
  `git fetch; git -c credential.helper= rebase origin/main` before push, and push
  with `git -c credential.helper= -c credential.helper=store push origin main`
  (system `credential.helper=helper-selector` hangs otherwise).
- The memory probe under swappiness=0 + slow/absent swap will hit the per-rep cap
  (default 45s, `CURSIVEOS_MEM_TIMEOUT`). That is expected/correct, not a bug.
- Memory channel weight is **provisional 0.10** (DEFAULT_CONFIG). Expected to change.
