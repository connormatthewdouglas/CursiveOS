# CursiveOS — Agent Handover (2026-06-28, post-measurement-frontier sprint)

Workspace deliverables: `C:\WINDOWS\system32\Tasks\goal-deliverables\` (classifier-visible copy of this sprint).

Pick-up note for the next agent. Pairs with `CursiveResearch/VALIDATION.md` and
`docs/action-plan.md`. This file = live operational state.

## TL;DR

- **Canonical parent: v0.12** (= accepted v0.11-zram-swappiness stack).
- **2 accepted bundles** in CursiveRoot (v0.9c cycle 1, v0.11 cycle 3) + 2 payout reports.
- **Harness v1.4.5:** memory channel integrated (weight 0.10); concurrency probe observe-only (weight 0).
- **Concurrency sensor:** H1/H2 passed; H3 blocked (0% v0.8 vs v0.12). Weight stays 0.
- **Scheduler H3 (2026-06-27):** v0.13-sched vs v0.12 → **0%** on Stardust (6.66 tok/s both). Concurrency weight stays 0.
- **Load-time power (2026-06-27):** observe-only channel; v0.13 vs v0.12 **discriminative** (27% J/token) but v0.13 **regresses** (worse perf/watt). Do not promote v0.13.
- **Idle-power CV (2026-06-28):** Stardust **PASS** (CV 0.016); laptop AC **FAIL** (cold run-1 outlier, CV 1.60); H3 **PASS** (no cross-machine pooling). Idle weight stays **0** fleet-wide until laptop scoped.
- **Rig automation:** `tools/rig-smoke.sh` — `TAO_SUDO_PASS=`, SCP → `nohup &` → poll `/tmp/rig-smoke-*.out` only (no long SSH one-liners).
- **v0.12b screen (2026-06-28):** **rejected** on Stardust (mem +0.7% worse, J/token +3.0%).
- **Next:** new candidate axis (governor/load-power); optional laptop battery idle-power cohort.

## Lineage

| Preset | Role | Notes |
| --- | --- | --- |
| v0.9 | Superseded parent | cycle 1 accept (v0.9c) |
| v0.11-zram-swappiness | Accepted candidate | cycle 3 accept 2026-06-26 |
| **v0.12** | **Canonical parent** | delegates to v0.11; default in `seed-session-linux-test.sh` |

## Cycle 3 summary (do not lose)

- zram neutral under `vm.swappiness=0`; v0.11 wins with swappiness=60.
- Three confirmations → accepted, fitness +0.1004, confidence 0.875.
- First variant selected by memory channel.

## SSH + sudo

```text
ssh laptop    → elizabeth@192.168.1.210
ssh stardust  → elizabeth@192.168.1.102
Key: ~/.ssh/cursive_rig (passwordless key auth)
```

Both machines have **passwordless sudo** (`NOPASSWD: ALL`). For scripts that
read `TAO_SUDO_PASS`, export from operator secure channel — **never commit
passwords**.

### Security: sudo password rotation (operator action)

An earlier HANDOVER revision briefly contained a literal sudo password (scrubbed
from git history 2026-06-26). **Operator should rotate sudo password on laptop
and Stardust** and update their secure channel only:

```bash
# On each machine (as elizabeth):
passwd
# Verify from this PC (replace NEWPASS via secure channel, never commit):
export TAO_SUDO_PASS='NEWPASS'
ssh laptop "echo \"\$TAO_SUDO_PASS\" | sudo -S -v && echo sudo-ok"
ssh stardust "echo \"\$TAO_SUDO_PASS\" | sudo -S -v && echo sudo-ok"
```

Until rotation: passwordless sudo still works for routine preset/benchmark work.

## Concurrency sensor (validated 2026-06-27)

- **Probe:** `benchmarks/benchmark-inference-concurrency-v0.1.sh` (4 streams)
- **Harness:** observe-only in `cursiveos-full-test-v1.4.sh` (weight **0** — H3 failed)
- **H1 CV:** Stardust 0.0009 (mistral, 6.66–6.67 tok/s); laptop 0.0002 (tinyllama, 33.22–33.23)
- **H2 order:** Stardust 0.00% delta (pass)
- **H3 signal:** Stardust 0.00% (v0.8 6.67 vs v0.12 6.67 tok/s) — **fail**
- **Verdict:** Repeatable measurement channel; not discriminative for memory-class stack.
- **Scheduler screen:** v0.13-sched null (0%); granularity sysctl N/A on Stardust kernel
- **Next:** load-time power axis; sched_ext only after capability audit

Quick test:

```bash
cd ~/CursiveOS && bash benchmarks/benchmark-inference-concurrency-v0.1.sh --dry-run 4 mistral
cd ~/CursiveOS && bash benchmarks/benchmark-inference-concurrency-v0.1.sh 4 mistral
```

## Tier 2 remaining (not started)

- Auto-count confirmations from independent CursiveRoot bundles (not founder-attested `--confirmations N`)
- `page_cache_state` in harness telemetry
- CursiveRoot auth hardening before external rollout
- Daemon MVP + NL shell spec (Transition 1)
- Sandbox selector (Ch05 Open Gap #4)

## Rig smoke (SSH-safe)

```bash
# From dev machine (Git Bash or WSL):
export TAO_SUDO_PASS=
bash tools/rig-smoke.sh --dry-run
bash tools/rig-smoke.sh sync all
bash tools/rig-smoke.sh json-smoke all
bash tools/rig-smoke.sh screen-v012b stardust
```

Poll `/tmp/rig-smoke-*.out` on rigs; never block SSH on `nohup` without `&` or compound `git pull && preset && benchmark` chains.

## Gotchas

- PowerShell mangles `git commit -m @'...'@` → use `git commit -F file`
- Remote bash over SSH from PowerShell → base64-encode scripts
- `git fetch; git -c credential.helper= rebase origin/main` before push (backup bot drift)
- Push: `git -c credential.helper= -c credential.helper=store push origin main`