-- Verify Layer 5 v1 objects exist

select table_name
from information_schema.tables
where table_schema='public'
  and table_name in (
    'l5_accounts',
    'l5_machine_entitlements',
    'l5_credit_ledger',
    'l5_pool_cycles',
    'l5_validator_cycles',
    'l5_contributor_submissions',
    'l5_contributor_settlements',
    'l5_appeals',
    'l5_governance_votes'
  )
order by table_name;

select table_name
from information_schema.views
where table_schema='public'
  and table_name in (
    'v_l5_account_balances',
    'v_l5_pool_balance',
    'v_l5_cycle_reconciliation'
  )
order by table_name;
