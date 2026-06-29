# H2 / H2* — Adversarial / Dishonest Tester Experiment Results

Status: **H2 pre-registered before adversarial submissions were run; H2* remediation pass applied after initial failure and rerun locally**
Branch: `h2-adversarial-tester`

## Purpose

H2 tests whether the seed-organism acceptance pipeline rejects fabricated or dishonest tester contributions **without relying on a trusted center**.

The experiment submits malicious bundles through the real acceptance path where possible, not through a mocked verdict function. The initial run intentionally did **not** modify acceptance logic to make H2 pass; it exposed the holes below. The remediation pass then hardened the shared seed/QD acceptance boundary and reran the same attack shapes.

Terminology: **H2** is the original adversarial test that intentionally exposed the holes; **H2*** is the hardened/remediated rerun after acceptance gates were added.

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

## Attack modes

- **Mode A — inflated delta:** real baseline metrics, but candidate metrics fabricate an improvement that was not measured.
- **Mode B — replay:** copy a genuine winning measurement from one machine/run and resubmit it as a different machine/session to fake independent confirmation.
- **Mode C — parsimony gaming:** claim knob removals that the genome does not actually reflect, testing the genome-derived-removal guard.
- **Mode D — confirmation Sybil:** submit N near-identical “independent” confirming sessions from one source to fraudulently raise confidence above `minimum_confidence`.

## Real-code grounding

The experiment is grounded in:

- `tools/seed_organism.py`
- `tools/qd_organism.py`
- regression gates
- evidence/provenance gates
- replay guard
- confirmation aggregation via `--confirmations`
- QD parsimony guard and shared seed parsimony invariant
- `references/seed-organism/variant-*.json`
- `references/seed-organism/metrics-*.example.json`

## Run command

```bash
python tools/exp_adversarial_tester.py
```

Machine-readable results:

`docs/experiments/H2-adversarial-tester-results.json`

Local audit state / submitted bundles:

`.cursiveos/h2-adversarial-tester/`

## Initial H2 result before remediation

The pre-remediation H2 run **failed** the registered bar:

| Mode | Initial result | Hole exposed |
|---|---:|---|
| A | `accepted`, payout triggered | Direct `run-variant` trusted submitted metric numbers with no decision-grade evidence/provenance gate. |
| B | `accepted`, payout triggered | Replayed measurements under a new claimed machine/session were not fingerprinted against previous accepted results. |
| C | `accepted` in direct seed path | QD recomputed parsimony, but direct seed scoring trusted `knobs_removed_vs_parent` metadata. |
| D | `accepted`, payout triggered | `--confirmations 3` was caller-asserted and lifted confidence without system-owned independence checks. |

That failure was the expected purpose of H2: identify where decentralized acceptance could be gamed before any real BTC/reward path depends on it.

## Remediation implemented

Implemented fixes in the production acceptance boundary, not only in the experiment runner:

1. **Evidence/provenance gate for acceptance-eligible direct submissions**
   - Positive external submissions now require decision-grade measurement evidence fields before they can be accepted.
   - Synthetic QD simulation remains allowed as a simulation-only path.
   - Rejection verdict: `rejected_unverified_evidence`.

2. **Measurement replay guard**
   - Sensor results now include a stable `measurement_fingerprint` computed from metric content while excluding caller-controlled identity.
   - `record_evaluation` rejects a new candidate if the fingerprint already appears in the accepted local ledger.
   - Rejection verdict: `rejected_replay`.

3. **Shared parsimony invariant**
   - `seed_organism.score_performance` no longer awards parsimony from `knobs_removed_vs_parent` metadata alone.
   - Removed knobs are derived from `parent_genome_knobs` and `genome_knobs`; mismatches become a shared acceptance-boundary invariant failure.
   - Rejection verdict: `rejected_invariant`.

4. **Caller-asserted confirmation gate**
   - `confirmation_count > 1` is no longer acceptance-grade unless `confirmation_source == "cursiveroot_independent_aggregation"`.
   - CLI `screen-variant --confirmations N` records the assertion for audit but cannot by itself produce independent confidence.
   - Verdict: `inconclusive` with the `confirmation independence gate`.

5. **Regression coverage**
   - Added tests for unverified evidence rejection, replay rejection, direct seed parsimony overclaim rejection, and caller-asserted confirmation rejection.

## H2* remediation verdict table

Latest local rerun of `python tools/exp_adversarial_tester.py`:

| Mode | Attack | Pipeline verdict | Gate caught it | Accepted? | Attack payout triggered? | H2 classification |
|---|---|---:|---|---:|---:|---|
| A | Inflated delta: real baseline, fabricated candidate improvement | `rejected_unverified_evidence` | evidence/provenance gate | no | no | **PASS** |
| B | Replay: winning measurement resubmitted as different machine/session | `rejected_replay` | measurement replay gate | no | no | **PASS** |
| C | Parsimony gaming: overdeclared knob removals | `rejected_invariant` | shared invariant gate | no | no | **PASS** |
| D | Confirmation Sybil: `--confirmations 3` asserted for same-source near-identical measurements | `inconclusive` | confirmation independence gate | no | no | **DEFERRED TO TRUST LAYER** — real independent aggregation still not implemented |

Current overall H2* status from the runner:

`PASSED_EXCEPT_MODE_D_DEFERRED_TO_TRUST_LAYER`

Latest checked from this branch on 2026-06-29 after the H2* rerun. The current machine-readable artifact is `docs/experiments/H2-adversarial-tester-results.json`; local submitted bundles and ledgers live under `.cursiveos/h2-adversarial-tester/`.

## Remaining gaps / explicitly not fixed yet

These are marked intentionally so future reruns do not mistake local hardening for a complete decentralized trust layer:

1. **Evidence gate is not cryptographic proof.**
   - The local gate rejects bare fabricated metric summaries, but a malicious submitter could still forge a self-consistent JSON blob unless raw detail logs, harness outputs, signatures, and content-addressed artifacts are verified by a system-owned verifier.
   - Required next fix: verifier-side recomputation from immutable raw artifacts, signed machine/session identity, and artifact hash binding.

2. **Replay guard is local-ledger scoped.**
   - The current `measurement_fingerprint` check catches duplicates already present in the same state ledger.
   - It does not prove global uniqueness across disconnected contributors unless CursiveRoot/Hub shares accepted fingerprints or consensus state.
   - Required next fix: CursiveRoot-wide accepted-measurement fingerprint index with signed session nonces.

3. **Independent confirmation aggregation is deferred.**
   - Caller-asserted confirmation counts are now blocked from acceptance, but there is not yet an implementation that derives confidence from distinct trusted roots/machines/sessions.
   - Required next fix: CursiveRoot-owned aggregation that counts independent evidence bundles and emits `confirmation_source == "cursiveroot_independent_aggregation"` only after identity/session/raw-artifact checks pass.

4. **Real BTC/reward path must remain gated.**
   - H2/H2* still uses simulated payout reports.
   - Do not connect scarce-resource payout to this path until the three gaps above are closed or explicitly bounded by policy.

## Rerun checklist

Before declaring a future H2/H2* pass:

```bash
python -m py_compile tools/seed_organism.py tools/qd_organism.py tools/exp_adversarial_tester.py
python -m unittest tests.test_seed_organism
python tools/exp_adversarial_tester.py
python -m json.tool docs/experiments/H2-adversarial-tester-results.json >/dev/null
```

Expected after this remediation pass:

- Modes A/B/C: rejected by named gates, no accepted adversarial bundle, no adversarial payout.
- Mode D: `inconclusive` / deferred until independent CursiveRoot aggregation exists.

Full-suite note: the older concurrency sprint contract is now kept as historical/fixture-backed evidence, not as a global ban on future `tools/seed_organism.py` changes. H2* intentionally changes `tools/seed_organism.py` to harden the shared acceptance boundary, and the legacy contract no longer treats that as a concurrency-sprint failure.
