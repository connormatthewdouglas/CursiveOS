-- Layer 5 Smoke Test v1
-- Safe sanity checks after migration. No destructive actions.

-- 1) Object existence counts
select 'tables' as kind, count(*) as count
from information_schema.tables
where table_schema='public' and table_name like 'l5_%'
union all
select 'views' as kind, count(*) as count
from information_schema.views
where table_schema='public' and table_name like 'v_l5_%';

-- 2) Seed minimal accounts for test (idempotent by role uniqueness assumption via not exists checks)
insert into l5_accounts (role, status)
select 'consumer','active'
where not exists (select 1 from l5_accounts where role='consumer');

insert into l5_accounts (role, status)
select 'validator','active'
where not exists (select 1 from l5_accounts where role='validator');

insert into l5_accounts (role, status)
select 'contributor','active'
where not exists (select 1 from l5_accounts where role='contributor');

-- 3) Create one entitlement row bound to consumer account (idempotent)
insert into l5_machine_entitlements (machine_id, account_id, plan, fast_cycle_fee)
select 'smoke-machine-001', a.account_id, 'fast', 5
from l5_accounts a
where a.role='consumer'
  and not exists (
    select 1 from l5_machine_entitlements e where e.machine_id='smoke-machine-001'
  )
limit 1;

-- 4) Create sample cycle if missing
insert into l5_pool_cycles (cycle_id, cycle_started_at, pool_open, status)
select 1, now(), 1000, 'open'
where not exists (select 1 from l5_pool_cycles where cycle_id=1);

-- 5) Simulate fast burn inflow ledger event (idempotent)
insert into l5_credit_ledger (
  cycle_id, event_type, source_account_id, target_account_id, amount, bucket,
  reference_type, reference_id, idempotency_key, metadata
)
select
  1,
  'fast_burn_inflow',
  e.account_id,
  null,
  5,
  'incentive_pool',
  'machine',
  'smoke-machine-001',
  'smoke-fast-burn-cycle-1-machine-001',
  jsonb_build_object('plan','fast','fee',5)
from l5_machine_entitlements e
where e.machine_id='smoke-machine-001'
  and not exists (
    select 1 from l5_credit_ledger l where l.idempotency_key='smoke-fast-burn-cycle-1-machine-001'
  );

-- 6) Read derived balances/reconciliation views
select * from v_l5_pool_balance;
select * from v_l5_account_balances order by account_id;
select * from v_l5_cycle_reconciliation where cycle_id=1;

-- 7) Show latest ledger rows
select event_time, cycle_id, event_type, bucket, amount, idempotency_key
from l5_credit_ledger
order by event_time desc
limit 10;
