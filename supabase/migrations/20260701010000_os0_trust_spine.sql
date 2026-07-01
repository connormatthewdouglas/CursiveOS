-- OS.0 trust spine: signed identity keys, immutable raw-artifact replay index,
-- and database-addressable local V trust evaluations.
--
-- This is deliberately NOT a money switch. Rows are alpha/founder-fleet trust
-- evidence only; `payout_eligible` is constrained false until production Sybil
-- resistance and CursiveRoot-owned aggregation are hardened.

create table if not exists public.os0_identity_keys (
  identity_public_key text primary key,
  machine_id text not null,
  key_scheme text not null,
  key_status text not null default 'local_sim' check (key_status in ('local_sim','active','revoked','superseded')),
  trust_scope text not null default 'simulated_not_payout_eligible' check (trust_scope in ('simulated_not_payout_eligible','observe_only_not_payout_eligible')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.os0_raw_artifact_index (
  raw_artifact_fingerprint text primary key,
  measurement_fingerprint text,
  metric_derivation_fingerprint text,
  artifact_kind text not null,
  artifact_sha256 text,
  artifact_uri text,
  bundle_hash text,
  variant_id text,
  decision text,
  machine_id text,
  identity_public_key text,
  first_seen_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.os0_trust_evaluations (
  bundle_hash text primary key,
  job_id uuid,
  request_id uuid,
  variant_id text,
  decision text not null,
  machine_id text,
  identity_public_keys text[] not null default '{}',
  raw_artifact_fingerprints text[] not null default '{}',
  measurement_fingerprint text,
  gate_status text not null,
  recompute_ok boolean not null default false,
  signed_identity_ok boolean not null default false,
  replay_ok boolean not null default false,
  independent_aggregation_ok boolean not null default false,
  selection_truth_eligible boolean not null default false,
  payout_eligible boolean not null default false check (payout_eligible is false),
  reasons text[] not null default '{}',
  trust_summary jsonb not null default '{}'::jsonb,
  evaluated_at timestamptz not null default now()
);

create index if not exists os0_identity_keys_machine_idx on public.os0_identity_keys (machine_id, last_seen_at desc);
create index if not exists os0_identity_keys_metadata_gin_idx on public.os0_identity_keys using gin (metadata);

create index if not exists os0_raw_artifact_index_bundle_idx on public.os0_raw_artifact_index (bundle_hash);
create index if not exists os0_raw_artifact_index_machine_idx on public.os0_raw_artifact_index (machine_id, first_seen_at desc);
create index if not exists os0_raw_artifact_index_identity_idx on public.os0_raw_artifact_index (identity_public_key);
create index if not exists os0_raw_artifact_index_measurement_idx on public.os0_raw_artifact_index (measurement_fingerprint);
create index if not exists os0_raw_artifact_index_metadata_gin_idx on public.os0_raw_artifact_index using gin (metadata);

create index if not exists os0_trust_evaluations_gate_idx on public.os0_trust_evaluations (gate_status, evaluated_at desc);
create index if not exists os0_trust_evaluations_machine_idx on public.os0_trust_evaluations (machine_id, evaluated_at desc);
create index if not exists os0_trust_evaluations_variant_idx on public.os0_trust_evaluations (variant_id, evaluated_at desc);
create index if not exists os0_trust_evaluations_identity_gin_idx on public.os0_trust_evaluations using gin (identity_public_keys);
create index if not exists os0_trust_evaluations_raw_gin_idx on public.os0_trust_evaluations using gin (raw_artifact_fingerprints);
create index if not exists os0_trust_evaluations_summary_gin_idx on public.os0_trust_evaluations using gin (trust_summary);

comment on table public.os0_identity_keys is 'OS.0 alpha signed identity key registry. Local-sim evidence only; not payout eligible.';
comment on table public.os0_raw_artifact_index is 'OS.0 content-addressed raw artifact replay index for immutable recompute checks.';
comment on table public.os0_trust_evaluations is 'OS.0 local V trust evaluations. payout_eligible is hard-constrained false until production Sybil resistance exists.';
comment on column public.os0_trust_evaluations.selection_truth_eligible is 'Local trust summary only; still simulated/not payout eligible.';
comment on column public.os0_trust_evaluations.payout_eligible is 'Hard money gate. CHECK keeps all OS.0 Sprint 3 rows not payout eligible.';

alter table public.os0_identity_keys enable row level security;
alter table public.os0_raw_artifact_index enable row level security;
alter table public.os0_trust_evaluations enable row level security;

-- Public alpha read surface for the static dashboard / supervised operators.
drop policy if exists os0_identity_keys_public_select on public.os0_identity_keys;
create policy os0_identity_keys_public_select on public.os0_identity_keys for select to public using (true);
drop policy if exists os0_raw_artifact_index_public_select on public.os0_raw_artifact_index;
create policy os0_raw_artifact_index_public_select on public.os0_raw_artifact_index for select to public using (true);
drop policy if exists os0_trust_evaluations_public_select on public.os0_trust_evaluations;
create policy os0_trust_evaluations_public_select on public.os0_trust_evaluations for select to public using (true);

-- Public alpha insert paths mirror seed_bundles/run_detail_bundles. They are
-- content-addressed and guarded by simulated trust_scope / payout_eligible=false.
drop policy if exists os0_identity_keys_anon_insert on public.os0_identity_keys;
create policy os0_identity_keys_anon_insert on public.os0_identity_keys for insert to anon with check (
  trust_scope in ('simulated_not_payout_eligible','observe_only_not_payout_eligible')
);
drop policy if exists os0_raw_artifact_index_anon_insert on public.os0_raw_artifact_index;
create policy os0_raw_artifact_index_anon_insert on public.os0_raw_artifact_index for insert to anon with check (true);
drop policy if exists os0_trust_evaluations_anon_insert on public.os0_trust_evaluations;
create policy os0_trust_evaluations_anon_insert on public.os0_trust_evaluations for insert to anon with check (
  payout_eligible is false
  and trust_summary->>'trust_scope' in ('simulated_not_payout_eligible','observe_only_not_payout_eligible')
);

grant select on public.os0_identity_keys to anon, authenticated;
grant select on public.os0_raw_artifact_index to anon, authenticated;
grant select on public.os0_trust_evaluations to anon, authenticated;
grant insert on public.os0_identity_keys to anon;
grant insert on public.os0_raw_artifact_index to anon;
grant insert on public.os0_trust_evaluations to anon;
