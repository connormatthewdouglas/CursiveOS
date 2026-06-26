-- 5th sensor channel: memory-pressure refault time (benchmark-memory-pressure probe).
-- All nullable so runs predating the channel remain valid.
-- Applied to CursiveRoot 2026-06-25 via apply_migration runs_memory_pressure_channel.
alter table public.runs
  add column if not exists memory_refault_baseline_s   double precision,
  add column if not exists memory_refault_tuned_s      double precision,
  add column if not exists memory_refault_delta_pct    double precision,
  add column if not exists memory_zram_ratio           double precision,
  add column if not exists memory_zram_peak_orig_mib   double precision,
  add column if not exists memory_sensor_mode          text,
  add column if not exists memory_ws_mb                integer,
  add column if not exists memory_ceiling_mb           integer;

comment on column public.runs.memory_refault_baseline_s is 'Memory-pressure sensor: median refault time (s) in baseline/parent state. Lower is better.';
comment on column public.runs.memory_refault_tuned_s is 'Memory-pressure sensor: median refault time (s) in tuned/candidate state. Lower is better.';
comment on column public.runs.memory_refault_delta_pct is 'Memory-pressure sensor: percent improvement (positive = tuned faster), lower-is-better convention.';
comment on column public.runs.memory_sensor_mode is 'cgroup-high (memory.high ceiling, valid) or uncapped (no ceiling, low validity).';
