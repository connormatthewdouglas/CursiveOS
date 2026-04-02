# Layer 5 Runtime Ops v1

Date: 2026-04-02
Owner: Copper Sage

## Added runtime artifacts
- references/SUPABASE-MIGRATION-layer5-runtime-v1.sql
- references/SUPABASE-LAYER5-runtime-smoketest-v1.sql

## What this enables
1) `l5_open_cycle(cycle_id, pool_open)`
- creates cycle row idempotently

2) `l5_apply_fast_burn(cycle_id, machine_id, idempotency_key)`
- verifies machine exists + plan is fast
- writes one inflow ledger event
- idempotent by key

3) `l5_close_cycle_reconcile(cycle_id)`
- computes inflow/outflow/burn totals from ledger
- enforces pool floor
- closes cycle as `closed` or `failed`

## Run order in Supabase
1. Run: SUPABASE-MIGRATION-layer5-runtime-v1.sql
2. Run: SUPABASE-LAYER5-runtime-smoketest-v1.sql
3. Confirm:
   - burn_result ok=true (or already_applied)
   - close_result ok=true
   - l5_pool_cycles(cycle_id=2) status=closed

## Notes
- This is scaffolding for Day 8-11.
- Validator and contributor payout functions still next.
