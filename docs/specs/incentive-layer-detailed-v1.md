# CursiveOS Incentive Layer — Detailed Description (v1)

Date: 2026-04-03
Owner: Copper Sage
Audience: Connor + e-Board + pilot operators

## One-line summary
The incentive layer is a cycle-based credit engine that charges Fast update convenience, rewards validated contribution, and reconciles every cycle with auditable accounting.

## What it does
1) Fast users pay credits each cycle (inflow to pool).
2) Contributors can earn credits through:
   - performance-tested changes (oracle path)
   - non-performance work (security/driver/reliability rubric path)
3) Appeals can delay settlement for review.
4) Every cycle closes with reconciliation and drift check.

## Core entities
- l5_machine_entitlements: machine plan state (stable/fast)
- l5_credit_ledger: immutable money-like event stream
- l5_pool_cycles: cycle accounting open/close snapshots
- l5_contributor_submissions: submission lifecycle
- l5_oracle_evaluations: measured verdicts for performance path
- l5_nondelta_reviews: rubric scoring for non-performance path
- l5_appeals + l5_governance_votes: dispute and vote trail
- l5_admin_actions: audited parameter changes

## Event types (human meaning)
- fast_burn_inflow: Fast machine paid cycle fee to pool
- validator_payout: validator paid from pool (path present)
- contributor_payout: performance contributor paid from pool
- contributor_nondelta_payout: non-performance contributor paid from pool
- flat_fee_inflow: flat verdict fee returned to pool
- stake_refund: contributor stake returned to account
- slash_inflow: contributor stake slashed to pool
- payout_burn: burn sink reduction event

## Settlement paths

### A) Performance path (oracle)
- Oracle records verdict: positive_delta / flat_delta / negative_delta / inconclusive
- If appeal window is closed and no open appeals:
  - positive_delta -> payout + stake refund (+ optional burn)
  - flat_delta -> flat_fee_inflow + stake_refund
  - negative_delta -> slash_inflow

### B) Non-performance path (rubric)
- Reviewer scores 4 dimensions (0-5 each):
  - severity
  - breadth
  - confidence
  - urgency
- Total score maps to band:
  - low (0-6)
  - medium (7-12)
  - high (13-16)
  - critical (17-20)
- Band maps to fixed payout credits from l5_nondelta_band_values.

## Appeals and governance
- Submission can enter pending settlement with appeal deadline.
- Open appeals block guarded settlement.
- Votes are recorded for appeal decisions.
- Governance is auditable, not hidden in chat/manual decisions.

## Cycle runner (automation)
l5_run_cycle(cycle_id, pool_open) does:
1) process fast burns
2) settle oracle-ready submissions (guarded)
3) settle non-delta ready reviews (guarded)
4) close cycle via reconciliation

## Reconciliation and integrity
- Every cycle records:
  - pool_open
  - inflow_total
  - outflow_total
  - burn_total
  - pool_close
- expected_close must match pool_close (drift should be 0)
- cycle status must be closed to be considered successful

## Parameter control and safety
- Tunable params via audited functions:
  - l5_set_param(...)
  - l5_set_nondelta_band_value(...)
- All changes require reason + are logged in l5_admin_actions.
- Test tuning should be reset after smoke runs.

## Current rail mode
- internal_credits
- no on-chain transfers yet
- architecture is rail-switchable (testnet/mainnet later) without rewriting economic logic

## What users should eventually see in Hub
- current cycle status
- machine plan and cycle burns
- reward events and balances
- submission status and verdicts
- appeals and votes
- rail badge: internal/testnet/mainnet

## What has been proven in internal pilot
- 3 consecutive cycles closed with drift = 0
- fast burn path works
- oracle settlement path works
- non-delta settlement path works
- cycle runner idempotency behavior is sane (re-run does not double-pay)

## What is still needed before public pilot
- full Hub flow so operators can do this without SQL editor
- auth/account scoping
- external behavior validation with real operators
