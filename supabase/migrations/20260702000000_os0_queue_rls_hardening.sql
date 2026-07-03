-- OS.0 measurement-queue RLS hardening (2026-07-02)
--
-- Threat model: measurement_requests is the organism's work queue, and a
-- contributor daemon EXECUTES what it finds there (screen-variant --execute on
-- the referenced variant paths). Two anon-writable surfaces existed:
--
--   1. anon INSERT on measurement_requests  -> unsolicited queue injection: an
--      attacker holding only the public key could enqueue arbitrary (scope-valid)
--      work for daemons to run, or spam the queue.
--   2. anon UPDATE on measurement_requests using(true) over ALL columns -> an
--      attacker could rewrite candidate_variant_path / cycle_id / scope on an
--      existing request, redirecting what a daemon executes.
--
-- The daemon's real needs are narrow: it only PATCHes a request's {status,
-- updated_at} to advance it (open -> claimed -> complete/failed). Requests are
-- authored exclusively by the organism via privileged migrations / service role
-- (e.g. the seed insert in 20260701000000), never by the anon key. So:
--
--   * remove the anon INSERT policy entirely (privileged authorship only);
--   * keep the scope-checked anon UPDATE policy, but strip anon's column
--     privileges down to exactly (status, updated_at) so no other field can be
--     touched -- execution targets, scope, trust, reward, and cycle become
--     immutable to anon.
--
-- Everything here stays payout_eligible = false. Residual (documented in
-- docs/action-plan.md G4): cross-row anon writes on machine_capabilities and
-- measurement_jobs remain possible in alpha and require signed-identity-gated
-- writes to fully close; they carry no money and no code-execution redirection.

-- 0) Least privilege: the rls_auto_enable event-trigger function is not
--    directly callable (RETURNS event_trigger) and only idempotently enables RLS
--    on new public tables, but anon/public had a needless EXECUTE grant. Revoke.
revoke execute on function public.rls_auto_enable() from anon, public;

-- 1) Requests are privileged-authored only.
drop policy if exists measurement_requests_anon_insert on public.measurement_requests;

-- 2) Anon may advance status only, never redirect execution or change scope.
--    RLS (the surviving scope-checked UPDATE policy) still gates the row; column
--    privileges gate which fields anon may write.
revoke update on public.measurement_requests from anon;
grant update (status, updated_at) on public.measurement_requests to anon;

-- Readback / verification (no-op selects; visible in migration logs).
do $$
declare
  has_insert boolean;
begin
  select exists(
    select 1 from pg_policy
    where polrelid = 'public.measurement_requests'::regclass
      and polname = 'measurement_requests_anon_insert'
  ) into has_insert;
  if has_insert then
    raise exception 'hardening failed: anon insert policy still present on measurement_requests';
  end if;
end $$;
