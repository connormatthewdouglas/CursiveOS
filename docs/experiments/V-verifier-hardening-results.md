# V — Verifier-Hardening Results

Status: **pre-registered before verifier-hardening fixes were written or run**
Branch: `h2-adversarial-tester`

## Purpose

V is the direct continuation of H2/H2*. H2* hardened the local acceptance boundary against bare fabricated evidence, local replay, parsimony metadata overclaims, and caller-asserted confirmations. V tests whether the acceptance referee is trustworthy enough to proceed to the daemon/UI phase while real BTC/reward remains simulated and gated.

This experiment must use the real production acceptance boundary. Do **not** soften thresholds after seeing results. Do **not** modify the adversarial tester to dodge a failure. If the runner exposes a hole, fix the production acceptance/referee boundary or record an honest fail/bounded policy gap.

## Pre-registered pass bar

The referee is "trustworthy enough to proceed" ONLY if **all** of the following pass:

1. **No H2 regression:** H2 Modes A/B/C remain rejected by named gates.
2. **Three H2 gaps closed or bounded:**
   - G-A verifier-side recomputation from immutable raw artifacts closes the self-consistent fabricated-summary gap, or a written policy bounds what remains.
   - G-B signed machine/session identity plus CursiveRoot-wide accepted-fingerprint replay index closes the local-ledger-only replay gap, or a written policy bounds what remains.
   - G-C CursiveRoot-owned independent confirmation aggregation counts only distinct signed identities with distinct raw-artifact fingerprints, or a written policy bounds what remains.
3. **Mode D-funded rejection:** a funded adversary controlling multiple signed identities and self-consistent fabricated raw artifacts is rejected, not quietly accepted and not silently deferred.
4. **Mode H false-positive control:** honest-but-noisy and honest-on-weird-hardware contributions are accepted, or correctly held inconclusive pending confirmation, and are not rejected as fraud above the registered false-positive rate.
5. **Real BTC/reward remains simulated and gated:** no scarce-resource payout path may be unlocked by V.

## KILL condition

If any fabricated bundle reaches accepted, or if honest contributions are rejected above the registered false-positive rate, V fails. Do not reinterpret after seeing results.

## Registered false-positive threshold

Mode H contains two honest controls:

- H1: genuine raw measurement with high but legitimate variance on an otherwise rock-solid channel.
- H2: genuine raw measurement from uncommon/old hardware.

Maximum acceptable false-rejection rate for V: **0% fraud-class rejection** across these registered honest controls. An honest control may be `accepted` or `inconclusive` for normal confidence/confirmation reasons, but it must not be rejected by fraud/referee gates such as recompute mismatch, replay, invalid signature, Sybil/funded-adversary policy, or unverified evidence.

## Registered attack/control modes

| Mode | Description | Required V result |
|---|---|---|
| A | H2 inflated delta: real baseline metrics, fabricated candidate improvement. | Rejected by named gate; no payout. |
| B | H2 replay: accepted measurement replayed across session/contributor. | Rejected by named replay gate; no payout. |
| C | H2 parsimony gaming: overdeclared knob removals. | Rejected by invariant/parsimony gate; no payout. |
| D-funded | Funded adversary controls multiple signed identities and submits self-consistent fabricated raw artifacts designed to pass recomputation and forge independence. | Rejected by production referee, or recorded as a named bounded policy gap with real BTC still gated. It may not be silently classified as deferred. |
| H | Honest controls: noisy-but-real and weird-hardware-but-real submissions. | Accepted or properly inconclusive; not rejected as fraud. |

## Production-boundary hardening targets

### G-A — verifier-side recomputation

Acceptance-eligible submissions must include immutable raw artifacts such as raw harness output and sample logs. A system-owned verifier recomputes summary metrics from those raw artifacts and rejects any claim where claimed metrics differ from recomputed metrics.

Registered verdict for mismatch: `rejected_recompute_mismatch`.

### G-B — signed identity plus global replay

Each submission must carry signed machine/session identity. The session nonce must be signed. The measurement fingerprint must bind to raw-artifact content. A CursiveRoot-wide accepted-fingerprint index, implemented as a shared local file/table for this phase, catches replays across sessions/contributors rather than only within one local ledger.

Registered verdict for global replay: `rejected_replay_global`.

### G-C — independent confirmation aggregation

CursiveRoot-owned aggregation must count confirmations only from distinct signed identities with distinct raw-artifact fingerprints. Only that system-owned aggregation may emit `confirmation_source == "cursiveroot_independent_aggregation"`. Caller-asserted `--confirmations` remains non-acceptance-grade.

## Artifact paths

- Human-readable results: `docs/experiments/V-verifier-hardening-results.md`
- Machine-readable results: `docs/experiments/V-verifier-hardening-results.json`
- Local run state / submitted bundles: `.cursiveos/v-verifier-hardening/`

## Results

Not run yet. This document is the pre-registration artifact and must be committed before writing V fixes.
