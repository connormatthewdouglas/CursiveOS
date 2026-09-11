/**
 * Identity-gated write policy. Replaces USING(true) on capabilities and jobs.
 * Executable here so the operator can see what CursiveRoot RLS still allows.
 */

export type PolicyTable =
  | "measurement_requests"
  | "measurement_jobs"
  | "machine_capabilities"
  | "os0_identity_keys"
  | "os0_trust_evaluations"
  | "l5_accruals";

export type PolicyAction = "insert" | "update" | "delete" | "select";

export type PolicyActor = {
  kind: "anon" | "claimed_machine" | "proposer" | "service_role";
  machine_id?: string | null;
  key_status?: string | null;
  identity_public_key?: string | null;
};

export type WriteAttempt = {
  table: PolicyTable;
  action: PolicyAction;
  actor: PolicyActor;
  row_machine_id?: string | null;
  fields?: string[];
};

export type PolicyDecision = {
  ok: boolean;
  reason: string;
  using_true: false;
};

const ANON_REQUEST_UPDATE = new Set(["status", "updated_at"]);

export function authorizeWrite(attempt: WriteAttempt): PolicyDecision {
  const { table, action, actor } = attempt;

  if (action === "select") return { ok: true, reason: "read_ok", using_true: false };

  if (actor.kind === "service_role") {
    return { ok: true, reason: "service_role_privileged", using_true: false };
  }

  if (table === "l5_accruals" || table === "os0_trust_evaluations") {
    return { ok: false, reason: "ledger_and_trust_are_origin_written", using_true: false };
  }

  if (table === "measurement_requests") {
    if (action === "insert") {
      if (actor.kind === "proposer" && actor.key_status === "active") {
        return { ok: true, reason: "signed_proposer_enqueue", using_true: false };
      }
      return { ok: false, reason: "enqueue_is_privileged", using_true: false };
    }
    if (action === "update") {
      const fields = attempt.fields ?? [];
      if (fields.length && fields.every((f) => ANON_REQUEST_UPDATE.has(f))) {
        return { ok: true, reason: "anon_may_touch_status_and_updated_at", using_true: false };
      }
      return { ok: false, reason: "anon_cannot_mutate_request_body", using_true: false };
    }
    return { ok: false, reason: "request_delete_forbidden", using_true: false };
  }

  if (table === "measurement_jobs" || table === "machine_capabilities") {
    if (actor.kind !== "claimed_machine") {
      return { ok: false, reason: "identity_gated_machine_write", using_true: false };
    }
    if (actor.key_status !== "active") {
      return { ok: false, reason: "key_must_be_active", using_true: false };
    }
    if (!actor.machine_id || !attempt.row_machine_id || actor.machine_id !== attempt.row_machine_id) {
      return { ok: false, reason: "cannot_cross_write_other_machine", using_true: false };
    }
    return { ok: true, reason: "own_machine_with_active_key", using_true: false };
  }

  if (table === "os0_identity_keys") {
    if (action === "insert" && actor.kind === "claimed_machine" && actor.key_status === "active") {
      return { ok: true, reason: "machine_may_register_rotation", using_true: false };
    }
    return { ok: false, reason: "identity_table_is_origin_or_self_rotate", using_true: false };
  }

  return { ok: false, reason: "default_deny", using_true: false };
}

/** Live CursiveRoot residual: USING(true) on capabilities + jobs. Named so we cannot forget it. */
export const LIVE_USING_TRUE_HOLES = ["machine_capabilities", "measurement_jobs"] as const;
