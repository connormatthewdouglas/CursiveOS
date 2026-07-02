# CursiveOS

**A new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.**

Measurement-first Linux optimization for local compute. One command. Measurable results. A Bitcoin-native economic layer with no token tricks, no pool, and no governance theater.

CursiveOS is built for two core audiences:

- Crypto miners and decentralized compute operators
- Local AI/LLM users running Ollama, llama.cpp, and home inference nodes

The OS-layer bottlenecks are the same for both: network transport ceilings, scheduler and governor latency, memory pressure, and GPU/CPU power-state behavior. CursiveOS benchmarks your machine, applies reversible presets, benchmarks again, and shows you the measured delta.

CursiveOS is building toward a v1.0 release that ships with a **natural-language shell as the default terminal**. The interface humans have used to operate Linux for fifty years becomes a conversation with a local agent. You describe outcomes; the agent finds the mechanism. Full roadmap: [ROADMAP.md](ROADMAP.md).

## Try It Now — one paste, full session

Paste this one command on a Linux test machine. It runs the entire Phase 0
measurement session and uploads everything to CursiveRoot automatically:

```bash
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y curl; }; (curl -fsSL https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-session-linux-test.sh || wget -qO- https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-session-linux-test.sh) | bash
```

What it does, in order:

1. **Recovers** any results still saved locally from earlier installs.
2. **Genesis baseline** — records this machine's v0.8 baseline under its
   hardware fingerprint (skipped automatically if CursiveRoot already has one).
3. **Optional mutation screen** — no candidate is active by default. To run an
   explicit historical or new screen, set `CURSIVEOS_SCREENS="normal:<variant>"`;
   the script compares that candidate against the current parent preset (`v0.12`).
   A single screen is diagnostic only — one observation can never accept a
   mutation or create a payout.
4. **Uploads** all artifacts and prints the analyzer verdict.

Every step is idempotent — if anything is interrupted, just paste the same
command again. All presets are reverted automatically at the end of each
benchmark pass. The genesis baseline does not produce a payout; accepted
variants can later flow through a *simulated* revenue cycle that pays no real
money, and benchmark testers are not paid for running a test unless they are
also the contributor of an accepted variant.

**Data transparency:** At the end of a run, CursiveOS uploads benchmark results to **CursiveRoot** (the project's sensor array and hardware-performance database). It uploads hardware and performance metadata (CPU/GPU model, OS/kernel version, benchmark deltas) — **not** personal files, documents, browser data, or shell history. The organism needs this data to learn which optimizations work on which hardware and to improve recommendations safely over time.

> **CursiveRoot durability:** CursiveRoot runs on free-tier Supabase and is backed up daily (encrypted) with an auto-pause keep-alive. See [supabase/README.md](supabase/README.md) and [docs/specs/cursiveroot-data-durability-v1.md](docs/specs/cursiveroot-data-durability-v1.md).

**See live results from all machines:**

```
./scripts/cursiveroot-status.sh
```

### Current mutation status

There is **no active candidate configured by default**. Cycle 3 already accepted
**v0.11-zram-swappiness** (v0.9 + zram + `vm.swappiness=60`) and promoted it to
**canonical parent v0.12**. Follow-on swappiness 100 (`v0.12b`) and scheduler
(`v0.13`) screens were rejected, so the near-term focus has moved from more
manual screens to **Seed Organism → OS.0**: contributor daemon + request queue.
The V verifier-hardening pass extends H2*: fabricated evidence is rejected by
raw-artifact recompute, cross-state replays by a CursiveRoot/global fingerprint
index, parsimony overclaims by invariant gates, and funded confirmation-Sybil
patterns by independent-aggregation policy. Honest noisy/weird-hardware controls
are accepted or held inconclusive rather than fraud-rejected. The first OS.0 DB
trust spine now stores signed identity keys, raw-artifact replay pointers, and
trust evaluations in CursiveRoot. Real BTC/reward remains simulated/gated until
production Sybil resistance exists.

To run an explicit historical screen on a Linux box, name the candidate:

```bash
command -v curl >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y curl; }; curl -fsSL https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-mutation-linux-test.sh | CURSIVEOS_CANDIDATE_VARIANT=v0.12b-swappiness bash
```

Cycle 3 result (accepted 2026-06-26): v0.11-zram-swappiness vs v0.9 parent,
three confirming screens (Stardust normal +0.0954, laptop +0.1004, Stardust
reversed +0.0947) → **accepted**, confidence 0.875, fitness +0.1004. Memory
channel drove the win; no inference regression. **Canonical parent is now v0.12**
(= settled v0.11 stack). CursiveRoot holds 2 accepted bundles and 2 payout
reports.

### A note on the network numbers (honesty box)

The old headline "+500–900% network" numbers are now scoped more tightly. The
large measured win on ordinary ≤1GbE lossy paths is the **CUBIC → BBR** switch;
with BBR held constant, the CursiveOS buffer/qdisc stack measured ~0% on that
real path. Loopback lossy-WAN tests remain useful for mechanism debugging, but
their magnitudes do not transfer directly to real links. Because in-tree BBRv1
has known multi-flow fairness / retransmit risks, public copy and future default
recommendations should stay scoped to "single flow under loss" until the
multi-flow fairness test is done.

### Individual test paths (advanced)

The full session above supersedes these for normal testing, but each phase can
still be run on its own:

- **Benchmark only** (no seed organism bookkeeping):
  `git clone https://github.com/connormatthewdouglas/CursiveOS.git; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh`
- **Genesis baseline only:** `seed-organism-linux-test.sh` (same curl-pipe pattern as above)
- **Mutation screen only:** `seed-mutation-linux-test.sh` (same curl-pipe pattern as above)

Details and development workflows: [docs/specs/seed-organism-runbook-v0.1.md](docs/specs/seed-organism-runbook-v0.1.md).

## Results

### What's validated now

The project no longer leads with a single headline percentage, because the honest
picture is per-channel and hardware-scoped. What the measurement loop has actually
established, on real hardware, with repeat + counterbalanced + cross-machine
confirmation:

- **Selection loop closed twice.** Lineage advanced **v0.8 → v0.9 → v0.12** through
  two accepted cycles (v0.9c cold-start retention, cycle 1; v0.11-zram-swappiness
  memory win, cycle 3). Equally important, a string of candidates were **rejected**
  by measurement — v0.10 (neutral), v0.12b (worse), v0.13 (regressed) — which is the
  half of selection most projects never show. CursiveRoot holds 2 accepted bundles
  and 2 (simulated) payout reports.
- **Network — scoped honestly.** On ordinary ≤1GbE lossy links the real win is the
  **CUBIC → BBR** congestion-control switch (large under loss); with BBR held
  constant, the CursiveOS buffer/qdisc stack measured **~0%**. The old "+500–900%"
  figures were loopback-BDP artifacts and do not transfer to real links. Claim is
  scoped to **single flow under loss** pending multi-flow fairness testing (see the
  honesty box above).
- **Cold-start latency — real but hardware-scoped.** ~**−51%** on the Ryzen 7 5700 +
  Arc A750 desktop and large gains on older CPU-only hardware; **~0%** on some
  laptops. Reported by hardware class, never as a universal number.
- **Memory pressure — the newest earned win.** v0.11 (zram + `vm.swappiness=60`) cut
  cgroup memory-pressure refault time **~4×** vs the v0.9 parent (e.g. Stardust
  45s→11s) with **no inference regression** (cold-start −0.5%, sustained 0.0%),
  confirmed on two machines before it earned any fitness weight. zram is neutral
  under `swappiness=0` — the swappiness change is what unlocks it.
- **Idle power — a real tradeoff, gated accordingly.** The v0.8-era stack raised idle
  power on some hosts; the idle-power channel is currently **gate-only** in fitness
  (blocks severe regressions, awards no reward) until its noise floor is trustworthy
  fleet-wide.

The per-hardware tables below are the **initial March-2026 measurements** and are
kept for transparency; their network magnitudes predate the real-path correction
and should be read through the scoping note that follows them.

### Initial per-hardware measurements (March 2026 — loopback, historical)

> **Read these as historical.** They use the repository's **loopback** WAN
> simulation, which inflates network deltas via a loopback-BDP artifact. The
> real-path correction and current scoping are summarized above and in the note
> after the tables.

### AMD Ryzen 7 5700 + Intel Arc A750

| Benchmark | Canonical baseline | CursiveOS Presets | Delta |
| --- | --- | --- | --- |
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 140–181 Mbit/s | **~1000 Mbit/s** | **+454–616%** |
| **Cold-start latency** (GPU idle → first inference token) | 1021–1024ms | 996–997ms | **-22–27ms (-2.3 to -2.6%)** |
| Sustained inference (warm model, steady-state) | 75–76 tok/s | 76–77 tok/s | +1.2–1.5% |
| **Idle power draw** (C-states + governor) | ~6W | ~20W | +~14W |

### AMD FX-8350 + RX 580

| Benchmark | Canonical baseline | CursiveOS Presets | Delta |
| --- | --- | --- | --- |
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 171 Mbit/s | **1182 Mbit/s** | **+591%** |
| **Cold-start latency** | 2462–2493ms | 2095–2098ms | **-366–395ms (-14.9 to -15.8%)** |
| Sustained inference (warm model, CPU-bound) | 19.5 tok/s | 20.5 tok/s | +4.5–5% |

### Lenovo IdeaPad Gaming 3 (11th Gen i5 + GTX laptop)

| Benchmark | Canonical baseline | CursiveOS Presets | Delta |
| --- | --- | --- | --- |
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 237.8 Mbit/s | **1429.8 Mbit/s** | **+501%** |
| **Cold-start latency** | 889.1ms | 630.8ms | **-29%** |
| Sustained inference (warm model, steady-state) | 32.86 tok/s | 33.25 tok/s | +1.2%|
| **Idle power draw** | 3.48W | 4.36W | +0.9W |

### Seed baseline recorded in CursiveRoot (May 25, 2026)

| Hardware | Benchmark | Canonical baseline | v0.8 | Delta |
| --- | --- | ---: | ---: | ---: |
| AMD Ryzen 7 5700 + Intel Arc device `e223` (`bda4bd63b3564822`) | Network throughput (loopback WAN sim) | 205.8 Mbit/s | 1266.1 Mbit/s | +515.20% |
| Same host | Cold-start latency | 793.7ms | 769.0ms | -3.11% |
| Same host | Sustained inference | 154.17 tok/s | 153.61 tok/s | -0.36% |
| Same host | Idle power draw | 14.88W | 18.11W | +3.2W |

This is a genesis baseline characterization, reconstructed into CursiveRoot from the terminal summary after the database was unavailable during upload. It is not a candidate acceptance and produces no payout.

**Network is now scoped as a safety/measurement claim.** Under the repository's controlled loopback WAN simulation (50ms RTT, 0.5% loss), transport changes can produce large throughput changes, but real-path A/B showed the ordinary ≤1GbE win is dominated by CUBIC→BBR while the CursiveOS buffer/qdisc stack adds ~0% with BBR held constant. Treat network magnitudes as path-scoped evidence, not a universal performance promise; multi-flow fairness/retransmit testing remains open before BBR becomes an unqualified public/default recommendation.

**Power tradeoff is real.** v0.8 disables CPU idle states and may pin GPU frequency. The recorded Vega seed baseline incurred +3.2W at idle, and older measurements also showed increases. Whether the latency benefit justifies the cost is workload-specific; the next candidate isolates this tradeoff instead of assuming it.

**Cold-start latency matters for mining and inference.** Testers query miners unpredictably. Between queries, your GPU idles to 300–600 MHz. CursiveOS pins the Arc A750 to 2000 MHz minimum — 22–27ms faster on every cold request. On older CPU-only hardware, C-state and governor changes alone cut 366–395ms per cold request. At scale this shifts active set membership.

---

## What it does

CursiveOS applies a set of temporary, safe OS tweaks tuned for local compute workloads. The full-test script automatically reverts presets at the end of each run. Reboot or `--undo` are optional fallback paths.

**Representative core tweaks** (early-lineage stack, shown for intuition). The
authoritative current stack is the canonical parent **v0.12** in
[`presets/`](presets/); the selection loop has since refined specific values —
see the note under the table.

| Tweak | Value | Why |
| --- | --- | --- |
| CPU governor | performance | Full clock speed, no scaling delays |
| Energy perf preference | performance | AMD/Intel power hint to hardware |
| Net buffers (rmem/wmem_max) | 16MB | High-BDP hypothesis; ordinary ≤1GbE BBR-held stack delta measured ~0% |
| tcp_rmem / tcp_wmem | 4096 / 262144 / 16MB | High-BDP hypothesis; keep magnitude scoped until real high-BDP test |
| TCP congestion control | BBR + fq | Path-scoped lossy single-flow win; multi-flow fairness/retransmit testing open |
| TCP slow start after idle | disabled | Throughput doesn't drop after pauses |
| net.core.netdev_max_backlog | 5000 | Prevents silent packet drops under P2P load |
| net.core.somaxconn | 4096 | Larger connection queue |
| Scheduler autogroup | disabled | Desktop grouping hurts server workloads |
| kernel.sched_min_granularity_ns | 1ms | Faster wakeup for inference threads |
| vm.swappiness | 10 | Avoid swap under sustained load |
| NMI watchdog | disabled | Reduces interrupt overhead |
| Transparent Huge Pages | always | Better for large ML model allocations |
| THP defrag | madvise | Targeted defrag for ML — no system-wide stall |
| vm.compaction_proactiveness | 0 | Stops background THP compaction jitter |
| vm.dirty_ratio | 5 | Start disk flushing earlier |
| vm.dirty_background_ratio | 2 | Background IO starts sooner |
| kernel.numa_balancing | 0 | Eliminates spurious page fault overhead |
| AMD CPU turbo boost | enabled | Ensure boost not disabled by power profile |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency |
| CPU C6 idle state | disabled (by name) | Cross-BIOS robust — eliminates ~1ms wakeup jitter |
| GPU SLPC efficiency hints | ignored | Arc A750 full performance mode |
| GPU min frequency | 2000 MHz | Prevents drop to 300 MHz between requests |
| SYCL persistent cache | enabled | Cache compiled GPU kernels (Arc only) |

> **What selection changed since this early stack.** The loop measured its way
> off several of these: **v0.9 dropped the Arc GPU frequency pin** (the two GPU
> rows above — measured dead weight, no cold-start benefit), and **v0.11 added a
> zram swap device and set `vm.swappiness=60`** (the memory-pressure win; the
> `swappiness=10` row above is early-lineage). The result is canonical parent
> **v0.12**. Treat the rows above as intuition for the *kind* of tuning involved,
> and `presets/cursiveos-presets-v0.12.sh` as the source of truth.

Apply manually (canonical parent):

```
./presets/cursiveos-presets-v0.12.sh --dry-run      # preview all changes first
./presets/cursiveos-presets-v0.12.sh --apply-temp   # apply
./presets/cursiveos-presets-v0.12.sh --undo         # revert
```

---

## Intel Arc A750 — AI Inference Setup

Getting Arc running AI inference is normally a 6-step process most people never finish. One script:

```
./setup-intel-arc.sh
```

Installs Intel compute-runtime (OpenCL 3.0), Level Zero, and configures Ollama's Vulkan backend for Arc. After running, your A750 does inference at ~76 tok/s on TinyLlama.

---

## Layer 5 — Economics (v3.3)

The incentive layer is Bitcoin-native and has no token, no pool, and no governance. See [`white-paper.md`](white-paper.md) and [`docs/specs/layer5-economics-v3.3.md`](docs/specs/layer5-economics-v3.3.md) for the full specification.

**How it works:**

- **Fast tier users** pay `$2.00/month` per machine (settled in BTC at payment time). Stable tier is free.
- **All cycle revenue** is distributed directly to contributors each cycle, split between two streams:
  - **Current-cycle stream** pays contributors whose variants were merged this cycle, weighted by measured fitness improvement.
  - **Lifetime stream** pays all contributors who have ever had work merged, weighted by cumulative lifetime fitness. Every cycle. Forever.
- **The split between streams is dynamic**, controlled by a **metabolic sensor** that measures the organism's current need for recruitment vs. retention. Genesis state is 20/80 lifetime-favored; the sensor moves it toward equilibrium as the organism matures.
- **Testers** run benchmarks on their hardware and report measurement data to the sensor array. In exchange they receive free Fast tier access. Testers do not earn lifetime fitness and do not receive revenue share — their compensation is the product itself. This is deliberate; it prevents spoofing attacks from being profitable.
- **No governance, no voting, no judgment.** Fitness is determined by sensor measurement. The sensor array replaces governance entirely.
- **Two-year claim window.** Accruals must be claimed within two years or redistribute to active claimants. Lifetime fitness itself is permanent.
- **Forks inherit obligations.** The lifetime ledger is Bitcoin-anchored; forks that use the genome owe the same payments to the same contributors.

**Current status (July 1, 2026):** v3.3 economics is specified, not deployed for real payment. Phase 0 has **2 accepted variants** (v0.9c cycle 1, v0.11 cycle 3) with simulated payout reports. Parent preset v0.12. Harness v1.4.5 with memory channel integrated. CursiveRoot now includes the OS.0 request/job queue and trust-spine tables; public-alpha write paths remain simulated/not payout eligible and must be auth-hardened before broader testing.

---

## Roadmap

- **Done** → Intel Arc inference stack (one-script setup)
- **Done** → Preset stack v0.8-locked (28 tweaks, fully reversible)
- **Done** → Initial v0.8 measurements: strong network change across 3 initial hardware configurations plus one recorded Vega seed baseline
- **Done** → Genesis seed bundle: real May 25 Vega baseline uploaded to CursiveRoot with no payout
- **Done** → Full-test wrapper v1.4 (CursiveRoot auto-submit, zero setup)
- **Done** → CursiveRoot: live hardware/performance database
- **Done** → Decision-grade CursiveRoot analyzer: cohort signal, organism state, and data hygiene reporting
- **Done** → Phase 0 selection loop closed twice: cycles 1 and 3 accepted (v0.9c, v0.11-zram-swappiness) with repeat + counterbalanced + cross-machine confirmation; lineage v0.8 → v0.9 → v0.12
- **Done** → Memory-pressure 5th sensor channel (harness v1.4.5), validated cross-machine before earning fitness weight
- **Done** → H2/H2* adversarial-tester audit: fabricated, replayed, and gamed submissions rejected by named production gates
- **Done** → V verifier-hardening: raw-artifact recompute, signed local identity, global replay index, independent aggregation policy, D-funded rejection, and H false-positive controls
- **Done** → OS.0 trust spine v1: CursiveRoot tables for identity keys, raw-artifact index, and trust evaluations with `payout_eligible` hard-disabled
- **Done** → OS.0 measurement queue + contributor daemon spine: first organism-requested measurement autonomously claimed, executed, and completed from the queue
- **Done** → v3.3 economic architecture specified (white paper v2.6)
- **Done** → Agent architecture specified (measurement daemon + natural-language shell)
- **In progress** → Hub rebuild to v3.3 (new design system, seven-tab frontend, Supabase backend)
- **In progress** → Productize V trust rails in CursiveRoot identity, request queue, and aggregation tables before external tester rollout
- **Next** → First external tester running full sensor array; validate population confirmation
- **Next** → v0.9 ISO alpha: first installable CursiveOS with measurement daemon
- **v1.0** → Flagship release with natural-language shell as default terminal
- **v2.0** → Self-updating fleet: measurement-native installs improve automatically as the organism learns
- **v3.0** → Workload-adaptive tuning across inference, mining, build, and other workload classes

Full roadmap with transition milestones: [ROADMAP.md](ROADMAP.md).

---

## Why this hardware

Local compute can't thrive long-term on a single vendor's silicon. CursiveOS is being measured on **AMD CPU + Intel Arc GPU**, plus Intel laptop hardware — configurations many optimization guides ignore. If you're a non-NVIDIA miner or inference operator, this project is built with you in mind. The sensor array measures empirical hardware variance, so unusual or underserved configurations are more valuable to the organism than popular ones.

---

## Documentation

- [`ROADMAP.md`](ROADMAP.md) — four-transition roadmap with milestones and flagship features by release
- [`white-paper.md`](white-paper.md) — technical white paper (v2.6)
- [`software-organisms.md`](software-organisms.md) — **Software Organisms: why human governance loses, and what replaces it** — the thesis beneath the whole project: capture, selection in the age of self-improving software, and the organism architecture
- [`docs/specs/seed-organism-v0.1.md`](docs/specs/seed-organism-v0.1.md) — Phase 0 minimum viable organism specification
- [`docs/experiments/H2-adversarial-tester-results.md`](docs/experiments/H2-adversarial-tester-results.md) — H2/H2* dishonest-submission audit and remediation record
- [`docs/experiments/V-verifier-hardening-results.md`](docs/experiments/V-verifier-hardening-results.md) — V verifier-hardening results: recompute, signed identity, global replay, independent aggregation, D-funded, and H controls
- [`docs/audits/2026-05-25-phase0-reality-check.md`](docs/audits/2026-05-25-phase0-reality-check.md) — current implementation and benchmark reality check
- [`docs/specs/layer5-economics-v3.3.md`](docs/specs/layer5-economics-v3.3.md) — authoritative economics specification
- [`docs/architecture/biological-architecture.md`](docs/architecture/biological-architecture.md) — the organism frame and biological mapping
- [`docs/architecture/agent-architecture.md`](docs/architecture/agent-architecture.md) — measurement daemon specification and natural-language shell architectural sketch
- [`docs/architecture/sensor-array.md`](docs/architecture/sensor-array.md) — sensor families, curation, genesis suite, and the metabolic sensor
- [`docs/architecture/testers.md`](docs/architecture/testers.md) — the tester tier, the free-Fast-access exchange, and the spoofing trap
- [`docs/architecture/hardening.md`](docs/architecture/hardening.md) — substrate dependencies, bootstrap risk, and attack-surface analysis
- [`docs/CHANGELOG-v2.5.md`](docs/CHANGELOG-v2.5.md) — decision-grade sensor loop and CursiveRoot analyzer pass
- [`docs/CHANGELOG-v2.4.md`](docs/CHANGELOG-v2.4.md) — first seed baseline and benchmark-method reality check
- [`docs/CHANGELOG-v2.3.md`](docs/CHANGELOG-v2.3.md) — what changed in the v2.2 → v2.3 technical/theory split
- [`docs/CHANGELOG-v2.2.md`](docs/CHANGELOG-v2.2.md) — what changed in the v2.1 → v2.2 update
- [`docs/CHANGELOG-v2.1.md`](docs/CHANGELOG-v2.1.md) — what changed in the v1.0/v3.1 → v2.1/v3.3 transition

---

Made by [@connormatthewdouglas](https://github.com/connormatthewdouglas)

**Got results?** Run the wrapper and they'll appear in CursiveRoot automatically. Or open an issue on GitHub.
