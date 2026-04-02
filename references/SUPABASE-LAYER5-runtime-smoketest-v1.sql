-- Layer 5 runtime smoke test v1
-- Use after applying SUPABASE-MIGRATION-layer5-runtime-v1.sql

-- 0) open or ensure cycle exists
select l5_open_cycle(2, 1000);

-- 1) ensure smoke entitlement exists and is fast
with c as (
  select account_id from l5_accounts where role='consumer' order by created_at asc limit 1
)
insert into l5_machine_entitlements (machine_id, account_id, plan, fast_cycle_fee)
select 'smoke-machine-runtime-001', c.account_id, 'fast', 5 from c
on conflict (machine_id) do update
set plan='fast', fast_cycle_fee=5, plan_updated_at=now();

-- 2) apply burn via function (idempotent key)
select l5_apply_fast_burn(
  2,
  'smoke-machine-runtime-001',
  'runtime-smoke-fast-burn-cycle-2-machine-001'
) as burn_result;

-- 3) close cycle with reconciliation
select l5_close_cycle_reconcile(2) as close_result;

-- 4) inspect cycle + latest ledger row
select cycle_id, pool_open, inflow_total, outflow_total, burn_total, pool_close, status
from l5_pool_cycles
where cycle_id=2;

select event_time, cycle_id, event_type, bucket, amount, idempotency_key
from l5_credit_ledger
where cycle_id=2
order by event_time desc;
