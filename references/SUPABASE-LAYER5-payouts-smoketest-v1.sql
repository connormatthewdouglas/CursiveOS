-- Layer 5 payouts smoke test v1
-- Use after applying SUPABASE-MIGRATION-layer5-payouts-v1.sql

-- Ensure cycle 3 open
select l5_open_cycle(3, 1000);

-- Ensure one validator account and contributor account exist
insert into l5_accounts(role, status)
select 'validator', 'active'
where not exists (select 1 from l5_accounts where role='validator');

insert into l5_accounts(role, status)
select 'contributor', 'active'
where not exists (select 1 from l5_accounts where role='contributor');

-- Pay a validator (idempotent key)
with v as (
  select account_id from l5_accounts where role='validator' order by created_at asc limit 1
)
select l5_pay_validator(
  3,
  (select account_id from v),
  'smoke-validator-machine-001',
  1.0,
  'smoke-validator-payout-cycle-3-001'
) as validator_result;

-- Create contributor submission if missing
with c as (
  select account_id from l5_accounts where role='contributor' order by created_at asc limit 1
)
insert into l5_contributor_submissions (
  account_id, submission_hash, title, class, stake_amount, state
)
select
  (select account_id from c),
  'smoke-submission-hash-001',
  'Smoke submission',
  'preset',
  5,
  'stake_locked'
where not exists (
  select 1 from l5_contributor_submissions where submission_hash='smoke-submission-hash-001'
);

-- Settle contributor as flat delta
select l5_settle_contributor(
  3,
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-001' limit 1),
  'flat_delta',
  0,
  'smoke-contrib-settle-cycle-3-001'
) as contributor_result;

-- Reconcile cycle
select l5_close_cycle_reconcile(3) as close_result;

-- Inspect cycle + latest ledger events
select cycle_id, pool_open, inflow_total, outflow_total, burn_total, pool_close, status
from l5_pool_cycles
where cycle_id=3;

select event_type, bucket, amount, idempotency_key
from l5_credit_ledger
where cycle_id=3
order by event_time desc;
