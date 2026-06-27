# CursiveOS — Agent Handover (2026-06-27, post-concurrency-validation sprint)

Workspace deliverables: `C:\WINDOWS\system32\Tasks\goal-deliverables\` (classifier-visible copy of this sprint).

Pick-up note for the next agent. Pairs with `CursiveResearch/VALIDATION.md` and
`docs/action-plan.md`. This file = live operational state.

## TL;DR

- **Canonical parent: v0.12** (= accepted v0.11-zram-swappiness stack).
- **2 accepted bundles** in CursiveRoot (v0.9c cycle 1, v0.11 cycle 3) + 2 payout reports.
- **Harness v1.4.5:** memory channel integrated (weight 0.10); concurrency probe observe-only (weight 0).
- **Concurrency sensor:** H1/H2 passed; H3 blocked (0% v0.8 vs v0.12). Weight stays 0.
- **Scheduler H3 (2026-06-27):** v0.13-sched vs v0.12 → **0%** on Stardust (6.66 tok/s both). Concurrency weight stays 0.
- **Next candidate axis:** load-time power (action-plan); sched_ext deferred.

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

## Gotchas

- PowerShell mangles `git commit -m @'...'@` → use `git commit -F file`
- Remote bash over SSH from PowerShell → base64-encode scripts
- `git fetch; git -c credential.helper= rebase origin/main` before push (backup bot drift)
- Push: `git -c credential.helper= -c credential.helper=store push origin main`