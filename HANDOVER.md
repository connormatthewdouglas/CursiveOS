# CursiveOS — Agent Handover (2026-09-10)

Pick-up note for the next agent. Pairs with `CursiveResearch/VALIDATION.md` and
`docs/action-plan.md`. This file = live operational state.

Supersedes the 2026-07-06 handover. July facts below are still the last closed
measurement cycle. September work is harness + ops, not a new accepted preset.

## TL;DR

- **Canonical parent: v0.12** (accepted v0.11-zram-swappiness stack).
- **2 accepted bundles** (v0.9c cycle 1, v0.11 cycle 3). Cycles 5 and 6 were
  honest nulls. Do not promote `v0.13-pagecluster0` or `v0.13-vfscache50`.
- **main from 2026-07-07 through 2026-09-09** is almost entirely
  `cursive-backup-bot` CursiveRoot snapshots. The measurement DB is alive; the
  selection loop is not.
- **PR #3 / branch `seed/harness-fail-closed-restore`:** Arc `OLLAMA_HOST`
  (`:11435`) path on inference benches; network decompose/stackdelta fail
  closed without `tc`; stock undo forced to cubic / pfifo_fast / 212992.
  Follow-up on this branch: `benchmark-network-v0.1.sh` now exits *before*
  mutating sysctls when `tc` or `iperf3` is missing (sandbox-verified
  2026-09-10). Dirty BBR restore was **not** live-verified here (no `tc` in
  the agent sandbox).
- **Not done from this sandbox:** clean Stardust Arc idle benchmark, Stardust
  clone sync, QD-archive proposer in production, origin-side raw recompute,
  key rotation, laptop nvidia-smi power channel, BBR multi-flow.
- **Do not Tailscale an agent onto founder machines.** Work the git tree;
  run screens on the rigs.

## Lineage

| Preset | Role | Notes |
| --- | --- | --- |
| v0.9 | Superseded parent | cycle 1 accept (v0.9c) |
| v0.11-zram-swappiness | Accepted candidate | cycle 3 accept 2026-06-26 |
| **v0.12** | **Canonical parent** | default in `seed-session-linux-test.sh` |
| v0.13-pagecluster0 | Retired | cycle 5 honest null |
| v0.13-vfscache50 | Retired | cycle 6 honest null / inconclusive |

## July 6 closed facts (do not lose)

- First autonomous loop (cycle 5) and second (cycle 6) both closed without a
  manual screen step. Both candidates were dead knobs on founder hardware.
- Evidence-gate collision fixed: `HONEST_HARDWARE_CONDITION_FLAGS` void only
  their channel. Config drift auto-heal via `config_version`.
- G4 shipped: Ed25519 SSHSIG v0.2 + `seed_organism confirm-variant` from
  CursiveRoot. Legacy local-sim confirmations count zero.
- Laptop CUDA unlocked (nvidia-580): tinyllama ~5x vs CPU-era. Pre-2026-07-06
  laptop sustained/cold-start numbers are not comparable across that change.
- Stardust Arc SYCL instance built at `~/ollama-arc` port **11435**, 23/23
  layers offloaded once during a game session. **No clean idle number exists.**
  `ollama ps` reports 100% CPU on ipex-llm — trust serve.log offload lines.
- Trust spine live (`os0_identity_keys`, `os0_raw_artifact_index`,
  `os0_trust_evaluations`). `payout_eligible` hard-false.
- Concurrency and idle-power weights stay **0**. Do not promote v0.13-sched.

## What the 2026-09-10 agent could and could not verify

Ran against `seed/harness-fail-closed-restore` in a cloud sandbox (no `tc`,
no Ollama, no founder GPUs):

- `python3 -m unittest discover -s tests` → 82 tests, **1 error**
  (`test_concurrency_sprint_verify` wants `powershell` — pre-existing, not
  introduced by PR #3).
- `benchmark-network-decompose-v0.1.sh` and `stackdelta` exit 1 with
  `tc missing or netem not applied. Refusing to print a stack delta.`
- Pre-fix `benchmark-network-v0.1.sh` did **not** fail closed first: it
  logged, attempted stock undo, then died on missing `ip`. Post-fix it
  exits 1 immediately if `tc` or `iperf3` is absent.
- Arc pin / SLPC / OLLAMA_HOST live paths were not executed.

## Next (priority)

1. On **idle Stardust**: `~/ollama-arc/start-arc.sh`,
   `OLLAMA_HOST=http://127.0.0.1:11435`, one clean sustained + cold-start.
   Only then un-void the Stardust sustained channel.
2. `git pull` on Stardust before the next screen (identity key auto-creates
   on first signing; config auto-heals).
3. Stop mining the audited sysctl library. Next proposer should be
   QD-archive-grounded, not another vfs_cache / page-cluster cousin.
4. Origin-side raw recompute for remote bundles + key rotation/revocation
   before external testers.
5. Wire nvidia-smi GPU power into the laptop harness.
6. BBR multi-flow only when both rigs are idle and `tc` is present.
7. After merge of PR #3, confirm README public claims still match v0.12 +
   two accepted cycles (PR said no README claim changes).

## Rig access (operator, not agent)

```text
ssh laptop    → elizabeth@192.168.1.210
ssh stardust  → elizabeth@192.168.1.102
Key: ~/.ssh/cursive_rig
```

Passwordless sudo is configured on both. Never commit `TAO_SUDO_PASS`.
An older handover revision leaked a sudo password (scrubbed 2026-06-26);
rotate if that was never done.

```bash
export TAO_SUDO_PASS=
bash tools/rig-smoke.sh --dry-run
bash tools/rig-smoke.sh sync all
```

Poll `/tmp/rig-smoke-*.out`. Do not block SSH on long `git pull && preset &&
benchmark` one-liners.

## Gotchas

- `git fetch` then rebase/merge `origin/main` before push — backup bot
  advances main every day.
- Full unittest suite still has the powershell fixture error on Linux-only
  hosts. That is not a merge blocker for harness scripts.
- Isolated Arc ollama is port **11435**, own model dir, leave STOPPED when
  idle.
- Hub API under `hub-api/` is legacy v3.1 scaffolding. Do not treat it as
  the v3.3 economics interface.
