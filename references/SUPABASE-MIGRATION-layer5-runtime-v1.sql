-- CursiveOS Layer 5 runtime scaffolding v1
-- Date: 2026-04-02
-- Purpose: add cycle/entitlement runtime functions for burns + reconciliation

create extension if not exists pgcrypto;

-- Runtime parameters (tunable without formula rewrites)
create table if not exists l5_params (
  key text primary key,
  value_numeric numeric(18,8) null,
  value_text text null,
  updated_at timestamptz not null default now()
);

insert into l5_params (key, value_numeric)
values
  ('fast_cycle_fee_default', 5),
  ('pool_floor', 500),
  ('validator_cap_pct', 0.40),
  ('burn_payout_pct', 0.02)
on conflict (key) do nothing;

-- Open cycle helper
create or replace function l5_open_cycle(p_cycle_id bigint, p_pool_open numeric)
returns void
language plpgsql
as $$
begin
  insert into l5_pool_cycles (
    cycle_id, cycle_started_at, pool_open, status
  ) values (
    p_cycle_id, now(), p_pool_open, 'open'
  )
  on conflict (cycle_id) do nothing;
end;
$$;

-- Fast burn event helper (idempotent)
create or replace function l5_apply_fast_burn(
  p_cycle_id bigint,
  p_machine_id text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
as $$
declare
  v_account_id uuid;
  v_plan text;
  v_fee numeric(18,6);
  v_exists int;
begin
  select account_id, plan, fast_cycle_fee
  into v_account_id, v_plan, v_fee
  from l5_machine_entitlements
  where machine_id = p_machine_id;

  if v_account_id is null then
    return jsonb_build_object('ok', false, 'reason', 'machine_not_found');
  end if;

  if v_plan <> 'fast' then
    return jsonb_build_object('ok', false, 'reason', 'plan_not_fast');
  end if;

  select count(*) into v_exists
  from l5_credit_ledger
  where idempotency_key = p_idempotency_key;

  if v_exists > 0 then
    return jsonb_build_object('ok', true, 'reason', 'already_applied');
  end if;

  insert into l5_credit_ledger (
    cycle_id,
    event_type,
    source_account_id,
    target_account_id,
    amount,
    bucket,
    reference_type,
    reference_id,
    idempotency_key,
    metadata
  ) values (
    p_cycle_id,
    'fast_burn_inflow',
    v_account_id,
    null,
    coalesce(v_fee, 5),
    'incentive_pool',
    'machine',
    p_machine_id,
    p_idempotency_key,
    jsonb_build_object('plan', 'fast', 'fee', coalesce(v_fee,5))
  );

  update l5_machine_entitlements
  set last_burn_cycle_id = p_cycle_id,
      plan_updated_at = now()
  where machine_id = p_machine_id;

  return jsonb_build_object('ok', true, 'reason', 'applied', 'amount', coalesce(v_fee,5));
end;
$$;

-- Reconciliation close helper
create or replace function l5_close_cycle_reconcile(p_cycle_id bigint)
returns jsonb
language plpgsql
as $$
declare
  v_open numeric(18,6);
  v_inflow numeric(18,6);
  v_outflow numeric(18,6);
  v_burn numeric(18,6);
  v_expected numeric(18,6);
  v_close numeric(18,6);
  v_floor numeric(18,6);
  v_drift numeric(18,6);
begin
  select pool_open into v_open
  from l5_pool_cycles
  where cycle_id = p_cycle_id
  for update;

  if v_open is null then
    return jsonb_build_object('ok', false, 'reason', 'cycle_not_found');
  end if;

  select coalesce(sum(amount),0) into v_inflow
  from l5_credit_ledger
  where cycle_id = p_cycle_id
    and event_type in ('fast_burn_inflow','flat_fee_inflow','slash_inflow','seed_topup')
    and bucket = 'incentive_pool';

  select coalesce(sum(amount),0) into v_outflow
  from l5_credit_ledger
  where cycle_id = p_cycle_id
    and event_type in ('validator_payout','contributor_payout')
    and bucket = 'incentive_pool';

  select coalesce(sum(amount),0) into v_burn
  from l5_credit_ledger
  where cycle_id = p_cycle_id
    and bucket = 'burn_sink';

  v_expected := v_open + v_inflow - v_outflow - v_burn;
  v_close := v_expected;
  v_drift := 0;

  select coalesce(value_numeric, 500) into v_floor
  from l5_params
  where key = 'pool_floor';

  if v_close < v_floor then
    update l5_pool_cycles
    set inflow_total = v_inflow,
        outflow_total = v_outflow,
        burn_total = v_burn,
        pool_close = v_close,
        reconciliation_drift = v_drift,
        cycle_closed_at = now(),
        status = 'failed'
    where cycle_id = p_cycle_id;

    return jsonb_build_object('ok', false, 'reason', 'pool_floor_breach', 'pool_close', v_close, 'pool_floor', v_floor);
  end if;

  update l5_pool_cycles
  set inflow_total = v_inflow,
      outflow_total = v_outflow,
      burn_total = v_burn,
      pool_close = v_close,
      reconciliation_drift = v_drift,
      cycle_closed_at = now(),
      status = 'closed'
  where cycle_id = p_cycle_id;

  return jsonb_build_object('ok', true, 'pool_close', v_close, 'inflow', v_inflow, 'outflow', v_outflow, 'burn', v_burn);
end;
$$;
