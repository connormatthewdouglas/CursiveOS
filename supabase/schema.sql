--
-- PostgreSQL database dump
--

\restrict 9pjRSy8rVJqQg3WtYgB1TjpXQps2xc9dPieqeG59xPBvSQUtQsGsofMKsvd252Y

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.10 (Ubuntu 17.10-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: l5_apply_fast_burn(bigint, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_apply_fast_burn(p_cycle_id bigint, p_machine_id text, p_idempotency_key text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
    cycle_id, event_type, source_account_id, target_account_id, amount, bucket,
    reference_type, reference_id, idempotency_key, metadata
  ) values (
    p_cycle_id, 'fast_burn_inflow', v_account_id, null, coalesce(v_fee, 5), 'incentive_pool',
    'machine', p_machine_id, p_idempotency_key,
    jsonb_build_object('plan', 'fast', 'fee', coalesce(v_fee,5))
  );

  update l5_machine_entitlements
  set last_burn_cycle_id = p_cycle_id,
      plan_updated_at = now()
  where machine_id = p_machine_id;

  return jsonb_build_object('ok', true, 'reason', 'applied', 'amount', coalesce(v_fee,5));
end;
$$;


--
-- Name: l5_close_cycle_reconcile(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_close_cycle_reconcile(p_cycle_id bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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


--
-- Name: l5_open_appeal(uuid, uuid, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_open_appeal(p_submission_id uuid, p_opened_by_account_id uuid, p_reason text, p_evidence_uri text DEFAULT NULL::text, p_fee_amount numeric DEFAULT 0.10) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_appeal_id uuid;
  v_deadline timestamptz;
begin
  select coalesce(appeal_deadline, now() + interval '72 hours')
  into v_deadline
  from l5_contributor_submissions
  where submission_id = p_submission_id;

  if v_deadline is null then
    return jsonb_build_object('ok', false, 'reason', 'submission_not_found');
  end if;

  insert into l5_appeals (
    submission_id, opened_by_account_id, reason, evidence_uri, fee_amount, state, deadline_at
  ) values (
    p_submission_id, p_opened_by_account_id, p_reason, p_evidence_uri, p_fee_amount, 'open', v_deadline
  ) returning appeal_id into v_appeal_id;

  return jsonb_build_object('ok', true, 'appeal_id', v_appeal_id, 'deadline_at', v_deadline);
end;
$$;


--
-- Name: l5_open_appeal_window(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_open_appeal_window(p_submission_id uuid, p_hours integer DEFAULT 72) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_exists int;
  v_deadline timestamptz;
begin
  select count(*) into v_exists
  from l5_contributor_submissions
  where submission_id = p_submission_id;

  if v_exists = 0 then
    return jsonb_build_object('ok', false, 'reason', 'submission_not_found');
  end if;

  v_deadline := now() + make_interval(hours => p_hours);

  update l5_contributor_submissions
  set state = 'pending_settlement',
      appeal_deadline = v_deadline,
      updated_at = now()
  where submission_id = p_submission_id;

  return jsonb_build_object('ok', true, 'appeal_deadline', v_deadline);
end;
$$;


--
-- Name: l5_open_cycle(bigint, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_open_cycle(p_cycle_id bigint, p_pool_open numeric) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin
  insert into l5_pool_cycles (
    cycle_id, cycle_started_at, pool_open, status
  ) values (
    p_cycle_id, now(), p_pool_open, 'open'
  )
  on conflict (cycle_id) do nothing;
end;
$$;


--
-- Name: l5_pay_validator(bigint, uuid, text, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_pay_validator(p_cycle_id bigint, p_account_id uuid, p_machine_id text, p_reward numeric, p_idempotency_key text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_exists int;
  v_cycle_status text;
begin
  select count(*) into v_exists
  from l5_credit_ledger
  where idempotency_key = p_idempotency_key;

  if v_exists > 0 then
    return jsonb_build_object('ok', true, 'reason', 'already_applied');
  end if;

  select status into v_cycle_status
  from l5_pool_cycles
  where cycle_id = p_cycle_id;

  if v_cycle_status is null then
    return jsonb_build_object('ok', false, 'reason', 'cycle_not_found');
  end if;

  if v_cycle_status = 'closed' then
    return jsonb_build_object('ok', false, 'reason', 'cycle_closed');
  end if;

  insert into l5_credit_ledger (
    cycle_id, event_type, source_account_id, target_account_id, amount, bucket,
    reference_type, reference_id, idempotency_key, metadata
  ) values (
    p_cycle_id, 'validator_payout', null, p_account_id, p_reward, 'incentive_pool',
    'machine', p_machine_id, p_idempotency_key,
    jsonb_build_object('machine_id', p_machine_id, 'account_id', p_account_id)
  );

  return jsonb_build_object('ok', true, 'reason', 'paid', 'amount', p_reward);
end;
$$;


--
-- Name: l5_process_fast_burns(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_process_fast_burns(p_cycle_id bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
    'ok', true, 'applied', v_applied, 'skipped', v_skipped, 'failed', v_failed
  );
end;
$$;


--
-- Name: l5_record_nondelta_review(uuid, bigint, uuid, text, integer, integer, integer, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_record_nondelta_review(p_submission_id uuid, p_cycle_id bigint, p_reviewer_account_id uuid, p_contribution_type text, p_severity integer, p_breadth integer, p_confidence integer, p_urgency integer, p_notes text DEFAULT NULL::text, p_evidence_uri text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_review_id uuid;
begin
  insert into l5_nondelta_reviews (
    submission_id, cycle_id, reviewer_account_id, contribution_type,
    severity_score, breadth_score, confidence_score, urgency_score,
    notes, evidence_uri, status
  ) values (
    p_submission_id, p_cycle_id, p_reviewer_account_id, p_contribution_type,
    p_severity, p_breadth, p_confidence, p_urgency,
    p_notes, p_evidence_uri, 'provisional'
  )
  on conflict (submission_id, cycle_id, reviewer_account_id) do update
    set contribution_type = excluded.contribution_type,
        severity_score = excluded.severity_score,
        breadth_score = excluded.breadth_score,
        confidence_score = excluded.confidence_score,
        urgency_score = excluded.urgency_score,
        notes = excluded.notes,
        evidence_uri = excluded.evidence_uri,
        status = 'provisional',
        updated_at = now()
  returning review_id into v_review_id;

  update l5_contributor_submissions
  set state = 'pending_settlement', updated_at = now()
  where submission_id = p_submission_id;

  return jsonb_build_object('ok', true, 'review_id', v_review_id);
end;
$$;


--
-- Name: l5_record_oracle_verdict(uuid, bigint, text, numeric, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_record_oracle_verdict(p_submission_id uuid, p_cycle_id bigint, p_verdict text, p_measured_score numeric, p_confidence numeric, p_manifest_hash text, p_notes text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_eval_id uuid;
  v_exists int;
begin
  if p_verdict not in ('positive_delta','flat_delta','negative_delta','inconclusive') then
    return jsonb_build_object('ok', false, 'reason', 'invalid_verdict');
  end if;

  select count(*) into v_exists
  from l5_contributor_submissions
  where submission_id = p_submission_id;

  if v_exists = 0 then
    return jsonb_build_object('ok', false, 'reason', 'submission_not_found');
  end if;

  insert into l5_oracle_evaluations (
    submission_id, cycle_id, verdict, measured_score, confidence, manifest_hash, status, notes
  ) values (
    p_submission_id, p_cycle_id, p_verdict, p_measured_score, coalesce(p_confidence,0), p_manifest_hash, 'final', p_notes
  )
  on conflict (submission_id, cycle_id, manifest_hash) do update
    set verdict = excluded.verdict,
        measured_score = excluded.measured_score,
        confidence = excluded.confidence,
        status = excluded.status,
        notes = excluded.notes
  returning evaluation_id into v_eval_id;

  update l5_contributor_submissions
  set verdict = p_verdict,
      measured_score = p_measured_score,
      state = case when p_verdict='inconclusive' then 'testing' else 'pending_settlement' end,
      updated_at = now()
  where submission_id = p_submission_id;

  return jsonb_build_object('ok', true, 'evaluation_id', v_eval_id, 'verdict', p_verdict);
end;
$$;


--
-- Name: l5_resolve_appeal(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_resolve_appeal(p_appeal_id uuid, p_state text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_exists int;
begin
  if p_state not in ('accepted','rejected','resolved') then
    return jsonb_build_object('ok', false, 'reason', 'invalid_state');
  end if;

  select count(*) into v_exists from l5_appeals where appeal_id = p_appeal_id;
  if v_exists = 0 then
    return jsonb_build_object('ok', false, 'reason', 'appeal_not_found');
  end if;

  update l5_appeals
  set state = p_state,
      resolved_at = now()
  where appeal_id = p_appeal_id;

  return jsonb_build_object('ok', true, 'state', p_state);
end;
$$;


--
-- Name: l5_run_cycle(bigint, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_run_cycle(p_cycle_id bigint, p_pool_open numeric DEFAULT 1000) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
    'ok', true, 'cycle_id', p_cycle_id,
    'fast_burns', v_fast, 'oracle_settlements', v_oracle,
    'nondelta_settlements', v_nondelta, 'reconcile', v_close
  );
end;
$$;


--
-- Name: l5_set_nondelta_band_value(uuid, text, numeric, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_set_nondelta_band_value(p_actor_account_id uuid, p_band text, p_value numeric, p_reason text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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


--
-- Name: l5_set_param(uuid, text, numeric, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_set_param(p_actor_account_id uuid, p_key text, p_value numeric, p_reason text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_old numeric;
begin
  if p_reason is null or length(trim(p_reason)) < 5 then
    return jsonb_build_object('ok', false, 'reason', 'reason_required');
  end if;

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


--
-- Name: l5_settle_contributor(bigint, uuid, text, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_settle_contributor(p_cycle_id bigint, p_submission_id uuid, p_verdict text, p_measured_score numeric, p_idempotency_prefix text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_account_id uuid;
  v_stake numeric;
  v_flat_fee numeric := 0.25;
  v_burn_pct numeric := 0.02;
  v_reward numeric := 0;
  v_burn numeric := 0;
  v_refund numeric := 0;
  v_state text;
begin
  select account_id, stake_amount, state
  into v_account_id, v_stake, v_state
  from l5_contributor_submissions
  where submission_id = p_submission_id
  for update;

  if v_account_id is null then
    return jsonb_build_object('ok', false, 'reason', 'submission_not_found');
  end if;

  if v_state = 'settled' then
    return jsonb_build_object('ok', true, 'reason', 'already_settled');
  end if;

  if p_verdict = 'positive_delta' then
    v_reward := greatest(coalesce(p_measured_score,0),0);
    v_burn := round(v_reward * v_burn_pct, 6);
    v_refund := v_stake;

    insert into l5_credit_ledger (
      cycle_id, event_type, source_account_id, target_account_id, amount, bucket,
      reference_type, reference_id, idempotency_key, metadata
    ) values
    (
      p_cycle_id, 'contributor_payout', null, v_account_id, v_reward, 'incentive_pool',
      'submission', p_submission_id::text, p_idempotency_prefix || '-payout',
      jsonb_build_object('verdict', p_verdict, 'measured_score', p_measured_score)
    ),
    (
      p_cycle_id, 'payout_burn', v_account_id, null, v_burn, 'burn_sink',
      'submission', p_submission_id::text, p_idempotency_prefix || '-burn',
      jsonb_build_object('verdict', p_verdict)
    ),
    (
      p_cycle_id, 'stake_refund', null, v_account_id, v_refund, 'account',
      'submission', p_submission_id::text, p_idempotency_prefix || '-refund',
      jsonb_build_object('verdict', p_verdict)
    );

    update l5_contributor_submissions
    set verdict = p_verdict,
        measured_score = p_measured_score,
        state = 'final_positive',
        updated_at = now()
    where submission_id = p_submission_id;

  elsif p_verdict = 'flat_delta' then
    v_refund := greatest(v_stake - v_flat_fee, 0);

    insert into l5_credit_ledger (
      cycle_id, event_type, source_account_id, target_account_id, amount, bucket,
      reference_type, reference_id, idempotency_key, metadata
    ) values
    (
      p_cycle_id, 'flat_fee_inflow', v_account_id, null, v_flat_fee, 'incentive_pool',
      'submission', p_submission_id::text, p_idempotency_prefix || '-flatfee',
      jsonb_build_object('verdict', p_verdict)
    ),
    (
      p_cycle_id, 'stake_refund', null, v_account_id, v_refund, 'account',
      'submission', p_submission_id::text, p_idempotency_prefix || '-refund',
      jsonb_build_object('verdict', p_verdict)
    );

    update l5_contributor_submissions
    set verdict = p_verdict,
        measured_score = p_measured_score,
        state = 'final_flat',
        updated_at = now()
    where submission_id = p_submission_id;

  elsif p_verdict = 'negative_delta' then
    insert into l5_credit_ledger (
      cycle_id, event_type, source_account_id, target_account_id, amount, bucket,
      reference_type, reference_id, idempotency_key, metadata
    ) values (
      p_cycle_id, 'slash_inflow', v_account_id, null, v_stake, 'incentive_pool',
      'submission', p_submission_id::text, p_idempotency_prefix || '-slash',
      jsonb_build_object('verdict', p_verdict)
    );

    update l5_contributor_submissions
    set verdict = p_verdict,
        measured_score = p_measured_score,
        state = 'final_negative',
        updated_at = now()
    where submission_id = p_submission_id;

  else
    return jsonb_build_object('ok', false, 'reason', 'unsupported_verdict');
  end if;

  insert into l5_contributor_settlements (
    submission_id, cycle_id, stake_refund, payout_gross, payout_burn, slash_amount, flat_fee, status
  ) values (
    p_submission_id, p_cycle_id, v_refund, v_reward, v_burn,
    case when p_verdict = 'negative_delta' then v_stake else 0 end,
    case when p_verdict = 'flat_delta' then v_flat_fee else 0 end,
    'finalized'
  );

  update l5_contributor_submissions
  set state = 'settled', updated_at = now()
  where submission_id = p_submission_id;

  return jsonb_build_object(
    'ok', true, 'verdict', p_verdict, 'reward', v_reward, 'burn', v_burn, 'refund', v_refund
  );
end;
$$;


--
-- Name: l5_settle_contributor_guarded(bigint, uuid, text, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_settle_contributor_guarded(p_cycle_id bigint, p_submission_id uuid, p_verdict text, p_measured_score numeric, p_idempotency_prefix text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_deadline timestamptz;
  v_open_appeals int;
  v_now timestamptz := now();
begin
  select appeal_deadline into v_deadline
  from l5_contributor_submissions
  where submission_id = p_submission_id;

  if v_deadline is not null and v_now < v_deadline then
    return jsonb_build_object('ok', false, 'reason', 'appeal_window_open', 'appeal_deadline', v_deadline);
  end if;

  select count(*) into v_open_appeals
  from l5_appeals
  where submission_id = p_submission_id
    and state = 'open';

  if v_open_appeals > 0 then
    return jsonb_build_object('ok', false, 'reason', 'open_appeals_exist');
  end if;

  return l5_settle_contributor(
    p_cycle_id, p_submission_id, p_verdict, p_measured_score, p_idempotency_prefix
  );
end;
$$;


--
-- Name: l5_settle_from_oracle_guarded(bigint, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_settle_from_oracle_guarded(p_cycle_id bigint, p_submission_id uuid, p_idempotency_prefix text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_verdict text;
  v_score numeric;
begin
  select verdict, measured_score
  into v_verdict, v_score
  from l5_oracle_evaluations
  where submission_id = p_submission_id
    and cycle_id = p_cycle_id
    and status = 'final'
  order by created_at desc
  limit 1;

  if v_verdict is null then
    return jsonb_build_object('ok', false, 'reason', 'oracle_verdict_not_found');
  end if;

  if v_verdict = 'inconclusive' then
    return jsonb_build_object('ok', false, 'reason', 'oracle_inconclusive');
  end if;

  return l5_settle_contributor_guarded(
    p_cycle_id, p_submission_id, v_verdict, coalesce(v_score,0), p_idempotency_prefix
  );
end;
$$;


--
-- Name: l5_settle_nondelta_from_review(bigint, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_settle_nondelta_from_review(p_cycle_id bigint, p_submission_id uuid, p_idempotency_prefix text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_account_id uuid;
  v_band text;
  v_payout numeric;
  v_review_id uuid;
  v_open_appeals int;
begin
  select account_id into v_account_id
  from l5_contributor_submissions
  where submission_id = p_submission_id;

  if v_account_id is null then
    return jsonb_build_object('ok', false, 'reason', 'submission_not_found');
  end if;

  select review_id, payout_band into v_review_id, v_band
  from l5_nondelta_reviews
  where submission_id = p_submission_id
    and cycle_id = p_cycle_id
  order by created_at desc
  limit 1;

  if v_review_id is null then
    return jsonb_build_object('ok', false, 'reason', 'review_not_found');
  end if;

  select count(*) into v_open_appeals
  from l5_appeals
  where submission_id = p_submission_id and state = 'open';

  if v_open_appeals > 0 then
    return jsonb_build_object('ok', false, 'reason', 'open_appeals_exist');
  end if;

  select payout_credits into v_payout
  from l5_nondelta_band_values
  where band = v_band;

  if v_payout is null then
    return jsonb_build_object('ok', false, 'reason', 'band_value_missing');
  end if;

  insert into l5_credit_ledger (
    cycle_id, event_type, source_account_id, target_account_id, amount, bucket,
    reference_type, reference_id, idempotency_key, metadata
  ) values (
    p_cycle_id, 'contributor_nondelta_payout', null, v_account_id, v_payout, 'incentive_pool',
    'nondelta_review', v_review_id::text, p_idempotency_prefix || '-nondelta-payout',
    jsonb_build_object('review_id', v_review_id, 'band', v_band)
  );

  update l5_nondelta_reviews
  set status = 'finalized', updated_at = now()
  where review_id = v_review_id;

  update l5_contributor_submissions
  set state = 'settled', updated_at = now()
  where submission_id = p_submission_id;

  return jsonb_build_object('ok', true, 'review_id', v_review_id, 'band', v_band, 'payout', v_payout);
end;
$$;


--
-- Name: l5_settle_nondelta_ready_reviews(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_settle_nondelta_ready_reviews(p_cycle_id bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
      p_cycle_id, r.submission_id,
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
    'ok', true, 'settled', v_settled, 'blocked', v_blocked, 'failed', v_failed
  );
end;
$$;


--
-- Name: l5_settle_oracle_ready_submissions(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.l5_settle_oracle_ready_submissions(p_cycle_id bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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
      p_cycle_id, r.submission_id,
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
    'ok', true, 'settled', v_settled, 'blocked', v_blocked, 'failed', v_failed
  );
end;
$$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: l5_account_controls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_account_controls (
    account_id uuid NOT NULL,
    control_mode text DEFAULT 'normal'::text NOT NULL,
    reason text,
    updated_by_account_id uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: l5_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_accounts (
    account_id uuid DEFAULT gen_random_uuid() NOT NULL,
    role text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    username text,
    password_hash text,
    CONSTRAINT l5_accounts_role_check CHECK ((role = ANY (ARRAY['consumer'::text, 'validator'::text, 'contributor'::text, 'mixed'::text]))),
    CONSTRAINT l5_accounts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'review'::text])))
);


--
-- Name: l5_admin_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_admin_actions (
    action_id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_account_id uuid,
    action_type text NOT NULL,
    target_key text NOT NULL,
    old_value_numeric numeric(18,8),
    new_value_numeric numeric(18,8),
    reason text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT l5_admin_actions_action_type_check CHECK ((action_type = ANY (ARRAY['set_param'::text, 'set_band_value'::text])))
);


--
-- Name: l5_appeals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_appeals (
    appeal_id uuid DEFAULT gen_random_uuid() NOT NULL,
    submission_id uuid NOT NULL,
    opened_by_account_id uuid NOT NULL,
    reason text NOT NULL,
    evidence_uri text,
    fee_amount numeric(18,6) DEFAULT 0 NOT NULL,
    state text NOT NULL,
    opened_at timestamp with time zone DEFAULT now() NOT NULL,
    deadline_at timestamp with time zone NOT NULL,
    resolved_at timestamp with time zone,
    CONSTRAINT l5_appeals_state_check CHECK ((state = ANY (ARRAY['open'::text, 'accepted'::text, 'rejected'::text, 'resolved'::text])))
);


--
-- Name: l5_auth_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_auth_sessions (
    session_token text NOT NULL,
    account_id uuid NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    last_seen_at timestamp with time zone
);


--
-- Name: l5_contribution_votes_v31; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_contribution_votes_v31 (
    vote_id uuid DEFAULT gen_random_uuid() NOT NULL,
    cycle_id integer NOT NULL,
    voter_account_id uuid NOT NULL,
    submission_id uuid NOT NULL,
    points numeric(10,4) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: l5_contributor_settlements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_contributor_settlements (
    settlement_id uuid DEFAULT gen_random_uuid() NOT NULL,
    submission_id uuid NOT NULL,
    cycle_id bigint NOT NULL,
    stake_refund numeric(18,6) DEFAULT 0 NOT NULL,
    payout_gross numeric(18,6) DEFAULT 0 NOT NULL,
    payout_burn numeric(18,6) DEFAULT 0 NOT NULL,
    slash_amount numeric(18,6) DEFAULT 0 NOT NULL,
    flat_fee numeric(18,6) DEFAULT 0 NOT NULL,
    status text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT l5_contributor_settlements_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'finalized'::text, 'superseded'::text])))
);


--
-- Name: l5_contributor_submissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_contributor_submissions (
    submission_id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    submission_hash text NOT NULL,
    title text NOT NULL,
    class text NOT NULL,
    stake_amount numeric(18,6) DEFAULT 5 NOT NULL,
    state text NOT NULL,
    measured_score numeric(18,8),
    verdict text,
    appeal_deadline timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    description text,
    CONSTRAINT l5_contributor_submissions_class_check CHECK ((class = ANY (ARRAY['preset'::text, 'benchmark'::text, 'driver'::text, 'kernel'::text, 'security'::text, 'other'::text]))),
    CONSTRAINT l5_contributor_submissions_state_check CHECK ((state = ANY (ARRAY['proposed'::text, 'stake_locked'::text, 'testing'::text, 'pending_settlement'::text, 'final_positive'::text, 'final_flat'::text, 'final_negative'::text, 'settled'::text]))),
    CONSTRAINT l5_contributor_submissions_verdict_check CHECK ((verdict = ANY (ARRAY['positive_delta'::text, 'flat_delta'::text, 'negative_delta'::text, 'inconclusive'::text])))
);


--
-- Name: l5_credit_ledger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_credit_ledger (
    event_id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_time timestamp with time zone DEFAULT now() NOT NULL,
    cycle_id bigint NOT NULL,
    event_type text NOT NULL,
    source_account_id uuid,
    target_account_id uuid,
    amount numeric(18,6) NOT NULL,
    bucket text NOT NULL,
    reference_type text,
    reference_id text,
    idempotency_key text NOT NULL,
    formula_version text DEFAULT 'l5-econ-v1'::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT l5_credit_ledger_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT l5_credit_ledger_bucket_check CHECK ((bucket = ANY (ARRAY['incentive_pool'::text, 'ops_reserve'::text, 'burn_sink'::text, 'account'::text])))
);


--
-- Name: l5_governance_votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_governance_votes (
    vote_id uuid DEFAULT gen_random_uuid() NOT NULL,
    appeal_id uuid,
    voter_account_id uuid NOT NULL,
    vote text NOT NULL,
    weight numeric(18,6) DEFAULT 1 NOT NULL,
    voted_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT l5_governance_votes_vote_check CHECK ((vote = ANY (ARRAY['yes'::text, 'no'::text, 'abstain'::text])))
);


--
-- Name: l5_hub_action_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_hub_action_log (
    log_id bigint NOT NULL,
    action text NOT NULL,
    actor_account_id uuid,
    route text NOT NULL,
    method text NOT NULL,
    status text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: l5_hub_action_log_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.l5_hub_action_log_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: l5_hub_action_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.l5_hub_action_log_log_id_seq OWNED BY public.l5_hub_action_log.log_id;


--
-- Name: l5_hub_anomaly_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_hub_anomaly_events (
    anomaly_id bigint NOT NULL,
    account_id uuid,
    signal_type text NOT NULL,
    severity text DEFAULT 'medium'::text NOT NULL,
    route text,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone
);


--
-- Name: l5_hub_anomaly_events_anomaly_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.l5_hub_anomaly_events_anomaly_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: l5_hub_anomaly_events_anomaly_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.l5_hub_anomaly_events_anomaly_id_seq OWNED BY public.l5_hub_anomaly_events.anomaly_id;


--
-- Name: l5_hub_network_lockouts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_hub_network_lockouts (
    lockout_key text NOT NULL,
    lockout_until timestamp with time zone NOT NULL,
    reason text NOT NULL,
    strike_count integer DEFAULT 0 NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: l5_lifetime_votes_v31; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_lifetime_votes_v31 (
    account_id uuid NOT NULL,
    lifetime_votes numeric(18,4) DEFAULT 0 NOT NULL,
    total_payout_btc numeric(18,8) DEFAULT 0 NOT NULL,
    total_royalty_btc numeric(18,8) DEFAULT 0 NOT NULL,
    cooldown_remaining integer DEFAULT 0 NOT NULL,
    consecutive_low_vote_cycles integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: l5_machine_entitlements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_machine_entitlements (
    machine_id text NOT NULL,
    account_id uuid NOT NULL,
    plan text DEFAULT 'stable'::text NOT NULL,
    fast_cycle_fee numeric(18,6) DEFAULT 5 NOT NULL,
    plan_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_burn_cycle_id bigint,
    CONSTRAINT l5_machine_entitlements_plan_check CHECK ((plan = ANY (ARRAY['stable'::text, 'fast'::text])))
);


--
-- Name: l5_nondelta_band_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_nondelta_band_values (
    band text NOT NULL,
    payout_credits numeric(18,6) NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT l5_nondelta_band_values_band_check CHECK ((band = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))),
    CONSTRAINT l5_nondelta_band_values_payout_credits_check CHECK ((payout_credits >= (0)::numeric))
);


--
-- Name: l5_nondelta_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_nondelta_reviews (
    review_id uuid DEFAULT gen_random_uuid() NOT NULL,
    submission_id uuid NOT NULL,
    cycle_id bigint NOT NULL,
    reviewer_account_id uuid NOT NULL,
    contribution_type text NOT NULL,
    severity_score integer NOT NULL,
    breadth_score integer NOT NULL,
    confidence_score integer NOT NULL,
    urgency_score integer NOT NULL,
    total_score integer GENERATED ALWAYS AS ((((severity_score + breadth_score) + confidence_score) + urgency_score)) STORED,
    payout_band text GENERATED ALWAYS AS (
CASE
    WHEN ((((severity_score + breadth_score) + confidence_score) + urgency_score) >= 17) THEN 'critical'::text
    WHEN ((((severity_score + breadth_score) + confidence_score) + urgency_score) >= 13) THEN 'high'::text
    WHEN ((((severity_score + breadth_score) + confidence_score) + urgency_score) >= 7) THEN 'medium'::text
    ELSE 'low'::text
END) STORED,
    notes text,
    evidence_uri text,
    status text DEFAULT 'provisional'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT l5_nondelta_reviews_breadth_score_check CHECK (((breadth_score >= 0) AND (breadth_score <= 5))),
    CONSTRAINT l5_nondelta_reviews_confidence_score_check CHECK (((confidence_score >= 0) AND (confidence_score <= 5))),
    CONSTRAINT l5_nondelta_reviews_contribution_type_check CHECK ((contribution_type = ANY (ARRAY['security'::text, 'driver'::text, 'reliability'::text, 'maintenance'::text]))),
    CONSTRAINT l5_nondelta_reviews_severity_score_check CHECK (((severity_score >= 0) AND (severity_score <= 5))),
    CONSTRAINT l5_nondelta_reviews_status_check CHECK ((status = ANY (ARRAY['provisional'::text, 'challenged'::text, 'finalized'::text]))),
    CONSTRAINT l5_nondelta_reviews_urgency_score_check CHECK (((urgency_score >= 0) AND (urgency_score <= 5)))
);


--
-- Name: l5_oracle_evaluations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_oracle_evaluations (
    evaluation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    submission_id uuid NOT NULL,
    cycle_id bigint NOT NULL,
    verdict text NOT NULL,
    measured_score numeric(18,8),
    confidence numeric(6,5) DEFAULT 0 NOT NULL,
    manifest_hash text NOT NULL,
    status text DEFAULT 'final'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT l5_oracle_evaluations_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'final'::text, 'superseded'::text]))),
    CONSTRAINT l5_oracle_evaluations_verdict_check CHECK ((verdict = ANY (ARRAY['positive_delta'::text, 'flat_delta'::text, 'negative_delta'::text, 'inconclusive'::text])))
);


--
-- Name: l5_params; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_params (
    key text NOT NULL,
    value_numeric numeric(18,8),
    value_text text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: l5_pool_cycles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_pool_cycles (
    cycle_id bigint NOT NULL,
    cycle_started_at timestamp with time zone NOT NULL,
    cycle_closed_at timestamp with time zone,
    pool_open numeric(18,6) NOT NULL,
    inflow_total numeric(18,6) DEFAULT 0 NOT NULL,
    outflow_total numeric(18,6) DEFAULT 0 NOT NULL,
    burn_total numeric(18,6) DEFAULT 0 NOT NULL,
    pool_close numeric(18,6),
    reconciliation_drift numeric(18,6) DEFAULT 0 NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    CONSTRAINT l5_pool_cycles_status_check CHECK ((status = ANY (ARRAY['open'::text, 'settling'::text, 'closed'::text, 'failed'::text])))
);


--
-- Name: l5_pool_state_v31; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_pool_state_v31 (
    id integer NOT NULL,
    cycle_id integer NOT NULL,
    fast_user_count integer DEFAULT 0 NOT NULL,
    fast_revenue_usd numeric(18,8) DEFAULT 0 NOT NULL,
    fast_revenue_btc numeric(18,8) DEFAULT 0 NOT NULL,
    btc_price_usd numeric(12,2) DEFAULT 85000 NOT NULL,
    payout_pot_btc numeric(18,8) DEFAULT 0 NOT NULL,
    pool_inflow_btc numeric(18,8) DEFAULT 0 NOT NULL,
    pool_principal_btc numeric(18,8) DEFAULT 0 NOT NULL,
    cycle_yield_btc numeric(18,8) DEFAULT 0 NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone
);


--
-- Name: l5_pool_state_v31_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.l5_pool_state_v31_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: l5_pool_state_v31_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.l5_pool_state_v31_id_seq OWNED BY public.l5_pool_state_v31.id;


--
-- Name: l5_validator_cycles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_validator_cycles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cycle_id bigint NOT NULL,
    account_id uuid NOT NULL,
    machine_id text NOT NULL,
    streak_count integer DEFAULT 0 NOT NULL,
    multiplier_continuity numeric(18,8) NOT NULL,
    multiplier_rarity numeric(18,8) NOT NULL,
    multiplier_quality numeric(18,8) NOT NULL,
    reward_gross numeric(18,6) NOT NULL,
    reward_net numeric(18,6) NOT NULL,
    payout_status text NOT NULL,
    hold_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT l5_validator_cycles_payout_status_check CHECK ((payout_status = ANY (ARRAY['eligible'::text, 'held'::text, 'paid'::text, 'prorated_paid'::text, 'rejected'::text])))
);


--
-- Name: l5_wallet_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l5_wallet_identities (
    account_id uuid NOT NULL,
    wallet_address text NOT NULL,
    chain_id text DEFAULT 'evm:1'::text NOT NULL,
    verification_status text DEFAULT 'unverified'::text NOT NULL,
    verification_method text,
    verification_nonce text,
    signature text,
    bound_at timestamp with time zone DEFAULT now() NOT NULL,
    verified_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: machine_aliases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.machine_aliases (
    alias text NOT NULL,
    machine_id text NOT NULL,
    alias_kind text DEFAULT 'legacy_fingerprint_v1'::text NOT NULL,
    source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: machines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.machines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    machine_id text NOT NULL,
    label text,
    cpu text,
    cpu_cores_logical integer,
    gpu text,
    gpu_vram_gb integer,
    ram_gb integer,
    os text,
    kernel text,
    created_at timestamp with time zone DEFAULT now(),
    gpu_vendor text,
    fingerprint_version integer
);


--
-- Name: run_detail_bundles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.run_detail_bundles (
    id bigint NOT NULL,
    source_hash text NOT NULL,
    machine_id text NOT NULL,
    run_date date,
    preset_version text,
    wrapper_version text,
    structured_telemetry jsonb DEFAULT '{}'::jsonb NOT NULL,
    measurement_quality jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_summary jsonb DEFAULT '{}'::jsonb NOT NULL,
    source text DEFAULT 'seed_organism.py'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: run_detail_bundles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.run_detail_bundles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: run_detail_bundles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.run_detail_bundles_id_seq OWNED BY public.run_detail_bundles.id;


--
-- Name: runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    machine_id text,
    run_date date,
    preset_version text,
    wrapper_version text,
    network_baseline_mbit double precision,
    network_tuned_mbit double precision,
    network_delta_pct double precision,
    coldstart_baseline_ms double precision,
    coldstart_tuned_ms double precision,
    coldstart_delta_pct double precision,
    sustained_baseline_toks double precision,
    sustained_tuned_toks double precision,
    sustained_delta_pct double precision,
    power_idle_baseline_w double precision,
    power_idle_tuned_w double precision,
    power_delta_w double precision,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    cpu_microcode_version text,
    cpu_l1_cache_kb numeric,
    cpu_l2_cache_kb numeric,
    cpu_l3_cache_kb numeric,
    gpu_vram_mb numeric,
    gpu_driver_version text,
    ram_speed_mhz numeric,
    ram_channel_config text,
    dmesg_errors_baseline integer,
    dmesg_errors_tuned integer,
    cpu_throttle_events_baseline integer,
    cpu_throttle_events_tuned integer,
    gpu_throttle_events_baseline integer,
    gpu_throttle_events_tuned integer,
    temp_throttle_count_baseline integer,
    temp_throttle_count_tuned integer
);


--
-- Name: seed_bundles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seed_bundles (
    id bigint NOT NULL,
    bundle_hash text NOT NULL,
    variant_id text NOT NULL,
    cycle_id text,
    decision text NOT NULL,
    reason text,
    machine_id text,
    contributor_id text,
    commit_ref text,
    fitness_score double precision,
    confidence double precision,
    sensor_result_hash text,
    regression_result_hash text,
    result_bundle jsonb NOT NULL,
    source text DEFAULT 'seed_organism.py'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: seed_bundles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seed_bundles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seed_bundles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seed_bundles_id_seq OWNED BY public.seed_bundles.id;


--
-- Name: seed_payout_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seed_payout_reports (
    id bigint NOT NULL,
    payout_report_hash text NOT NULL,
    cycle_id text NOT NULL,
    simulated_revenue_sats bigint,
    contributor_count integer,
    report jsonb NOT NULL,
    source text DEFAULT 'seed_organism.py'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: seed_payout_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seed_payout_reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seed_payout_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seed_payout_reports_id_seq OWNED BY public.seed_payout_reports.id;


--
-- Name: v_l5_account_balances; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_l5_account_balances WITH (security_invoker='true') AS
 WITH inbound AS (
         SELECT l5_credit_ledger.target_account_id AS account_id,
            sum(l5_credit_ledger.amount) AS amt
           FROM public.l5_credit_ledger
          WHERE ((l5_credit_ledger.target_account_id IS NOT NULL) AND (l5_credit_ledger.bucket = 'account'::text))
          GROUP BY l5_credit_ledger.target_account_id
        ), outbound AS (
         SELECT l5_credit_ledger.source_account_id AS account_id,
            sum(l5_credit_ledger.amount) AS amt
           FROM public.l5_credit_ledger
          WHERE ((l5_credit_ledger.source_account_id IS NOT NULL) AND (l5_credit_ledger.bucket = 'account'::text))
          GROUP BY l5_credit_ledger.source_account_id
        )
 SELECT a.account_id,
    (COALESCE(i.amt, (0)::numeric) - COALESCE(o.amt, (0)::numeric)) AS balance
   FROM ((public.l5_accounts a
     LEFT JOIN inbound i ON ((i.account_id = a.account_id)))
     LEFT JOIN outbound o ON ((o.account_id = a.account_id)));


--
-- Name: v_l5_cycle_reconciliation; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_l5_cycle_reconciliation WITH (security_invoker='true') AS
 SELECT cycle_id,
    pool_open,
    inflow_total,
    outflow_total,
    burn_total,
    pool_close,
    (((pool_open + inflow_total) - outflow_total) - burn_total) AS expected_close,
    reconciliation_drift,
    status
   FROM public.l5_pool_cycles c;


--
-- Name: v_l5_pool_balance; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_l5_pool_balance WITH (security_invoker='true') AS
 SELECT (COALESCE(sum(
        CASE
            WHEN ((bucket = 'incentive_pool'::text) AND (event_type = ANY (ARRAY['fast_burn_inflow'::text, 'flat_fee_inflow'::text, 'slash_inflow'::text, 'seed_topup'::text]))) THEN amount
            ELSE (0)::numeric
        END), (0)::numeric) - COALESCE(sum(
        CASE
            WHEN ((bucket = 'incentive_pool'::text) AND (event_type = ANY (ARRAY['validator_payout'::text, 'contributor_payout'::text]))) THEN amount
            ELSE (0)::numeric
        END), (0)::numeric)) AS incentive_pool_balance,
    COALESCE(sum(
        CASE
            WHEN (bucket = 'burn_sink'::text) THEN amount
            ELSE (0)::numeric
        END), (0)::numeric) AS burn_sink_total
   FROM public.l5_credit_ledger;


--
-- Name: l5_hub_action_log log_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_hub_action_log ALTER COLUMN log_id SET DEFAULT nextval('public.l5_hub_action_log_log_id_seq'::regclass);


--
-- Name: l5_hub_anomaly_events anomaly_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_hub_anomaly_events ALTER COLUMN anomaly_id SET DEFAULT nextval('public.l5_hub_anomaly_events_anomaly_id_seq'::regclass);


--
-- Name: l5_pool_state_v31 id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_pool_state_v31 ALTER COLUMN id SET DEFAULT nextval('public.l5_pool_state_v31_id_seq'::regclass);


--
-- Name: run_detail_bundles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.run_detail_bundles ALTER COLUMN id SET DEFAULT nextval('public.run_detail_bundles_id_seq'::regclass);


--
-- Name: seed_bundles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seed_bundles ALTER COLUMN id SET DEFAULT nextval('public.seed_bundles_id_seq'::regclass);


--
-- Name: seed_payout_reports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seed_payout_reports ALTER COLUMN id SET DEFAULT nextval('public.seed_payout_reports_id_seq'::regclass);


--
-- Name: l5_account_controls l5_account_controls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_account_controls
    ADD CONSTRAINT l5_account_controls_pkey PRIMARY KEY (account_id);


--
-- Name: l5_accounts l5_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_accounts
    ADD CONSTRAINT l5_accounts_pkey PRIMARY KEY (account_id);


--
-- Name: l5_admin_actions l5_admin_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_admin_actions
    ADD CONSTRAINT l5_admin_actions_pkey PRIMARY KEY (action_id);


--
-- Name: l5_appeals l5_appeals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_appeals
    ADD CONSTRAINT l5_appeals_pkey PRIMARY KEY (appeal_id);


--
-- Name: l5_auth_sessions l5_auth_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_auth_sessions
    ADD CONSTRAINT l5_auth_sessions_pkey PRIMARY KEY (session_token);


--
-- Name: l5_contribution_votes_v31 l5_contribution_votes_v31_cycle_id_voter_account_id_submiss_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_contribution_votes_v31
    ADD CONSTRAINT l5_contribution_votes_v31_cycle_id_voter_account_id_submiss_key UNIQUE (cycle_id, voter_account_id, submission_id);


--
-- Name: l5_contribution_votes_v31 l5_contribution_votes_v31_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_contribution_votes_v31
    ADD CONSTRAINT l5_contribution_votes_v31_pkey PRIMARY KEY (vote_id);


--
-- Name: l5_contributor_settlements l5_contributor_settlements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_contributor_settlements
    ADD CONSTRAINT l5_contributor_settlements_pkey PRIMARY KEY (settlement_id);


--
-- Name: l5_contributor_submissions l5_contributor_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_contributor_submissions
    ADD CONSTRAINT l5_contributor_submissions_pkey PRIMARY KEY (submission_id);


--
-- Name: l5_contributor_submissions l5_contributor_submissions_submission_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_contributor_submissions
    ADD CONSTRAINT l5_contributor_submissions_submission_hash_key UNIQUE (submission_hash);


--
-- Name: l5_credit_ledger l5_credit_ledger_idempotency_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_credit_ledger
    ADD CONSTRAINT l5_credit_ledger_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: l5_credit_ledger l5_credit_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_credit_ledger
    ADD CONSTRAINT l5_credit_ledger_pkey PRIMARY KEY (event_id);


--
-- Name: l5_governance_votes l5_governance_votes_appeal_id_voter_account_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_governance_votes
    ADD CONSTRAINT l5_governance_votes_appeal_id_voter_account_id_key UNIQUE (appeal_id, voter_account_id);


--
-- Name: l5_governance_votes l5_governance_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_governance_votes
    ADD CONSTRAINT l5_governance_votes_pkey PRIMARY KEY (vote_id);


--
-- Name: l5_hub_action_log l5_hub_action_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_hub_action_log
    ADD CONSTRAINT l5_hub_action_log_pkey PRIMARY KEY (log_id);


--
-- Name: l5_hub_anomaly_events l5_hub_anomaly_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_hub_anomaly_events
    ADD CONSTRAINT l5_hub_anomaly_events_pkey PRIMARY KEY (anomaly_id);


--
-- Name: l5_hub_network_lockouts l5_hub_network_lockouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_hub_network_lockouts
    ADD CONSTRAINT l5_hub_network_lockouts_pkey PRIMARY KEY (lockout_key);


--
-- Name: l5_lifetime_votes_v31 l5_lifetime_votes_v31_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_lifetime_votes_v31
    ADD CONSTRAINT l5_lifetime_votes_v31_pkey PRIMARY KEY (account_id);


--
-- Name: l5_machine_entitlements l5_machine_entitlements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_machine_entitlements
    ADD CONSTRAINT l5_machine_entitlements_pkey PRIMARY KEY (machine_id);


--
-- Name: l5_nondelta_band_values l5_nondelta_band_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_nondelta_band_values
    ADD CONSTRAINT l5_nondelta_band_values_pkey PRIMARY KEY (band);


--
-- Name: l5_nondelta_reviews l5_nondelta_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_nondelta_reviews
    ADD CONSTRAINT l5_nondelta_reviews_pkey PRIMARY KEY (review_id);


--
-- Name: l5_nondelta_reviews l5_nondelta_reviews_submission_id_cycle_id_reviewer_account_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_nondelta_reviews
    ADD CONSTRAINT l5_nondelta_reviews_submission_id_cycle_id_reviewer_account_key UNIQUE (submission_id, cycle_id, reviewer_account_id);


--
-- Name: l5_oracle_evaluations l5_oracle_evaluations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_oracle_evaluations
    ADD CONSTRAINT l5_oracle_evaluations_pkey PRIMARY KEY (evaluation_id);


--
-- Name: l5_oracle_evaluations l5_oracle_evaluations_submission_id_cycle_id_manifest_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_oracle_evaluations
    ADD CONSTRAINT l5_oracle_evaluations_submission_id_cycle_id_manifest_hash_key UNIQUE (submission_id, cycle_id, manifest_hash);


--
-- Name: l5_params l5_params_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_params
    ADD CONSTRAINT l5_params_pkey PRIMARY KEY (key);


--
-- Name: l5_pool_cycles l5_pool_cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_pool_cycles
    ADD CONSTRAINT l5_pool_cycles_pkey PRIMARY KEY (cycle_id);


--
-- Name: l5_pool_state_v31 l5_pool_state_v31_cycle_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_pool_state_v31
    ADD CONSTRAINT l5_pool_state_v31_cycle_id_key UNIQUE (cycle_id);


--
-- Name: l5_pool_state_v31 l5_pool_state_v31_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_pool_state_v31
    ADD CONSTRAINT l5_pool_state_v31_pkey PRIMARY KEY (id);


--
-- Name: l5_validator_cycles l5_validator_cycles_cycle_id_account_id_machine_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_validator_cycles
    ADD CONSTRAINT l5_validator_cycles_cycle_id_account_id_machine_id_key UNIQUE (cycle_id, account_id, machine_id);


--
-- Name: l5_validator_cycles l5_validator_cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_validator_cycles
    ADD CONSTRAINT l5_validator_cycles_pkey PRIMARY KEY (id);


--
-- Name: l5_wallet_identities l5_wallet_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_wallet_identities
    ADD CONSTRAINT l5_wallet_identities_pkey PRIMARY KEY (account_id);


--
-- Name: machine_aliases machine_aliases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.machine_aliases
    ADD CONSTRAINT machine_aliases_pkey PRIMARY KEY (alias);


--
-- Name: machines machines_machine_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.machines
    ADD CONSTRAINT machines_machine_id_key UNIQUE (machine_id);


--
-- Name: machines machines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.machines
    ADD CONSTRAINT machines_pkey PRIMARY KEY (id);


--
-- Name: run_detail_bundles run_detail_bundles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.run_detail_bundles
    ADD CONSTRAINT run_detail_bundles_pkey PRIMARY KEY (id);


--
-- Name: run_detail_bundles run_detail_bundles_source_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.run_detail_bundles
    ADD CONSTRAINT run_detail_bundles_source_hash_key UNIQUE (source_hash);


--
-- Name: runs runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runs
    ADD CONSTRAINT runs_pkey PRIMARY KEY (id);


--
-- Name: seed_bundles seed_bundles_bundle_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seed_bundles
    ADD CONSTRAINT seed_bundles_bundle_hash_key UNIQUE (bundle_hash);


--
-- Name: seed_bundles seed_bundles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seed_bundles
    ADD CONSTRAINT seed_bundles_pkey PRIMARY KEY (id);


--
-- Name: seed_payout_reports seed_payout_reports_payout_report_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seed_payout_reports
    ADD CONSTRAINT seed_payout_reports_payout_report_hash_key UNIQUE (payout_report_hash);


--
-- Name: seed_payout_reports seed_payout_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seed_payout_reports
    ADD CONSTRAINT seed_payout_reports_pkey PRIMARY KEY (id);


--
-- Name: idx_l5_accounts_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_accounts_role ON public.l5_accounts USING btree (role);


--
-- Name: idx_l5_admin_actions_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_admin_actions_key ON public.l5_admin_actions USING btree (target_key);


--
-- Name: idx_l5_admin_actions_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_admin_actions_time ON public.l5_admin_actions USING btree (created_at DESC);


--
-- Name: idx_l5_admin_actions_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_admin_actions_type ON public.l5_admin_actions USING btree (action_type);


--
-- Name: idx_l5_appeals_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_appeals_state ON public.l5_appeals USING btree (state);


--
-- Name: idx_l5_appeals_submission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_appeals_submission ON public.l5_appeals USING btree (submission_id);


--
-- Name: idx_l5_contrib_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_contrib_account ON public.l5_contributor_submissions USING btree (account_id);


--
-- Name: idx_l5_contrib_settle_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_contrib_settle_cycle ON public.l5_contributor_settlements USING btree (cycle_id);


--
-- Name: idx_l5_contrib_settle_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_contrib_settle_status ON public.l5_contributor_settlements USING btree (status);


--
-- Name: idx_l5_contrib_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_contrib_state ON public.l5_contributor_submissions USING btree (state);


--
-- Name: idx_l5_entitlements_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_entitlements_account ON public.l5_machine_entitlements USING btree (account_id);


--
-- Name: idx_l5_entitlements_plan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_entitlements_plan ON public.l5_machine_entitlements USING btree (plan);


--
-- Name: idx_l5_ledger_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_ledger_cycle ON public.l5_credit_ledger USING btree (cycle_id);


--
-- Name: idx_l5_ledger_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_ledger_source ON public.l5_credit_ledger USING btree (source_account_id);


--
-- Name: idx_l5_ledger_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_ledger_target ON public.l5_credit_ledger USING btree (target_account_id);


--
-- Name: idx_l5_ledger_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_ledger_type ON public.l5_credit_ledger USING btree (event_type);


--
-- Name: idx_l5_nondelta_reviews_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_nondelta_reviews_cycle ON public.l5_nondelta_reviews USING btree (cycle_id);


--
-- Name: idx_l5_nondelta_reviews_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_nondelta_reviews_status ON public.l5_nondelta_reviews USING btree (status);


--
-- Name: idx_l5_nondelta_reviews_submission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_nondelta_reviews_submission ON public.l5_nondelta_reviews USING btree (submission_id);


--
-- Name: idx_l5_oracle_eval_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_oracle_eval_cycle ON public.l5_oracle_evaluations USING btree (cycle_id);


--
-- Name: idx_l5_oracle_eval_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_oracle_eval_status ON public.l5_oracle_evaluations USING btree (status);


--
-- Name: idx_l5_oracle_eval_submission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_oracle_eval_submission ON public.l5_oracle_evaluations USING btree (submission_id);


--
-- Name: idx_l5_pool_cycles_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_pool_cycles_status ON public.l5_pool_cycles USING btree (status);


--
-- Name: idx_l5_validator_cycles_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_validator_cycles_cycle ON public.l5_validator_cycles USING btree (cycle_id);


--
-- Name: idx_l5_validator_cycles_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_l5_validator_cycles_status ON public.l5_validator_cycles USING btree (payout_status);


--
-- Name: l5_accounts_username_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX l5_accounts_username_lower_idx ON public.l5_accounts USING btree (lower(username)) WHERE (username IS NOT NULL);


--
-- Name: l5_auth_sessions_account_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX l5_auth_sessions_account_idx ON public.l5_auth_sessions USING btree (account_id);


--
-- Name: l5_auth_sessions_expires_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX l5_auth_sessions_expires_idx ON public.l5_auth_sessions USING btree (expires_at);


--
-- Name: l5_hub_action_log_actor_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX l5_hub_action_log_actor_idx ON public.l5_hub_action_log USING btree (actor_account_id, created_at DESC);


--
-- Name: l5_hub_anomaly_account_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX l5_hub_anomaly_account_idx ON public.l5_hub_anomaly_events USING btree (account_id, created_at DESC);


--
-- Name: l5_hub_network_lockouts_until_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX l5_hub_network_lockouts_until_idx ON public.l5_hub_network_lockouts USING btree (lockout_until);


--
-- Name: l5_wallet_identities_address_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX l5_wallet_identities_address_unique ON public.l5_wallet_identities USING btree (lower(wallet_address));


--
-- Name: machine_aliases_machine_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX machine_aliases_machine_idx ON public.machine_aliases USING btree (machine_id);


--
-- Name: run_detail_bundles_machine_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX run_detail_bundles_machine_idx ON public.run_detail_bundles USING btree (machine_id, created_at DESC);


--
-- Name: run_detail_bundles_preset_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX run_detail_bundles_preset_idx ON public.run_detail_bundles USING btree (preset_version, created_at DESC);


--
-- Name: run_detail_bundles_quality_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX run_detail_bundles_quality_gin_idx ON public.run_detail_bundles USING gin (measurement_quality);


--
-- Name: run_detail_bundles_telemetry_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX run_detail_bundles_telemetry_gin_idx ON public.run_detail_bundles USING gin (structured_telemetry);


--
-- Name: seed_bundles_bundle_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX seed_bundles_bundle_gin_idx ON public.seed_bundles USING gin (result_bundle);


--
-- Name: seed_bundles_decision_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX seed_bundles_decision_idx ON public.seed_bundles USING btree (decision, created_at DESC);


--
-- Name: seed_bundles_machine_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX seed_bundles_machine_idx ON public.seed_bundles USING btree (machine_id, created_at DESC);


--
-- Name: seed_bundles_variant_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX seed_bundles_variant_idx ON public.seed_bundles USING btree (variant_id, created_at DESC);


--
-- Name: seed_payout_reports_cycle_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX seed_payout_reports_cycle_idx ON public.seed_payout_reports USING btree (cycle_id, created_at DESC);


--
-- Name: seed_payout_reports_report_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX seed_payout_reports_report_gin_idx ON public.seed_payout_reports USING gin (report);


--
-- Name: l5_account_controls l5_account_controls_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_account_controls
    ADD CONSTRAINT l5_account_controls_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.l5_accounts(account_id) ON DELETE CASCADE;


--
-- Name: l5_admin_actions l5_admin_actions_actor_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_admin_actions
    ADD CONSTRAINT l5_admin_actions_actor_account_id_fkey FOREIGN KEY (actor_account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_appeals l5_appeals_opened_by_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_appeals
    ADD CONSTRAINT l5_appeals_opened_by_account_id_fkey FOREIGN KEY (opened_by_account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_appeals l5_appeals_submission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_appeals
    ADD CONSTRAINT l5_appeals_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.l5_contributor_submissions(submission_id);


--
-- Name: l5_auth_sessions l5_auth_sessions_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_auth_sessions
    ADD CONSTRAINT l5_auth_sessions_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.l5_accounts(account_id) ON DELETE CASCADE;


--
-- Name: l5_contribution_votes_v31 l5_contribution_votes_v31_voter_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_contribution_votes_v31
    ADD CONSTRAINT l5_contribution_votes_v31_voter_account_id_fkey FOREIGN KEY (voter_account_id) REFERENCES public.l5_accounts(account_id) ON DELETE CASCADE;


--
-- Name: l5_contributor_settlements l5_contributor_settlements_submission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_contributor_settlements
    ADD CONSTRAINT l5_contributor_settlements_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.l5_contributor_submissions(submission_id);


--
-- Name: l5_contributor_submissions l5_contributor_submissions_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_contributor_submissions
    ADD CONSTRAINT l5_contributor_submissions_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_credit_ledger l5_credit_ledger_source_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_credit_ledger
    ADD CONSTRAINT l5_credit_ledger_source_account_id_fkey FOREIGN KEY (source_account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_credit_ledger l5_credit_ledger_target_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_credit_ledger
    ADD CONSTRAINT l5_credit_ledger_target_account_id_fkey FOREIGN KEY (target_account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_governance_votes l5_governance_votes_appeal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_governance_votes
    ADD CONSTRAINT l5_governance_votes_appeal_id_fkey FOREIGN KEY (appeal_id) REFERENCES public.l5_appeals(appeal_id);


--
-- Name: l5_governance_votes l5_governance_votes_voter_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_governance_votes
    ADD CONSTRAINT l5_governance_votes_voter_account_id_fkey FOREIGN KEY (voter_account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_lifetime_votes_v31 l5_lifetime_votes_v31_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_lifetime_votes_v31
    ADD CONSTRAINT l5_lifetime_votes_v31_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.l5_accounts(account_id) ON DELETE CASCADE;


--
-- Name: l5_machine_entitlements l5_machine_entitlements_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_machine_entitlements
    ADD CONSTRAINT l5_machine_entitlements_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_nondelta_reviews l5_nondelta_reviews_reviewer_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_nondelta_reviews
    ADD CONSTRAINT l5_nondelta_reviews_reviewer_account_id_fkey FOREIGN KEY (reviewer_account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_nondelta_reviews l5_nondelta_reviews_submission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_nondelta_reviews
    ADD CONSTRAINT l5_nondelta_reviews_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.l5_contributor_submissions(submission_id);


--
-- Name: l5_oracle_evaluations l5_oracle_evaluations_submission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_oracle_evaluations
    ADD CONSTRAINT l5_oracle_evaluations_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES public.l5_contributor_submissions(submission_id);


--
-- Name: l5_validator_cycles l5_validator_cycles_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_validator_cycles
    ADD CONSTRAINT l5_validator_cycles_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.l5_accounts(account_id);


--
-- Name: l5_wallet_identities l5_wallet_identities_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l5_wallet_identities
    ADD CONSTRAINT l5_wallet_identities_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.l5_accounts(account_id) ON DELETE CASCADE;


--
-- Name: runs runs_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runs
    ADD CONSTRAINT runs_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: l5_account_controls; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_account_controls ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_admin_actions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_admin_actions ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_appeals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_appeals ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_auth_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_auth_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_contribution_votes_v31; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_contribution_votes_v31 ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_contributor_settlements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_contributor_settlements ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_contributor_submissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_contributor_submissions ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_credit_ledger; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_credit_ledger ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_governance_votes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_governance_votes ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_hub_action_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_hub_action_log ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_hub_anomaly_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_hub_anomaly_events ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_hub_network_lockouts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_hub_network_lockouts ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_lifetime_votes_v31; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_lifetime_votes_v31 ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_machine_entitlements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_machine_entitlements ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_nondelta_band_values; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_nondelta_band_values ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_nondelta_reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_nondelta_reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_oracle_evaluations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_oracle_evaluations ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_params; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_params ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_pool_cycles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_pool_cycles ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_pool_state_v31; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_pool_state_v31 ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_validator_cycles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_validator_cycles ENABLE ROW LEVEL SECURITY;

--
-- Name: l5_wallet_identities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.l5_wallet_identities ENABLE ROW LEVEL SECURITY;

--
-- Name: machine_aliases; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.machine_aliases ENABLE ROW LEVEL SECURITY;

--
-- Name: machine_aliases machine_aliases_anon_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY machine_aliases_anon_insert ON public.machine_aliases FOR INSERT TO anon WITH CHECK (true);


--
-- Name: machine_aliases machine_aliases_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY machine_aliases_anon_select ON public.machine_aliases FOR SELECT TO anon USING (true);


--
-- Name: machines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.machines ENABLE ROW LEVEL SECURITY;

--
-- Name: machines public insert machines; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public insert machines" ON public.machines FOR INSERT WITH CHECK (true);


--
-- Name: runs public insert runs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public insert runs" ON public.runs FOR INSERT WITH CHECK (true);


--
-- Name: machines public read machines; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public read machines" ON public.machines FOR SELECT USING (true);


--
-- Name: runs public read runs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public read runs" ON public.runs FOR SELECT USING (true);


--
-- Name: run_detail_bundles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.run_detail_bundles ENABLE ROW LEVEL SECURITY;

--
-- Name: run_detail_bundles run_detail_bundles_anon_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY run_detail_bundles_anon_insert ON public.run_detail_bundles FOR INSERT TO anon WITH CHECK (true);


--
-- Name: run_detail_bundles run_detail_bundles_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY run_detail_bundles_anon_select ON public.run_detail_bundles FOR SELECT TO anon USING (true);


--
-- Name: runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.runs ENABLE ROW LEVEL SECURITY;

--
-- Name: seed_bundles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.seed_bundles ENABLE ROW LEVEL SECURITY;

--
-- Name: seed_bundles seed_bundles_anon_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY seed_bundles_anon_insert ON public.seed_bundles FOR INSERT TO anon WITH CHECK (true);


--
-- Name: seed_bundles seed_bundles_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY seed_bundles_anon_select ON public.seed_bundles FOR SELECT TO anon USING (true);


--
-- Name: seed_payout_reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.seed_payout_reports ENABLE ROW LEVEL SECURITY;

--
-- Name: seed_payout_reports seed_payout_reports_anon_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY seed_payout_reports_anon_insert ON public.seed_payout_reports FOR INSERT TO anon WITH CHECK (true);


--
-- Name: seed_payout_reports seed_payout_reports_anon_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY seed_payout_reports_anon_select ON public.seed_payout_reports FOR SELECT TO anon USING (true);


--
-- PostgreSQL database dump complete
--

\unrestrict 9pjRSy8rVJqQg3WtYgB1TjpXQps2xc9dPieqeG59xPBvSQUtQsGsofMKsvd252Y

