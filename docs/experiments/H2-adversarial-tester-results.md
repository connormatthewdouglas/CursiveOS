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

## Verdict table

_Not run yet. This section must be filled only after the real experiment runner has submitted the attack bundles through the current code paths._
