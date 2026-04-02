-- Layer 5 admin controls smoke test v1

-- ensure at least one actor account exists
insert into l5_accounts(role, status)
select 'mixed', 'active'
where not exists (select 1 from l5_accounts where role='mixed');

-- update core param with audit
select l5_set_param(
  (select account_id from l5_accounts where role='mixed' order by created_at asc limit 1),
  'validator_cap_pct',
  0.45,
  'pilot tuning increase for validator rewards',
  jsonb_build_object('source','smoketest','ticket','L5-ADM-001')
) as set_param_result;

-- update non-delta band value with audit
select l5_set_nondelta_band_value(
  (select account_id from l5_accounts where role='mixed' order by created_at asc limit 1),
  'high',
  3.5,
  'pilot tuning for high-band nondelta payouts',
  jsonb_build_object('source','smoketest','ticket','L5-ADM-002')
) as set_band_result;

-- inspect last admin actions
select action_type, target_key, old_value_numeric, new_value_numeric, reason, created_at
from l5_admin_actions
order by created_at desc
limit 5;
