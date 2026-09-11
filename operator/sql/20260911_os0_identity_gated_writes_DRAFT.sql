-- DRAFT. DO NOT APPLY.
-- Drops USING(true) UPDATE holes on machine_capabilities and measurement_jobs.
--
-- Today founder daemons authenticate as anon with local_sim keys. Applying this
-- while key_status is still local_sim will stall heartbeats and job claims.
-- The close is a signed-identity JWT bound to an active Ed25519 key, then
-- identity-gated USING (machine_id = request.jwt.machine_id).
--
-- This file only removes the open cross-write. It does not invent a spoofable
-- x-machine-id header policy. Service role keeps full access.
-- payout_eligible remains hard-false. Do not combine with the v3.3 ledger draft.

drop policy if exists machine_capabilities_anon_update on public.machine_capabilities;
drop policy if exists measurement_jobs_anon_update on public.measurement_jobs;

-- Intentionally no USING(true) replacement.
-- Updates become service-role-only until the signed JWT policy lands.

comment on table public.machine_capabilities is
  'DRAFT 2026-09-11: anon UPDATE policy dropped. Do not apply until active identity keys exist.';
comment on table public.measurement_jobs is
  'DRAFT 2026-09-11: anon UPDATE policy dropped. Do not apply until active identity keys exist.';
