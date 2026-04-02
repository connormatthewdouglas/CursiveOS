-- CursiveOS Layer 5 appeals/hold integration v1
-- Date: 2026-04-02
-- Purpose: enforce appeal window before contributor settlement finalization

create extension if not exists pgcrypto;

-- Open appeal window on a submission
create or replace function l5_open_appeal_window(
  p_submission_id uuid,
  p_hours integer default 72
)
returns jsonb
language plpgsql
as $$
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

-- Record an appeal
create or replace function l5_open_appeal(
  p_submission_id uuid,
  p_opened_by_account_id uuid,
  p_reason text,
  p_evidence_uri text default null,
  p_fee_amount numeric default 0.10
)
returns jsonb
language plpgsql
as $$
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

-- Resolve an appeal
create or replace function l5_resolve_appeal(
  p_appeal_id uuid,
  p_state text
)
returns jsonb
language plpgsql
as $$
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

-- Guarded contributor settle wrapper:
-- blocks settlement while appeal window open or unresolved appeal exists
create or replace function l5_settle_contributor_guarded(
  p_cycle_id bigint,
  p_submission_id uuid,
  p_verdict text,
  p_measured_score numeric,
  p_idempotency_prefix text
)
returns jsonb
language plpgsql
as $$
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
$$;
