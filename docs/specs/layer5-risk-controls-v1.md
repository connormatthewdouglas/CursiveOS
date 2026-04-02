# Layer 5 Risk Controls v1 (Day 4 Freeze)

Status: FROZEN v1
Date: 2026-04-02
Owner: Copper Sage

## Objective
Define trust, anti-sybil, abuse prevention, and dispute controls so incentives reward real contribution and resist manipulation.

## 1) Threat Model
Primary adversaries:
1. Validator sybil farms (same operator pretending to be many independent validators)
2. Fake/duplicated hardware submissions for rarity farming
3. Contributor spam exploiting low stake and payout asymmetry
4. Appeal spam to stall settlements
5. Coordinated vote capture in small cohorts

## 2) Identity & Sybil Controls
### 2.1 Account-level controls
- Account verification tier required before payouts above threshold
- One payout destination per account until trust tier upgrade
- Cooldown for changing payout destination (default 14 days)

### 2.2 Machine-level controls
- Machine fingerprint hash required for eligibility
- Duplicate-risk scoring from hardware profile overlap + network timing + behavioral similarity
- High duplicate-risk => payout hold-review (not immediate ban)

### 2.3 Cluster detection
- Detect correlated submission timing, identical benchmark variance patterns, and identical environmental signatures
- Clustered accounts get reduced rarity multiplier pending review

## 3) Validator Reward Integrity Controls
- Minimum evidence package per cycle (required benchmark set)
- Stability flag must pass for eligibility
- Random audit sampling each cycle (default 10% of paid validator packages)
- Failed audit => reward clawback queued next cycle + temporary hold tier

## 4) Contributor Submission Controls
- Max active submissions per contributor: 2 (v1)
- Minimum cooldown between submissions: 12h
- Stake required before testing assignment
- New contributors start in gated tier (reviewed cohort) before broader access
- Submission classes routed to appropriate test cohorts; no cross-class payout shortcuts

## 5) Oracle & Measurement Safeguards
- Verdict requires minimum test breadth:
  - >= N1 same-class hardware samples
  - >= N2 cross-class hardware samples
- Inconclusive verdict path mandatory if variance above threshold
- Oracle output includes confidence score and test manifest hash
- Any missing test manifest blocks settlement

## 6) Appeals & Governance Controls
- Appeal window default: 72h
- Appeal requires fee stake (refundable if appeal upheld)
- One appeal per submission state unless materially new evidence
- Voting rights: validators in good standing
- Quorum and supermajority required for verdict override
- Emergency admin override allowed only with signed reason + public log record

## 7) Economic Abuse Controls
- Pool floor guard: payouts never push below floor
- Pro-rata payout when cycle obligations exceed caps
- Payout throttle ladder auto-engages under stress
- Rarity multiplier cap prevents outsized extraction
- Continuity bonus reset cycle prevents unbounded liabilities

## 8) Monitoring & Alerts
Trigger alerts on:
- duplicate-risk spikes
- sudden concentration in top payout recipients
- reconciliation drift != 0
- abnormal appeal rate
- contributor negative-delta surge

## 9) Enforcement Ladder
1. soft warning
2. payout hold + manual review
3. temporary suspension
4. permanent ban (requires evidence packet + recorded decision)

## 10) False-Positive Policy
- Holds are reversible
- Appeals available for enforcement actions
- If false positive confirmed, missed payout is restored in next cycle with note

## 11) v1 Parameter Defaults
- duplicate-risk hold threshold: 0.80
- audit sample rate: 10%
- max active submissions: 2
- submission cooldown: 12h
- appeal fee: 0.10 credits
- quorum: 20% of active validators
- override supermajority: 67%

## 12) Governance Scope v1
Allowed by validator vote:
- parameter tuning within predefined ranges
- appeal outcome override
Not allowed by validator vote:
- changing core formula family
- bypassing ledger/reconciliation invariants
- minting credits outside policy

## 13) Review Cadence
- Weekly risk review during first 8 weeks
- Parameter changes logged with before/after rationale and observed effects
