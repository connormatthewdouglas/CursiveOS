import type { MeasurementRequest, RequestStatus, SelectionScope, TrustScope } from "./types";

const TRUST_OK: TrustScope[] = [
  "simulated_not_payout_eligible",
  "observe_only_not_payout_eligible",
];

const LINUX_SELECTION: SelectionScope[] = [
  "linux_bare_metal",
  "linux_founder_fleet",
  "linux_observe_only",
];

export type EnqueueDraft = {
  request_key: string;
  parent_variant_id: string;
  candidate_variant_id: string;
  cycle_id: number;
  selection_scope: string;
  trust_scope: string;
  requested_by: string;
  notes: string;
  reward_sats_placeholder?: number;
  payout_eligible?: boolean;
};

export type EnqueueResult =
  | { ok: true; request: MeasurementRequest }
  | { ok: false; reasons: string[] };

export function validateEnqueue(draft: EnqueueDraft): string[] {
  const reasons: string[] = [];
  if (!draft.request_key?.trim()) reasons.push("request_key_required");
  if (!draft.parent_variant_id?.trim()) reasons.push("parent_required");
  if (!draft.candidate_variant_id?.trim()) reasons.push("candidate_required");
  if (
    draft.parent_variant_id &&
    draft.candidate_variant_id &&
    draft.parent_variant_id === draft.candidate_variant_id
  ) {
    reasons.push("parent_equals_candidate");
  }
  if (!TRUST_OK.includes(draft.trust_scope as TrustScope)) {
    reasons.push("trust_scope_must_be_simulated_or_observe_only");
  }
  if (!LINUX_SELECTION.includes(draft.selection_scope as SelectionScope)) {
    reasons.push("selection_scope_must_be_linux");
  }
  if (draft.payout_eligible) reasons.push("payout_eligible_must_be_false");
  if ((draft.reward_sats_placeholder ?? 0) < 0) reasons.push("reward_cannot_be_negative");
  if (!Number.isInteger(draft.cycle_id) || draft.cycle_id < 0) {
    reasons.push("cycle_id_invalid");
  }
  return reasons;
}

export function enqueueLocal(
  draft: EnqueueDraft,
  nowIso: string,
  existingKeys: string[],
): EnqueueResult {
  const reasons = validateEnqueue(draft);
  if (existingKeys.includes(draft.request_key)) reasons.push("request_key_duplicate");
  if (reasons.length) return { ok: false, reasons };

  const request: MeasurementRequest = {
    request_id: `local-${draft.request_key}`,
    request_key: draft.request_key,
    status: "open",
    parent_variant_id: draft.parent_variant_id,
    candidate_variant_id: draft.candidate_variant_id,
    cycle_id: draft.cycle_id,
    selection_scope: draft.selection_scope,
    trust_scope: draft.trust_scope,
    reward_sats_placeholder: draft.reward_sats_placeholder ?? 0,
    requested_by: draft.requested_by || "local-operator",
    notes: draft.notes || "Local draft. Not written to CursiveRoot.",
    created_at: nowIso,
    updated_at: nowIso,
  };
  return { ok: true, request };
}

const RANK: Record<string, number> = {
  open: 0,
  claimed: 1,
  running: 2,
  planned: 3,
  complete: 4,
  failed: 5,
  upload_failed: 5,
  ineligible: 5,
  cancelled: 6,
};

export function statusRank(status: string) {
  return RANK[status] ?? 9;
}

export function canClaim(request: MeasurementRequest, platform: string) {
  if (request.status !== "open") return { ok: false, reason: "request_not_open" };
  if (platform !== "linux") return { ok: false, reason: "linux_bare_metal_only" };
  if (!LINUX_SELECTION.includes(request.selection_scope as SelectionScope)) {
    return { ok: false, reason: "selection_scope_rejected" };
  }
  return { ok: true as const };
}

export function nextJobStatus(from: RequestStatus, event: "claim" | "start" | "complete" | "fail") {
  const table: Record<string, Partial<Record<typeof event, RequestStatus>>> = {
    open: { claim: "claimed" },
    claimed: { start: "running", fail: "failed" },
    running: { complete: "complete", fail: "failed" },
  };
  return table[from]?.[event] ?? null;
}
