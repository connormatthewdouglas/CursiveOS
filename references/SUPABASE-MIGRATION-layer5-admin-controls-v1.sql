-- CursiveOS Layer 5 admin controls + audit trail v1
-- Date: 2026-04-03
-- Purpose: safe parameter tuning with immutable audit records

create extension if not exists pgcrypto;

create table if not exists l5_admin_actions (
  action_id uuid primary key default gen_random_uuid(),
  actor_account_id uuid null references l5_accounts(account_id),
  action_type text not null check (action_type in ('set_param','set_band_value')),
  target_key text not null,
  old_value_numeric numeric(18,8) null,
  new_value_numeric numeric(18,8) null,
  reason text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_l5_admin_actions_type on l5_admin_actions(action_type);
create index if not exists idx_l5_admin_actions_key on l5_admin_actions(target_key);
create index if not exists idx_l5_admin_actions_time on l5_admin_actions(created_at desc);

create or replace function l5_set_param(
  p_actor_account_id uuid,
  p_key text,
  p_value numeric,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_old numeric;
begin
  if p_reason is null or length(trim(p_reason)) < 5 then
    return jsonb_build_object('ok', false, 'reason', 'reason_required');
  end if;

  -- Guardrails
  if p_key = 'pool_floor' and (p_value < 0 or p_value > 1000000) then
    return jsonb_build_object('ok', false, 'reason', 'pool_floor_out_of_range');
  end if;

  if p_key = 'validator_cap_pct' and (p_value <= 0 or p_value > 1) then
    return jsonb_build_object('ok', false, 'reason', 'validator_cap_pct_out_of_range');
  end if;

  if p_key = 'burn_payout_pct' and (p_value < 0 or p_value > 0.5) then
    return jsonb_build_object('ok', false, 'reason', 'burn_payout_pct_out_of_range');
  end if;

  if p_key = 'fast_cycle_fee_default' and (p_value < 0 or p_value > 1000) then
    return jsonb_build_object('ok', false, 'reason', 'fast_cycle_fee_out_of_range');
  end if;

  select value_numeric into v_old from l5_params where key = p_key;

  insert into l5_params (key, value_numeric, updated_at)
  values (p_key, p_value, now())
  on conflict (key) do update set
    value_numeric = excluded.value_numeric,
    updated_at = now();

  insert into l5_admin_actions (
    actor_account_id, action_type, target_key, old_value_numeric, new_value_numeric, reason, metadata
  ) values (
    p_actor_account_id, 'set_param', p_key, v_old, p_value, p_reason, coalesce(p_metadata,'{}'::jsonb)
  );

  return jsonb_build_object('ok', true, 'key', p_key, 'old', v_old, 'new', p_value);
end;
$$;

create or replace function l5_set_nondelta_band_value(
  p_actor_account_id uuid,
  p_band text,
  p_value numeric,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_old numeric;
begin
  if p_band not in ('low','medium','high','critical') then
    return jsonb_build_object('ok', false, 'reason', 'invalid_band');
  end if;

  if p_reason is null or length(trim(p_reason)) < 5 then
    return jsonb_build_object('ok', false, 'reason', 'reason_required');
  end if;

  if p_value < 0 or p_value > 10000 then
    return jsonb_build_object('ok', false, 'reason', 'band_value_out_of_range');
  end if;

  select payout_credits into v_old
  from l5_nondelta_band_values
  where band = p_band;

  insert into l5_nondelta_band_values (band, payout_credits, updated_at)
  values (p_band, p_value, now())
  on conflict (band) do update set
    payout_credits = excluded.payout_credits,
    updated_at = now();

  insert into l5_admin_actions (
    actor_account_id, action_type, target_key, old_value_numeric, new_value_numeric, reason, metadata
  ) values (
    p_actor_account_id, 'set_band_value', 'nondelta_band:' || p_band, v_old, p_value, p_reason, coalesce(p_metadata,'{}'::jsonb)
  );

  return jsonb_build_object('ok', true, 'band', p_band, 'old', v_old, 'new', p_value);
end;
$$;
