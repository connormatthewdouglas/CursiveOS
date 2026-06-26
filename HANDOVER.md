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
- **Cycle-3 first screen (Stardust, normal order):** v0.11 vs v0.9 = **fitness
  +0.0954**, decision `inconclusive` (single screen, confidence 0.50). Bundle in
  CursiveRoot.
- **IN FLIGHT when this note was written:** two more confirming screens running in
  parallel to reach confidence 0.875 and ACCEPT v0.11:
  - **laptop** (cross-machine): `nohup` job, log `/tmp/lapscreen.out` (JSON paths
    printed as `LAP_V09_JSON=` / `LAP_V11_JSON=`).
  - **Stardust reversed-order**: `nohup` job, log `/tmp/sdrev.out`
    (`SDREV_V11_JSON=` / `SDREV_V09_JSON=`).

## Key finding this sprint (don't lose this)

**zram does nothing while `vm.swappiness=0`.** v0.9 pins swappiness=0 to keep model
weights resident. Under cgroup memory pressure, v0.9 AND v0.10-zram both throttle to
the probe's wall-clock cap — zram is touched (ratio ~55x) but the kernel won't swap
to it. So **v0.10-zram is correctly NEUTRAL.** The real win is **v0.11 = v0.9 + zram
+ swappiness=60**: memory refault 45s(capped) → ~11s (>4x), and on the full screen
**cold-start −0.5% / sustained 0.0%** — i.e. re-enabling swap did NOT regress
inference. Also: v0.9 itself *regresses* memory −55% vs untuned (swappiness=0 cost,
previously invisible).

## TO FINISH THE SPRINT (do this when both background jobs report DONE)

SSH: `ssh stardust` and `ssh laptop` (config already in `~/.ssh/config`, key
`~/.ssh/cursive_rig`). sudo via `TAO_SUDO_PASS='***REDACTED***'`. For complex
remote bash, base64-encode: `ssh host "echo <b64> | base64 -d | bash"`.

1. **Confirm both jobs finished:** `ssh laptop "cat /tmp/lapscreen.out"` and
   `ssh stardust "cat /tmp/sdrev.out"`. Grab the 4 JSON paths.
2. **Verify each confirmation is positive** (v0.11 beats v0.9). Quick check: each
   candidate JSON's `variant.memory_refault_s` should be far below the v0.9
   `variant.memory_refault_s` (capped ~45s). Or run a 1-confirmation screen for each
   pair and confirm `fitness_score > 0`, `severe_regressions == []`.
   - We already have confirmation #1: Stardust normal, +0.0954 (in CursiveRoot).
   - #2 = laptop pair; #3 = Stardust-reversed pair.
3. **Run the ACCEPT screen** (confidence 0.875). Use one representative pair — the
   laptop (cross-machine) pair is the strongest evidence:
   ```bash
   ssh laptop "cd ~/CursiveOS && python3 tools/seed_organism.py --state-dir .cursiveos/seed-mem-c3 screen-variant \
     --parent-variant references/seed-organism/variant.v0.9.json \
     --candidate-variant references/seed-organism/variant.v0.11-zram-swappiness.json \
     --parent-result-json <LAP_V09_JSON> --candidate-result-json <LAP_V11_JSON> \
     --confirmations 3 --cycle-id 3"
   ```
   Expect `decision: accepted` (confidence 0.875 >= 0.65, fitness > 0.01).
   `--confirmations 3` is founder-attested here; the 3 real screens (Stardust normal
   + laptop + Stardust reversed) are the evidence. Phase 0 allows this attestation;
   pre-rollout this must be auto-counted from independent bundles in CursiveRoot.
4. **Upload + close cycle 3 + upload payout:**
   ```bash
   ssh laptop "cd ~/CursiveOS && python3 tools/seed_organism.py --state-dir .cursiveos/seed-mem-c3 upload"
   ssh laptop "cd ~/CursiveOS && python3 tools/seed_organism.py --state-dir .cursiveos/seed-mem-c3 close-cycle --cycle-id 3 --revenue-sats 100000"
   ssh laptop "cd ~/CursiveOS && python3 tools/seed_organism.py --state-dir .cursiveos/seed-mem-c3 upload"
   ```
   (100000 sats matches cycle-1's simulated revenue. close-cycle reads the ledger,
   which only has an entry once the screen `decision == accepted`, so step 3 must run
   in the SAME `--state-dir`.)
5. **Verify in CursiveRoot:** `seed_bundles` has an `accepted` `candidate-v0.11-zram-swappiness`
   row; `seed_payout_reports` has a cycle-3 report. The dashboard
   (https://connormatthewdouglas.github.io/CursiveOS/) reads these live.
6. **Promote v0.11 → new canonical parent** (mirrors the v0.9c→v0.9 promotion): create
   `presets/cursiveos-presets-v0.12.sh` (= v0.11 settled) + `variant.v0.12.json`
   (`evaluation_role: parent_baseline`, `fitness_eligible: false`), and point future
   screens at it. Optional this session; can be its own task.

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
