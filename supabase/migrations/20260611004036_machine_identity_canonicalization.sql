-- Machine identity canonicalization (action-plan #3, 2026-06-10)
--
-- The canonical CursiveRoot machine key is the hardware fingerprint hash.
-- Wrapper v1.4.1 computes fingerprint v2 from stable hardware identity only
-- (CPU model | board vendor | board name | GPU PCI ids), so identity survives
-- kernel/microcode/driver updates. The old v1 hash (microcode+vBIOS+kernel)
-- drifted on every kernel update; rows uploaded under v1 hashes (and any old
-- slug-style ids) are preserved as aliases that map to the canonical machine.

create table if not exists public.machine_aliases (
  alias text primary key,
  machine_id text not null,
  alias_kind text not null default 'legacy_fingerprint_v1',
  source text,
  created_at timestamptz not null default now()
);

create index if not exists machine_aliases_machine_idx on public.machine_aliases (machine_id);

alter table public.machine_aliases enable row level security;

drop policy if exists machine_aliases_anon_insert on public.machine_aliases;
create policy machine_aliases_anon_insert on public.machine_aliases
  for insert to anon with check (true);

drop policy if exists machine_aliases_anon_select on public.machine_aliases;
create policy machine_aliases_anon_select on public.machine_aliases
  for select to anon using (true);

-- Columns the wrapper submits that were missing from machines
-- (gpu_vendor previously caused the full insert to fail into a minimal
-- fallback that dropped cores/vendor/ram data).
alter table public.machines add column if not exists gpu_vendor text;
alter table public.machines add column if not exists fingerprint_version integer;
