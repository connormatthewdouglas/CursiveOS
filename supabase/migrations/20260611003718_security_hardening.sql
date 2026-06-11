-- CursiveRoot security hardening (2026-06-10)
-- Addresses Supabase security advisor findings without changing the documented
-- Phase 0 bootstrap posture (anon insert/select on benchmark + seed tables).
--
-- 1. security_definer_view (ERROR x3): the v_l5_* views ran with definer
--    privileges, bypassing RLS for any role allowed to select from them.
--    security_invoker makes them run with the caller's privileges; the l5_*
--    base tables are deny-by-default, so API roles get nothing while
--    privileged server-side connections are unaffected.
-- 2. function_search_path_mutable (WARN x19): pin search_path so the l5_*
--    functions cannot be hijacked by objects planted in another schema.
-- 3. Economics functions were executable by anon/authenticated via PostgREST
--    RPC (default grants). RLS already blocked their inner writes for those
--    roles, but they should not be invokable by API roles at all.

-- 1. Views run with caller's privileges
alter view public.v_l5_account_balances set (security_invoker = true);
alter view public.v_l5_cycle_reconciliation set (security_invoker = true);
alter view public.v_l5_pool_balance set (security_invoker = true);

-- 2. Pin search_path on all Layer 5 functions
alter function public.l5_open_cycle(bigint, numeric) set search_path = public;
alter function public.l5_apply_fast_burn(bigint, text, text) set search_path = public;
alter function public.l5_close_cycle_reconcile(bigint) set search_path = public;
alter function public.l5_pay_validator(bigint, uuid, text, numeric, text) set search_path = public;
alter function public.l5_process_fast_burns(bigint) set search_path = public;
alter function public.l5_settle_contributor(bigint, uuid, text, numeric, text) set search_path = public;
alter function public.l5_open_appeal_window(uuid, integer) set search_path = public;
alter function public.l5_open_appeal(uuid, uuid, text, text, numeric) set search_path = public;
alter function public.l5_resolve_appeal(uuid, text) set search_path = public;
alter function public.l5_settle_contributor_guarded(bigint, uuid, text, numeric, text) set search_path = public;
alter function public.l5_record_oracle_verdict(uuid, bigint, text, numeric, numeric, text, text) set search_path = public;
alter function public.l5_settle_from_oracle_guarded(bigint, uuid, text) set search_path = public;
alter function public.l5_record_nondelta_review(uuid, bigint, uuid, text, integer, integer, integer, integer, text, text) set search_path = public;
alter function public.l5_settle_nondelta_from_review(bigint, uuid, text) set search_path = public;
alter function public.l5_settle_nondelta_ready_reviews(bigint) set search_path = public;
alter function public.l5_settle_oracle_ready_submissions(bigint) set search_path = public;
alter function public.l5_run_cycle(bigint, numeric) set search_path = public;
alter function public.l5_set_param(uuid, text, numeric, text, jsonb) set search_path = public;
alter function public.l5_set_nondelta_band_value(uuid, text, numeric, text, jsonb) set search_path = public;

-- 3. Economics functions are server-side only: not callable through the API
revoke execute on function public.l5_open_cycle(bigint, numeric) from anon, authenticated;
revoke execute on function public.l5_apply_fast_burn(bigint, text, text) from anon, authenticated;
revoke execute on function public.l5_close_cycle_reconcile(bigint) from anon, authenticated;
revoke execute on function public.l5_pay_validator(bigint, uuid, text, numeric, text) from anon, authenticated;
revoke execute on function public.l5_process_fast_burns(bigint) from anon, authenticated;
revoke execute on function public.l5_settle_contributor(bigint, uuid, text, numeric, text) from anon, authenticated;
revoke execute on function public.l5_open_appeal_window(uuid, integer) from anon, authenticated;
revoke execute on function public.l5_open_appeal(uuid, uuid, text, text, numeric) from anon, authenticated;
revoke execute on function public.l5_resolve_appeal(uuid, text) from anon, authenticated;
revoke execute on function public.l5_settle_contributor_guarded(bigint, uuid, text, numeric, text) from anon, authenticated;
revoke execute on function public.l5_record_oracle_verdict(uuid, bigint, text, numeric, numeric, text, text) from anon, authenticated;
revoke execute on function public.l5_settle_from_oracle_guarded(bigint, uuid, text) from anon, authenticated;
revoke execute on function public.l5_record_nondelta_review(uuid, bigint, uuid, text, integer, integer, integer, integer, text, text) from anon, authenticated;
revoke execute on function public.l5_settle_nondelta_from_review(bigint, uuid, text) from anon, authenticated;
revoke execute on function public.l5_settle_nondelta_ready_reviews(bigint) from anon, authenticated;
revoke execute on function public.l5_settle_oracle_ready_submissions(bigint) from anon, authenticated;
revoke execute on function public.l5_run_cycle(bigint, numeric) from anon, authenticated;
revoke execute on function public.l5_set_param(uuid, text, numeric, text, jsonb) from anon, authenticated;
revoke execute on function public.l5_set_nondelta_band_value(uuid, text, numeric, text, jsonb) from anon, authenticated;

-- Platform RLS helper should not be callable by API roles either
revoke execute on function public.rls_auto_enable() from anon, authenticated;
