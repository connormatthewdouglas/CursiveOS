import assert from "node:assert/strict";
import { test } from "node:test";
import { proposeNext } from "./propose.ts";
import {
  attachLeftover,
  cellFromCandidate,
  changedAxes,
  leftoverForAxis,
  materializeProposal,
} from "./materialize.ts";

const elite = {
  cell: "cpos-sneu-ineu-mpos",
  variant_id: "candidate-v0.11-zram-swappiness",
  fitness: 0.10037807,
  coverage: "under" as const,
  knobs: [],
};

test("QD cold-pos neighbor has no audited leftover — hypothesis only", () => {
  const p = proposeNext({
    parent_variant_id: "v0.12",
    taken: [],
    source: "qd",
    elites: [elite],
    cycle_id: 7,
  });
  assert.equal(p.source, "qd-archive");
  assert.equal(cellFromCandidate(p.candidate_variant_id), "cpos-sneu-ineu-mpos");
  const axes = changedAxes("cneu-sneu-ineu-mpos", "cpos-sneu-ineu-mpos");
  assert.deepEqual(axes.map((a) => a.axis), ["cold"]);
  assert.equal(leftoverForAxis("cold"), null);
  const mat = materializeProposal({ proposal: p, parentCell: "cneu-sneu-ineu-mpos" });
  assert.equal(mat.files_ok, false);
  assert.equal(mat.preset_sh, null);
  assert.equal(mat.payout_eligible, false);
  assert.ok(mat.reasons.includes("no_audited_knob_for_qd_axis"));
  assert.match(mat.variant_json, /Behavioral target only/);
  assert.match(mat.enqueue_sql, /simulated_not_payout_eligible/);
});

test("sustained leftover may attach, mined-out knobs may not", () => {
  const p = proposeNext({
    parent_variant_id: "v0.12",
    taken: [],
    source: "qd",
    elites: [
      {
        cell: "cneu-spos-ineu-mpos",
        variant_id: "candidate-v0.11-zram-swappiness",
        fitness: 0.1,
        coverage: "under",
        knobs: [],
      },
    ],
    cycle_id: 7,
  });
  const axes = changedAxes("cneu-sneu-ineu-mpos", "cneu-spos-ineu-mpos");
  assert.equal(leftoverForAxis("sustained")?.slug, "migcost5ms");
  assert.equal(attachLeftover(axes, "migcost5ms")?.slug, "migcost5ms");
  assert.equal(attachLeftover(axes, "pagecluster0"), null);
  const mat = materializeProposal({
    proposal: p,
    parentCell: "cneu-sneu-ineu-mpos",
    attachSlug: "migcost5ms",
  });
  assert.equal(mat.files_ok, true);
  assert.ok(mat.preset_sh?.includes("kernel.sched_migration_cost_ns=5000000"));
  assert.match(mat.preset_sh ?? "", /--undo/);
  assert.equal(mat.payout_eligible, false);
});

test("refused proposal does not materialize files", () => {
  const p = proposeNext({
    parent_variant_id: "v0.12",
    taken: [],
    source: "qd",
    elites: [],
    cycle_id: 7,
  });
  const mat = materializeProposal({ proposal: p, parentCell: "cneu-sneu-ineu-mpos" });
  assert.equal(mat.files_ok, false);
  assert.ok(mat.reasons.includes("nothing_to_materialize"));
});
