export type TrustScope =
  | "simulated_not_payout_eligible"
  | "observe_only_not_payout_eligible";

export type SelectionScope =
  | "linux_bare_metal"
  | "linux_founder_fleet"
  | "linux_observe_only"
  | "windows_wsl_observe_only";

export type RequestStatus =
  | "open"
  | "claimed"
  | "running"
  | "planned"
  | "complete"
  | "failed"
  | "upload_failed"
  | "ineligible"
  | "cancelled";

export type JobStatus = RequestStatus;

export type KeyStatus = "local_sim" | "active" | "revoked" | "superseded";

export type RailMode = "internal_credits" | "crypto_testnet" | "crypto_mainnet";

export type TransferStatus =
  | "queued"
  | "submitted"
  | "confirmed"
  | "failed"
  | "blocked";

export type StreamType = "current" | "lifetime" | "redistribution";

export type Machine = {
  machine_id: string;
  cpu: string | null;
  gpu: string | null;
  os: string | null;
};

export type MachineAlias = {
  alias: string;
  machine_id: string;
  alias_kind?: string | null;
};

export type MeasurementRequest = {
  request_id: string;
  request_key: string;
  status: RequestStatus;
  parent_variant_id: string;
  candidate_variant_id: string;
  cycle_id: number;
  selection_scope: SelectionScope | string;
  trust_scope: TrustScope | string;
  reward_sats_placeholder: number | null;
  requested_by: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string | null;
};

export type MeasurementJob = {
  job_id: string;
  request_id: string;
  machine_id: string;
  status: JobStatus;
  result_bundle_hash: string | null;
  failure_reason: string | null;
  claimed_at: string | null;
  started_at: string | null;
  finished_at: string | null;
  last_heartbeat_at: string | null;
};

export type MachineCapability = {
  machine_id: string;
  daemon_version: string | null;
  platform: string | null;
  os_name: string | null;
  kernel: string | null;
  cpu: string | null;
  gpu: string | null;
  selection_scopes: string[] | null;
  last_seen_at: string | null;
};

export type BundleMetrics = {
  idle_watts?: number | null;
  coldstart_ms?: number | null;
  network_mbps?: number | null;
  sustained_tokps?: number | null;
  memory_refault_s?: number | null;
};

export type SeedBundle = {
  variant_id: string;
  confidence: number | null;
  fitness_score: number | null;
  reason: string | null;
  machine_id: string | null;
  decision?: string | null;
  created_at: string;
  cycle_id?: string | number | null;
  contributor_id?: string | null;
  bundle_hash?: string | null;
  result_bundle?: {
    metrics?: {
      variant?: BundleMetrics;
      baseline?: BundleMetrics;
      comparison?: Record<string, unknown>;
    } | null;
  } | null;
};

export type RawArtifact = {
  artifact_kind: string;
  artifact_sha256: string | null;
  artifact_uri: string | null;
  bundle_hash: string | null;
  variant_id: string | null;
  machine_id: string | null;
  decision: string | null;
  identity_public_key: string | null;
  first_seen_at: string | null;
};


export type PayoutContributor = {
  contributor_id: string;
  cycle_fitness: number;
  lifetime_fitness: number;
  total_payout_sats: number;
  lifetime_payout_sats: number;
  current_cycle_payout_sats: number;
};

export type PayoutReport = {
  cycle_id: string;
  simulated_revenue_sats: number;
  contributor_count: number;
  created_at: string;
  report: {
    contributors?: PayoutContributor[];
    lifetime_share?: number;
    current_cycle_share?: number;
    schema_version?: string;
    payout_report_hash?: string;
  } | null;
};

export type TrustEvaluation = {
  bundle_hash: string;
  variant_id: string | null;
  decision: string | null;
  machine_id: string | null;
  gate_status: string | null;
  recompute_ok: boolean | null;
  signed_identity_ok: boolean | null;
  replay_ok: boolean | null;
  independent_aggregation_ok: boolean | null;
  selection_truth_eligible: boolean | null;
  payout_eligible: boolean | null;
  evaluated_at: string | null;
  reasons?: string[] | null;
};

export type IdentityKey = {
  identity_public_key: string;
  machine_id: string;
  key_scheme: string;
  key_status: KeyStatus | string;
  trust_scope: TrustScope | string;
  first_seen_at: string;
  last_seen_at: string;
};

export type RunRow = {
  machine_id: string;
  preset_version: string | null;
  network_delta_pct: number | null;
  coldstart_delta_pct: number | null;
  power_delta_w: number | null;
  created_at: string;
};

export type CursiveSnapshot = {
  fetched_at: string;
  source: "live" | "snapshot";
  run_count: number;
  machines: Machine[];
  aliases: MachineAlias[];
  requests: MeasurementRequest[];
  jobs: MeasurementJob[];
  capabilities: MachineCapability[];
  accepted: SeedBundle[];
  bundles: SeedBundle[];
  artifacts: RawArtifact[];
  payouts: PayoutReport[];
  trust: TrustEvaluation[];
  identity_keys: IdentityKey[];
  runs: RunRow[];
};

export type Accrual = {
  accrual_id: string;
  contributor_wallet: string;
  cycle_id: number;
  stream_type: StreamType;
  amount_sats: number;
  created_at: string;
  claim_deadline: string;
  claimed_at: string | null;
  claim_tx_id: string | null;
};

export type TransferIntent = {
  payout_id: string;
  accrual_id: string;
  rail_mode: RailMode;
  destination_wallet: string;
  amount_sats: number;
  tx_status: TransferStatus;
  tx_hash: string | null;
  retries: number;
  last_error: string | null;
  blocked_reason: string | null;
  created_at: string;
};

export type MergeEvent = {
  contributor_wallet: string;
  variant_id: string;
  fitness_delta: number;
  prior_merge_count: number;
};

export type LifetimeRow = {
  contributor_wallet: string;
  fitness: number;
};
