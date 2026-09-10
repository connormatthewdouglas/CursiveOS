import assert from "node:assert/strict";
import { test } from "node:test";
import {
  availableLibrary,
  enqueueSigned,
  isMinedOut,
  proposeNext,
  signProposal,
} from "./propose.ts";

test("mined-out knobs are never the default proposal", () => {
  const p = proposeNext({
    parent_variant_id: "v0.12",
    taken: [],
    source: "library",
    cycle_id: 7,
  });
  assert.equal(p.source, "library-opt-in");
  assert.equal(p.candidate_variant_id, "v0.13-watermark200");
  assert.equal(p.payout_eligible, false);
  assert.equal(isMinedOut({ slug: "pagecluster0", key: "vm.page-cluster" }), true);
  assert.ok(!availableLibrary([]).some((k) => k.slug === "pagecluster0"));
});

test("explicit pagecluster opt-in is refused", () => {
  const p = proposeNext({
    parent_variant_id: "v0.12",
    taken: [],
    source: "library",
    opt_in_slug: "pagecluster0",
    cycle_id: 7,
  });
  assert.equal(p.source, "refused");
  assert.equal(p.candidate_variant_id, "");
});

test("QD source refuses to mine the library when the archive is empty", () => {
  const p = proposeNext({
    parent_variant_id: "v0.12",
    taken: [],
    source: "qd",
    elites: [],
    cycle_id: 7,
  });
  assert.equal(p.source, "refused");
  assert.match(p.notes, /QD archive/);
});

test("QD elite becomes v0.14 candidate and can be locally enqueued", () => {
  const p = proposeNext({
    parent_variant_id: "v0.12",
    taken: [],
    source: "qd",
    elites: [{ cell: "cold-pos-sust-neu", variant_id: "v0.12", fitness: 0.1, coverage: "under", knobs: [] }],
    cycle_id: 7,
  });
  assert.equal(p.source, "qd-archive");
  const signed = signProposal(p, { requested_by: "organism-proposer", key_status: "local_sim" });
  assert.equal(signed.signed, true);
  assert.equal(signed.auto_enqueue_ok, false);
  const enq = enqueueSigned(signed, "2026-09-10T00:00:00.000Z", []);
  assert.equal(enq.ok, true);
  if (enq.ok) {
    assert.ok(enq.request.request_id.startsWith("local-"));
    assert.equal(enq.request.parent_variant_id, "v0.12");
  }
});
