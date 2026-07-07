# CursiveOS — Agent Handover (2026-07-06, post first autonomous cycle)

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
- **V verifier hardening (2026-06-30):** `tools/exp_adversarial_tester.py` now reports A/B/C/D-funded rejected by named gates, with Mode H honest controls accepted or held inconclusive rather than fraud-rejected. See `docs/experiments/V-verifier-hardening-results.md` and `.json`.
- **OS.0 identity contract (2026-07-01):** wrapper + contributor daemon canonical machine ids are `sha256(HW_ID_TUPLE + "\\n")[:16]` (`fingerprint_version=2`). See `docs/os0-machine-identity-contract.md`; dashboard tests collapse aliases and count only `claimed/running` daemon jobs as active.
- **OS.0 dashboard contribution panel (2026-07-01):** dashboard keeps completed requests visible, joins jobs back to request/candidate/reward metadata, and renders per-machine contribution history with alias collapse. This is still read-only/public-alpha and simulated reward only.
- **OS.0 trust spine (2026-07-01):** CursiveRoot now has database-backed `os0_identity_keys`, `os0_raw_artifact_index`, and `os0_trust_evaluations`; seed bundle upload writes identity/raw-artifact/trust rows alongside bundles. `payout_eligible` is hard-constrained false.
- **FIRST AUTONOMOUS CYCLE (cycle 5, 2026-07-06):** proposer-materialized `v0.13-pagecluster0` was privileged-enqueued, daemon-claimed on Stardust, screened, uploaded, and closed **with zero manual screen steps** — request+job `complete`, bundle `7eee6272…`. Per-channel the candidate is **neutral** (cold-start 0.0%, idle 0.0%, memory refault −0.9% ≈ noise, sustained −0.4%): the pre-registered page-cluster hypothesis is not supported on Stardust. Honest null; first proposer→queue→daemon→sensors loop closure.
- **Trust spine exercised live (first rows, 2026-07-06):** upload wrote 1 identity key, 2 raw artifacts, 7 trust evaluations. New bundle gates: recompute ✓ / signed identity ✓ / replay ✓ / independent aggregation pending (correct for a single founder screen). Legacy bundles correctly read `blocked_recompute_mismatch`. Dashboard now renders the trust ledger (panel shipped + verified 2026-07-06).
- **EVIDENCE-GATE COLLISION FIXED (2026-07-06, commit `d69587a`):** honest hardware-condition flags (`HONEST_HARDWARE_CONDITION_FLAGS`) now void only their channel — `sustained_inference_cpu_bound` removes sustained from scoring and severe-gating (recorded in sensor `voided_channels`) instead of fraud-rejecting the bundle; disqualifying flags still reject. Root cause of CPU-bound sustained on BOTH founder rigs: **stock ollama has no Intel Arc or (as installed) NVIDIA backend in use** — A750/GTX-1650 sit idle during inference. Getting GPU inference (ipex-llm ollama or llama.cpp SYCL) is a candidate high-value experiment.
- **CONFIG-DRIFT BUG FIXED (2026-07-06, same commit):** rig-local `.cursiveos/seed/config.json` snapshots froze retired selection math — both founder rigs still carried pre-2026-06-16 weights (network 0.40), which is exactly the Stardust cycle-5 fitness −0.1198 (−14.98% network noise × 0.40 / 50). `DEFAULT_CONFIG` now carries `config_version`; `load_config` replaces older on-disk configs (preserved as `config.json.superseded-vN`). Verified auto-heal live on the laptop.
- **Cycle-5 cross-machine verdict (2026-07-06):** laptop screen through the fixed gate → `inconclusive` (confidence 0.50, fitness −0.0023, `voided_channels: sustained`), trust rows recompute ✓ / identity ✓ / replay ✓. Combined with Stardust's per-channel-neutral screen: **v0.13-pagecluster0 is a dead knob on both machines — retire it; the proposer's next knob is `vfscache50`.** ⚠ Stardust screened with the old fitness weights (config drift) and under normal desktop use; its −0.1198 number is an artifact — trust the per-channel deltas and the laptop screen.
- **LAPTOP GPU INFERENCE ENABLED (2026-07-06):** installed Canonical-signed `nvidia-driver-580` + `linux-modules-nvidia-580-generic-hwe-24.04` (Secure Boot stays enabled — no MOK needed; nouveau was the blocker). ollama now discovers `CUDA0 GTX 1650 4GiB`. Measured: **tinyllama 33.4 → ~166 tok/s (5.0×, 100% GPU)**; phi3 ~25 tok/s (19%/81% CPU/GPU — model+KV slightly exceed 4 GiB VRAM; phi3 pulled to the laptop for the first time). Stability probe: 6 consecutive generations clean (48–52 °C, ≤50 W, no Xid/NVRM errors). ⚠ One unexplained hard reboot occurred during the very first phi3 load (concurrent with its download) — watch for recurrence. **Measurement implications:** laptop sustained channel is now real (no `sustained_inference_cpu_bound` flag → no longer voided); laptop cold-start/sustained numbers from before 2026-07-06 are CPU-era and NOT comparable across the driver change (paired screens stay internally valid); nvidia-smi now exposes GPU power on the laptop (potential new power source — harness currently reads `gpu_none` there). Stardust remains CPU-bound pending an Intel Arc backend (ipex-llm / llama.cpp SYCL).
- **STARDUST ARC BACKEND BUILT (2026-07-06, evening):** ipex-llm SYCL ollama (`2.3.0b20250725-ubuntu`) installed at `~/ollama-arc` as an isolated second instance (port **11435**, own model dir, launcher `~/ollama-arc/start-arc.sh`); Intel compute runtime added via apt (`intel-opencl-icd`, `libze1`, `libze-intel-gpu1`) — userspace only, no driver/kernel change, done while a game ran without disturbing it. **Verified: `Found 1 SYCL devices … Intel Arc A750`, tinyllama `offloaded 23/23 layers to GPU`, KV+compute buffers on SYCL0.** Perf numbers from tonight are meaningless (game owned the GPU). Known quirk: `ollama ps` reports "100% CPU" in ipex-llm builds — trust the serve.log offload lines. Instance left STOPPED (zero VRAM footprint).
- **CYCLE 6 (2026-07-06, laptop):** proposer-materialized `v0.13-vfscache50` screened via the queue → **inconclusive, fitness +0.0023** (neutral, single screen). Second autonomous cycle, second honest null — the audited sysctl library may be near exhaustion on this hardware; QD-archive-grounded proposals are the next selection upgrade.
- **G4 SHIPPED (2026-07-06, `de4aa82`):** real per-machine **Ed25519 identity (SSHSIG v0.2)** — signatures bind identity+nonce to raw-artifact fingerprints, verified via `ssh-keygen -Y`, zero new packages; local-sim demoted to non-independence-grade fallback. New **`seed_organism confirm-variant`** derives confirmation counts from CursiveRoot (signature verify + key registration + replay/Sybil tuple collapse), replacing caller-attested `--confirmations` as the evidence source. Verified live: legacy local-sim bundles count zero. 82 tests pass. Laptop synced + keyed; **Stardust clone still pre-fix — pull before its next screen** (config auto-heals, identity key auto-creates on first signing).
- **Next:** (1) clean Arc benchmark on idle Stardust (`~/ollama-arc/start-arc.sh`, port 11435) + harness integration → un-void Stardust sustained; (2) sync Stardust clone; (3) QD-archive-grounded proposer selection + gated auto-enqueue via the new signed identity; (4) origin-side raw recompute for remote bundles + key rotation/revocation policy (last trust gaps before external testers); (5) wire nvidia-smi GPU power into the laptop harness; (6) BBR multi-flow experiment when both rigs are idle.

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

## Tier 2 remaining

- Productize V trust layer: first CursiveRoot DB trust spine is live (`os0_identity_keys`, `os0_raw_artifact_index`, `os0_trust_evaluations`), but key/wallet/hardware independence and production aggregation still need hardening. Caller-attested `--confirmations N` still cannot create acceptance-grade confidence.
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
- Full `python -m unittest discover -s tests` passes after scoping the older concurrency sprint contract as historical/fixture-backed evidence rather than a global ban on future `tools/seed_organism.py` changes. Use focused H2* checks plus the experiment runner when judging the adversarial hardening itself.