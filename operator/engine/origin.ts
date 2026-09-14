/**
 * Fail-closed origin adapter.
 *
 * This console may GET live CursiveRoot. It must never POST/PATCH/PUT/DELETE.
 * payout_eligible cannot be flipped from here. The publishable anon key is a
 * read path, not a write path — treat any mutate as a bug even if RLS is loose.
 */

export const ORIGIN_WRITE_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

export const ORIGIN_TABLES = [
  "measurement_requests",
  "measurement_jobs",
  "machine_capabilities",
  "os0_identity_keys",
  "os0_trust_evaluations",
  "os0_raw_artifact_index",
  "seed_bundles",
  "seed_payout_reports",
  "runs",
] as const;

export type OriginTable = (typeof ORIGIN_TABLES)[number] | string;

export type OriginAttempt = {
  method: string;
  table: OriginTable;
  payout_eligible?: boolean;
  using_true?: boolean;
};

export type OriginDecision = {
  allowed: boolean;
  reasons: string[];
};

export function authorizeOriginRequest(attempt: OriginAttempt): OriginDecision {
  const reasons: string[] = [];
  const method = attempt.method.toUpperCase();

  if (ORIGIN_WRITE_METHODS.has(method)) {
    reasons.push("origin_writes_disabled_in_operator_console");
  }
  if (attempt.payout_eligible) {
    reasons.push("payout_eligible_hard_false");
  }
  if (attempt.using_true && method !== "GET") {
    reasons.push("using_true_denied");
  }
  if (method !== "GET" && method !== "HEAD" && method !== "OPTIONS" && !ORIGIN_WRITE_METHODS.has(method)) {
    reasons.push(`method_not_allowed:${method}`);
  }

  return { allowed: reasons.length === 0, reasons };
}

export async function originMutate(
  attempt: OriginAttempt,
  fetchImpl?: typeof fetch,
): Promise<OriginDecision> {
  const decision = authorizeOriginRequest(attempt);
  if (!decision.allowed) return decision;
  // GET is the only allowed path; this helper never sends a body.
  if (fetchImpl) {
    // Intentionally unused: a future read-through can pass fetch. Writes never reach it.
  }
  return decision;
}
