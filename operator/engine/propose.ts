import { enqueueLocal, type EnqueueDraft } from "./queue.ts";
import type { MeasurementRequest } from "./types.ts";

/**
 * Autonomous proposer (G3) — operator-side.
 *
 * The audited sysctl library is mined out of its first two knobs (honest nulls).
 * Default selection is QD-archive grounded. Library knobs remain opt-in and
 * never include pagecluster / vfs_cache cousins. Auto-enqueue still requires a
 * privileged identity; this console never writes live CursiveRoot.
 */

export type KnobChannel = "memory" | "sustained" | "network" | "coldstart" | "idle";

export type Knob = {
  slug: string;
  key: string;
  value: string;
  channel: KnobChannel;
  priority: number;
  hypothesis: string;
  mined_out: boolean;
};

export const MINED_OUT_SLUGS = new Set(["pagecluster0", "vfscache50"]);
export const MINED_OUT_KEYS = new Set(["vm.page-cluster", "vm.vfs_cache_pressure"]);

export const KNOB_LIBRARY: Knob[] = [
  {
    slug: "pagecluster0",
    key: "vm.page-cluster",
    value: "0",
    channel: "memory",
    priority: 100,
    mined_out: true,
    hypothesis: "Retired. Cycle 5 honest null on founder hardware.",
  },
  {
    slug: "vfscache50",
    key: "vm.vfs_cache_pressure",
    value: "50",
    channel: "memory",
    priority: 80,
    mined_out: true,
    hypothesis: "Retired. Cycle 6 honest null / inconclusive.",
  },
  {
    slug: "watermark200",
    key: "vm.watermark_scale_factor",
    value: "200",
    channel: "memory",
    priority: 70,
    mined_out: false,
    hypothesis:
      "Raising watermark_scale_factor (10->200) starts reclaim earlier. Library leftover — not QD-grounded.",
  },
  {
    slug: "dirtyexpire1500",
    key: "vm.dirty_expire_centisecs",
    value: "1500",
    channel: "memory",
    priority: 55,
    mined_out: false,
    hypothesis: "Expire dirty pages sooner. Library leftover — not QD-grounded.",
  },
  {
    slug: "migcost5ms",
    key: "kernel.sched_migration_cost_ns",
    value: "5000000",
    channel: "sustained",
    priority: 50,
    mined_out: false,
    hypothesis: "Less eager migration of warm inference threads. Near noise floor.",
  },
  {
    slug: "notsentlowat16k",
    key: "net.ipv4.tcp_notsent_lowat",
    value: "16384",
    channel: "network",
    priority: 40,
    mined_out: false,
    hypothesis: "Network is gate-only. Mapping axis, expected neutral for scoring.",
  },
];

export type QdElite = {
  cell: string;
  variant_id: string;
  fitness: number;
  coverage: "under" | "covered";
  knobs: string[];
};

export type Proposal = {
  parent_variant_id: string;
  candidate_variant_id: string;
  knob: Knob | null;
  source: "qd-archive" | "library-opt-in" | "refused";
  request_key: string;
  notes: string;
  reversible: boolean;
  payout_eligible: false;
};

export type ProposeInput = {
  parent_variant_id: string;
  taken: string[];
  source: "qd" | "library";
  elites?: QdElite[];
  opt_in_slug?: string;
  cycle_id: number;
};

export function isMinedOut(knob: Pick<Knob, "slug" | "key">) {
  return MINED_OUT_SLUGS.has(knob.slug) || MINED_OUT_KEYS.has(knob.key);
}

export function availableLibrary(taken: string[]) {
  return KNOB_LIBRARY.filter(
    (k) => !k.mined_out && !isMinedOut(k) && !taken.includes(`v0.13-${k.slug}`) && !taken.includes(k.slug),
  ).sort((a, b) => b.priority - a.priority);
}

export function proposeNext(input: ProposeInput): Proposal {
  const parent = input.parent_variant_id || "v0.12";

  if (input.source === "qd") {
    const under = (input.elites ?? [])
      .filter((e) => e.coverage === "under" && e.fitness > 0)
      .sort((a, b) => b.fitness - a.fitness);
    const elite = under[0];
    if (!elite) {
      return {
        parent_variant_id: parent,
        candidate_variant_id: "",
        knob: null,
        source: "refused",
        request_key: "",
        notes:
          "QD archive has no under-covered elite. Refusing to mine another vfs/page-cluster cousin. Remaining library knobs are operator opt-in only.",
        reversible: true,
        payout_eligible: false,
      };
    }
    const candidate = `v0.14-qd-${elite.cell}`;
    return {
      parent_variant_id: parent,
      candidate_variant_id: candidate,
      knob: null,
      source: "qd-archive",
      request_key: `os0-proposed-${candidate}-vs-${parent}`,
      notes: `QD-archive grounded. Cell ${elite.cell} under-covered. Elite ${elite.variant_id} fitness ${elite.fitness}. Mutate this elite, do not pick a library cousin.`,
      reversible: true,
      payout_eligible: false,
    };
  }

  if (input.opt_in_slug && MINED_OUT_SLUGS.has(input.opt_in_slug)) {
    return {
      parent_variant_id: parent,
      candidate_variant_id: "",
      knob: KNOB_LIBRARY.find((k) => k.slug === input.opt_in_slug) ?? null,
      source: "refused",
      request_key: "",
      notes: `${input.opt_in_slug} is mined out (honest null). Do not promote it.`,
      reversible: true,
      payout_eligible: false,
    };
  }

  const knob =
    KNOB_LIBRARY.find((k) => k.slug === input.opt_in_slug && !k.mined_out) ??
    availableLibrary(input.taken)[0];

  if (!knob) {
    return {
      parent_variant_id: parent,
      candidate_variant_id: "",
      knob: null,
      source: "refused",
      request_key: "",
      notes: "Audited library exhausted or mined out. Wire live CursiveRoot fitness into QD.",
      reversible: true,
      payout_eligible: false,
    };
  }

  const candidate = `v0.13-${knob.slug}`;
  return {
    parent_variant_id: parent,
    candidate_variant_id: candidate,
    knob,
    source: "library-opt-in",
    request_key: `os0-proposed-${candidate}-vs-${parent}`,
    notes: `Operator-opt-in library knob ${knob.key}=${knob.value}. Not QD-grounded. ${knob.hypothesis}`,
    reversible: true,
    payout_eligible: false,
  };
}

export type SignedProposal = {
  proposal: Proposal;
  requested_by: string;
  key_status: string;
  signed: boolean;
  auto_enqueue_ok: boolean;
  reasons: string[];
};

export function signProposal(
  proposal: Proposal,
  actor: { requested_by: string; key_status: string },
): SignedProposal {
  const reasons: string[] = [];
  if (proposal.source === "refused" || !proposal.candidate_variant_id) {
    reasons.push("nothing_to_sign");
  }
  if (actor.key_status === "revoked" || actor.key_status === "superseded") {
    reasons.push("identity_not_signable");
  }
  const signed = reasons.length === 0;
  const auto_enqueue_ok = signed && actor.key_status === "active";
  if (signed && actor.key_status === "local_sim") {
    reasons.push("local_sim_cannot_auto_enqueue_production");
  }
  return {
    proposal,
    requested_by: actor.requested_by,
    key_status: actor.key_status,
    signed,
    auto_enqueue_ok,
    reasons,
  };
}

export function enqueueSigned(
  signed: SignedProposal,
  nowIso: string,
  existingKeys: string[],
  allowLocalSim = true,
): { ok: true; request: MeasurementRequest } | { ok: false; reasons: string[] } {
  if (!signed.signed) return { ok: false, reasons: signed.reasons };
  if (!allowLocalSim && !signed.auto_enqueue_ok) {
    return { ok: false, reasons: [...signed.reasons, "auto_enqueue_requires_active_identity"] };
  }
  const draft: EnqueueDraft = {
    request_key: signed.proposal.request_key,
    parent_variant_id: signed.proposal.parent_variant_id,
    candidate_variant_id: signed.proposal.candidate_variant_id,
    cycle_id: 7,
    selection_scope: "linux_bare_metal",
    trust_scope: "simulated_not_payout_eligible",
    requested_by: signed.requested_by,
    notes: signed.proposal.notes,
    payout_eligible: false,
  };
  return enqueueLocal(draft, nowIso, existingKeys);
}
