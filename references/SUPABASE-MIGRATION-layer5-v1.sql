-- CursiveOS Layer 5 migration v1
-- Date: 2026-04-02
-- Purpose: add incentive accounting, entitlement, and settlement tables
-- Safe to run multiple times (IF NOT EXISTS guards)

create extension if not exists pgcrypto;

create table if not exists l5_accounts (
  account_id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('consumer','validator','contributor','mixed')),
  status text not null default 'active' check (status in ('active','suspended','review')),
  created_at timestamptz not null default now()
);
create index if not exists idx_l5_accounts_role on l5_accounts(role);

create table if not exists l5_machine_entitlements (
  machine_id text primary key,
  account_id uuid not null references l5_accounts(account_id),
  plan text not null default 'stable' check (plan in ('stable','fast')),
  fast_cycle_fee numeric(18,6) not null default 5,
  plan_updated_at timestamptz not null default now(),
  last_burn_cycle_id bigint null
);
create index if not exists idx_l5_entitlements_account on l5_machine_entitlements(account_id);
create index if not exists idx_l5_entitlements_plan on l5_machine_entitlements(plan);

create table if not exists l5_credit_ledger (
  event_id uuid primary key default gen_random_uuid(),
  event_time timestamptz not null default now(),
  cycle_id bigint not null,
  event_type text not null,
  source_account_id uuid null references l5_accounts(account_id),
  target_account_id uuid null references l5_accounts(account_id),
  amount numeric(18,6) not null check (amount >= 0),
  bucket text not null check (bucket in ('incentive_pool','ops_reserve','burn_sink','account')),
  reference_type text null,
  reference_id text null,
  idempotency_key text not null,
  formula_version text not null default 'l5-econ-v1',
  metadata jsonb not null default '{}'::jsonb,
  unique(idempotency_key)
);
create index if not exists idx_l5_ledger_cycle on l5_credit_ledger(cycle_id);
create index if not exists idx_l5_ledger_type on l5_credit_ledger(event_type);
create index if not exists idx_l5_ledger_source on l5_credit_ledger(source_account_id);
create index if not exists idx_l5_ledger_target on l5_credit_ledger(target_account_id);

create table if not exists l5_pool_cycles (
  cycle_id bigint primary key,
  cycle_started_at timestamptz not null,
  cycle_closed_at timestamptz null,
  pool_open numeric(18,6) not null,
  inflow_total numeric(18,6) not null default 0,
  outflow_total numeric(18,6) not null default 0,
  burn_total numeric(18,6) not null default 0,
  pool_close numeric(18,6) null,
  reconciliation_drift numeric(18,6) not null default 0,
  status text not null default 'open' check (status in ('open','settling','closed','failed'))
);
create index if not exists idx_l5_pool_cycles_status on l5_pool_cycles(status);

create table if not exists l5_validator_cycles (
  id uuid primary key default gen_random_uuid(),
  cycle_id bigint not null,
  account_id uuid not null references l5_accounts(account_id),
  machine_id text not null,
  streak_count integer not null default 0,
  multiplier_continuity numeric(18,8) not null,
  multiplier_rarity numeric(18,8) not null,
  multiplier_quality numeric(18,8) not null,
  reward_gross numeric(18,6) not null,
  reward_net numeric(18,6) not null,
  payout_status text not null check (payout_status in ('eligible','held','paid','prorated_paid','rejected')),
  hold_reason text null,
  created_at timestamptz not null default now(),
  unique(cycle_id, account_id, machine_id)
);
create index if not exists idx_l5_validator_cycles_cycle on l5_validator_cycles(cycle_id);
create index if not exists idx_l5_validator_cycles_status on l5_validator_cycles(payout_status);

create table if not exists l5_contributor_submissions (
  submission_id uuid primary key default gen_random_uuid(),
  account_id uuid not null references l5_accounts(account_id),
  submission_hash text not null unique,
  title text not null,
  class text not null check (class in ('preset','benchmark','driver','kernel','security','other')),
  stake_amount numeric(18,6) not null default 5,
  state text not null check (state in ('proposed','stake_locked','testing','pending_settlement','final_positive','final_flat','final_negative','settled')),
  measured_score numeric(18,8) null,
  verdict text null check (verdict in ('positive_delta','flat_delta','negative_delta','inconclusive')),
  appeal_deadline timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_l5_contrib_state on l5_contributor_submissions(state);
create index if not exists idx_l5_contrib_account on l5_contributor_submissions(account_id);

create table if not exists l5_contributor_settlements (
  settlement_id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references l5_contributor_submissions(submission_id),
  cycle_id bigint not null,
  stake_refund numeric(18,6) not null default 0,
  payout_gross numeric(18,6) not null default 0,
  payout_burn numeric(18,6) not null default 0,
  slash_amount numeric(18,6) not null default 0,
  flat_fee numeric(18,6) not null default 0,
  status text not null check (status in ('pending','finalized','superseded')),
  created_at timestamptz not null default now()
);
create index if not exists idx_l5_contrib_settle_cycle on l5_contributor_settlements(cycle_id);
create index if not exists idx_l5_contrib_settle_status on l5_contributor_settlements(status);

create table if not exists l5_appeals (
  appeal_id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references l5_contributor_submissions(submission_id),
  opened_by_account_id uuid not null references l5_accounts(account_id),
  reason text not null,
  evidence_uri text null,
  fee_amount numeric(18,6) not null default 0,
  state text not null check (state in ('open','accepted','rejected','resolved')),
  opened_at timestamptz not null default now(),
  deadline_at timestamptz not null,
  resolved_at timestamptz null
);
create index if not exists idx_l5_appeals_submission on l5_appeals(submission_id);
create index if not exists idx_l5_appeals_state on l5_appeals(state);

create table if not exists l5_governance_votes (
  vote_id uuid primary key default gen_random_uuid(),
  appeal_id uuid null references l5_appeals(appeal_id),
  voter_account_id uuid not null references l5_accounts(account_id),
  vote text not null check (vote in ('yes','no','abstain')),
  weight numeric(18,6) not null default 1,
  voted_at timestamptz not null default now(),
  unique(appeal_id, voter_account_id)
);

-- Views
create or replace view v_l5_account_balances as
with inbound as (
  select target_account_id as account_id, sum(amount) as amt
  from l5_credit_ledger
  where target_account_id is not null and bucket = 'account'
  group by 1
), outbound as (
  select source_account_id as account_id, sum(amount) as amt
  from l5_credit_ledger
  where source_account_id is not null and bucket = 'account'
  group by 1
)
select a.account_id,
       coalesce(i.amt,0) - coalesce(o.amt,0) as balance
from l5_accounts a
left join inbound i on i.account_id = a.account_id
left join outbound o on o.account_id = a.account_id;

create or replace view v_l5_pool_balance as
select
  coalesce(sum(case when bucket='incentive_pool' and event_type in ('fast_burn_inflow','flat_fee_inflow','slash_inflow','seed_topup') then amount else 0 end),0)
  - coalesce(sum(case when bucket='incentive_pool' and event_type in ('validator_payout','contributor_payout') then amount else 0 end),0)
  as incentive_pool_balance,
  coalesce(sum(case when bucket='burn_sink' then amount else 0 end),0) as burn_sink_total
from l5_credit_ledger;

create or replace view v_l5_cycle_reconciliation as
select c.cycle_id,
       c.pool_open,
       c.inflow_total,
       c.outflow_total,
       c.burn_total,
       c.pool_close,
       (c.pool_open + c.inflow_total - c.outflow_total - c.burn_total) as expected_close,
       c.reconciliation_drift,
       c.status
from l5_pool_cycles c;
