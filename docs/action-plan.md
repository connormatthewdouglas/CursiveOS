# CursiveOS Action Plan
**Last updated:** 2026-05-31
**Current parent preset:** v0.8 (28 tweaks)
**Current candidate:** v0.9-network-efficient (network-only power tradeoff screen)
**Current wrapper:** v1.4
**Board reviewed:** 2026-03-23 05:30 EDT

---

## Current State

Phase 0 has begun in operation. CursiveRoot now has a live decision-grade analyzer that separates characterization data from mutation-selection evidence. One real Vega genesis baseline is recorded in CursiveRoot with decision `measured_baseline`, not accepted fitness: network +515.20% under loopback WAN simulation, cold-start -3.11%, sustained -0.36%, idle power +3.2W. The latest Intel i5 run on 2026-05-31 shows the same pattern: strong network lift, a promising cold-start result, small sustained-inference movement, and a measurable idle-power cost. The next action is still to screen a network-only candidate against v0.8, with multi-sample power capture and no payout from one observation.

**CursiveRoot status at May 31, 2026:**
- 74 regular benchmark run records are visible.
- 1 seed bundle exists (`genesis-baseline-v0.8`, machine `bda4bd63b3564822`).
- 0 accepted seed mutations and 0 seed payout reports exist.
- 0 candidate screen bundles are visible.
- 0 run detail bundles are visible until the v0.2 migration is applied.
- Public insert/read policy is acceptable only for controlled Phase 0 and must be hardened before external rollout.

**v0.8 confirmed stack (3 tweaks on top of v0.7 base):**
- `kernel.sched_util_clamp_min=128` (wq-013)
- `net.ipv4.tcp_tw_reuse=1` (wq-014)
- `vm.swappiness=0` (wq-015)

---

## Active Board Tasks — Priority Order

### 1. Apply the decision-grade sensor migration
- Apply `references/SUPABASE-MIGRATION-decision-grade-sensors-v0.2.sql` to CursiveRoot.
- Confirm `run_detail_bundles` accepts recovered full-test detail uploads.
- Keep anon insert/select only for founder bootstrap; plan authenticated tester/machine identity before external rollout.

### 2. Run the v0.9 network-efficient parent/candidate screen
- Run v0.8 -> v0.9 and then v0.9 -> v0.8 on the same host.
- Repeat on at least one additional machine.
- Treat each single screen as diagnostic only; do not accept inheritance from one host/order.

### 3. Canonicalize machine identity
- Use hardware fingerprint ids as the canonical CursiveRoot join key.
- Preserve old slug machine ids as aliases, not primary organism identity.
- Backfill missing `os` and `kernel` on old machine rows where possible.

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
- **Concurrent throughput not measured** — this is where scheduler tuning (autogroup, granularity, sched_util_clamp_min) shows its real inference impact. Multiple parallel requests stress the scheduler in ways single-stream doesn't.
- **VRAM model table incomplete** — inference benchmark covers 4GB+ (phi3) and 8GB+ (mistral). Cards with 2–3GB VRAM have no recommendation yet.
- **ROCm auto-install Ubuntu/Debian only** — other distros get a manual URL. Covers the majority of mining rigs.
- **CPU inference correctly suppressed** — cold-start is the honest CPU story; sustained CPU inference delta is unreliable due to thermal variance from C-state changes.

## Parking Lot (post-v1.5)

- **Full NVIDIA GPU tuning** — power limits, persistence mode, clock management targeting desktop RTX cards (3080/4090). Dedicated workstream, requires desktop NVIDIA hardware to validate properly.
- **Concurrent throughput benchmark** — measure requests/sec under parallel load. Scheduler tweaks show here.
- **VRAM model table expansion** — add llama3.2:1b (~0.8GB), qwen2:1.5b (~0.9GB) for 2–3GB cards.
- Intel Arc SYCL backend for llama.cpp (current Vulkan crashes on 3B+)
- DePIN incentive layer (Hivemapper/Helium style)
- SN64 Chutes live validator test
- Bittensor subnet design (v3.0)
- Bootable ISO (v4.0+)
