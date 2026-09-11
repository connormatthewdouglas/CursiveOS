import type {
  CursiveSnapshot,
  IdentityKey,
  Machine,
  MachineAlias,
  MachineCapability,
  MeasurementJob,
  MeasurementRequest,
  PayoutReport,
  RawArtifact,
  RunRow,
  SeedBundle,
  TrustEvaluation,
} from "./types";
import { FALLBACK_SNAPSHOT } from "./snapshot";

const URL = "https://iovvktpuoinmjdgfxgvm.supabase.co/rest/v1";
const KEY = "sb_publishable_4WefsfMl0sNNo9O2c_lxnA_q2VQ01jn";
const HEADERS = { apikey: KEY, Authorization: `Bearer ${KEY}` };

async function q<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${URL}/${path}`, { headers: HEADERS, ...init });
  if (!res.ok) throw new Error(`${res.status} ${path}`);
  return res.json() as Promise<T>;
}

async function count(path: string): Promise<number> {
  const res = await fetch(`${URL}/${path}`, {
    headers: { ...HEADERS, Prefer: "count=exact", Range: "0-0" },
  });
  if (!res.ok) throw new Error(`${res.status} count ${path}`);
  const range = res.headers.get("content-range");
  const total = range?.split("/")[1];
  const n = Number(total);
  return Number.isFinite(n) ? n : 0;
}

export async function fetchLiveSnapshot(timeoutMs = 9000): Promise<CursiveSnapshot> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const [
      run_count,
      machines,
      aliases,
      requests,
      jobs,
      capabilities,
      bundles,
      payouts,
      trust,
      identity_keys,
      runs,
      artifacts,
    ] = await Promise.all([
      count("runs?select=id"),
      q<Machine[]>("machines?select=machine_id,cpu,gpu,os&order=created_at.desc"),
      q<MachineAlias[]>("machine_aliases?select=alias,machine_id,alias_kind"),
      q<MeasurementRequest[]>(
        "measurement_requests?select=request_id,request_key,status,parent_variant_id,candidate_variant_id,cycle_id,selection_scope,trust_scope,reward_sats_placeholder,requested_by,notes,created_at,updated_at&order=priority.desc,created_at.asc&limit=24",
      ),
      q<MeasurementJob[]>(
        "measurement_jobs?select=job_id,request_id,machine_id,status,result_bundle_hash,failure_reason,claimed_at,started_at,finished_at,last_heartbeat_at&order=claimed_at.desc&limit=24",
      ),
      q<MachineCapability[]>(
        "machine_capabilities?select=machine_id,daemon_version,platform,os_name,kernel,cpu,gpu,selection_scopes,last_seen_at,capabilities&order=last_seen_at.desc&limit=24",
      ),
      q<SeedBundle[]>(
        "seed_bundles?select=variant_id,confidence,fitness_score,reason,machine_id,decision,created_at,cycle_id,contributor_id,bundle_hash,result_bundle&order=created_at.desc&limit=24",
      ),
      q<PayoutReport[]>(
        "seed_payout_reports?select=cycle_id,simulated_revenue_sats,contributor_count,report,created_at&order=created_at.desc&limit=8",
      ),
      q<TrustEvaluation[]>(
        "os0_trust_evaluations?select=bundle_hash,variant_id,decision,machine_id,gate_status,recompute_ok,signed_identity_ok,replay_ok,independent_aggregation_ok,selection_truth_eligible,payout_eligible,evaluated_at,reasons&order=evaluated_at.desc&limit=12",
      ),
      q<IdentityKey[]>(
        "os0_identity_keys?select=identity_public_key,machine_id,key_scheme,key_status,trust_scope,first_seen_at,last_seen_at&order=last_seen_at.desc&limit=16",
      ),
      q<RunRow[]>(
        "runs?select=machine_id,preset_version,network_delta_pct,coldstart_delta_pct,power_delta_w,created_at&order=created_at.desc&limit=24",
      ),
      q<RawArtifact[]>(
        "os0_raw_artifact_index?select=artifact_kind,artifact_sha256,artifact_uri,bundle_hash,variant_id,machine_id,decision,identity_public_key,first_seen_at&order=first_seen_at.desc&limit=40",
      ),
    ]);
    const accepted = bundles.filter((b) => b.decision === "accepted");
    return {
      fetched_at: new Date().toISOString(),
      source: "live",
      run_count,
      machines,
      aliases,
      requests,
      jobs,
      capabilities,
      accepted,
      bundles,
      artifacts,
      payouts,
      trust,
      identity_keys,
      runs,
    };
  } finally {
    clearTimeout(timer);
  }
}

export async function loadSnapshot(): Promise<CursiveSnapshot> {
  try {
    return await fetchLiveSnapshot();
  } catch {
    return { ...FALLBACK_SNAPSHOT, fetched_at: new Date().toISOString() };
  }
}
