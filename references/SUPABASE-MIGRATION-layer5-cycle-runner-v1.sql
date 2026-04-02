-- CursiveOS Layer 5 cycle runner v1
-- Date: 2026-04-02
-- Purpose: one-shot cycle orchestration for burns, settlements, and reconciliation

create extension if not exists pgcrypto;

create or replace function l5_process_fast_burns(p_cycle_id bigint)
returns jsonb
language plpgsql
as $$
declare
  r record;
  v_result jsonb;
  v_applied int := 0;
  v_skipped int := 0;
  v_failed int := 0;
  v_key text;
begin
  for r in
    select machine_id
    from l5_machine_entitlements
    where plan = 'fast'
  loop
    v_key := 'cycle-' || p_cycle_id::text || '-fastburn-' || r.machine_id;
    v_result := l5_apply_fast_burn(p_cycle_id, r.machine_id, v_key);

    if coalesce(v_result->>'ok','false') = 'true' then
      if coalesce(v_result->>'reason','') in ('applied') then
        v_applied := v_applied + 1;
      else
        v_skipped := v_skipped + 1;
      end if;
    else
      v_failed := v_failed + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'applied', v_applied,
    'skipped', v_skipped,
    'failed', v_failed
  );
end;
$$;

create or replace function l5_settle_oracle_ready_submissions(p_cycle_id bigint)
returns jsonb
language plpgsql
as $$
declare
  r record;
  v_result jsonb;
  v_settled int := 0;
  v_blocked int := 0;
  v_failed int := 0;
begin
  for r in
    select distinct s.submission_id
    from l5_contributor_submissions s
    join l5_oracle_evaluations o on o.submission_id = s.submission_id
    where o.cycle_id = p_cycle_id
      and o.status = 'final'
      and o.verdict in ('positive_delta','flat_delta','negative_delta')
      and s.state in ('pending_settlement','stake_locked','testing')
  loop
    v_result := l5_settle_from_oracle_guarded(
      p_cycle_id,
      r.submission_id,
      'cycle-' || p_cycle_id::text || '-oracle-' || r.submission_id::text
    );

    if coalesce(v_result->>'ok','false') = 'true' then
      v_settled := v_settled + 1;
    else
      if coalesce(v_result->>'reason','') in ('appeal_window_open','open_appeals_exist','oracle_inconclusive','oracle_verdict_not_found') then
        v_blocked := v_blocked + 1;
      else
        v_failed := v_failed + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'settled', v_settled,
    'blocked', v_blocked,
    'failed', v_failed
  );
end;
$$;

create or replace function l5_settle_nondelta_ready_reviews(p_cycle_id bigint)
returns jsonb
language plpgsql
as $$
declare
  r record;
  v_result jsonb;
  v_settled int := 0;
  v_blocked int := 0;
  v_failed int := 0;
begin
  for r in
    select distinct nr.submission_id
    from l5_nondelta_reviews nr
    where nr.cycle_id = p_cycle_id
      and nr.status in ('provisional','challenged')
  loop
    v_result := l5_settle_nondelta_from_review(
      p_cycle_id,
      r.submission_id,
      'cycle-' || p_cycle_id::text || '-nondelta-' || r.submission_id::text
    );

    if coalesce(v_result->>'ok','false') = 'true' then
      v_settled := v_settled + 1;
    else
      if coalesce(v_result->>'reason','') in ('open_appeals_exist','review_not_found','band_value_missing') then
        v_blocked := v_blocked + 1;
      else
        v_failed := v_failed + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'settled', v_settled,
    'blocked', v_blocked,
    'failed', v_failed
  );
end;
$$;

create or replace function l5_run_cycle(
  p_cycle_id bigint,
  p_pool_open numeric default 1000
)
returns jsonb
language plpgsql
as $$
declare
  v_cycle_exists int;
  v_fast jsonb;
  v_oracle jsonb;
  v_nondelta jsonb;
  v_close jsonb;
begin
  select count(*) into v_cycle_exists
  from l5_pool_cycles
  where cycle_id = p_cycle_id;

  if v_cycle_exists = 0 then
    perform l5_open_cycle(p_cycle_id, p_pool_open);
  end if;

  v_fast := l5_process_fast_burns(p_cycle_id);
  v_oracle := l5_settle_oracle_ready_submissions(p_cycle_id);
  v_nondelta := l5_settle_nondelta_ready_reviews(p_cycle_id);
  v_close := l5_close_cycle_reconcile(p_cycle_id);

  return jsonb_build_object(
    'ok', true,
    'cycle_id', p_cycle_id,
    'fast_burns', v_fast,
    'oracle_settlements', v_oracle,
    'nondelta_settlements', v_nondelta,
    'reconcile', v_close
  );
end;
$$;
