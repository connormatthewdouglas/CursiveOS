-- CursiveRoot baseline schema migration
-- Captured 2026-06-10 from the live database catalog after the free-tier
-- pause/restore incident (see docs/specs/cursiveroot-data-durability-v1.md).
-- This file makes the full public schema reproducible from an empty database.
-- Every statement is idempotent so it can be applied over a live database.
--
-- Sources consolidated here:
--   references/SUPABASE-MIGRATION-v1.5.sql                     (machines, runs)
--   references/SUPABASE-MIGRATION-seed-organism-v0.1.sql       (seed bundles/payouts)
--   references/SUPABASE-MIGRATION-decision-grade-sensors-v0.2.sql (run_detail_bundles)
--   references/SUPABASE-MIGRATION-layer5-*.sql                 (l5_* economics)
--   hub-api/server.js ensureSchema                             (hub/auth/v31 tables)

-- ---------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------

create sequence if not exists public.l5_hub_action_log_log_id_seq;
create sequence if not exists public.l5_hub_anomaly_events_anomaly_id_seq;
create sequence if not exists public.l5_pool_state_v31_id_seq;
create sequence if not exists public.run_detail_bundles_id_seq;
create sequence if not exists public.seed_bundles_id_seq;
create sequence if not exists public.seed_payout_reports_id_seq;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.machines (
  id uuid not null default gen_random_uuid(),
  machine_id text not null,
  label text,
  cpu text,
  cpu_cores_logical integer,
  gpu text,
  gpu_vram_gb integer,
  ram_gb integer,
  os text,
  kernel text,
  created_at timestamp with time zone default now(),
  constraint machines_machine_id_key UNIQUE (machine_id),
  constraint machines_pkey PRIMARY KEY (id)
);

create table if not exists public.runs (
  id uuid not null default gen_random_uuid(),
  machine_id text,
  run_date date,
  preset_version text,
  wrapper_version text,
  network_baseline_mbit double precision,
  network_tuned_mbit double precision,
  network_delta_pct double precision,
  coldstart_baseline_ms double precision,
  coldstart_tuned_ms double precision,
  coldstart_delta_pct double precision,
  sustained_baseline_toks double precision,
  sustained_tuned_toks double precision,
  sustained_delta_pct double precision,
  power_idle_baseline_w double precision,
  power_idle_tuned_w double precision,
  power_delta_w double precision,
  notes text,
  created_at timestamp with time zone default now(),
  cpu_microcode_version text,
  cpu_l1_cache_kb numeric,
  cpu_l2_cache_kb numeric,
  cpu_l3_cache_kb numeric,
  gpu_vram_mb numeric,
  gpu_driver_version text,
  ram_speed_mhz numeric,
  ram_channel_config text,
  dmesg_errors_baseline integer,
  dmesg_errors_tuned integer,
  cpu_throttle_events_baseline integer,
  cpu_throttle_events_tuned integer,
  gpu_throttle_events_baseline integer,
  gpu_throttle_events_tuned integer,
  temp_throttle_count_baseline integer,
  temp_throttle_count_tuned integer,
  constraint runs_pkey PRIMARY KEY (id)
);

create table if not exists public.seed_bundles (
  id bigint not null default nextval('seed_bundles_id_seq'::regclass),
  bundle_hash text not null,
  variant_id text not null,
  cycle_id text,
  decision text not null,
  reason text,
  machine_id text,
  contributor_id text,
  commit_ref text,
  fitness_score double precision,
  confidence double precision,
  sensor_result_hash text,
  regression_result_hash text,
  result_bundle jsonb not null,
  source text not null default 'seed_organism.py'::text,
  created_at timestamp with time zone not null default now(),
  uploaded_at timestamp with time zone not null default now(),
  constraint seed_bundles_bundle_hash_key UNIQUE (bundle_hash),
  constraint seed_bundles_pkey PRIMARY KEY (id)
);

create table if not exists public.seed_payout_reports (
  id bigint not null default nextval('seed_payout_reports_id_seq'::regclass),
  payout_report_hash text not null,
  cycle_id text not null,
  simulated_revenue_sats bigint,
  contributor_count integer,
  report jsonb not null,
  source text not null default 'seed_organism.py'::text,
  created_at timestamp with time zone not null default now(),
  uploaded_at timestamp with time zone not null default now(),
  constraint seed_payout_reports_payout_report_hash_key UNIQUE (payout_report_hash),
  constraint seed_payout_reports_pkey PRIMARY KEY (id)
);

create table if not exists public.run_detail_bundles (
  id bigint not null default nextval('run_detail_bundles_id_seq'::regclass),
  source_hash text not null,
  machine_id text not null,
  run_date date,
  preset_version text,
  wrapper_version text,
  structured_telemetry jsonb not null default '{}'::jsonb,
  measurement_quality jsonb not null default '{}'::jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  source text not null default 'seed_organism.py'::text,
  created_at timestamp with time zone not null default now(),
  constraint run_detail_bundles_pkey PRIMARY KEY (id),
  constraint run_detail_bundles_source_hash_key UNIQUE (source_hash)
);

create table if not exists public.l5_accounts (
  account_id uuid not null default gen_random_uuid(),
  role text not null,
  status text not null default 'active'::text,
  created_at timestamp with time zone not null default now(),
  username text,
  password_hash text,
  constraint l5_accounts_pkey PRIMARY KEY (account_id),
  constraint l5_accounts_role_check CHECK ((role = ANY (ARRAY['consumer'::text, 'validator'::text, 'contributor'::text, 'mixed'::text]))),
  constraint l5_accounts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'review'::text])))
);

create table if not exists public.l5_machine_entitlements (
  machine_id text not null,
  account_id uuid not null,
  plan text not null default 'stable'::text,
  fast_cycle_fee numeric(18,6) not null default 5,
  plan_updated_at timestamp with time zone not null default now(),
  last_burn_cycle_id bigint,
  constraint l5_machine_entitlements_pkey PRIMARY KEY (machine_id),
  constraint l5_machine_entitlements_plan_check CHECK ((plan = ANY (ARRAY['stable'::text, 'fast'::text])))
);

create table if not exists public.l5_credit_ledger (
  event_id uuid not null default gen_random_uuid(),
  event_time timestamp with time zone not null default now(),
  cycle_id bigint not null,
  event_type text not null,
  source_account_id uuid,
  target_account_id uuid,
  amount numeric(18,6) not null,
  bucket text not null,
  reference_type text,
  reference_id text,
  idempotency_key text not null,
  formula_version text not null default 'l5-econ-v1'::text,
  metadata jsonb not null default '{}'::jsonb,
  constraint l5_credit_ledger_amount_check CHECK ((amount >= (0)::numeric)),
  constraint l5_credit_ledger_bucket_check CHECK ((bucket = ANY (ARRAY['incentive_pool'::text, 'ops_reserve'::text, 'burn_sink'::text, 'account'::text]))),
  constraint l5_credit_ledger_idempotency_key_key UNIQUE (idempotency_key),
  constraint l5_credit_ledger_pkey PRIMARY KEY (event_id)
);

create table if not exists public.l5_pool_cycles (
  cycle_id bigint not null,
  cycle_started_at timestamp with time zone not null,
  cycle_closed_at timestamp with time zone,
  pool_open numeric(18,6) not null,
  inflow_total numeric(18,6) not null default 0,
  outflow_total numeric(18,6) not null default 0,
  burn_total numeric(18,6) not null default 0,
  pool_close numeric(18,6),
  reconciliation_drift numeric(18,6) not null default 0,
  status text not null default 'open'::text,
  constraint l5_pool_cycles_pkey PRIMARY KEY (cycle_id),
  constraint l5_pool_cycles_status_check CHECK ((status = ANY (ARRAY['open'::text, 'settling'::text, 'closed'::text, 'failed'::text])))
);

create table if not exists public.l5_validator_cycles (
  id uuid not null default gen_random_uuid(),
  cycle_id bigint not null,
  account_id uuid not null,
  machine_id text not null,
  streak_count integer not null default 0,
  multiplier_continuity numeric(18,8) not null,
  multiplier_rarity numeric(18,8) not null,
  multiplier_quality numeric(18,8) not null,
  reward_gross numeric(18,6) not null,
  reward_net numeric(18,6) not null,
  payout_status text not null,
  hold_reason text,
  created_at timestamp with time zone not null default now(),
  constraint l5_validator_cycles_cycle_id_account_id_machine_id_key UNIQUE (cycle_id, account_id, machine_id),
  constraint l5_validator_cycles_payout_status_check CHECK ((payout_status = ANY (ARRAY['eligible'::text, 'held'::text, 'paid'::text, 'prorated_paid'::text, 'rejected'::text]))),
  constraint l5_validator_cycles_pkey PRIMARY KEY (id)
);

create table if not exists public.l5_contributor_submissions (
  submission_id uuid not null default gen_random_uuid(),
  account_id uuid not null,
  submission_hash text not null,
  title text not null,
  class text not null,
  stake_amount numeric(18,6) not null default 5,
  state text not null,
  measured_score numeric(18,8),
  verdict text,
  appeal_deadline timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  description text,
  constraint l5_contributor_submissions_class_check CHECK ((class = ANY (ARRAY['preset'::text, 'benchmark'::text, 'driver'::text, 'kernel'::text, 'security'::text, 'other'::text]))),
  constraint l5_contributor_submissions_pkey PRIMARY KEY (submission_id),
  constraint l5_contributor_submissions_state_check CHECK ((state = ANY (ARRAY['proposed'::text, 'stake_locked'::text, 'testing'::text, 'pending_settlement'::text, 'final_positive'::text, 'final_flat'::text, 'final_negative'::text, 'settled'::text]))),
  constraint l5_contributor_submissions_submission_hash_key UNIQUE (submission_hash),
  constraint l5_contributor_submissions_verdict_check CHECK ((verdict = ANY (ARRAY['positive_delta'::text, 'flat_delta'::text, 'negative_delta'::text, 'inconclusive'::text])))
);

create table if not exists public.l5_contributor_settlements (
  settlement_id uuid not null default gen_random_uuid(),
  submission_id uuid not null,
  cycle_id bigint not null,
  stake_refund numeric(18,6) not null default 0,
  payout_gross numeric(18,6) not null default 0,
  payout_burn numeric(18,6) not null default 0,
  slash_amount numeric(18,6) not null default 0,
  flat_fee numeric(18,6) not null default 0,
  status text not null,
  created_at timestamp with time zone not null default now(),
  constraint l5_contributor_settlements_pkey PRIMARY KEY (settlement_id),
  constraint l5_contributor_settlements_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'finalized'::text, 'superseded'::text])))
);

create table if not exists public.l5_appeals (
  appeal_id uuid not null default gen_random_uuid(),
  submission_id uuid not null,
  opened_by_account_id uuid not null,
  reason text not null,
  evidence_uri text,
  fee_amount numeric(18,6) not null default 0,
  state text not null,
  opened_at timestamp with time zone not null default now(),
  deadline_at timestamp with time zone not null,
  resolved_at timestamp with time zone,
  constraint l5_appeals_pkey PRIMARY KEY (appeal_id),
  constraint l5_appeals_state_check CHECK ((state = ANY (ARRAY['open'::text, 'accepted'::text, 'rejected'::text, 'resolved'::text])))
);

create table if not exists public.l5_governance_votes (
  vote_id uuid not null default gen_random_uuid(),
  appeal_id uuid,
  voter_account_id uuid not null,
  vote text not null,
  weight numeric(18,6) not null default 1,
  voted_at timestamp with time zone not null default now(),
  constraint l5_governance_votes_appeal_id_voter_account_id_key UNIQUE (appeal_id, voter_account_id),
  constraint l5_governance_votes_pkey PRIMARY KEY (vote_id),
  constraint l5_governance_votes_vote_check CHECK ((vote = ANY (ARRAY['yes'::text, 'no'::text, 'abstain'::text])))
);

create table if not exists public.l5_params (
  key text not null,
  value_numeric numeric(18,8),
  value_text text,
  updated_at timestamp with time zone not null default now(),
  constraint l5_params_pkey PRIMARY KEY (key)
);

create table if not exists public.l5_oracle_evaluations (
  evaluation_id uuid not null default gen_random_uuid(),
  submission_id uuid not null,
  cycle_id bigint not null,
  verdict text not null,
  measured_score numeric(18,8),
  confidence numeric(6,5) not null default 0,
  manifest_hash text not null,
  status text not null default 'final'::text,
  notes text,
  created_at timestamp with time zone not null default now(),
  constraint l5_oracle_evaluations_pkey PRIMARY KEY (evaluation_id),
  constraint l5_oracle_evaluations_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'final'::text, 'superseded'::text]))),
  constraint l5_oracle_evaluations_submission_id_cycle_id_manifest_hash_key UNIQUE (submission_id, cycle_id, manifest_hash),
  constraint l5_oracle_evaluations_verdict_check CHECK ((verdict = ANY (ARRAY['positive_delta'::text, 'flat_delta'::text, 'negative_delta'::text, 'inconclusive'::text])))
);

create table if not exists public.l5_nondelta_reviews (
  review_id uuid not null default gen_random_uuid(),
  submission_id uuid not null,
  cycle_id bigint not null,
  reviewer_account_id uuid not null,
  contribution_type text not null,
  severity_score integer not null,
  breadth_score integer not null,
  confidence_score integer not null,
  urgency_score integer not null,
  total_score integer default (((severity_score + breadth_score) + confidence_score) + urgency_score),
  payout_band text default
CASE
    WHEN ((((severity_score + breadth_score) + confidence_score) + urgency_score) >= 17) THEN 'critical'::text
    WHEN ((((severity_score + breadth_score) + confidence_score) + urgency_score) >= 13) THEN 'high'::text
    WHEN ((((severity_score + breadth_score) + confidence_score) + urgency_score) >= 7) THEN 'medium'::text
    ELSE 'low'::text
END,
  notes text,
  evidence_uri text,
  status text not null default 'provisional'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint l5_nondelta_reviews_breadth_score_check CHECK (((breadth_score >= 0) AND (breadth_score <= 5))),
  constraint l5_nondelta_reviews_confidence_score_check CHECK (((confidence_score >= 0) AND (confidence_score <= 5))),
  constraint l5_nondelta_reviews_contribution_type_check CHECK ((contribution_type = ANY (ARRAY['security'::text, 'driver'::text, 'reliability'::text, 'maintenance'::text]))),
  constraint l5_nondelta_reviews_pkey PRIMARY KEY (review_id),
  constraint l5_nondelta_reviews_severity_score_check CHECK (((severity_score >= 0) AND (severity_score <= 5))),
  constraint l5_nondelta_reviews_status_check CHECK ((status = ANY (ARRAY['provisional'::text, 'challenged'::text, 'finalized'::text]))),
  constraint l5_nondelta_reviews_submission_id_cycle_id_reviewer_account_key UNIQUE (submission_id, cycle_id, reviewer_account_id),
  constraint l5_nondelta_reviews_urgency_score_check CHECK (((urgency_score >= 0) AND (urgency_score <= 5)))
);

create table if not exists public.l5_nondelta_band_values (
  band text not null,
  payout_credits numeric(18,6) not null,
  updated_at timestamp with time zone not null default now(),
  constraint l5_nondelta_band_values_band_check CHECK ((band = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))),
  constraint l5_nondelta_band_values_payout_credits_check CHECK ((payout_credits >= (0)::numeric)),
  constraint l5_nondelta_band_values_pkey PRIMARY KEY (band)
);

create table if not exists public.l5_admin_actions (
  action_id uuid not null default gen_random_uuid(),
  actor_account_id uuid,
  action_type text not null,
  target_key text not null,
  old_value_numeric numeric(18,8),
  new_value_numeric numeric(18,8),
  reason text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  constraint l5_admin_actions_action_type_check CHECK ((action_type = ANY (ARRAY['set_param'::text, 'set_band_value'::text]))),
  constraint l5_admin_actions_pkey PRIMARY KEY (action_id)
);

create table if not exists public.l5_auth_sessions (
  session_token text not null,
  account_id uuid not null,
  status text not null default 'active'::text,
  created_at timestamp with time zone not null default now(),
  expires_at timestamp with time zone not null,
  last_seen_at timestamp with time zone,
  constraint l5_auth_sessions_pkey PRIMARY KEY (session_token)
);

create table if not exists public.l5_hub_action_log (
  log_id bigint not null default nextval('l5_hub_action_log_log_id_seq'::regclass),
  action text not null,
  actor_account_id uuid,
  route text not null,
  method text not null,
  status text not null,
  details jsonb,
  created_at timestamp with time zone not null default now(),
  constraint l5_hub_action_log_pkey PRIMARY KEY (log_id)
);

create table if not exists public.l5_account_controls (
  account_id uuid not null,
  control_mode text not null default 'normal'::text,
  reason text,
  updated_by_account_id uuid,
  updated_at timestamp with time zone not null default now(),
  constraint l5_account_controls_pkey PRIMARY KEY (account_id)
);

create table if not exists public.l5_hub_anomaly_events (
  anomaly_id bigint not null default nextval('l5_hub_anomaly_events_anomaly_id_seq'::regclass),
  account_id uuid,
  signal_type text not null,
  severity text not null default 'medium'::text,
  route text,
  details jsonb,
  created_at timestamp with time zone not null default now(),
  resolved_at timestamp with time zone,
  constraint l5_hub_anomaly_events_pkey PRIMARY KEY (anomaly_id)
);

create table if not exists public.l5_hub_network_lockouts (
  lockout_key text not null,
  lockout_until timestamp with time zone not null,
  reason text not null,
  strike_count integer not null default 0,
  details jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint l5_hub_network_lockouts_pkey PRIMARY KEY (lockout_key)
);

create table if not exists public.l5_wallet_identities (
  account_id uuid not null,
  wallet_address text not null,
  chain_id text not null default 'evm:1'::text,
  verification_status text not null default 'unverified'::text,
  verification_method text,
  verification_nonce text,
  signature text,
  bound_at timestamp with time zone not null default now(),
  verified_at timestamp with time zone,
  updated_at timestamp with time zone not null default now(),
  constraint l5_wallet_identities_pkey PRIMARY KEY (account_id)
);

create table if not exists public.l5_pool_state_v31 (
  id integer not null default nextval('l5_pool_state_v31_id_seq'::regclass),
  cycle_id integer not null,
  fast_user_count integer not null default 0,
  fast_revenue_usd numeric(18,8) not null default 0,
  fast_revenue_btc numeric(18,8) not null default 0,
  btc_price_usd numeric(12,2) not null default 85000,
  payout_pot_btc numeric(18,8) not null default 0,
  pool_inflow_btc numeric(18,8) not null default 0,
  pool_principal_btc numeric(18,8) not null default 0,
  cycle_yield_btc numeric(18,8) not null default 0,
  status text not null default 'open'::text,
  created_at timestamp with time zone not null default now(),
  closed_at timestamp with time zone,
  constraint l5_pool_state_v31_cycle_id_key UNIQUE (cycle_id),
  constraint l5_pool_state_v31_pkey PRIMARY KEY (id)
);

create table if not exists public.l5_contribution_votes_v31 (
  vote_id uuid not null default gen_random_uuid(),
  cycle_id integer not null,
  voter_account_id uuid not null,
  submission_id uuid not null,
  points numeric(10,4) not null default 0,
  created_at timestamp with time zone not null default now(),
  constraint l5_contribution_votes_v31_cycle_id_voter_account_id_submiss_key UNIQUE (cycle_id, voter_account_id, submission_id),
  constraint l5_contribution_votes_v31_pkey PRIMARY KEY (vote_id)
);

create table if not exists public.l5_lifetime_votes_v31 (
  account_id uuid not null,
  lifetime_votes numeric(18,4) not null default 0,
  total_payout_btc numeric(18,8) not null default 0,
  total_royalty_btc numeric(18,8) not null default 0,
  cooldown_remaining integer not null default 0,
  consecutive_low_vote_cycles integer not null default 0,
  updated_at timestamp with time zone not null default now(),
  constraint l5_lifetime_votes_v31_pkey PRIMARY KEY (account_id)
);

-- Tie serial-style sequences to their columns
alter sequence public.seed_bundles_id_seq owned by public.seed_bundles.id;
alter sequence public.seed_payout_reports_id_seq owned by public.seed_payout_reports.id;
alter sequence public.run_detail_bundles_id_seq owned by public.run_detail_bundles.id;
alter sequence public.l5_hub_action_log_log_id_seq owned by public.l5_hub_action_log.log_id;
alter sequence public.l5_hub_anomaly_events_anomaly_id_seq owned by public.l5_hub_anomaly_events.anomaly_id;
alter sequence public.l5_pool_state_v31_id_seq owned by public.l5_pool_state_v31.id;

-- ---------------------------------------------------------------------------
-- Foreign keys (added separately so table creation order is irrelevant)
-- ---------------------------------------------------------------------------

do $$
begin
  begin
    alter table public.runs add constraint runs_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES machines(machine_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_account_controls add constraint l5_account_controls_account_id_fkey FOREIGN KEY (account_id) REFERENCES l5_accounts(account_id) ON DELETE CASCADE;
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_admin_actions add constraint l5_admin_actions_actor_account_id_fkey FOREIGN KEY (actor_account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_appeals add constraint l5_appeals_opened_by_account_id_fkey FOREIGN KEY (opened_by_account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_appeals add constraint l5_appeals_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES l5_contributor_submissions(submission_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_auth_sessions add constraint l5_auth_sessions_account_id_fkey FOREIGN KEY (account_id) REFERENCES l5_accounts(account_id) ON DELETE CASCADE;
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_contribution_votes_v31 add constraint l5_contribution_votes_v31_voter_account_id_fkey FOREIGN KEY (voter_account_id) REFERENCES l5_accounts(account_id) ON DELETE CASCADE;
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_contributor_settlements add constraint l5_contributor_settlements_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES l5_contributor_submissions(submission_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_contributor_submissions add constraint l5_contributor_submissions_account_id_fkey FOREIGN KEY (account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_credit_ledger add constraint l5_credit_ledger_target_account_id_fkey FOREIGN KEY (target_account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_credit_ledger add constraint l5_credit_ledger_source_account_id_fkey FOREIGN KEY (source_account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_governance_votes add constraint l5_governance_votes_appeal_id_fkey FOREIGN KEY (appeal_id) REFERENCES l5_appeals(appeal_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_governance_votes add constraint l5_governance_votes_voter_account_id_fkey FOREIGN KEY (voter_account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_lifetime_votes_v31 add constraint l5_lifetime_votes_v31_account_id_fkey FOREIGN KEY (account_id) REFERENCES l5_accounts(account_id) ON DELETE CASCADE;
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_machine_entitlements add constraint l5_machine_entitlements_account_id_fkey FOREIGN KEY (account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_nondelta_reviews add constraint l5_nondelta_reviews_reviewer_account_id_fkey FOREIGN KEY (reviewer_account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_nondelta_reviews add constraint l5_nondelta_reviews_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES l5_contributor_submissions(submission_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_oracle_evaluations add constraint l5_oracle_evaluations_submission_id_fkey FOREIGN KEY (submission_id) REFERENCES l5_contributor_submissions(submission_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_validator_cycles add constraint l5_validator_cycles_account_id_fkey FOREIGN KEY (account_id) REFERENCES l5_accounts(account_id);
  exception when duplicate_object then null; end;
  begin
    alter table public.l5_wallet_identities add constraint l5_wallet_identities_account_id_fkey FOREIGN KEY (account_id) REFERENCES l5_accounts(account_id) ON DELETE CASCADE;
  exception when duplicate_object then null; end;
end $$;

-- ---------------------------------------------------------------------------
-- Indexes (non-constraint)
-- ---------------------------------------------------------------------------

create index if not exists idx_l5_accounts_role on public.l5_accounts using btree (role);
create index if not exists idx_l5_admin_actions_key on public.l5_admin_actions using btree (target_key);
create index if not exists idx_l5_admin_actions_time on public.l5_admin_actions using btree (created_at DESC);
create index if not exists idx_l5_admin_actions_type on public.l5_admin_actions using btree (action_type);
create index if not exists idx_l5_appeals_state on public.l5_appeals using btree (state);
create index if not exists idx_l5_appeals_submission on public.l5_appeals using btree (submission_id);
create index if not exists idx_l5_contrib_account on public.l5_contributor_submissions using btree (account_id);
create index if not exists idx_l5_contrib_settle_cycle on public.l5_contributor_settlements using btree (cycle_id);
create index if not exists idx_l5_contrib_settle_status on public.l5_contributor_settlements using btree (status);
create index if not exists idx_l5_contrib_state on public.l5_contributor_submissions using btree (state);
create index if not exists idx_l5_entitlements_account on public.l5_machine_entitlements using btree (account_id);
create index if not exists idx_l5_entitlements_plan on public.l5_machine_entitlements using btree (plan);
create index if not exists idx_l5_ledger_cycle on public.l5_credit_ledger using btree (cycle_id);
create index if not exists idx_l5_ledger_source on public.l5_credit_ledger using btree (source_account_id);
create index if not exists idx_l5_ledger_target on public.l5_credit_ledger using btree (target_account_id);
create index if not exists idx_l5_ledger_type on public.l5_credit_ledger using btree (event_type);
create index if not exists idx_l5_nondelta_reviews_cycle on public.l5_nondelta_reviews using btree (cycle_id);
create index if not exists idx_l5_nondelta_reviews_status on public.l5_nondelta_reviews using btree (status);
create index if not exists idx_l5_nondelta_reviews_submission on public.l5_nondelta_reviews using btree (submission_id);
create index if not exists idx_l5_oracle_eval_cycle on public.l5_oracle_evaluations using btree (cycle_id);
create index if not exists idx_l5_oracle_eval_status on public.l5_oracle_evaluations using btree (status);
create index if not exists idx_l5_oracle_eval_submission on public.l5_oracle_evaluations using btree (submission_id);
create index if not exists idx_l5_pool_cycles_status on public.l5_pool_cycles using btree (status);
create index if not exists idx_l5_validator_cycles_cycle on public.l5_validator_cycles using btree (cycle_id);
create index if not exists idx_l5_validator_cycles_status on public.l5_validator_cycles using btree (payout_status);
create unique index if not exists l5_accounts_username_lower_idx on public.l5_accounts using btree (lower(username)) where (username is not null);
create index if not exists l5_auth_sessions_account_idx on public.l5_auth_sessions using btree (account_id);
create index if not exists l5_auth_sessions_expires_idx on public.l5_auth_sessions using btree (expires_at);
create index if not exists l5_hub_action_log_actor_idx on public.l5_hub_action_log using btree (actor_account_id, created_at DESC);
create index if not exists l5_hub_anomaly_account_idx on public.l5_hub_anomaly_events using btree (account_id, created_at DESC);
create index if not exists l5_hub_network_lockouts_until_idx on public.l5_hub_network_lockouts using btree (lockout_until);
create unique index if not exists l5_wallet_identities_address_unique on public.l5_wallet_identities using btree (lower(wallet_address));
create index if not exists run_detail_bundles_machine_idx on public.run_detail_bundles using btree (machine_id, created_at DESC);
create index if not exists run_detail_bundles_preset_idx on public.run_detail_bundles using btree (preset_version, created_at DESC);
create index if not exists run_detail_bundles_quality_gin_idx on public.run_detail_bundles using gin (measurement_quality);
create index if not exists run_detail_bundles_telemetry_gin_idx on public.run_detail_bundles using gin (structured_telemetry);
create index if not exists seed_bundles_bundle_gin_idx on public.seed_bundles using gin (result_bundle);
create index if not exists seed_bundles_decision_idx on public.seed_bundles using btree (decision, created_at DESC);
create index if not exists seed_bundles_machine_idx on public.seed_bundles using btree (machine_id, created_at DESC);
create index if not exists seed_bundles_variant_idx on public.seed_bundles using btree (variant_id, created_at DESC);
create index if not exists seed_payout_reports_cycle_idx on public.seed_payout_reports using btree (cycle_id, created_at DESC);
create index if not exists seed_payout_reports_report_gin_idx on public.seed_payout_reports using gin (report);

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

create or replace view public.v_l5_account_balances as
with inbound as (
  select l5_credit_ledger.target_account_id as account_id,
         sum(l5_credit_ledger.amount) as amt
  from l5_credit_ledger
  where l5_credit_ledger.target_account_id is not null and l5_credit_ledger.bucket = 'account'::text
  group by l5_credit_ledger.target_account_id
), outbound as (
  select l5_credit_ledger.source_account_id as account_id,
         sum(l5_credit_ledger.amount) as amt
  from l5_credit_ledger
  where l5_credit_ledger.source_account_id is not null and l5_credit_ledger.bucket = 'account'::text
  group by l5_credit_ledger.source_account_id
)
select a.account_id,
       coalesce(i.amt, 0::numeric) - coalesce(o.amt, 0::numeric) as balance
from l5_accounts a
left join inbound i on i.account_id = a.account_id
left join outbound o on o.account_id = a.account_id;

create or replace view public.v_l5_cycle_reconciliation as
select cycle_id,
       pool_open,
       inflow_total,
       outflow_total,
       burn_total,
       pool_close,
       pool_open + inflow_total - outflow_total - burn_total as expected_close,
       reconciliation_drift,
       status
from l5_pool_cycles c;

create or replace view public.v_l5_pool_balance as
select coalesce(sum(
         case
           when bucket = 'incentive_pool'::text and (event_type = any (array['fast_burn_inflow'::text, 'flat_fee_inflow'::text, 'slash_inflow'::text, 'seed_topup'::text])) then amount
           else 0::numeric
         end), 0::numeric) - coalesce(sum(
         case
           when bucket = 'incentive_pool'::text and (event_type = any (array['validator_payout'::text, 'contributor_payout'::text])) then amount
           else 0::numeric
         end), 0::numeric) as incentive_pool_balance,
       coalesce(sum(
         case
           when bucket = 'burn_sink'::text then amount
           else 0::numeric
         end), 0::numeric) as burn_sink_total
from l5_credit_ledger;

-- ---------------------------------------------------------------------------
-- Row level security + policies
-- ---------------------------------------------------------------------------

alter table public.machines enable row level security;
alter table public.runs enable row level security;
alter table public.seed_bundles enable row level security;
alter table public.seed_payout_reports enable row level security;
alter table public.run_detail_bundles enable row level security;
alter table public.l5_accounts enable row level security;
alter table public.l5_machine_entitlements enable row level security;
alter table public.l5_credit_ledger enable row level security;
alter table public.l5_pool_cycles enable row level security;
alter table public.l5_validator_cycles enable row level security;
alter table public.l5_contributor_submissions enable row level security;
alter table public.l5_contributor_settlements enable row level security;
alter table public.l5_appeals enable row level security;
alter table public.l5_governance_votes enable row level security;
alter table public.l5_params enable row level security;
alter table public.l5_oracle_evaluations enable row level security;
alter table public.l5_nondelta_reviews enable row level security;
alter table public.l5_nondelta_band_values enable row level security;
alter table public.l5_admin_actions enable row level security;
alter table public.l5_auth_sessions enable row level security;
alter table public.l5_hub_action_log enable row level security;
alter table public.l5_account_controls enable row level security;
alter table public.l5_hub_anomaly_events enable row level security;
alter table public.l5_hub_network_lockouts enable row level security;
alter table public.l5_wallet_identities enable row level security;
alter table public.l5_pool_state_v31 enable row level security;
alter table public.l5_contribution_votes_v31 enable row level security;
alter table public.l5_lifetime_votes_v31 enable row level security;

-- Phase 0 bootstrap posture: anonymous clients may insert and read benchmark
-- and seed artifacts, but cannot update or delete them. The l5_* tables have
-- RLS enabled with NO policies on purpose: deny-by-default for API roles;
-- only privileged server-side functions touch them.
-- This is documented as a bootstrap convenience and must be tightened before
-- broad external tester rollout (see docs/specs/seed-organism-v0.1.md §10-11).

drop policy if exists "public insert machines" on public.machines;
create policy "public insert machines" on public.machines for insert to public with check (true);
drop policy if exists "public read machines" on public.machines;
create policy "public read machines" on public.machines for select to public using (true);
drop policy if exists "public insert runs" on public.runs;
create policy "public insert runs" on public.runs for insert to public with check (true);
drop policy if exists "public read runs" on public.runs;
create policy "public read runs" on public.runs for select to public using (true);
drop policy if exists seed_bundles_anon_insert on public.seed_bundles;
create policy seed_bundles_anon_insert on public.seed_bundles for insert to anon with check (true);
drop policy if exists seed_bundles_anon_select on public.seed_bundles;
create policy seed_bundles_anon_select on public.seed_bundles for select to anon using (true);
drop policy if exists seed_payout_reports_anon_insert on public.seed_payout_reports;
create policy seed_payout_reports_anon_insert on public.seed_payout_reports for insert to anon with check (true);
drop policy if exists seed_payout_reports_anon_select on public.seed_payout_reports;
create policy seed_payout_reports_anon_select on public.seed_payout_reports for select to anon using (true);
drop policy if exists run_detail_bundles_anon_insert on public.run_detail_bundles;
create policy run_detail_bundles_anon_insert on public.run_detail_bundles for insert to anon with check (true);
drop policy if exists run_detail_bundles_anon_select on public.run_detail_bundles;
create policy run_detail_bundles_anon_select on public.run_detail_bundles for select to anon using (true);

-- Sequence grants used by the anon insert paths
grant usage, select on sequence public.seed_bundles_id_seq to anon;
grant usage, select on sequence public.seed_bundles_id_seq to authenticated;
grant usage, select on sequence public.seed_payout_reports_id_seq to anon;
grant usage, select on sequence public.seed_payout_reports_id_seq to authenticated;
grant usage, select on sequence public.run_detail_bundles_id_seq to anon;
grant usage, select on sequence public.run_detail_bundles_id_seq to authenticated;
grant usage, select on sequence public.l5_hub_action_log_log_id_seq to anon;
grant usage, select on sequence public.l5_hub_action_log_log_id_seq to authenticated;
grant usage, select on sequence public.l5_hub_anomaly_events_anomaly_id_seq to anon;
grant usage, select on sequence public.l5_hub_anomaly_events_anomaly_id_seq to authenticated;
grant usage, select on sequence public.l5_pool_state_v31_id_seq to anon;
grant usage, select on sequence public.l5_pool_state_v31_id_seq to authenticated;

-- ---------------------------------------------------------------------------
-- Seed data (parameters wiped in the 2026-06-10 incident, restored here)
-- ---------------------------------------------------------------------------

insert into l5_params (key, value_numeric)
values
  ('fast_cycle_fee_default', 5),
  ('pool_floor', 500),
  ('validator_cap_pct', 0.40),
  ('burn_payout_pct', 0.02)
on conflict (key) do nothing;

insert into l5_nondelta_band_values (band, payout_credits)
values
  ('low', 0.50),
  ('medium', 1.50),
  ('high', 3.00),
  ('critical', 6.00)
on conflict (band) do nothing;
