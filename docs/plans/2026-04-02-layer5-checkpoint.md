# Layer 5 Checkpoint — 2026-04-02

Owner: Copper Sage
Status: Active build (post-migration runtime validation passed)

## Completed
- Wrote and froze Layer 5 spec pack:
  - docs/specs/layer5-economics-v1.md
  - docs/specs/layer5-architecture-v1.md
  - docs/specs/layer5-schema-v1.md
  - docs/specs/layer5-risk-controls-v1.md
  - docs/specs/layer5-contributor-policy-v1.md
  - docs/specs/layer5-consumer-policy-v1.md
  - docs/specs/layer5-v1-freeze.md
- Created and executed base schema migration:
  - references/SUPABASE-MIGRATION-layer5-v1.sql
- Verified base schema in Supabase:
  - 9 l5_* tables present
  - 3 v_l5_* views present
- Created runtime scaffolding migration:
  - references/SUPABASE-MIGRATION-layer5-runtime-v1.sql
- Runtime smoke validation confirmed:
  - l5_apply_fast_burn recorded fast_burn_inflow
  - ledger row present for cycle_id=2 with amount 5.000000

## Current Known Good Signals
- Fast burn path writes idempotent inflow event into l5_credit_ledger.
- Cycle close/reconcile function can close cycle with deterministic accounting status.

## Next Build Slice (in progress)
1) Validator payout functions
2) Contributor settlement functions (positive/flat/negative)
3) Appeal hold integration into contributor settlement timing
4) End-to-end payout smoke test cycle

## Newly added after checkpoint
- references/SUPABASE-MIGRATION-layer5-payouts-v1.sql
  - l5_pay_validator(...)
  - l5_settle_contributor(...)
- references/SUPABASE-LAYER5-payouts-smoketest-v1.sql
  - validator + contributor settlement smoke run on cycle 3
- references/SUPABASE-MIGRATION-layer5-appeals-v1.sql
  - l5_open_appeal_window(...)
  - l5_open_appeal(...)
  - l5_resolve_appeal(...)
  - l5_settle_contributor_guarded(...)
- references/SUPABASE-LAYER5-appeals-smoketest-v1.sql
  - guarded settle blocked while appeal window open, then passes after deadline
- references/SUPABASE-MIGRATION-layer5-oracle-v1.sql
  - l5_oracle_evaluations table
  - l5_record_oracle_verdict(...)
  - l5_settle_from_oracle_guarded(...)
- references/SUPABASE-LAYER5-oracle-smoketest-v1.sql
  - oracle verdict -> guarded settle -> ledger events confirmed (cycle 5)
- references/SUPABASE-MIGRATION-layer5-nondelta-rubric-v1.sql
  - l5_nondelta_reviews + l5_nondelta_band_values
  - l5_record_nondelta_review(...)
  - l5_settle_nondelta_from_review(...)
- references/SUPABASE-LAYER5-nondelta-smoketest-v1.sql
  - non-delta critical-band payout confirmed (cycle 6)
- references/SUPABASE-MIGRATION-layer5-cycle-runner-v1.sql
  - l5_process_fast_burns(...)
  - l5_settle_oracle_ready_submissions(...)
  - l5_settle_nondelta_ready_reviews(...)
  - l5_run_cycle(...)
- references/SUPABASE-LAYER5-cycle-runner-smoketest-v1.sql
  - one-shot cycle orchestration confirmed (cycle 7)
- references/SUPABASE-MIGRATION-layer5-admin-controls-v1.sql
  - l5_admin_actions audit table
  - l5_set_param(...)
  - l5_set_nondelta_band_value(...)
- references/SUPABASE-LAYER5-admin-controls-smoketest-v1.sql
  - parameter and band tuning audit records confirmed
## External dependencies currently needed
- None right now.

## Recovery note
If session is interrupted, resume from:
- references/SUPABASE-MIGRATION-layer5-runtime-v1.sql
- then proceed to payout migration file and smoke test queries.
