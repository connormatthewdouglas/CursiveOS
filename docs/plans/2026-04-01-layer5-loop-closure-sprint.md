# Layer 5 Loop Closure Sprint (Execution Plan)

Owner: Copper Sage (execution)
Founder support: Connor (accounts/keys/wallet/legal ops only)
Duration: 28 days (4 weeks)
Objective: Ship a working Layer 5 incentive system that funds/controls Fast updates, rewards validators, and rewards contributor deltas with dispute window.

Success gates (must all pass):
1) Fast/Stable billing and entitlement works in production.
2) Validator reward pipeline runs end-to-end with anti-fraud checks.
3) Contributor submission -> test-oracle -> payout/refund/slash lifecycle works end-to-end.
4) Pool accounting reconciles exactly (no drift).
5) At least 3 consecutive payout cycles execute without manual patching.

Non-goals in this sprint:
- Full permissionless governance token launch.
- Cross-chain expansion.
- Public mass marketing.

--------------------------------------------------
WEEK 1 — SPEC LOCK + ECONOMICS + CONTROL SURFACE
--------------------------------------------------
Day 1
- Freeze v1 economic spec (credits, burns, payouts, stake states, appeals, halving/reset schedule).
- Define canonical formulas and edge-case rules (missed cycle, validator inactivity, pool depletion).
- Output: docs/specs/layer5-economics-v1.md

Day 2
- Define system architecture and service boundaries:
  - entitlement service (Fast/Stable)
  - pool ledger
  - validator rewards
  - contributor stake/reward engine
  - disputes/appeals module
- Output: docs/specs/layer5-architecture-v1.md

Day 3
- Data model design for Layer 5 (tables + event log + reconciliation views).
- Output: docs/specs/layer5-schema-v1.md + migration plan.

Day 4
- Abuse model + controls:
  - sybil controls
  - duplicate-hardware/fleet clustering
  - payout cooldowns
  - minimum evidence thresholds
- Output: docs/specs/layer5-risk-controls-v1.md

Day 5
- Contributor workflow policy:
  - submission classes
  - gated contributor admission
  - testing cohorts
  - payout delay and appeal window
- Output: docs/specs/layer5-contributor-policy-v1.md

Day 6
- Consumer policy finalization:
  - Fast cadence + fee
  - Stable cadence
  - early-update manual path rules
- Output: docs/specs/layer5-consumer-policy-v1.md

Day 7
- Integration review and final v1 sign-off packet.
- Output: docs/specs/layer5-v1-freeze.md

--------------------------------------------------
WEEK 2 — BUILD CORE LEDGER + ENTITLEMENT + POOL ACCOUNTING
--------------------------------------------------
Day 8
- Implement credit ledger core (append-only events, idempotency keys).
- Add balance and pool projection views.

Day 9
- Implement Fast/Stable entitlement and burn trigger hooks.
- Wire burn events into ledger.

Day 10
- Build pool accounting service:
  - inflows (burns, slashes, fees)
  - outflows (validator/contributor payouts)
  - reserve floor checks

Day 11
- Implement reconciliation job and daily mismatch alerting.

Day 12
- Build admin controls for tuning knobs (rates, multipliers, cooldowns).

Day 13
- Add integration tests for entitlement + pool + reconciliation.

Day 14
- Dry-run cycle #1 on staging with replay data.

--------------------------------------------------
WEEK 3 — VALIDATOR + CONTRIBUTOR ECONOMIC LOOPS
--------------------------------------------------
Day 15
- Implement validator payout eligibility engine:
  - quality gates
  - cycle continuity
  - rarity modifier hooks

Day 16
- Implement validator payout calculation + schedule + receipts.

Day 17
- Implement contributor submission lifecycle:
  - stake lock
  - test batch assignment
  - result finalization states

Day 18
- Implement contributor payout/refund/slash logic from oracle verdict.

Day 19
- Implement disputes and appeal timer + vote capture + final settlement states.

Day 20
- Add anti-spam and anti-abuse controls (submission rate limits, stake lock windows, contributor trust tiering).

Day 21
- Dry-run cycle #2 on staging with adversarial test cases.

--------------------------------------------------
WEEK 4 — SHADOW RUN, PARAMETER TUNING, PRODUCTION CUTOVER
--------------------------------------------------
Day 22
- Stand up shadow run with selected pilot cohort.
- No public open call yet.

Day 23
- Execute payout cycle #1 (shadow), reconcile all balances.

Day 24
- Execute payout cycle #2 (shadow), run dispute simulation.

Day 25
- Tune parameters from observed behavior (without schema changes).

Day 26
- Execute payout cycle #3 (shadow), verify stability.

Day 27
- Production readiness review:
  - controls
  - rollback plan
  - observability
  - operator runbook

Day 28
- Production cutover for Layer 5 v1.
- Publish operator/contributor policy docs.

--------------------------------------------------
AUTONOMY MODEL (WHO DOES WHAT)
--------------------------------------------------
Copper Sage executes:
- Spec drafting and freezing
- Data model and implementation planning
- Build sequencing, test strategy, verification, and cutover checklist
- Daily status and blocker reporting

Connor provides only when required:
- Wallet(s) + signing policy decisions
- Exchange/on-ramp/off-ramp accounts (if used)
- API keys/credentials for payment rails
- Legal/tax advisor decisions

--------------------------------------------------
EXTERNAL DEPENDENCIES I WILL REQUEST EXACTLY WHEN NEEDED
--------------------------------------------------
D1-D7: none required (spec and architecture only)
D8-D14: infra credentials only if deployment target needs them
D15-D21: wallet and signing setup needed for stake/payout testing
D22-D28: production keys, payout rails, and operating wallet approvals

--------------------------------------------------
DEFINITION OF LAYER 5 COMPLETE
--------------------------------------------------
Layer 5 is complete when:
- Fast burns reliably fund the pool.
- Validators are paid by deterministic rules for quality data.
- Contributors are paid/slashed by measured outcomes after appeal window.
- Pool remains reconciled and policy-tunable without code rewrites.
- The loop runs 3+ consecutive cycles with no manual emergency intervention.
