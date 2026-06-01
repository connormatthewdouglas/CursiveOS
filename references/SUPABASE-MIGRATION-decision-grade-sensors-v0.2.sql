-- Decision-grade sensor detail bundles for CursiveOS Phase 0.
-- This migration is additive. Existing `runs` rows remain the compact status
-- surface; this table stores structured benchmark details and measurement
-- quality flags keyed by the source full-test JSON hash.

create table if not exists run_detail_bundles (
  id bigserial primary key,
  source_hash text not null unique,
  machine_id text not null,
  run_date date,
  preset_version text,
  wrapper_version text,
  structured_telemetry jsonb not null default '{}'::jsonb,
  measurement_quality jsonb not null default '{}'::jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  source text not null default 'seed_organism.py',
  created_at timestamptz not null default now()
);

create index if not exists run_detail_bundles_machine_idx
  on run_detail_bundles (machine_id, created_at desc);

create index if not exists run_detail_bundles_preset_idx
  on run_detail_bundles (preset_version, created_at desc);

create index if not exists run_detail_bundles_quality_gin_idx
  on run_detail_bundles using gin (measurement_quality);

create index if not exists run_detail_bundles_telemetry_gin_idx
  on run_detail_bundles using gin (structured_telemetry);

alter table run_detail_bundles enable row level security;

drop policy if exists run_detail_bundles_anon_insert on run_detail_bundles;
create policy run_detail_bundles_anon_insert on run_detail_bundles
  for insert
  to anon
  with check (true);

drop policy if exists run_detail_bundles_anon_select on run_detail_bundles;
create policy run_detail_bundles_anon_select on run_detail_bundles
  for select
  to anon
  using (true);

grant select, insert on run_detail_bundles to anon;
grant usage, select on sequence run_detail_bundles_id_seq to anon;

-- Founder-bootstrap boundary:
-- anon insert/select matches the current Phase 0 benchmark upload pattern so
-- Linux rigs can submit without an account. Before external incentives attach,
-- replace this with authenticated tester/machine identity plus server-side
-- validation.
