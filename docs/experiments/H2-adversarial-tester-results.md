# H2 — Adversarial / Dishonest Tester Experiment Results

Status: **pre-registered before adversarial submissions were run**
Branch: `h2-adversarial-tester`

## Purpose

H2 tests whether the current seed-organism acceptance pipeline rejects fabricated or dishonest tester contributions **without relying on a trusted center**.

The experiment must submit malicious bundles through the real acceptance path where possible, not through a mocked verdict function. The point is to find holes, not to adjust the acceptance logic until it passes.

## Pre-registered pass / fail thresholds

### PASS

H2 passes only if **zero fabricated bundles** reach an `accepted` state or trigger any payout, across all attack modes.

For every rejected fabricated submission, the run must record which specific gate caught it.

### FAIL / KILL

H2 fails if **any fabricated-delta bundle** reaches `accepted`.

If this happens, record exactly which gate failed and why. Do **not** soften or reinterpret this threshold after seeing results.

### Trust-layer exception / deferred classification

If confirmation Sybil resistance cannot be defended by the current code without a trust/reputation layer, record Mode D as:

`deferred to trust layer; real BTC must stay gated`

Do not pretend that near-identical confirmations from one source are independently trustworthy if the current code has no mechanism to distinguish them.

## Attack modes to run

- **Mode A — inflated delta:** real baseline metrics, but candidate metrics fabricate an improvement that was not measured.
- **Mode B — replay:** copy a genuine winning measurement from one machine/run and resubmit it as a different machine/session to fake independent confirmation.
- **Mode C — parsimony gaming:** claim knob removals that the genome does not actually reflect, testing the genome-derived-removal guard.
- **Mode D — confirmation Sybil:** submit N near-identical “independent” confirming sessions from one source to fraudulently raise confidence above `minimum_confidence`.

## Real-code grounding

The experiment is grounded in:

- `tools/seed_organism.py`
- `tools/qd_organism.py`
- regression gates
- confirmation aggregation via `--confirmations`
- QD parsimony guard
- `references/seed-organism/variant-*.json`
- `references/seed-organism/metrics-*.example.json`

## Results JSON

Machine-readable results will be written to:

`docs/experiments/H2-adversarial-tester-results.json`

## Run record

Runner:

```bash
python tools/exp_adversarial_tester.py
```

Machine-readable results:

`docs/experiments/H2-adversarial-tester-results.json`

Local audit state / submitted bundles:

`.cursiveos/h2-adversarial-tester/`

## Verdict table

| Mode | Attack | Pipeline verdict | Gate caught it | Accepted? | Payout triggered? | H2 classification |
|---|---|---:|---|---:|---:|---|
| A | Inflated delta: real baseline, fabricated candidate improvement | `accepted` | none | yes | yes | **FAIL/KILL** — fabricated delta reached accepted |
| B | Replay: winning measurement resubmitted as different machine/session | `accepted` | none | yes | yes | **FAIL** — replay not detected |
| C | Parsimony gaming: overdeclared knob removals | `accepted` in direct seed path | QD path caught via genome-derived parsimony guard, but direct `run-variant` path had no guard | yes | yes | **FAIL** — guard is bypassable outside QD path |
| D | Confirmation Sybil: `--confirmations 3` asserted for same-source near-identical measurements | `accepted` | none in current code | yes | yes | **DEFERRED TO TRUST LAYER** — current code only records founder-attested confirmation count; real BTC must stay gated |

## Detailed findings

### Mode A — inflated delta

- Submitted through: `seed_organism.py run-variant` → `record_evaluation` → `verdict` → bundle/ledger.
- Result: `accepted`.
- Gate triggered: none.
- Payout: simulated payout triggered after `close-cycle`.
- Finding: current scoring trusts submitted metric numbers. It does not require signed/raw measurement provenance, detail-log consistency, or recomputation from immutable harness output before acceptance.
- Minimal fix: acceptance-eligible metric bundles need content-addressed raw artifacts and verifier-side recomputation/cross-checks before `score_performance` can accept a positive fabricated delta.

### Mode B — replay

- Submitted through: `seed_organism.py run-variant` → `record_evaluation` → `verdict` → bundle/ledger.
- Result: `accepted`.
- Gate triggered: none.
- Payout: simulated payout triggered after `close-cycle`.
- Finding: replayed metrics with a changed machine/session identity were treated as fresh independent evidence.
- Minimal fix: bind measurements to signed machine identity/session nonce/result hash, reject duplicate metric fingerprints across claimed machines, and require CursiveRoot-side independence checks before acceptance or payout.

### Mode C — parsimony gaming

Two real-code paths were probed:

1. QD guarded path: `qd_organism.evaluate_variant` synchronized `knobs_removed_vs_parent` from `parent_genome_knobs` + `genome_knobs`, reducing the malicious claim from 5 removed knobs to 0. The resulting bundle was `rejected_negative_fitness` by the `minimum_accept_fitness` gate.
2. Direct seed path: the same overclaim shape submitted through `seed_organism.py run-variant` was `accepted`, because `seed_organism.score_performance` still trusts `variant["knobs_removed_vs_parent"]` directly.

- Overall Mode C result: **failed** for the external contributor surface, even though the QD-internal guard works.
- Minimal fix: move the genome-derived parsimony synchronization/validation into the seed acceptance path itself, or reject `knobs_removed_vs_parent > 0` unless the variant includes verifiable parent and child genomes and the accepted value is recomputed by `seed_organism` before scoring.

### Mode D — confirmation Sybil

- Submitted through: `seed_organism.py screen-variant --confirmations 3`.
- Result: `accepted`.
- Gate triggered: none.
- Payout: simulated payout triggered after `close-cycle`.
- Finding: current confirmation aggregation is an asserted integer (`--confirmations`), not an automatic count of independent CursiveRoot bundles with distinct trust roots, machine IDs, session nonces, or raw evidence.
- Classification: **deferred to trust layer; real BTC must stay gated**. This is not defendable by the current code alone without an identity/reputation/stake/trust layer.

## Final H2 verdict

**H2 FAILED** against the pre-registered bar.

The failure is not subtle: fabricated-delta bundles in Modes A and B reached `accepted` and triggered simulated payout reports. Mode C also exposes a bypass where the QD parsimony guard catches overclaims only when the submission actually routes through QD code; direct seed submissions can still claim false parsimony. Mode D is explicitly deferred to the trust layer, and should block real BTC payout until independent-confirmation accounting is no longer caller-asserted.
