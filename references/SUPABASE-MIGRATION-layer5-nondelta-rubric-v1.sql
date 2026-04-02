-- CursiveOS Layer 5 non-delta reward rubric v1
-- Date: 2026-04-02
-- Purpose: evidence-based payouts for security/driver/reliability contributions

create extension if not exists pgcrypto;

create table if not exists l5_nondelta_reviews (
  review_id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references l5_contributor_submissions(submission_id),
  cycle_id bigint not null,
  reviewer_account_id uuid not null references l5_accounts(account_id),
  contribution_type text not null check (contribution_type in ('security','driver','reliability','maintenance')),
  severity_score int not null check (severity_score between 0 and 5),
  breadth_score int not null check (breadth_score between 0 and 5),
  confidence_score int not null check (confidence_score between 0 and 5),
  urgency_score int not null check (urgency_score between 0 and 5),
  total_score int generated always as (severity_score + breadth_score + confidence_score + urgency_score) stored,
  payout_band text generated always as (
    case
      when (severity_score + breadth_score + confidence_score + urgency_score) >= 17 then 'critical'
      when (severity_score + breadth_score + confidence_score + urgency_score) >= 13 then 'high'
      when (severity_score + breadth_score + confidence_score + urgency_score) >= 7 then 'medium'
      else 'low'
    end
  ) stored,
  notes text null,
  evidence_uri text null,
  status text not null default 'provisional' check (status in ('provisional','challenged','finalized')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(submission_id, cycle_id, reviewer_account_id)
);

create index if not exists idx_l5_nondelta_reviews_submission on l5_nondelta_reviews(submission_id);
create index if not exists idx_l5_nondelta_reviews_cycle on l5_nondelta_reviews(cycle_id);
create index if not exists idx_l5_nondelta_reviews_status on l5_nondelta_reviews(status);

create table if not exists l5_nondelta_band_values (
  band text primary key check (band in ('low','medium','high','critical')),
  payout_credits numeric(18,6) not null check (payout_credits >= 0),
  updated_at timestamptz not null default now()
);

insert into l5_nondelta_band_values (band, payout_credits)
values
  ('low', 0.50),
  ('medium', 1.50),
  ('high', 3.00),
  ('critical', 6.00)
on conflict (band) do nothing;

create or replace function l5_record_nondelta_review(
  p_submission_id uuid,
  p_cycle_id bigint,
  p_reviewer_account_id uuid,
  p_contribution_type text,
  p_severity int,
  p_breadth int,
  p_confidence int,
  p_urgency int,
  p_notes text default null,
  p_evidence_uri text default null
)
returns jsonb
language plpgsql
as $$
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

create or replace function l5_settle_nondelta_from_review(
  p_cycle_id bigint,
  p_submission_id uuid,
  p_idempotency_prefix text
)
returns jsonb
language plpgsql
as $$
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
$$;
