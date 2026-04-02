-- Layer 5 cycle runner smoke test v1
-- Use after applying SUPABASE-MIGRATION-layer5-cycle-runner-v1.sql

-- Ensure at least one fast entitlement exists
insert into l5_accounts(role, status)
select 'consumer', 'active'
where not exists (select 1 from l5_accounts where role='consumer');

with c as (
  select account_id from l5_accounts where role='consumer' order by created_at asc limit 1
)
insert into l5_machine_entitlements (machine_id, account_id, plan, fast_cycle_fee)
select 'smoke-machine-cycle-runner-001', (select account_id from c), 'fast', 5
where not exists (
  select 1 from l5_machine_entitlements where machine_id='smoke-machine-cycle-runner-001'
);

-- Prepare oracle-backed submission for cycle 7
insert into l5_accounts(role, status)
select 'contributor', 'active'
where not exists (select 1 from l5_accounts where role='contributor');

with c as (
  select account_id from l5_accounts where role='contributor' order by created_at asc limit 1
)
insert into l5_contributor_submissions (
  account_id, submission_hash, title, class, stake_amount, state
)
select (select account_id from c), 'smoke-submission-hash-cycle7-001', 'Cycle 7 oracle smoke', 'preset', 5, 'stake_locked'
where not exists (
  select 1 from l5_contributor_submissions where submission_hash='smoke-submission-hash-cycle7-001'
);

select l5_record_oracle_verdict(
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-cycle7-001' limit 1),
  7,
  'flat_delta',
  0,
  0.93,
  'smoke-manifest-cycle7-001',
  'cycle runner smoke oracle verdict'
) as oracle_result;

update l5_contributor_submissions
set appeal_deadline = now() - interval '1 minute'
where submission_hash='smoke-submission-hash-cycle7-001';

-- Prepare non-delta review for cycle 7
insert into l5_accounts(role, status)
select 'validator', 'active'
where not exists (select 1 from l5_accounts where role='validator');

select l5_record_nondelta_review(
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-cycle7-001' limit 1),
  7,
  (select account_id from l5_accounts where role='validator' order by created_at asc limit 1),
  'reliability',
  3,
  3,
  4,
  3,
  'reliability smoke review',
  null
) as nondelta_review_result;

-- Run cycle orchestration
select l5_run_cycle(7, 1000) as cycle_runner_result;

-- Inspect cycle + ledger
select cycle_id, pool_open, inflow_total, outflow_total, burn_total, pool_close, status
from l5_pool_cycles
where cycle_id=7;

select event_type, bucket, amount, idempotency_key
from l5_credit_ledger
where cycle_id=7
order by event_time desc;
