# CursiveOS Action Plan
**Last updated:** 2026-06-16
**Current parent preset:** v0.9 (v0.8 stack minus the Arc GPU frequency pin; promoted 2026-06-16 — first lineage inheritance)
**Current candidate:** none active — next mutation TBD from the buffer-decomposition + variance sprint
**Current wrapper:** v1.4.3 (stable fingerprint v2 + power-source/phase telemetry + GPU-side power)
**Board reviewed:** 2026-03-23 05:30 EDT

---

## 2026-06-16 Sprint Outcomes

- **Lineage advanced: v0.8 → v0.9** (first inheritance). v0.9 = v0.8 minus the Arc GPU frequency pin, confirmed equal-or-simpler on both machines (Stardust both orders + i5 laptop). GPU pin proven dead weight.
- **Network claim corrected (real-path A/B).** On a real 1GbE NIC at 50ms+0.5% loss: CUBIC 43 → BBR 851 Mbit/s (+1875%), but BBR+our-buffer-stack 845 (−0.7%). The real-world network win is **entirely the CUBIC→BBR swap**; our buffer/qdisc tuning adds ~0 on ordinary links. The loopback "+246% ours" was a BDP artifact. Public claim going forward = "switch to BBR," not buffer tuning.
- **Noise floor measured (6× v0.9).** Cold-start CV 0.002 (rock-solid, the reliable selection channel), network CV 0.192 (needs CV-escalation; magnitude unreliable), sustained signal<noise, idle-power(CPU) CV 0.83 (near-random). Use per-channel confirmation counts; don't gate on sustained-single-stream or idle power until measurement improves.
- **Telemetry/tooling:** wrapper v1.4.3 adds a working GPU-side power channel (A750 ~37W idle; total power now visible). Fitness gained a parsimony term (equal-performance-fewer-knobs is now acceptable). Buffer-decomposition + real-path benchmarks added.

### Phase D outcomes (2026-06-16)
- ✅ **Power measurement fixed (wrapper v1.4.4).** The CV 0.83 idle-power noise was a *sampling artifact* (sampling during the post-benchmark thermal tail), not inherent. Added settle (`IDLE_SETTLE` 6s) + inter-sample spacing + higher counts (CPU 8, GPU 5). Settled true-idle gives CV ≈ 0.01 — idle power is now a usable selection channel.
- ✅ **GPU-pin power cost quantified: ~0 W at idle** (42.15 W unpinned vs 42.16 W pinned, reproduced). So v0.9 dropping the pin is **parsimony, not power savings** (corrects the earlier "unmeasured GPU power" worry). A750 idle is static-dominated; **load-time power still untested**.

### Next steps
1. **Add a concurrency inference sensor** — single-stream sustained is below its noise floor; scheduler tweaks can only show under parallel load. (Now the top measurement gap.)
2. **Next mutation candidate** evaluated primarily on cold-start (lowest-noise channel) + now-reliable idle power: a memory-pressure (zram/THP) or scheduler tweak vs v0.9. Network is no longer a useful mutation axis (lever is just BBR, already in the stack).
3. **Load-time power** measurement (the probe covers idle only) before any load-power claim about GPU pinning or governors.

## Current State

Phase 0 has begun in operation. CursiveRoot now has a live decision-grade analyzer that separates characterization data from mutation-selection evidence. One real Vega genesis baseline is recorded in CursiveRoot with decision `measured_baseline`, not accepted fitness: network +515.20% under loopback WAN simulation, cold-start -3.11%, sustained -0.36%, idle power +3.2W. The latest Intel i5 run on 2026-05-31 shows the same pattern: strong network lift, a promising cold-start result, small sustained-inference movement, and a measurable idle-power cost. The next action is still to screen a network-only candidate against v0.8, with multi-sample power capture and no payout from one observation.

**CursiveRoot status at June 10, 2026:**
- 77 regular benchmark run records are visible (Mar 20 → Jun 1).
- 1 seed bundle exists (`genesis-baseline-v0.8`, machine `bda4bd63b3564822`).
- 0 accepted seed mutations and 0 seed payout reports exist.
- 0 candidate screen bundles are visible (a v0.9 run row exists from Jun 1 on the i5, but no screen bundle was uploaded).
- 0 run detail bundles; the v0.2 migration **is applied** (table exists), detail bundles will appear with the next recovered/new upload.
- Public insert/read policy is acceptable only for controlled Phase 0 and must be hardened before external rollout.

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
