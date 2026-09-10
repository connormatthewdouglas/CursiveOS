-- DRAFT. DO NOT APPLY.
-- v3.3 ledger tables for CursiveRoot. Not production-ready until origin-side
-- recompute, key rotation, and hardware/wallet independence land.
-- payout_eligible remains hard-false. No rail execution in this migration.

-- l5_cycles replaces l5_pool_cycles (v3.1). There is no pool.
create table if not exists public.l5_cycles (
  cycle_id integer primary key,
  cycle_opened_at timestamptz not null,
  cycle_closed_at timestamptz,
  revenue_sats bigint not null default 0 check (revenue_sats >= 0),
  split_current numeric not null check (split_current >= 0 and split_current <= 1),
  split_lifetime numeric not null check (split_lifetime >= 0 and split_lifetime <= 1),
  metabolic_r numeric,
  status text not null check (status in ('open', 'closing', 'closed')),
  constraint l5_cycles_split_sum check (abs(split_current + split_lifetime - 1) < 1e-9)
);

-- Append-only lifetime fitness. Testers never appear here.
create table if not exists public.l5_lifetime_fitness (
  contributor_wallet text not null,
  variant_id text not null,
  cycle_id integer not null references public.l5_cycles (cycle_id),
  fitness_score numeric not null check (fitness_score >= 0),
  sensor_set_version text not null,
  recorded_at timestamptz not null default now(),
  primary key (variant_id)
);
create index if not exists l5_lifetime_fitness_wallet on public.l5_lifetime_fitness (contributor_wallet, recorded_at);
create index if not exists l5_lifetime_fitness_cycle on public.l5_lifetime_fitness (cycle_id);

create table if not exists public.l5_accruals (
  accrual_id text primary key,
  contributor_wallet text not null,
  cycle_id integer not null references public.l5_cycles (cycle_id),
  stream_type text not null check (stream_type in ('current', 'lifetime', 'redistribution')),
  amount_sats bigint not null check (amount_sats > 0),
  created_at timestamptz not null,
  claim_deadline timestamptz not null,
  claimed_at timestamptz,
  claim_tx_id text
);
create index if not exists l5_accruals_wallet on public.l5_accruals (contributor_wallet, claimed_at);
create index if not exists l5_accruals_deadline on public.l5_accruals (claim_deadline) where claimed_at is null;

-- Tester Fast-tier rebate. Explicitly not fitness.
create table if not exists public.l5_tester_rebates (
  rebate_id text primary key,
  tester_wallet text not null,
  cycle_id integer not null references public.l5_cycles (cycle_id),
  rebate_sats bigint not null check (rebate_sats >= 0),
  created_at timestamptz not null default now()
);

alter table public.l5_cycles enable row level security;
alter table public.l5_lifetime_fitness enable row level security;
alter table public.l5_accruals enable row level security;
alter table public.l5_tester_rebates enable row level security;

-- Read-only for anon. Writes are service-role only.
create policy l5_cycles_read on public.l5_cycles for select using (true);
create policy l5_lifetime_read on public.l5_lifetime_fitness for select using (true);
create policy l5_accruals_read on public.l5_accruals for select using (true);
create policy l5_rebates_read on public.l5_tester_rebates for select using (true);
