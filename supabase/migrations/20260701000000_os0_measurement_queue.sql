-- OS.0 nervous-system queue: measurement requests, daemon heartbeats, and job records.
-- Bootstrap posture mirrors seed_bundles/runs: public read plus anon daemon writes
-- for a founder-controlled alpha fleet. Tighten before broad external rollout.

create table if not exists public.machine_capabilities (
  machine_id text primary key,
  daemon_version text not null,
  platform text not null,
  os_name text,
  kernel text,
  arch text,
  cpu text,
  gpu text,
  selection_scopes text[] not null default '{}',
  capabilities jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table if not exists public.measurement_requests (
  request_id uuid primary key default gen_random_uuid(),
  request_key text unique,
  status text not null default 'open' check (status in ('open','claimed','running','complete','failed','cancelled')),
  priority integer not null default 0,
  parent_variant_id text not null,
  parent_variant_path text not null,
  candidate_variant_id text not null,
  candidate_variant_path text not null,
  cycle_id integer not null default 4,
  screen_order text not null default 'normal' check (screen_order in ('normal','reversed')),
  required_capabilities text[] not null default array['linux_bare_metal','sudo_noninteractive','bash','python3','git','curl'],
  selection_scope text not null default 'linux_bare_metal' check (selection_scope in ('linux_bare_metal','linux_founder_fleet','linux_observe_only')),
  trust_scope text not null default 'simulated_not_payout_eligible' check (trust_scope in ('simulated_not_payout_eligible','observe_only_not_payout_eligible')),
  reward_sats_placeholder bigint not null default 0,
  requested_by text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.measurement_jobs (
  job_id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.measurement_requests(request_id) on delete cascade,
  machine_id text,
  daemon_id text not null,
  daemon_version text not null,
  status text not null default 'claimed' check (status in ('planned','claimed','running','complete','failed','upload_failed','ineligible','cancelled')),
  capabilities_snapshot jsonb not null default '{}'::jsonb,
  result_bundle_hash text,
  result_summary jsonb,
  failure_reason text,
  claimed_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  last_heartbeat_at timestamptz not null default now()
);

create index if not exists machine_capabilities_seen_idx on public.machine_capabilities (last_seen_at desc);
create index if not exists machine_capabilities_scopes_gin_idx on public.machine_capabilities using gin (selection_scopes);
create index if not exists measurement_requests_status_priority_idx on public.measurement_requests (status, priority desc, created_at asc);
create index if not exists measurement_requests_key_idx on public.measurement_requests (request_key);
create index if not exists measurement_requests_candidate_idx on public.measurement_requests (candidate_variant_id, created_at desc);
create index if not exists measurement_jobs_request_idx on public.measurement_jobs (request_id, claimed_at desc);
create index if not exists measurement_jobs_machine_idx on public.measurement_jobs (machine_id, claimed_at desc);
create index if not exists measurement_jobs_status_idx on public.measurement_jobs (status, last_heartbeat_at desc);

comment on table public.machine_capabilities is 'OS.0 alpha daemon host capability snapshots. Public alpha upsert; tighten before external fleet.';
comment on table public.measurement_requests is 'Explicit Linux measurement work orders for contributor daemons. Requests remain simulated/observe-only until trust hardening.';
comment on table public.measurement_jobs is 'Claim/execution records for measurement_requests. A job points to seed_bundles.result_bundle via result_bundle_hash when complete.';
comment on column public.measurement_requests.trust_scope is 'OS.0 alpha guard: no request is payout eligible. Real BTC requires later trust hardening.';
comment on column public.measurement_requests.selection_scope is 'Linux-only scope; Windows/WSL must not enter selection truth.';

alter table public.machine_capabilities enable row level security;
alter table public.measurement_requests enable row level security;
alter table public.measurement_jobs enable row level security;

-- Public alpha read surface for the static dashboard and daemon polling.
drop policy if exists machine_capabilities_public_select on public.machine_capabilities;
create policy machine_capabilities_public_select on public.machine_capabilities for select to public using (true);
drop policy if exists measurement_requests_public_select on public.measurement_requests;
create policy measurement_requests_public_select on public.measurement_requests for select to public using (true);
drop policy if exists measurement_jobs_public_select on public.measurement_jobs;
create policy measurement_jobs_public_select on public.measurement_jobs for select to public using (true);

-- Public alpha write paths for founder-controlled daemons. These intentionally
-- permit upsert/PATCH with the publishable key for local fleet bootstrap.
drop policy if exists machine_capabilities_anon_insert on public.machine_capabilities;
create policy machine_capabilities_anon_insert on public.machine_capabilities for insert to anon with check (true);
drop policy if exists machine_capabilities_anon_update on public.machine_capabilities;
create policy machine_capabilities_anon_update on public.machine_capabilities for update to anon using (true) with check (true);

drop policy if exists measurement_jobs_anon_insert on public.measurement_jobs;
create policy measurement_jobs_anon_insert on public.measurement_jobs for insert to anon with check (true);
drop policy if exists measurement_jobs_anon_update on public.measurement_jobs;
create policy measurement_jobs_anon_update on public.measurement_jobs for update to anon using (true) with check (true);

-- Request writes are left anon-enabled only for alpha queue bootstrapping from
-- lightweight tooling; disable this before broad public dashboard traffic.
drop policy if exists measurement_requests_anon_insert on public.measurement_requests;
create policy measurement_requests_anon_insert on public.measurement_requests for insert to anon with check (
  trust_scope in ('simulated_not_payout_eligible','observe_only_not_payout_eligible')
  and selection_scope in ('linux_bare_metal','linux_founder_fleet','linux_observe_only')
);
drop policy if exists measurement_requests_anon_update on public.measurement_requests;
create policy measurement_requests_anon_update on public.measurement_requests for update to anon using (true) with check (
  trust_scope in ('simulated_not_payout_eligible','observe_only_not_payout_eligible')
  and selection_scope in ('linux_bare_metal','linux_founder_fleet','linux_observe_only')
);

grant select on public.machine_capabilities to anon, authenticated;
grant select on public.measurement_requests to anon, authenticated;
grant select on public.measurement_jobs to anon, authenticated;
grant insert, update on public.machine_capabilities to anon;
grant insert, update on public.measurement_requests to anon;
grant insert, update on public.measurement_jobs to anon;

insert into public.measurement_requests (
  request_key,
  status,
  priority,
  parent_variant_id,
  parent_variant_path,
  candidate_variant_id,
  candidate_variant_path,
  cycle_id,
  screen_order,
  required_capabilities,
  selection_scope,
  trust_scope,
  reward_sats_placeholder,
  requested_by,
  notes
) values (
  'os0-alpha-v0.12-vs-v0.12b-swappiness-normal',
  'open',
  100,
  'v0.12',
  'references/seed-organism/variant.v0.12.json',
  'v0.12b-swappiness',
  'references/seed-organism/variant.v0.12b-swappiness.json',
  4,
  'normal',
  array['linux_bare_metal','sudo_noninteractive','bash','python3','git','curl'],
  'linux_bare_metal',
  'simulated_not_payout_eligible',
  0,
  'founder-os0-alpha',
  'First OS.0 queue seed: screen v0.12 parent against v0.12b swappiness=100. Simulated reward only; not payout eligible.'
) on conflict (request_key) do nothing;
