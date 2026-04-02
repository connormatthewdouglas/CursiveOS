# Layer 5 Economics Spec v1 (Day 1 Freeze)

Status: FROZEN v1
Date: 2026-04-02
Owner: Copper Sage

## 0) Purpose
Define deterministic economics for the CursiveOS Layer 5 loop:
- Consumers fund speed/security convenience (Fast lane)
- Validators are rewarded for high-quality benchmark data
- Contributors are rewarded/slashed based on measured upgrade outcomes
- Pool remains solvent, auditable, and tunable

This spec defines formulas, state transitions, and edge-case handling.

## 1) Core Units and Buckets
- Unit: `credit` (internal accounting unit)
- Treasury buckets:
  1. `incentive_pool` (payout source)
  2. `ops_reserve` (non-payout emergency reserve)
  3. `burn_sink` (credits permanently removed)

Rule: only `incentive_pool` funds validator/contributor payouts.

## 2) Consumer Modes (Fast vs Stable)
### 2.1 Stable
- Free
- Auto-update cadence: monthly release window
- No credit burn

### 2.2 Fast
- Continuous update channel (target daily/hourly recursive updates)
- Burn: `F_fast = 5` credits per cycle per active machine
- Fast burns route:
  - `pool_inflow_fast = F_fast * alpha_pool`
  - `burn_sink_fast = F_fast * (1 - alpha_pool)`
- v1 default: `alpha_pool = 1.0` (all Fast fees into pool)

## 3) Validator Rewards
## 3.1 Eligibility per cycle c
Validator `v` is eligible if all are true:
1. submitted benchmark package in cycle `c`
2. package passed integrity checks
3. hardware fingerprint not flagged duplicate-risk above threshold
4. stability checks pass (`stability_flag = true`)

### 3.2 Reward function
`reward_validator(v,c) = B_v * C_v(c) * R_v(c) * Q_v(c)`
Where:
- `B_v` = base validator reward (v1 default = 1.0 credit)
- `C_v(c)` = continuity multiplier
- `R_v(c)` = rarity multiplier
- `Q_v(c)` = quality multiplier

Continuity multiplier (v1):
- If no missed cycle streak: `C_v(c) = 1 + g * s_v(c)`
- `g = 0.00025` (0.025% per successful consecutive cycle)
- `s_v(c)` = streak length in cycles
- Missed cycle resets streak to 0

Rarity multiplier (bounded):
- `R_v(c) in [1.00, 1.50]`
- Computed from hardware-class scarcity index (lower representation => higher value)

Quality multiplier:
- `Q_v(c) in {0, 1.0, 1.1}`
- 0 if invalid/failed integrity
- 1.0 normal accepted
- 1.1 high-confidence package (repeat consistency + low variance)

### 3.3 Validator payout cap
Cycle-wide validator cap:
`sum_v reward_validator(v,c) <= cap_validator_pct * pool_available(c)`
- v1 default: `cap_validator_pct = 0.40`
- If exceeded, pro-rate all validator rewards equally.

## 4) Contributor Economics
## 4.1 Submission stake
Each submission locks stake `S = 5` credits (v1 default).
State: `stake_locked` until verdict finalization.

## 4.2 Verdict states
After test-oracle evaluation:
1. `positive_delta`
2. `flat_delta`
3. `negative_delta`

## 4.3 Contributor settlement
Let measured normalized improvement score = `M >= 0`.

A) Positive delta:
- payout formula:
  `reward_contrib = k_contrib * M * pool_scale(c)`
- `pool_scale(c) = clamp(pool_available(c)/pool_target, min_scale, max_scale)`
- stake refunded in full
- payout burn applied: `burn_payout_pct` (v1 default 2%)

B) Flat delta:
- stake refunded minus flat fee
- `refund = S - flat_fee`
- `flat_fee` -> incentive_pool inflow

C) Negative delta:
- full stake slashed
- `S` -> incentive_pool inflow

v1 defaults:
- `k_contrib = 1.0`
- `pool_target = 10,000 credits`
- `min_scale = 0.25`, `max_scale = 2.0`
- `flat_fee = 0.25 credits`
- `burn_payout_pct = 0.02`

## 5) Appeals and Settlement Delay
- Every contributor result enters `pending_settlement` for `T_appeal`
- v1 default: `T_appeal = 72h`
- Validators may challenge with evidence
- If challenge accepted: rerun/expand cohort, replace verdict
- Only final verdict triggers payout/refund/slash

## 6) Pool Accounting
At cycle `c`:

`pool_open(c)` = prior close

Inflows:
- Fast lane inflow
- flat fees
- slashed stakes
- optional seed top-up

Outflows:
- validator payouts
- contributor payouts

Burns:
- payout burn
- optional Fast split burn

`pool_close(c) = pool_open(c) + inflows - outflows - burns_from_pool`

Rule: `pool_close(c) >= pool_floor`
- v1 default `pool_floor = 500 credits`
- if predicted close < floor: trigger payout throttling policy

## 7) Solvency Guardrails
### 7.1 Payout throttle ladder
If projected pool stress:
1. reduce contributor multiplier (`k_contrib`) by 20%
2. reduce validator cap percentage by 10 pts
3. increase Fast fee by +1 credit (after governance/admin approval)

### 7.2 Hard safety
- Never execute payouts that would violate `pool_floor`
- All over-cap payouts are pro-rated, never skipped silently

## 8) Anti-Gaming Economic Rules
- No payout for unverified benchmark integrity
- Duplicate-risk hardware above threshold can submit data but gets `Q=0` pending review
- Contributor cooldown: max N active submissions per contributor (v1 default N=2)
- Stake must remain locked during appeal window

## 9) Halving/Reset Cycle
To avoid unbounded continuity inflation:
- Every `H` cycles, continuity component resets globally
- v1 default: `H = 180 cycles`
- Reset affects only streak-derived bonus, not base reward

## 10) Deterministic State Machine (economic)
Consumer machine:
- `stable` -> `fast_active` (if paid)
- `fast_active` -> burn event per cycle
- `fast_active` -> `stable` (if unpaid or downgraded)

Validator submission:
- `submitted` -> `validated`/`rejected`
- `validated` -> `eligible`
- `eligible` -> `paid` (or `prorated_paid`)

Contributor submission:
- `proposed` -> `stake_locked` -> `testing`
- `testing` -> `pending_settlement`
- `pending_settlement` -> `final_positive | final_flat | final_negative`
- final state -> `paid+refund | partial_refund | slashed`

## 11) Edge Cases (explicit)
1. Pool depletion mid-cycle:
   - freeze new contributor payouts
   - pay validators first up to cap with pro-rating
   - carry unpaid contributor rewards as queued obligations (non-interest bearing)

2. Oracle failure / inconclusive tests:
   - verdict = `flat_delta_pending`
   - extend test cohort once
   - if still inconclusive -> flat settlement (refund minus flat fee)

3. Appeal spam:
   - each appeal requires micro-stake `A_fee` (refundable if successful)

4. Contributor disappears during lock:
   - no action needed; stake remains bound to verdict lifecycle

5. Validator misses cycle:
   - streak reset only; no punitive slash

## 12) v1 Parameters (editable knobs)
- `F_fast = 5`
- `alpha_pool = 1.0`
- `B_v = 1.0`
- `g = 0.00025`
- `R_v max = 1.50`
- `cap_validator_pct = 0.40`
- `S = 5`
- `flat_fee = 0.25`
- `burn_payout_pct = 0.02`
- `T_appeal = 72h`
- `pool_floor = 500`
- `H = 180 cycles`

## 13) Freeze Notes
- v1 is intentionally conservative.
- All parameters are configurable without schema rewrite.
- Any change to formulas (not just parameter values) requires v1.1 spec bump.
