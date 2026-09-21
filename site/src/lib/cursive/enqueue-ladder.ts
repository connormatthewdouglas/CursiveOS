/**
 * Submission enqueue ladder — local rehearsal of the public wire path.
 *
 * self-clean on the submitter machine → exactly one foreign confirmer →
 * public work queue eligible. Identity fail-closed. payout_eligible hard-false.
 * This module never writes live CursiveRoot.
 */

export type LadderStage =
  | "draft"
  | "self_pending"
  | "self_clean"
  | "foreign_pending"
  | "public_eligible"
  | "refused";

export type LadderKind = "idea" | "sensor";

export type LadderRecord = {
  id: string;
  kind: LadderKind;
  stage: LadderStage;
  submitter_machine_id: string | null;
  confirmer_machine_id: string | null;
  refused_reason: string | null;
  payout_eligible: false;
};

export type LadderResult =
  | { ok: true; record: LadderRecord }
  | { ok: false; record: LadderRecord; reason: string };

const ADVANCE: Record<Exclude<LadderStage, "public_eligible" | "refused">, LadderStage> = {
  draft: "self_pending",
  self_pending: "self_clean",
  self_clean: "foreign_pending",
  foreign_pending: "public_eligible",
};

function refuse(record: LadderRecord, reason: string): LadderResult {
  const next: LadderRecord = {
    ...record,
    stage: "refused",
    refused_reason: reason,
    payout_eligible: false,
  };
  return { ok: false, record: next, reason };
}

export function createLadderDraft(input: {
  id: string;
  kind: LadderKind;
  submitter_machine_id?: string | null;
}): LadderRecord {
  return {
    id: input.id,
    kind: input.kind,
    stage: "draft",
    submitter_machine_id: input.submitter_machine_id?.trim() || null,
    confirmer_machine_id: null,
    refused_reason: null,
    payout_eligible: false,
  };
}

/** draft → self_pending. Requires a non-empty submitter machine id. */
export function submitToWire(
  record: LadderRecord,
  submitter_machine_id: string,
): LadderResult {
  if (record.stage === "refused" || record.stage === "public_eligible") {
    return refuse(record, "terminal_stage");
  }
  if (record.stage !== "draft") {
    return refuse(record, "submit_requires_draft");
  }
  const mid = submitter_machine_id.trim();
  if (!mid) {
    return refuse(record, "submitter_identity_required");
  }
  return {
    ok: true,
    record: {
      ...record,
      stage: "self_pending",
      submitter_machine_id: mid,
      confirmer_machine_id: null,
      refused_reason: null,
      payout_eligible: false,
    },
  };
}

/** self_pending → self_clean. Actor must be the submitter. */
export function markSelfClean(record: LadderRecord, actor_machine_id: string): LadderResult {
  if (record.stage === "refused" || record.stage === "public_eligible") {
    return refuse(record, "terminal_stage");
  }
  if (record.stage !== "self_pending") {
    return refuse(record, "self_clean_requires_self_pending");
  }
  const actor = actor_machine_id.trim();
  const submitter = record.submitter_machine_id?.trim() || "";
  if (!submitter || !actor) {
    return refuse(record, "submitter_identity_required");
  }
  if (actor !== submitter) {
    return refuse(record, "self_clean_must_be_submitter");
  }
  return {
    ok: true,
    record: {
      ...record,
      stage: "self_clean",
      refused_reason: null,
      payout_eligible: false,
    },
  };
}

/**
 * After self_clean, open the foreign confirmation slot
 * (self_clean → foreign_pending).
 */
export function openForeignSlot(record: LadderRecord): LadderResult {
  if (record.stage === "refused" || record.stage === "public_eligible") {
    return refuse(record, "terminal_stage");
  }
  if (record.stage !== "self_clean") {
    return refuse(record, "foreign_slot_requires_self_clean");
  }
  return {
    ok: true,
    record: {
      ...record,
      stage: "foreign_pending",
      refused_reason: null,
      payout_eligible: false,
    },
  };
}

/** foreign_pending → public_eligible. Confirmer must differ from submitter. */
export function confirmForeign(
  record: LadderRecord,
  confirmer_machine_id: string,
): LadderResult {
  if (record.stage === "refused" || record.stage === "public_eligible") {
    return refuse(record, "terminal_stage");
  }
  if (record.stage !== "foreign_pending") {
    return refuse(record, "confirm_requires_foreign_pending");
  }
  const confirmer = confirmer_machine_id.trim();
  const submitter = record.submitter_machine_id?.trim() || "";
  if (!submitter) {
    return refuse(record, "submitter_identity_required");
  }
  if (!confirmer) {
    return refuse(record, "confirmer_identity_required");
  }
  if (confirmer === submitter) {
    return refuse(record, "foreign_confirmer_must_differ");
  }
  return {
    ok: true,
    record: {
      ...record,
      stage: "public_eligible",
      confirmer_machine_id: confirmer,
      refused_reason: null,
      payout_eligible: false,
    },
  };
}

export function refuseLadder(record: LadderRecord, reason: string): LadderResult {
  const msg = reason.trim() || "refused";
  return refuse(record, msg);
}

/**
 * Advance one legal step. Optional actor is required for identity-gated steps
 * (submit, self-clean, foreign confirm). self_clean → foreign_pending needs no actor.
 */
export function advanceLadder(
  record: LadderRecord,
  opts?: { actor_machine_id?: string },
): LadderResult {
  if (record.stage === "refused" || record.stage === "public_eligible") {
    return refuse(record, "terminal_stage");
  }
  const actor = opts?.actor_machine_id ?? "";
  switch (record.stage) {
    case "draft":
      return submitToWire(record, actor);
    case "self_pending":
      return markSelfClean(record, actor);
    case "self_clean":
      return openForeignSlot(record);
    case "foreign_pending":
      return confirmForeign(record, actor);
    default: {
      const _exhaustive: never = record.stage;
      return refuse(record, `unknown_stage:${_exhaustive}`);
    }
  }
}

export function nextStage(stage: LadderStage): LadderStage | null {
  if (stage === "public_eligible" || stage === "refused") return null;
  return ADVANCE[stage];
}

export function isPublicEligible(record: LadderRecord): boolean {
  return record.stage === "public_eligible" && record.payout_eligible === false;
}

/** Enqueue stub downloaded on "Submit to the wire". Never a live DB write. */
export function buildEnqueueStub(input: {
  kind: LadderKind;
  id: string;
  title: string;
  submitter_machine_id: string;
  body: Record<string, unknown>;
}): string {
  return (
    JSON.stringify(
      {
        schema_version: "cursiveos.enqueue-stub.v0.1",
        kind: input.kind,
        id: input.id,
        title: input.title,
        ladder_stage: "self_pending" as LadderStage,
        submitter_machine_id: input.submitter_machine_id,
        live_ledger_write: false,
        awaits: "signed_proposer_rail",
        payout_eligible: false,
        trust_scope: "simulated_not_payout_eligible",
        note: "Local browser stub only. Anon INSERT on measurement_requests stays denied.",
        body: input.body,
      },
      null,
      2,
    ) + "\n"
  );
}
