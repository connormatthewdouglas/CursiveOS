-- CursiveOS Layer 5 payout functions v1
-- Date: 2026-04-02
-- Purpose: validator and contributor settlement runtime functions

create extension if not exists pgcrypto;

-- Validator payout event (idempotent)
create or replace function l5_pay_validator(
  p_cycle_id bigint,
  p_account_id uuid,
  p_machine_id text,
  p_reward numeric,
  p_idempotency_key text
)
returns jsonb
language plpgsql
as $$
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
$$;

-- Contributor settlement function (positive/flat/negative)
create or replace function l5_settle_contributor(
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
$$;
