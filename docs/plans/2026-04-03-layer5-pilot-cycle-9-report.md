# Layer 5 Pilot Report — Cycle 9

Date: 2026-04-03
Run by: Copper Sage
Path tested: Performance/oracle settlement path

## Result
PASS

## What was tested
- Added one oracle-evaluated contributor submission for cycle 9 (`flat_delta`).
- Expired appeal deadline to allow guarded settlement.
- Ran cycle runner for cycle 9.

## Cycle accounting
- pool_open: 1010.000000
- inflow_total: 10.250000
- outflow_total: 0.000000
- burn_total: 0.000000
- pool_close: 1020.250000
- status: closed
- reconciliation_drift: 0.000000

## Ledger events observed (cycle 9)
1) fast_burn_inflow | incentive_pool | 5.000000 | cycle-9-fastburn-smoke-machine-runtime-001
2) fast_burn_inflow | incentive_pool | 5.000000 | cycle-9-fastburn-smoke-machine-cycle-runner-001
3) flat_fee_inflow | incentive_pool | 0.250000 | cycle-9-oracle-6ebc96bb-19c0-4267-bbc7-e6bf3dc747f6-flatfee
4) stake_refund | account | 4.750000 | cycle-9-oracle-6ebc96bb-19c0-4267-bbc7-e6bf3dc747f6-refund

## Idempotency check
- Re-running `l5_run_cycle(9,1010)` did not duplicate burns or payouts (applied=0, skipped=2), as expected.
