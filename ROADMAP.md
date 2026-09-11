# CursiveOS Roadmap

*CursiveOS is a new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.*

This roadmap describes what CursiveOS is becoming. It's organized around four transitions — each one changes what the project fundamentally is, not just what features it has. Every architectural decision in the current specifications is sized for the end state, which is why some choices look overbuilt for where the project is now. They're sized for where it's going.

## Where We Are: Pre-Transition-One (September 11, 2026)

The current state of the project:

- Canonical parent preset **v0.12** (v0.9 stack + zram + swappiness=60), promoted from accepted v0.11 (cycle 3, 2026-06-26). **Still the genome.** Cycle 7 leftover screens (2026-09-11) all rejected.
- **Two surfaces, un-mashed.** The public notebook (ledger + dashboard) shows science: genome, what passed, what failed. The **CursiveOS Desktop window** is the client-side task manager: Update from GitHub, now/next, phase bar, Stop. Occupancy is local; it is not written to CursiveRoot.
- **The loop can run a screen without the founder at the keyboard** (first time: cycle 5, 2026-07-06). Proposal, execution, and judgment ran. **Enqueue is still founder-gated** — anon INSERT on `measurement_requests` is denied. That is load-bearing, not a bug.
- **Trust spine live:** signed identity, raw-artifact, trust-evaluation rows; `payout_eligible` hard-false. Independent aggregation is still pending.
- Harness **v1.4.x** with five measured channels (network gate-only, cold-start, sustained, idle power, memory-pressure); concurrency observe-only.
- **Stardust Arc A750 un-voided (2026-09-11):** idle package 5.50 W (CV 0.006), GPU 36.94 W (CV 0.002); cold 3703 ms (CV 0.002); sustained 141.5 tok/s (CV 0.005); 23/23 layers offloaded.
- CursiveRoot: physical machines in the low single digits, **2 accepted bundles**, simulated payouts only. Rejected verdicts are kept and shown.
- Layer 5 economics v3.3 specified. Real money stays gated behind production Sybil resistance.
- The operator-facing public surface is a **read-only organism notebook**. Do not grow it into a remote kill-switch for someone else's PC.

The immediate engineering frontier: a signed proposer identity so leftovers can be enqueued without a human SQL paste; CursiveRoot-owned independent aggregation; QD-archive-grounded proposal instead of mining the audited sysctl library. Real money stays gated.

What exists today is a measurement apparatus that has begun to run itself, plus an honest client window for the person sitting at the chair. It is not yet an operating system. Making it one is Transition 1.

---

## Transition 1: Tweak Stack → Tuned Distribution

**Target release: ISO alpha ("release 0.9") through ISO stable ("release 1.0")**

> **Naming note:** release numbers and preset-lineage numbers are separate namespaces. The preset lineage (v0.8 → v0.9 → v0.12 → …) counts accepted genome generations and is already past 0.9; the ISO releases below count what a user can install. The **v1.5 gate** in `docs/action-plan.md` (5+ external machines, clean safety record, confirmed external gains, auto-submit from machines we don't control) is the fleet-validation exit bar of this transition — it must pass before public solicitation, and it sits between the alpha ISO and the stable release.

CursiveOS becomes a thing people install, not a thing people apply on top of Ubuntu. The tweak stack becomes part of the base image. The benchmarks and the full-test harness ship with the install. Users boot into a configured system and verify their hardware received the intended config with one command.

Milestones:

- ✅ Phase 0 seed organism complete on founder rigs — measurement-to-ledger loop demonstrated end-to-end across **five cycles** (two accepted, two rejected, one autonomous null), with repeat, counterbalanced, and cross-machine confirmation
- ✅ OS.0 autonomy spine: request queue, unattended contributor daemon, trust-spine tables, and autonomous proposer all live — first organism-proposed candidate screened by daemons with zero manual screen steps (cycle 5)
- Operator window: the **static read-only dashboard** (live: queue, jobs, contributions, trust ledger, fleet, honesty box) grows only as real operators validate the need. *The former "hub v3.3 seven-tab frontend" rebuild is retired as over-build — that complexity is what nearly killed the project once; legacy hub surfaces are locked down, not developed.*
- Signed identity + CursiveRoot-owned independent aggregation replace the local-sim scheme and caller-attested confirmations (the hard gate in front of both external testers and any real reward)
- First external tester successfully running the full sensor array (validates population confirmation works with more than one operator)
- **v1.5 gate passes** (see naming note above) — the wrapper proves itself on machines we don't control
- ISO build pipeline established (live-build or Cubic-based; automatable, reproducible)
- Alpha ISO: installable, boots to a working system with presets applied, ships with benchmark harness and the contributor daemon
- Contributor daemon (non-LLM) running locally on installed systems, submitting sensor data to CursiveRoot with explicit user consent — *this is the OS.0 daemon that already exists, matured, not a new build*
- Stable ISO: above, plus the **natural-language shell** (see Transition 4 flagship feature) as the default operator interface

Release 1.0 is the moment CursiveOS is first a thing the world can download and try. The natural-language shell is intentionally sequenced here — not deferred to a later transition — because 1.0 is the first impression the project makes, and the natural-language shell is the feature that makes the first impression memorable.

---

## Transition 2: Tuned Distribution → Measurement-Native

**Target: v1.x through v2.0**

The organism stops being external scaffolding and starts being part of the OS. Every CursiveOS install contributes measurement data (opt-in, privacy-preserving aggregation) and receives updated presets as the organism validates better configurations. The user's machine is simultaneously a consumer of organism output and a contributor to organism state.

Milestones:

- Measurement daemon matured: automatic workload detection, continuous sensor execution during real workloads (not just synthetic benchmarks), local caching with batched hub submission
- Signed preset update channel: hub-validated presets delivered to installed systems with cryptographic verification, applied non-disruptively, auto-rolled-back on local regression
- Metabolic sensor activated in production (requires >1 contributor and meaningful cycle history)
- Claim processing runtime live (two-year claim window enforced, accrual records honored)
- Fleet grows beyond founder's rig; sensor array validates measurements from a diverse hardware population
- First forks appear; fork obligation inheritance via Bitcoin anchoring tested in practice

This is the transition where the "self-improving" claim becomes empirically true rather than architecturally promised. A machine installed in month one gets better over year one because the organism learned across the whole fleet, not because Connor shipped manual updates.

---

## Transition 3: Measurement-Native → Workload-Native

**Target: v2.x**

CursiveOS detects what workloads are actually running on each user's machine and tunes for them. The sensor suite expands to cover multiple workload classes — inference, mining, build systems, compilation, media encoding, gaming, research computing. The metabolic sensor governs how contributor effort is allocated across workload classes based on the actual distribution of the user population.

Milestones:

- Workload detection subsystem: classifies running processes into workload classes with measured confidence
- Sensor suite expansion: at minimum inference, mining, and a general-purpose compilation/build class; ideally 5-7 classes with clear adoption
- Per-workload preset families: instead of one canonical preset, the organism maintains preset variants tuned to workload classes
- Natural-language shell gains workload context: the agent knows what the user is doing and can suggest optimizations specific to that work
- Multi-curator sensor array: each workload class has its own curator(s), following the succession criteria in the sensor array spec

This is where CursiveOS stops being "Linux tuned for AI inference" and starts being "Linux tuned for what you actually do." A different product. A much broader target audience.

---

## Transition 4: Workload-Native → Substrate

**Target: v3.x and beyond**

The final transition is ecological. CursiveOS becomes the substrate that other projects are built on top of — the default host for specific operator categories, the reference deployment for inference and mining work, the platform hardware vendors optimize for. This is not a feature release. It's a positional change that happens over years, as adoption and ecosystem reach a threshold where other actors start assuming CursiveOS rather than adapting to it.

Signals that this transition has started:

- Third-party documentation starts saying "on CursiveOS, do X instead"
- Hardware vendors reach out about optimizing drivers specifically for CursiveOS benchmarks
- Other open-source projects declare CursiveOS as a tier-1 supported platform
- The natural-language shell becomes a point of reference for how Linux interaction evolves more broadly
- Forks of CursiveOS appear that specialize for adjacent use cases (gaming, research, specific hardware families) — the fork ecology matures

This stage is not something the project can schedule. It either happens or it doesn't, and what determines which one is the quality of execution on transitions 1 through 3 plus the degree to which the project earns credibility over time.

---

## Flagship Features by Release

**Release 0.9 (ISO alpha)**
First installable CursiveOS. Tuned distribution, benchmarks included, contributor/measurement daemon running. No natural-language shell yet — this release validates the ISO build path and the daemon on real user hardware. (Release numbers are independent of the preset lineage's v0.9 — see the naming note in Transition 1.)

**Release 1.0 (ISO stable) — flagship: the natural-language shell**
The interface that turns CursiveOS from "another Linux distribution" into something categorically different. The terminal, as it has existed for fifty years, becomes a conversation with a local agent. Users describe outcomes; the agent finds the mechanism. Commands still exist and remain inspectable, but they are no longer the primary interface.

Tiered model approach per hardware class:
- Entry hardware: small local model (4-8B), handles the majority of routine requests
- Workstation hardware: larger local model (20-30B class, e.g. Gemma 31B on Arc Pro B70)
- Fleet operators: shared local inference server option for edge nodes
- Optional: remote frontier model for users who opt in, with clear scoping of what leaves the machine

The natural-language shell is not an add-on to the terminal. It replaces the default terminal experience while preserving full terminal access for users who want it. See [`docs/architecture/agent-architecture.md`](docs/architecture/agent-architecture.md).

**v2.0 — flagship: the self-updating fleet**
CursiveOS installs no longer need manual updates to benefit from organism learning. The measurement daemon, the signed preset channel, and the metabolic sensor combine so that every machine's install gets better as the organism learns across the full fleet. "The OS that teaches itself and reaches every user who runs it."

**v3.0 — flagship: workload-adaptive tuning**
Per-workload preset families. A user running inference gets inference-tuned configuration; a user running mining gets mining-tuned configuration; a user running both gets non-regressing hybrid configuration. The organism's sensor array, multiplied by workload classes, produces a distribution that collectively covers the matrix of hardware × workload combinations that operators actually run.

**Beyond v3.0: substrate**
Not a flagship feature. A position in the ecosystem that, if earned, changes what the project means to its users.

---

## What This Roadmap Is Not

This is not a commitment schedule. Dates are not given because most of the milestones depend on external factors (first external tester, first fork, first third-party documentation) that cannot be scheduled from the inside. The transitions are sequenced because they depend on each other — you cannot go workload-native before you're measurement-native, and you cannot be measurement-native before you're a shippable distribution. Within each transition, work may proceed in parallel.

This is also not a feature list sorted by nice-to-have. Every item here is load-bearing for the transition it belongs to. If a transition slips, it's because a specific load-bearing piece is still being built, not because priorities shifted.

The roadmap is a north star, not a contract. The direction is stable; the timing adapts to what the project actually encounters.

---

*CursiveOS is a new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.*
