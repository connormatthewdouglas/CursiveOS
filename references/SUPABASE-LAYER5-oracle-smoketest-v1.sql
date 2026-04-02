-- Layer 5 oracle smoke test v1
-- Use after applying SUPABASE-MIGRATION-layer5-oracle-v1.sql

-- Ensure cycle 5 exists
select l5_open_cycle(5, 1000);

-- Ensure contributor account exists
insert into l5_accounts(role, status)
select 'contributor', 'active'
where not exists (select 1 from l5_accounts where role='contributor');

-- Create submission if missing
with c as (
  select account_id from l5_accounts where role='contributor' order by created_at asc limit 1
)
insert into l5_contributor_submissions (
  account_id, submission_hash, title, class, stake_amount, state
)
select
  (select account_id from c),
  'smoke-submission-hash-oracle-001',
  'Smoke oracle submission',
  'preset',
  5,
  'stake_locked'
where not exists (
  select 1 from l5_contributor_submissions where submission_hash='smoke-submission-hash-oracle-001'
);

-- Record oracle final flat verdict
select l5_record_oracle_verdict(
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-oracle-001' limit 1),
  5,
  'flat_delta',
  0,
  0.95,
  'smoke-manifest-cycle-5-001',
  'oracle smoke test flat verdict'
) as oracle_result;

-- Open short appeal window then force-expire for smoke
select l5_open_appeal_window(
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-oracle-001' limit 1),
  1
) as open_window_result;

update l5_contributor_submissions
set appeal_deadline = now() - interval '1 minute'
where submission_hash='smoke-submission-hash-oracle-001';

-- Settle directly from oracle verdict through guarded pathway
select l5_settle_from_oracle_guarded(
  5,
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-oracle-001' limit 1),
  'smoke-oracle-settle-cycle-5-001'
) as settle_result;

-- Inspect resulting ledger events for cycle 5
select event_type, bucket, amount, idempotency_key
from l5_credit_ledger
where cycle_id = 5
order by event_time desc;
