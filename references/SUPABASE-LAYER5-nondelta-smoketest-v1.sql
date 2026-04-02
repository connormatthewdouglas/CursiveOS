-- Layer 5 non-delta payout smoke test v1

select l5_open_cycle(6, 1000);

insert into l5_accounts(role, status)
select 'contributor', 'active'
where not exists (select 1 from l5_accounts where role='contributor');

insert into l5_accounts(role, status)
select 'validator', 'active'
where not exists (select 1 from l5_accounts where role='validator');

with c as (
  select account_id from l5_accounts where role='contributor' order by created_at asc limit 1
)
insert into l5_contributor_submissions (
  account_id, submission_hash, title, class, stake_amount, state
)
select
  (select account_id from c),
  'smoke-submission-hash-nondelta-001',
  'Smoke non-delta security patch',
  'security',
  5,
  'stake_locked'
where not exists (
  select 1 from l5_contributor_submissions where submission_hash='smoke-submission-hash-nondelta-001'
);

select l5_record_nondelta_review(
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-nondelta-001' limit 1),
  6,
  (select account_id from l5_accounts where role='validator' order by created_at asc limit 1),
  'security',
  5,
  4,
  4,
  5,
  'critical security fix with broad impact',
  'https://example.com/evidence'
) as review_result;

select l5_settle_nondelta_from_review(
  6,
  (select submission_id from l5_contributor_submissions where submission_hash='smoke-submission-hash-nondelta-001' limit 1),
  'smoke-nondelta-settle-cycle-6-001'
) as settle_result;

select event_type, bucket, amount, idempotency_key
from l5_credit_ledger
where cycle_id=6
order by event_time desc;
