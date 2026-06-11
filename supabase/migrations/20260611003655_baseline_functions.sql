-- CursiveRoot baseline functions migration
-- Captured 2026-06-10 from the live database (pg_get_functiondef).
-- All Layer 5 runtime functions. Companion to 20260610230000_baseline_schema.sql.
-- Note: rls_auto_enable() and the ensure_rls event trigger are platform-managed
-- and intentionally excluded (event trigger creation requires superuser).

CREATE OR REPLACE FUNCTION public.l5_open_cycle(p_cycle_id bigint, p_pool_open numeric)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
begin
  insert into l5_pool_cycles (
    cycle_id, cycle_started_at, pool_open, status
  ) values (
    p_cycle_id, now(), p_pool_open, 'open'
  )
  on conflict (cycle_id) do nothing;
end;
$function$;

CREATE OR REPLACE FUNCTION public.l5_apply_fast_burn(p_cycle_id bigint, p_machine_id text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_close_cycle_reconcile(p_cycle_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_pay_validator(p_cycle_id bigint, p_account_id uuid, p_machine_id text, p_reward numeric, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
    p_cycle_id,
    'validator_payout',
    null,
    p_account_id,
    p_reward,
    'incentive_pool',
    'machine',
    p_machine_id,
    p_idempotency_key,
    jsonb_build_object('machine_id', p_machine_id, 'account_id', p_account_id)
  );

  return jsonb_build_object('ok', true, 'reason', 'paid', 'amount', p_reward);
end;
$function$;

CREATE OR REPLACE FUNCTION public.l5_process_fast_burns(p_cycle_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_settle_contributor(p_cycle_id bigint, p_submission_id uuid, p_verdict text, p_measured_score numeric, p_idempotency_prefix text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
    p_submission_id,
    p_cycle_id,
    v_refund,
    v_reward,
    v_burn,
    case when p_verdict = 'negative_delta' then v_stake else 0 end,
    case when p_verdict = 'flat_delta' then v_flat_fee else 0 end,
    'finalized'
  );

  update l5_contributor_submissions
  set state = 'settled', updated_at = now()
  where submission_id = p_submission_id;

  return jsonb_build_object(
    'ok', true,
    'verdict', p_verdict,
    'reward', v_reward,
    'burn', v_burn,
    'refund', v_refund
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.l5_open_appeal_window(p_submission_id uuid, p_hours integer DEFAULT 72)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_open_appeal(p_submission_id uuid, p_opened_by_account_id uuid, p_reason text, p_evidence_uri text DEFAULT NULL::text, p_fee_amount numeric DEFAULT 0.10)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_resolve_appeal(p_appeal_id uuid, p_state text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_settle_contributor_guarded(p_cycle_id bigint, p_submission_id uuid, p_verdict text, p_measured_score numeric, p_idempotency_prefix text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
    p_cycle_id,
    p_submission_id,
    p_verdict,
    p_measured_score,
    p_idempotency_prefix
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.l5_record_oracle_verdict(p_submission_id uuid, p_cycle_id bigint, p_verdict text, p_measured_score numeric, p_confidence numeric, p_manifest_hash text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_settle_from_oracle_guarded(p_cycle_id bigint, p_submission_id uuid, p_idempotency_prefix text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
    p_cycle_id,
    p_submission_id,
    v_verdict,
    coalesce(v_score,0),
    p_idempotency_prefix
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.l5_record_nondelta_review(p_submission_id uuid, p_cycle_id bigint, p_reviewer_account_id uuid, p_contribution_type text, p_severity integer, p_breadth integer, p_confidence integer, p_urgency integer, p_notes text DEFAULT NULL::text, p_evidence_uri text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_settle_nondelta_from_review(p_cycle_id bigint, p_submission_id uuid, p_idempotency_prefix text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
    p_cycle_id,
    'contributor_nondelta_payout',
    null,
    v_account_id,
    v_payout,
    'incentive_pool',
    'nondelta_review',
    v_review_id::text,
    p_idempotency_prefix || '-nondelta-payout',
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_settle_nondelta_ready_reviews(p_cycle_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_settle_oracle_ready_submissions(p_cycle_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_run_cycle(p_cycle_id bigint, p_pool_open numeric DEFAULT 1000)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_set_param(p_actor_account_id uuid, p_key text, p_value numeric, p_reason text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.l5_set_nondelta_band_value(p_actor_account_id uuid, p_band text, p_value numeric, p_reason text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$;
