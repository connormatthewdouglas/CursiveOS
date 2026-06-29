# CursiveOS Action Plan
**Last updated:** 2026-06-28
**Current parent preset:** v0.12 (promoted from accepted v0.11-zram-swappiness; cycle 3 closed 2026-06-26)
**Current candidate:** none — v0.12b-swappiness **rejected** 2026-06-28; v0.13-sched **rejected** 2026-06-27
**Current wrapper:** v1.4.5 (memory-pressure 5th channel + observe-only concurrency probe)
**Next focus:** Seed Organism → OS.0 — remove the founder from the loop's center (contributor daemon + requests queue first). See "Next Phase" section below.
**Board reviewed:** 2026-03-23 05:30 EDT

---

## 2026-06-26 Sprint Outcomes (memory-pressure + lineage promotion)

- **Cycle 3 closed — v0.11 ACCEPTED.** Three confirming screens: Stardust normal +0.0954, laptop cross-machine +0.1004, Stardust reversed +0.0947 → confidence 0.875, fitness +0.1004. **2nd accepted variant ever; first selected by the memory channel.** CursiveRoot: 2 accepted bundles (v0.9c cycle 1, v0.11 cycle 3) + 2 payout reports.
- **Key finding preserved:** zram is neutral under `vm.swappiness=0`; v0.11 (= v0.9 + zram + swappiness=60) wins memory (+75.4%) with no inference regression (cold-start −0.5%, sustained 0.0%).
- **5th channel integrated:** `benchmark-memory-pressure-v0.2.sh` in harness v1.4.5; `runs` memory columns; fitness weight 0.10 (provisional).
- **Lineage promoted:** v0.12 canonical parent (= settled v0.11 stack). Future screens use `CURSIVEOS_PARENT_VARIANT=v0.12` by default.

### Measurement frontier (2026-06-28 status)
1. **Concurrency** — H1/H2 pass; H3 fail (0% v0.8 vs v0.12). **Weight 0** (observe-only).
2. **v0.13-sched** — **rejected**: 0% tok/s delta + worse load-power (27% higher J/token).
3. **Load-time power** — observe-only; channel discriminates but no promotable candidate yet.
4. **Idle-power** — Stardust production-path CV **0.016** (selection-usable on desktop); laptop AC scoped (cold run-1 fails N=10); **no cross-machine pooling** (H3). Weight **0** until laptop battery + drop-first rule tested.
5. **v0.12b swappiness** — **rejected** on Stardust (mem +0.7% worse, J/token +3.0%); see `experiments/v0.12b-swappiness-screen-plan.md`.
6. **Rig automation** — `tools/rig-smoke.sh` (SCP/nohup/poll pattern).
7. **Schema:** add `page_cache_state` to harness telemetry (Ch00 open gap).

**Sprint verdict:** the measurement frontier is largely exhausted — concurrency, scheduler (v0.13), load-power, idle-pooling, and v0.12b swappiness were all ruled out with rigor. Diminishing returns on adding sensors. The binding constraint is no longer *measurement quality*; it is that **the loop still has the founder as its hub** (founder picks the variant, runs the screen, attests confirmations, triggers payout). Focus now shifts to removing the founder from the center.

---

## Next Phase: Seed Organism → OS.0  (opened 2026-06-28)

**Diagnosis.** Phase 0 is proven: the loop closes (2 accepted cycles), measures honestly (5 validated channels), and — importantly — *rejects* dead ends correctly. What it cannot yet do is run **without a human orchestrator in the middle.** "Seed → OS.0" is fundamentally the work of removing the founder from the loop so machines we don't own can contribute.

**OS.0 north star (testable definition).** One external person installs one thing; their machine autonomously runs a measurement the organism *requested* and uploads it; they can see their contribution and a placeholder reward — **with zero founder involvement.** This single milestone forces gaps G1, G2, G4, G5 into existence without boiling the ocean.

**Gaps, in dependency order:**

- **G1 — Contributor runtime (daemon). KEYSTONE.** A process that lives on any contributor machine and autonomously: pulls "what should I measure" → runs the screen via the existing harness → uploads → reverts, no SSH/agent babysitting. Embryos exist (`seed-session-linux-test.sh`, `tools/rig-smoke.sh`); productize into an unattended, restartable daemon. Everything else hangs off this.
- **G2 — Requests / job queue in CursiveRoot. (build with G1).** A table the organism writes ("need N confirmations of candidate X on hardware-class Y") and the daemon + dashboard read. This one object unifies *interaction*, *dashboard*, and future *BTC bounties* into a single coordination spine instead of three separate problems. Makes contributor work non-redundant.
- **G3 — Autonomous proposer.** Wire `tools/qd_organism.py` (QD/MAP-Elites simulator, already built) to emit real candidate presets into the G2 queue, so the next variant isn't bottlenecked on founder imagination. This is the "self" in self-improvement.
- **G4 — Trust / independence layer.** Auto-counted confirmations (replace founder-attested `--confirmations N` with independent-bundle counting), hardware/wallet independence, immune/anomaly sensors. **Hard gate in front of money** — believing data from a machine we don't control.
- **G5 — Incentive + interface.**
  - **Dashboard → bidirectional:** render the request queue, per-machine lineage, contributions, and placeholder rewards — not just read-only state. (Addresses the "how does a user feed the organism" gap directly.)
  - **BTC payout — gated by G4.** Real (even tiny) payout cannot ship before Sybil detection exists, or it just funds fake benchmark farms. Order is: trust, *then* money.

**Recommended first build (next sprint): G1 + G2 together** — a minimal contributor daemon + a `requests` table + a dashboard panel that renders the queue. It removes the founder from orchestration, gives the dashboard something real and bidirectional, creates the slot BTC bounties drop into, and makes the "first external tester" milestone (board tasks #6–8) actually runnable by a non-founder. Then layer G3, G4, G5.

**Relationship to the Founding-Operator board tasks (#4–13):** those are the go-to-market wrapper around G1–G5. Sequence matters — **build the daemon + queue spine (G1–G2) before recruiting operators (#7)**, because operators need something that runs itself.

### Housekeeping carried from the 2026-06-28 assessment
- **Reconcile `idle_power` weight vs its own validation.** `DEFAULT_CONFIG` weights `idle_power` 0.30, but the 2026-06-28 CV check failed on laptop AC (CV 1.60) while passing on Stardust (0.016). Either scope idle per-machine or fix the laptop cold-run-1 sampling (same class as the earlier 0.83→0.01 settle fix) — a 0.30-weighted channel should not run on an unreliable measurement.
- **Remove the `C:\WINDOWS\system32\Tasks\goal-deliverables\` reference** from the top of `HANDOVER.md` — a Windows system path leaked into a committed doc; meaningless to other contributors.
- **Prune the 5 stale `claude/*` branches** on the CursiveResearch origin (review/merge/delete).
- **Resolve the 3 open red-team flags** in `CursiveResearch/VALIDATION.md` — especially the **BBR single-flow** flag (keep "switch to BBR" out of public copy / default presets until multi-flow fairness is tested).

---

## 2026-06-16 Sprint Outcomes (historical)

- **Lineage advanced: v0.8 → v0.9** (first inheritance). v0.9 = v0.8 minus the Arc GPU frequency pin.
- **Network claim corrected (real-path A/B):** real 1GbE win is CUBIC→BBR; buffer stack ~0% on ordinary links.
- **Noise floor measured (6× v0.9):** cold-start CV 0.002; network CV 0.192; sustained signal<noise; idle-power fixed in v1.4.4 (CV ≈ 0.01 settled).

## Current State

Phase 0 selection loop is operational. CursiveRoot has **2 accepted mutation bundles** and **2 simulated payout reports** (cycles 1 and 3). The seed organism closes variant → measure → gate → ledger → simulated payout → inheritance on founder rigs. Dashboard: https://connormatthewdouglas.github.io/CursiveOS/

**CursiveRoot status at June 26, 2026:**
- Accepted bundles: v0.9c-cpu-retained (cycle 1), v0.11-zram-swappiness (cycle 3).
- Harness v1.4.5 uploads runs with memory columns + detail bundles.
- Public insert/read policy acceptable for controlled Phase 0 only; harden before external rollout.

**Infrastructure status at June 10, 2026:**
- **Data durability incident:** the free-tier auto-pause + resume left CursiveRoot looking empty for 1–2 hours before the async restore completed. A daily encrypted backup + keep-alive GitHub Action now prevents the pause and keeps independent backups. See `docs/specs/cursiveroot-data-durability-v1.md`. ⚠️ Requires two repo secrets (`SUPABASE_DB_URL`, `BACKUP_PASSPHRASE`) — not yet configured.
- **Schema is now tracked:** full CursiveRoot schema captured as migrations under `supabase/migrations/` and registered in `supabase_migrations` on the live project.
- **Security hardening applied:** `security_invoker` on `v_l5_*` views, pinned `search_path` on all l5 functions, anon/authenticated EXECUTE revoked on economics functions.
- **Machine identity canonicalized (board task #3 done):** wrapper v1.4.1 computes fingerprint v2 from stable hardware only (CPU model | board | GPU PCI ids) so kernel updates no longer fragment identity. Legacy slugs and v1 hashes map via the new `machine_aliases` table (backfilled: vega, elizabe, stardust). Missing `os`/`kernel` on machine rows backfilled.
- **Founder rig hardware changed:** the Vega rig was rebuilt (Intel CPU + Arc A750, 64 GB RAM, 1 TB NVMe). New hardware = new fingerprint = new machine; it needs its own genesis baseline before the v0.9 screen. The one-paste session script `seed-session-linux-test.sh` handles recovery → genesis → screen → upload in a single command.

**v0.8 confirmed stack (3 tweaks on top of v0.7 base):**
- `kernel.sched_util_clamp_min=128` (wq-013)
- `net.ipv4.tcp_tw_reuse=1` (wq-014)
- `vm.swappiness=0` (wq-015)

---

## Active Board Tasks — Priority Order

### 1. ~~Apply the decision-grade sensor migration~~ ✅ done (2026-06-10)
- `run_detail_bundles` exists on CursiveRoot and is part of the tracked baseline migration.
- Anon insert/select retained for founder bootstrap; authenticated tester/machine identity still required before external rollout.

### 2. Run the v0.9 network-efficient parent/candidate screen ← NEXT PHYSICAL TEST
- On the rebuilt founder rig (Intel + Arc A750), paste the one-command session:
  it recovers any saved results, records the new machine's genesis baseline,
  runs the v0.8 → v0.9 screen, uploads everything, and prints the verdict.
- Then repeat with reversed order (v0.9 → v0.8) and on at least one additional machine.
- Treat each single screen as diagnostic only; do not accept inheritance from one host/order.

### 3. ~~Canonicalize machine identity~~ ✅ done (2026-06-10)
- Fingerprint v2 (stable hardware identity) is the canonical join key as of wrapper v1.4.1.
- Old slug ids and v1 hashes preserved in `machine_aliases`; `os`/`kernel` backfilled.

### 4. Define the Founding Operator program
- Write the simple rules for who qualifies, what they do, what they get, and how future upside will be considered.
- Keep the framing serious and non-hype: early operators, not disposable testers.

### 5. Create the contributor ledger
- Track who contributed hardware, runs, bugs found, and overall contribution value.
- This is the bridge between goodwill now and stronger incentives later.

### 6. Improve the first-run external experience
- Tighten onboarding, rollback clarity, error reporting, and expectation-setting.
- Goal: the first external run feels safe, legible, and worth repeating.

### 7. Recruit 3–5 technically aligned founding operators
- Prioritize local AI, mining, homelab, and builder communities.
- Prefer mission-aligned operators over one-off paid testers.

### 8. White-glove the first cohort
- Treat the first external operators as collaborators.
- Use their runs and feedback to harden the product and onboarding.

### 9. Use paid testers only for narrow QA later
- Fiverr-style testing is not the main validation engine.
- Reserve paid testers for controlled onboarding/usability checks after the first-run flow is stable.

### 10. Buy hardware only where it closes meaningful validation gaps
- Spend hardware budget where it reduces uncertainty or covers an important user segment.
- Prefer coverage/relevance over raw compute prestige.

### 11. Prioritize reliability and repeatability over flashy features
- Near-term product work should focus on safe rollback, debuggability, and predictable external success.
- Add new features only when they support trust or leverage.

### 12. Continue improving the preset stack only when gains are measured
- Every new tweak should be benchmarked, meaningful, and worth the added complexity.
- Avoid complexity creep that makes external testing harder.

### 13. Build early community through measured proof
- Share evidence, real deltas, and trust-building results where target users already gather.
- The immediate goal is not broad hype; it is converting a few good operators into repeat contributors.

---

## v1.5 Gate Checklist

- [ ] 5+ external machines running the wrapper with auto-submit to CursiveRoot
- [ ] Clean safety record — no bricked systems, no data loss
- [ ] ≥1.5% average mining/inference gain confirmed from external machines
- [ ] CursiveRoot confirmed receiving auto-submit from machines we don't control
- [ ] Safety audit: `--undo` tested on every fleet machine
- [ ] Wrapper works on fresh git clone
- [ ] Plain-English explainer written for external testers
- [x] CursiveOS rebrand executed (2026-03-25)

---

## Scope Rules (standing)

- **Complexity kill switch:** >1 new package required → simplify or drop
- **Validation rule:** ≥2 paired runs before any tweak enters preset stack
- **No permanent changes:** every tweak reversible, `--undo` always works
- **Self-fleet only** until v1.5 gate — no public solicitation before then
- **No DePIN/incentive layer** before v1.5 gate
- **Broader crypto mining scope:** tool is chain-agnostic, Kaspa/ETC/Monero valid targets for Phase 2+

---

## Copper Execution Docket (deferred to Copper)

*No pending items.*

---

## Benchmark Limitations (known, documented)

- **Inference delta is small on GPU (~5–15%)** — network is the headline (+400–900%). Inference improvement from GPU freq + THP is real but modest for single-stream workloads.
- **Concurrent throughput measured but not yet discriminative** — `benchmark-inference-concurrency-v0.1.sh` reports aggregate tok/s under 4 parallel streams (H1 CV ≤ 0.15 on both founder rigs). v0.12 vs v0.8 shows 0% delta on Stardust; fitness weight stays 0 until a scheduler-axis candidate moves the channel.
- **VRAM model table incomplete** — inference benchmark covers 4GB+ (phi3) and 8GB+ (mistral). Cards with 2–3GB VRAM have no recommendation yet.
- **ROCm auto-install Ubuntu/Debian only** — other distros get a manual URL. Covers the majority of mining rigs.
- **CPU inference correctly suppressed** — cold-start is the honest CPU story; sustained CPU inference delta is unreliable due to thermal variance from C-state changes.

## Parking Lot (post-v1.5)

- **Full NVIDIA GPU tuning** — power limits, persistence mode, clock management targeting desktop RTX cards (3080/4090). Dedicated workstream, requires desktop NVIDIA hardware to validate properly.
- ~~**Concurrent throughput benchmark**~~ — shipped v0.1 probe; H3 signal blocked for memory-class stack. Re-test with scheduler candidate.
- **VRAM model table expansion** — add llama3.2:1b (~0.8GB), qwen2:1.5b (~0.9GB) for 2–3GB cards.
- Intel Arc SYCL backend for llama.cpp (current Vulkan crashes on 3B+)
- DePIN incentive layer (Hivemapper/Helium style)
- SN64 Chutes live validator test
- Bittensor subnet design (v3.0)
- Bootable ISO (v4.0+)
