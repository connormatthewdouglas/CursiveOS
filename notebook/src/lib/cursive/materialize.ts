import { availableLibrary, isMinedOut, type Knob, type Proposal } from "./propose.ts";
import { BIN_LABEL, QD_AXES, parseCellKey } from "./qd.ts";

/**
 * Materialize a proposed candidate into the files a daemon can screen.
 *
 * QD names a behavioral cell, not a sysctl. A reversible preset is only
 * written when an operator-opt-in leftover knob matches the changed axis.
 * Mined-out pagecluster / vfs knobs never materialize. Nothing here POSTs
 * to CursiveRoot; enqueue SQL is printed for a privileged founder to run.
 */

export type ChangedAxis = {
  axis: (typeof QD_AXES)[number];
  from: (typeof BIN_LABEL)[number];
  to: (typeof BIN_LABEL)[number];
};

export type Material = {
  proposal: Proposal;
  axes: ChangedAxis[];
  knob: Knob | null;
  files_ok: boolean;
  reasons: string[];
  variant_json: string;
  preset_sh: string | null;
  enqueue_sql: string;
  payout_eligible: false;
};

export function cellFromCandidate(id: string) {
  const m = /^v0\.14-qd-(.+)$/.exec(id);
  return m?.[1] ?? null;
}

export function changedAxes(parentCell: string | null, targetCell: string | null): ChangedAxis[] {
  if (!parentCell || !targetCell) return [];
  const a = parseCellKey(parentCell);
  const b = parseCellKey(targetCell);
  if (!a || !b) return [];
  const out: ChangedAxis[] = [];
  QD_AXES.forEach((axis, i) => {
    if (a[i] !== b[i]) {
      out.push({ axis, from: BIN_LABEL[a[i]], to: BIN_LABEL[b[i]] });
    }
  });
  return out;
}

/** Leftover library knobs that may attach to a QD axis. Never pagecluster/vfs. */
export function leftoverForAxis(axis: (typeof QD_AXES)[number], taken: string[] = []): Knob | null {
  const want: Record<(typeof QD_AXES)[number], string[]> = {
    cold: [],
    idle: [],
    memory: ["watermark200", "dirtyexpire1500"],
    sustained: ["migcost5ms"],
  };
  const pool = availableLibrary(taken);
  for (const slug of want[axis] ?? []) {
    const knob = pool.find((k) => k.slug === slug);
    if (knob && !isMinedOut(knob)) return knob;
  }
  return null;
}

export function attachLeftover(axes: ChangedAxis[], slug: string | undefined, taken: string[] = []): Knob | null {
  if (!slug) return null;
  if (isMinedOut({ slug, key: slug === "pagecluster0" ? "vm.page-cluster" : slug === "vfscache50" ? "vm.vfs_cache_pressure" : "" })) {
    return null;
  }
  const changed = new Set(axes.map((a) => a.axis));
  for (const axis of changed) {
    const knob = leftoverForAxis(axis, taken);
    if (knob && knob.slug === slug) return knob;
  }
  const pool = availableLibrary(taken);
  const requested = pool.find((k) => k.slug === slug);
  if (!requested) return null;
  // Refuse attaching a leftover whose channel is not the QD axis we are filling.
  return null;
}

function variantJson(proposal: Proposal, knob: Knob | null, axes: ChangedAxis[]) {
  const axisNote = axes.length
    ? axes.map((a) => `${a.axis} ${a.from}→${a.to}`).join(", ")
    : "no descriptor delta";
  const candidate = proposal.candidate_variant_id;
  const parent = proposal.parent_variant_id;
  const body = {
    schema_version: "seed-organism.variant.v0.1",
    variant_id: `candidate-${candidate}`,
    parent_variant_id: `parent-baseline-${parent}`,
    contributor_id: "organism-proposer",
    commit_ref: `candidate-${candidate}`,
    preset_version: candidate,
    preset_path: knob ? `presets/cursiveos-presets-${candidate}.sh` : null,
    evaluation_role: "candidate_screen",
    fitness_eligible: Boolean(knob),
    knobs_removed_vs_parent: 0,
    proposed_by: "organism_proposer.qd-v0.14",
    declared_scope: knob
      ? `The ${parent} parent stack plus one reversible sysctl: ${knob.key}=${knob.value} targeting QD cell ${cellFromCandidate(candidate) ?? "unknown"} (${axisNote}).`
      : `Behavioral target only. QD cell ${cellFromCandidate(candidate) ?? "unknown"} (${axisNote}). No audited leftover maps to this axis — do not invent a sysctl.`,
    hypothesis: knob
      ? `${knob.hypothesis} QD-grounded attachment: ${axisNote}.`
      : `Mutate ${parent} toward ${axisNote}. No reversible knob is attached. Do not mine pagecluster/vfs cousins.`,
    rollback_method: knob
      ? `Restores the prior ${knob.key} value captured at apply time, then delegates the rest of the revert to the ${parent} preset undo.`
      : "No mutation materialized; nothing to roll back.",
    payout_eligible: false,
    trust_scope: "simulated_not_payout_eligible",
  };
  return JSON.stringify(body, null, 2) + "\n";
}

function presetSh(proposal: Proposal, knob: Knob) {
  const candidate = proposal.candidate_variant_id;
  const parent = proposal.parent_variant_id;
  const parentPreset = `cursiveos-presets-${parent}.sh`;
  const stateFile = `preset_state_${candidate}.txt`;
  return `#!/usr/bin/env bash
# CursiveOS ${candidate} — QD-attached leftover, autonomously proposed.
# Parent ${parent} plus one reversible sysctl: ${knob.key}=${knob.value}.
# Hypothesis: ${knob.hypothesis}
set -uo pipefail
ACTION="\${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PARENT="$SCRIPT_DIR/${parentPreset}"
STATE="$HOME/CursiveOS/${stateFile}"
KEY="${knob.key}"
VAL="${knob.value}"
if [[ -z "\${TAO_SUDO_PASS:-}" ]]; then
    if ! sudo -n true 2>/dev/null; then
        read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
    fi
fi
export TAO_SUDO_PASS
s() {
    if [[ -n "\${TAO_SUDO_PASS:-}" ]]; then echo "$TAO_SUDO_PASS" | sudo -S "$@" 2>/dev/null;
    else sudo -n "$@" 2>/dev/null; fi
}
echo "CursiveOS Candidate ${candidate} (${parent} stack + $KEY=$VAL)"
case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    ;;
  --dry-run)
    bash "$PARENT" --dry-run
    echo "  + sysctl: $KEY=$VAL (prior value captured for undo)"
    ;;
  --apply-temp)
    bash "$PARENT" --apply-temp
    OLD="$(s sysctl -n "$KEY" 2>/dev/null || sysctl -n "$KEY" 2>/dev/null || true)"
    if [[ -n "$OLD" ]]; then
        mkdir -p "$(dirname "$STATE")"
        echo "$KEY=$OLD" > "$STATE"
    fi
    if s sysctl -w "$KEY=$VAL" >/dev/null 2>&1; then
        echo "OK $KEY set to $VAL (was \${OLD:-unknown})"
    else
        echo "  sysctl set failed for $KEY — parent stack still applied"
    fi
    echo "OK Applied ${candidate} temporarily."
    ;;
  --undo)
    if [[ -f "$STATE" ]]; then
        SAVED="$(cut -d= -f2- < "$STATE")"
        [[ -n "$SAVED" ]] && s sysctl -w "$KEY=$SAVED" >/dev/null 2>&1 && echo "OK $KEY restored to $SAVED"
        rm -f "$STATE"
    fi
    bash "$PARENT" --undo
    echo "OK ${candidate} reverted (sysctl + ${parent} stack)."
    ;;
  *) echo "Unknown option: $ACTION"; exit 1 ;;
esac
`;
}

export function enqueueSql(proposal: Proposal, cycleId = 7) {
  const notes = proposal.notes.replace(/'/g, "''");
  return `insert into public.measurement_requests
  (request_key, status, priority, parent_variant_id, parent_variant_path,
   candidate_variant_id, candidate_variant_path, cycle_id, screen_order,
   selection_scope, trust_scope, reward_sats_placeholder, requested_by, notes)
values
  ('${proposal.request_key}', 'open', 70, '${proposal.parent_variant_id}',
   'references/seed-organism/variant.${proposal.parent_variant_id}.json',
   '${proposal.candidate_variant_id}', 'references/seed-organism/variant.${proposal.candidate_variant_id}.json',
   ${cycleId}, 'normal', 'linux_bare_metal',
   'simulated_not_payout_eligible', 0, 'organism-proposer',
   '${notes}')
on conflict (request_key) do nothing;
-- Privileged / service-role only. This console will not run it.
`;
}

export function materializeProposal(input: {
  proposal: Proposal;
  parentCell?: string | null;
  attachSlug?: string;
  taken?: string[];
}): Material {
  const proposal = input.proposal;
  const reasons: string[] = [];
  const targetCell =
    cellFromCandidate(proposal.candidate_variant_id) ??
    (proposal.source === "qd-archive" ? proposal.candidate_variant_id.replace(/^v0\.14-qd-/, "") : null);
  const axes = changedAxes(input.parentCell ?? null, targetCell);

  if (proposal.source === "refused" || !proposal.candidate_variant_id) {
    reasons.push("nothing_to_materialize");
  }
  if (proposal.source === "qd-archive" && axes.length === 0) {
    reasons.push("cannot_parse_qd_axes");
  }

  let knob: Knob | null = proposal.knob;
  if (proposal.source === "qd-archive") {
    knob = attachLeftover(axes, input.attachSlug, input.taken ?? []);
    if (input.attachSlug && !knob) reasons.push(`leftover_does_not_match_axis:${input.attachSlug}`);
    if (!input.attachSlug) {
      const auto = axes.map((a) => leftoverForAxis(a.axis, input.taken ?? [])).find(Boolean) ?? null;
      if (!auto) reasons.push("no_audited_knob_for_qd_axis");
      // Do not auto-attach. QD names the cell; leftover attachment is operator opt-in.
    }
  }
  if (knob && isMinedOut(knob)) {
    reasons.push("mined_out_knob");
    knob = null;
  }

  const files_ok =
    Boolean(knob) &&
    proposal.source !== "refused" &&
    Boolean(proposal.candidate_variant_id) &&
    !reasons.includes("mined_out_knob");

  if (!files_ok && !reasons.includes("nothing_to_materialize") && !reasons.includes("no_audited_knob_for_qd_axis")) {
    if (!knob && proposal.source === "qd-archive") reasons.push("hypothesis_only_no_preset");
  }

  return {
    proposal,
    axes,
    knob,
    files_ok,
    reasons,
    variant_json: variantJson(proposal, files_ok ? knob : null, axes),
    preset_sh: files_ok && knob ? presetSh(proposal, knob) : null,
    enqueue_sql: proposal.request_key ? enqueueSql(proposal) : "-- nothing to enqueue\n",
    payout_eligible: false,
  };
}
