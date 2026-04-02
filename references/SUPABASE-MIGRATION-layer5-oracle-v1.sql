-- CursiveOS Layer 5 oracle integration v1
-- Date: 2026-04-02
-- Purpose: record oracle verdicts and settle contributors from oracle outputs

create extension if not exists pgcrypto;

create table if not exists l5_oracle_evaluations (
  evaluation_id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references l5_contributor_submissions(submission_id),
  cycle_id bigint not null,
  verdict text not null check (verdict in ('positive_delta','flat_delta','negative_delta','inconclusive')),
  measured_score numeric(18,8) null,
  confidence numeric(6,5) not null default 0,
  manifest_hash text not null,
  status text not null default 'final' check (status in ('draft','final','superseded')),
  notes text null,
  created_at timestamptz not null default now(),
  unique(submission_id, cycle_id, manifest_hash)
);

create index if not exists idx_l5_oracle_eval_submission on l5_oracle_evaluations(submission_id);
create index if not exists idx_l5_oracle_eval_cycle on l5_oracle_evaluations(cycle_id);
create index if not exists idx_l5_oracle_eval_status on l5_oracle_evaluations(status);

create or replace function l5_record_oracle_verdict(
  p_submission_id uuid,
  p_cycle_id bigint,
  p_verdict text,
  p_measured_score numeric,
  p_confidence numeric,
  p_manifest_hash text,
  p_notes text default null
)
returns jsonb
language plpgsql
as $$
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

create or replace function l5_settle_from_oracle_guarded(
  p_cycle_id bigint,
  p_submission_id uuid,
  p_idempotency_prefix text
)
returns jsonb
language plpgsql
as $$
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
$$;
