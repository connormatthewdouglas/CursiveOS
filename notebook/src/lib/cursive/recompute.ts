import { independentConfirmations, type IndependenceWitness } from "./identity.ts";
import type { MachineAlias } from "./types.ts";

/**
 * Origin-side raw recompute — the missing G4 gate.
 *
 * CursiveRoot currently stores caller-attested hashes. This engine is what origin
 * must run: hash the immutable payload itself, require the expected artifacts,
 * reject replays, and count independent witnesses. It never sets payout_eligible.
 */

export const REQUIRED_ARTIFACT_KINDS = [
  "raw_metrics",
  "sysctl_dump",
  "harness_log",
  "signature",
] as const;

export type ArtifactKind = (typeof REQUIRED_ARTIFACT_KINDS)[number];

export type Artifact = {
  kind: ArtifactKind | string;
  sha256: string;
  bytes: number;
  /** Canonical bytes origin hashes. Missing payload = cannot recompute. */
  payload?: string | null;
  claimed_digest?: string | null;
};

export type ReplayIndexEntry = {
  bundle_hash: string;
  artifact_sha256s: string[];
};

export type RecomputeInput = {
  bundle_hash: string;
  variant_id: string;
  parent_variant_id: string;
  candidate_variant_id: string;
  claimed_metrics: Record<string, number | null>;
  expected_channels: string[];
  artifacts: Artifact[];
  witnesses: IndependenceWitness[];
  aliases: MachineAlias[];
  fleet_size: number;
  replay_index?: ReplayIndexEntry[];
};

export type RecomputeReport = {
  bundle_hash: string;
  digest: string | null;
  recompute_ok: boolean;
  replay_ok: boolean;
  independent_aggregation_ok: boolean;
  selection_truth_eligible: boolean;
  payout_eligible: false;
  reasons: string[];
  independent_count: number;
  required: number;
  hashed_kinds: string[];
};

function toHex(buf: ArrayBuffer) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return toHex(digest);
}

export async function recomputeBundle(input: RecomputeInput): Promise<RecomputeReport> {
  const reasons: string[] = [];
  const hashed_kinds: string[] = [];
  let digest: string | null = null;

  if (!input.bundle_hash?.trim()) reasons.push("bundle_hash_required");
  if (!input.parent_variant_id || !input.candidate_variant_id) {
    reasons.push("parent_and_candidate_required");
  } else if (input.parent_variant_id === input.candidate_variant_id) {
    reasons.push("parent_equals_candidate");
  }

  for (const channel of input.expected_channels) {
    if (!(channel in input.claimed_metrics) || input.claimed_metrics[channel] == null) {
      reasons.push(`channel_missing:${channel}`);
    }
  }

  const byKind = new Map(input.artifacts.map((a) => [a.kind, a]));
  for (const kind of REQUIRED_ARTIFACT_KINDS) {
    if (!byKind.has(kind)) reasons.push(`artifact_missing:${kind}`);
  }

  const canonicalParts: string[] = [];
  let hashMismatch = false;
  let payloadMissing = false;

  for (const artifact of input.artifacts) {
    if (!artifact.payload) {
      payloadMissing = true;
      reasons.push(`payload_missing:${artifact.kind}`);
      continue;
    }
    const computed = await sha256Hex(artifact.payload);
    hashed_kinds.push(artifact.kind);
    canonicalParts.push(`${artifact.kind}:${computed}`);
    if (artifact.sha256 && artifact.sha256 !== computed) {
      hashMismatch = true;
      reasons.push(`hash_mismatch:${artifact.kind}`);
    }
    if (artifact.claimed_digest && artifact.claimed_digest !== computed) {
      hashMismatch = true;
      reasons.push(`caller_digest_untrusted:${artifact.kind}`);
    }
  }

  if (canonicalParts.length) {
    digest = await sha256Hex(canonicalParts.sort().join("|"));
    if (input.bundle_hash && digest !== input.bundle_hash && input.artifacts.every((a) => a.payload)) {
      // bundle_hash must equal origin digest of sorted kind:sha pairs
      reasons.push("bundle_hash_does_not_match_origin_digest");
      hashMismatch = true;
    }
  }

  const recompute_ok = !payloadMissing && !hashMismatch && hashed_kinds.length === REQUIRED_ARTIFACT_KINDS.length;

  const seen = (input.replay_index ?? []).some((row) => {
    if (row.bundle_hash === input.bundle_hash) return true;
    const a = [...row.artifact_sha256s].sort().join(",");
    const b = [...input.artifacts.map((x) => x.sha256)].sort().join(",");
    return a === b && a.length > 0;
  });
  const replay_ok = !seen;
  if (seen) reasons.push("replay_detected");

  const independence = independentConfirmations(input.witnesses, input.aliases, input.fleet_size);
  if (!independence.ok) reasons.push("independent_aggregation_short");

  const selection_truth_eligible =
    recompute_ok && replay_ok && independence.ok && !reasons.includes("parent_equals_candidate");

  return {
    bundle_hash: input.bundle_hash,
    digest,
    recompute_ok,
    replay_ok,
    independent_aggregation_ok: independence.ok,
    selection_truth_eligible,
    payout_eligible: false,
    reasons,
    independent_count: independence.independent_count,
    required: independence.required,
    hashed_kinds,
  };
}
