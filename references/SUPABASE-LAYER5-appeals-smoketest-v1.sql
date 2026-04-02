-- Layer 5 appeals smoke test v1
-- Use after applying SUPABASE-MIGRATION-layer5-appeals-v1.sql

-- Ensure cycle 4 open
select l5_open_cycle(4, 1000);

-- Ensure contributor exists
insert into l5_accounts(role, status)
select 'contributor', 'active'
where not exists (select 1 from l5_accounts where role='contributor');

-- Create smoke submission with pending state if missing
with c as (
  select account_id from l5_accounts where role='contributor' order by created_at asc limit 1
)
insert into l5_contributor_submissions (
  account_id, submission_hash, title, class, stake_amount, state
)
select
  (select account_id from c),
  'smoke-submission-hash-appeal-001',
  'Smoke appeal submission',
  'preset',
  5,
  'stake_locked'
where not exists (
  select 1 from l5_contributor_submissions where submission_hash='smoke-submission-hash-appeal-001'
);

-- Open appeal window (1 hour)
select l5_open_appeal_window(
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-appeal-001' limit 1),
  1
) as open_window_result;

-- Attempt guarded settle should fail due to window open
select l5_settle_contributor_guarded(
  4,
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-appeal-001' limit 1),
  'flat_delta',
  0,
  'smoke-appeal-guarded-settle-001'
) as guarded_result_blocked;

-- Force deadline in past for smoke continuation
update l5_contributor_submissions
set appeal_deadline = now() - interval '1 minute'
where submission_hash='smoke-submission-hash-appeal-001';

-- Guarded settle should now pass
select l5_settle_contributor_guarded(
  4,
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-appeal-001' limit 1),
  'flat_delta',
  0,
  'smoke-appeal-guarded-settle-002'
) as guarded_result_pass;

-- Inspect cycle 4 ledger rows
select event_type, bucket, amount, idempotency_key
from l5_credit_ledger
where cycle_id=4
order by event_time desc;
