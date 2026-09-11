import type { IdentityKey, KeyStatus, TrustEvaluation, TrustScope } from "./types";

export const PAYOUT_ELIGIBLE_HARD_FALSE = false as const;

export const PRODUCTION_GATES = [
  "recompute",
  "signed_identity",
  "replay",
  "independent_aggregation",
  "hardware_wallet_independence",
  "key_rotation_revocation",
] as const;

export type GateName = (typeof PRODUCTION_GATES)[number];

export type TrustInputs = {
  recompute_ok: boolean;
  signed_identity_ok: boolean;
  replay_ok: boolean;
  independent_aggregation_ok: boolean;
  key_status: KeyStatus | string;
  trust_scope: TrustScope | string;
  linux_bare_metal: boolean;
  hardware_wallet_independent: boolean;
  key_not_revoked: boolean;
};

export type EvaluatedTrust = {
  gate_status: string;
  selection_truth_eligible: boolean;
  payout_eligible: false;
  reasons: string[];
  checks: Record<GateName, boolean>;
};

export function evaluateTrust(input: TrustInputs): EvaluatedTrust {
  const reasons: string[] = [];
  const checks: Record<GateName, boolean> = {
    recompute: input.recompute_ok,
    signed_identity: input.signed_identity_ok && input.key_status !== "local_sim",
    replay: input.replay_ok,
    independent_aggregation: input.independent_aggregation_ok,
    hardware_wallet_independence: input.hardware_wallet_independent,
    key_rotation_revocation: input.key_not_revoked && input.key_status !== "revoked",
  };

  if (!input.linux_bare_metal) reasons.push("selection_scope_not_linux_bare_metal");
  if (input.key_status === "local_sim") reasons.push("identity_is_local_sim");
  if (input.key_status === "revoked") reasons.push("identity_key_revoked");
  if (input.trust_scope !== "simulated_not_payout_eligible" &&
      input.trust_scope !== "observe_only_not_payout_eligible") {
    reasons.push("unrecognized_trust_scope");
  }
  for (const [name, ok] of Object.entries(checks)) {
    if (!ok) reasons.push(`gate_fail:${name}`);
  }

  const selection =
    input.linux_bare_metal &&
    checks.recompute &&
    checks.signed_identity &&
    checks.replay &&
    checks.independent_aggregation &&
    checks.hardware_wallet_independence &&
    checks.key_rotation_revocation;

  let gate_status = "pass";
  if (!checks.recompute) gate_status = "blocked_recompute_mismatch";
  else if (!checks.signed_identity) gate_status = "blocked_unsigned_identity";
  else if (!checks.replay) gate_status = "blocked_replay";
  else if (!checks.independent_aggregation) gate_status = "awaiting_independent_aggregation";
  else if (!checks.hardware_wallet_independence) gate_status = "blocked_sybil_independence";
  else if (!checks.key_rotation_revocation) gate_status = "blocked_revoked_key";
  else if (!selection) gate_status = "blocked";

  return {
    gate_status,
    selection_truth_eligible: Boolean(selection),
    payout_eligible: PAYOUT_ELIGIBLE_HARD_FALSE,
    reasons,
    checks,
  };
}

export function productionMoneyReady(rows: TrustEvaluation[]) {
  if (!rows.length) return false;
  return rows.every(
    (r) =>
      r.recompute_ok &&
      r.signed_identity_ok &&
      r.replay_ok &&
      r.independent_aggregation_ok &&
      r.selection_truth_eligible &&
      r.payout_eligible === true,
  );
}

export function rotateKey(
  keys: IdentityKey[],
  machineId: string,
  oldPublicKey: string,
  newPublicKey: string,
  nowIso: string,
): { ok: true; keys: IdentityKey[] } | { ok: false; reason: string } {
  if (!newPublicKey || newPublicKey === oldPublicKey) {
    return { ok: false, reason: "new_key_required" };
  }
  if (keys.some((k) => k.identity_public_key === newPublicKey)) {
    return { ok: false, reason: "key_already_registered" };
  }
  const current = keys.find((k) => k.identity_public_key === oldPublicKey);
  if (!current) return { ok: false, reason: "unknown_current_key" };
  if (current.machine_id !== machineId) return { ok: false, reason: "machine_mismatch" };
  if (current.key_status === "revoked") return { ok: false, reason: "cannot_rotate_revoked" };

  const next = keys.map((k) =>
    k.identity_public_key === oldPublicKey
      ? { ...k, key_status: "superseded" as const, last_seen_at: nowIso }
      : k,
  );
  next.push({
    identity_public_key: newPublicKey,
    machine_id: machineId,
    key_scheme: "cursiveos-ed25519-sshsig-v0.2",
    key_status: "active",
    trust_scope: "simulated_not_payout_eligible",
    first_seen_at: nowIso,
    last_seen_at: nowIso,
  });
  return { ok: true, keys: next };
}

export function revokeKey(
  keys: IdentityKey[],
  publicKey: string,
  nowIso: string,
): { ok: true; keys: IdentityKey[] } | { ok: false; reason: string } {
  const current = keys.find((k) => k.identity_public_key === publicKey);
  if (!current) return { ok: false, reason: "unknown_key" };
  if (current.key_status === "revoked") return { ok: false, reason: "already_revoked" };
  return {
    ok: true,
    keys: keys.map((k) =>
      k.identity_public_key === publicKey
        ? { ...k, key_status: "revoked" as const, last_seen_at: nowIso }
        : k,
    ),
  };
}

export function signatureAcceptable(key: IdentityKey | undefined) {
  if (!key) return false;
  if (key.key_status === "revoked" || key.key_status === "superseded") return false;
  if (key.key_status === "local_sim") return false;
  return key.key_status === "active";
}

export function liveGateSummary(rows: TrustEvaluation[]) {
  const total = rows.length;
  const count = (fn: (r: TrustEvaluation) => boolean) => rows.filter(fn).length;
  return {
    total,
    recompute: count((r) => r.recompute_ok === true),
    signed_identity: count((r) => r.signed_identity_ok === true),
    replay: count((r) => r.replay_ok === true),
    independent_aggregation: count((r) => r.independent_aggregation_ok === true),
    selection_truth: count((r) => r.selection_truth_eligible === true),
    payout_true: count((r) => r.payout_eligible === true),
  };
}
