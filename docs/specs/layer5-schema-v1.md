# Layer 5 Schema v1 (Day 3 Freeze)

Status: FROZEN v1
Date: 2026-04-02
Owner: Copper Sage

Context: Existing CursiveRoot has `runs` table and hardware/stability extensions from v1.5 migration.
Goal: Add Layer 5 accounting/incentive tables without breaking current ingestion.

## Design Principles
- Append-only ledger for all credit movement
- Deterministic cycle settlement snapshots
- No hidden balance writes
- Idempotent event ingestion

## New Tables

### 1) l5_accounts
Purpose: wallet/account identity for consumers, validators, contributors.
Columns:
- account_id uuid pk
- role text check in ('consumer','validator','contributor','mixed')
- status text check in ('active','suspended','review') default 'active'
- created_at timestamptz default now()

Indexes:
- idx_l5_accounts_role(role)

### 2) l5_machine_entitlements
Purpose: Fast/Stable plan state per machine fingerprint.
Columns:
- machine_id text pk (hardware fingerprint hash key)
- account_id uuid fk -> l5_accounts
- plan text check in ('stable','fast') default 'stable'
- fast_cycle_fee numeric(18,6) default 5
- plan_updated_at timestamptz default now()
- last_burn_cycle_id bigint null

Indexes:
- idx_l5_entitlements_account(account_id)
- idx_l5_entitlements_plan(plan)

### 3) l5_credit_ledger
Purpose: canonical append-only credit events.
Columns:
- event_id uuid pk
- event_time timestamptz default now()
- cycle_id bigint not null
- event_type text not null
- source_account_id uuid null fk -> l5_accounts
- target_account_id uuid null fk -> l5_accounts
- amount numeric(18,6) not null check (amount >= 0)
- bucket text not null check in ('incentive_pool','ops_reserve','burn_sink','account')
- reference_type text null
- reference_id text null
- idempotency_key text not null
- formula_version text not null default 'l5-econ-v1'
- metadata jsonb not null default '{}'::jsonb

Constraints:
- unique(idempotency_key)

Indexes:
- idx_l5_ledger_cycle(cycle_id)
- idx_l5_ledger_type(event_type)
- idx_l5_ledger_source(source_account_id)
- idx_l5_ledger_target(target_account_id)

### 4) l5_pool_cycles
Purpose: cycle-level accounting snapshot.
Columns:
- cycle_id bigint pk
- cycle_started_at timestamptz not null
- cycle_closed_at timestamptz null
- pool_open numeric(18,6) not null
- inflow_total numeric(18,6) not null default 0
- outflow_total numeric(18,6) not null default 0
- burn_total numeric(18,6) not null default 0
- pool_close numeric(18,6) null
- reconciliation_drift numeric(18,6) default 0
- status text check in ('open','settling','closed','failed') default 'open'

Indexes:
- idx_l5_pool_cycles_status(status)

### 5) l5_validator_cycles
Purpose: validator reward calc + payment status by cycle.
Columns:
- id uuid pk
- cycle_id bigint not null
- account_id uuid not null fk -> l5_accounts
- machine_id text not null
- streak_count integer not null default 0
- multiplier_continuity numeric(18,8) not null
- multiplier_rarity numeric(18,8) not null
- multiplier_quality numeric(18,8) not null
- reward_gross numeric(18,6) not null
- reward_net numeric(18,6) not null
- payout_status text check in ('eligible','held','paid','prorated_paid','rejected') not null
- hold_reason text null
- created_at timestamptz default now()

Constraints:
- unique(cycle_id, account_id, machine_id)

Indexes:
- idx_l5_validator_cycles_cycle(cycle_id)
- idx_l5_validator_cycles_status(payout_status)

### 6) l5_contributor_submissions
Purpose: contributor submission lifecycle and economic settlement.
Columns:
- submission_id uuid pk
- account_id uuid not null fk -> l5_accounts
- submission_hash text not null
- title text not null
- class text check in ('preset','benchmark','driver','kernel','security','other')
- stake_amount numeric(18,6) not null default 5
- state text check in ('proposed','stake_locked','testing','pending_settlement','final_positive','final_flat','final_negative','settled') not null
- measured_score numeric(18,8) null
- verdict text check in ('positive_delta','flat_delta','negative_delta','inconclusive') null
- appeal_deadline timestamptz null
- created_at timestamptz default now()
- updated_at timestamptz default now()

Constraints:
- unique(submission_hash)

Indexes:
- idx_l5_contrib_state(state)
- idx_l5_contrib_account(account_id)

### 7) l5_contributor_settlements
Purpose: immutable settlement record.
Columns:
- settlement_id uuid pk
- submission_id uuid not null fk -> l5_contributor_submissions
- cycle_id bigint not null
- stake_refund numeric(18,6) not null default 0
- payout_gross numeric(18,6) not null default 0
- payout_burn numeric(18,6) not null default 0
- slash_amount numeric(18,6) not null default 0
- flat_fee numeric(18,6) not null default 0
- status text check in ('pending','finalized','superseded') not null
- created_at timestamptz default now()

Indexes:
- idx_l5_contrib_settle_cycle(cycle_id)
- idx_l5_contrib_settle_status(status)

### 8) l5_appeals
Purpose: challenge/appeal workflow.
Columns:
- appeal_id uuid pk
- submission_id uuid not null fk -> l5_contributor_submissions
- opened_by_account_id uuid not null fk -> l5_accounts
- reason text not null
- evidence_uri text null
- fee_amount numeric(18,6) not null default 0
- state text check in ('open','accepted','rejected','resolved') not null
- opened_at timestamptz default now()
- deadline_at timestamptz not null
- resolved_at timestamptz null

Indexes:
- idx_l5_appeals_submission(submission_id)
- idx_l5_appeals_state(state)

### 9) l5_governance_votes
Purpose: record validator voting events (appeals/policy toggles).
Columns:
- vote_id uuid pk
- appeal_id uuid null fk -> l5_appeals
- voter_account_id uuid not null fk -> l5_accounts
- vote text check in ('yes','no','abstain') not null
- weight numeric(18,6) not null default 1
- voted_at timestamptz default now()

Constraints:
- unique(appeal_id, voter_account_id)

## Views

### v_l5_account_balances
Derived balance per account from ledger events.

### v_l5_pool_balance
Derived incentive_pool and burn_sink balances.

### v_l5_cycle_reconciliation
Cycle-level expected vs actual totals and drift.

## Migration Plan
1) create new tables + indexes
2) create views
3) backfill l5_accounts from known validator/contributor identities
4) set all existing machines to stable plan in l5_machine_entitlements
5) dry-run cycle with no payouts to verify zero drift

## Backward Compatibility
- Existing benchmark ingestion remains unchanged
- Layer 5 reads from existing runs/validation outputs
- No required changes to legacy runs schema

## Integrity Rules
- Any payout/refund/slash must produce corresponding ledger events
- Settlement jobs must be idempotent via idempotency_key
- Reconciliation drift != 0 blocks cycle close
