# CursiveOS Hub Data Contract v1

Date: 2026-04-03
Owner: Copper Sage

Goal: define exactly what each MVP Hub panel reads/writes so users can complete the loop without SQL.

## 1) Install tab
Read:
- latest wrapper version (static config for now)
- install command text
Write:
- none

## 2) Machines tab
Read:
- machine_id, plan, fast_cycle_fee, last_burn_cycle_id from l5_machine_entitlements
- inferred machine health from latest runs rows (phase 2)
Write:
- plan toggle stable/fast (via RPC/API)
- machine enroll (machine_id + account binding)

## 3) Rewards tab
Read:
- account balance from v_l5_account_balances
- pool status from v_l5_pool_balance
- recent ledger events by account/cycle from l5_credit_ledger
Write:
- none (view only in MVP)

## 4) Contributions tab
Read:
- submissions from l5_contributor_submissions
- oracle eval status from l5_oracle_evaluations
- non-delta review status from l5_nondelta_reviews
Write:
- create submission metadata
- open appeal window request (role-gated)

## 5) Governance tab
Read:
- open appeals from l5_appeals
- votes from l5_governance_votes
- admin action log from l5_admin_actions
Write:
- cast vote
- open appeal (with reason/evidence)

## 6) Cycle card (global header)
Read:
- latest cycle from l5_pool_cycles
- reconciliation status from v_l5_cycle_reconciliation
Write:
- run cycle action (admin-only)

## MVP access model (temporary)
- account_id selected by operator login identity map (simple)
- role determines button visibility
- no public anonymous write actions

## Output format rules
- all timestamps shown in local timezone + UTC tooltip
- all credits shown with 2-6 decimal precision
- all status badges: open/closed/failed/pending/blocked
