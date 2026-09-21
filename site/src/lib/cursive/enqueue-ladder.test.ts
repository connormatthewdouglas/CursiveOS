import assert from "node:assert/strict";
import { test } from "node:test";
import {
  advanceLadder,
  buildEnqueueStub,
  confirmForeign,
  createLadderDraft,
  isPublicEligible,
  markSelfClean,
  nextStage,
  refuseLadder,
  submitToWire,
} from "./enqueue-ladder.ts";

test("happy path: draft → self → foreign → public_eligible", () => {
  let r = createLadderDraft({ id: "v1", kind: "idea" });
  assert.equal(r.stage, "draft");
  assert.equal(r.payout_eligible, false);

  let res = submitToWire(r, "machine-a");
  assert.equal(res.ok, true);
  r = res.record;
  assert.equal(r.stage, "self_pending");
  assert.equal(r.submitter_machine_id, "machine-a");

  res = markSelfClean(r, "machine-a");
  assert.equal(res.ok, true);
  r = res.record;
  assert.equal(r.stage, "self_clean");

  res = advanceLadder(r);
  assert.equal(res.ok, true);
  r = res.record;
  assert.equal(r.stage, "foreign_pending");

  res = confirmForeign(r, "machine-b");
  assert.equal(res.ok, true);
  r = res.record;
  assert.equal(r.stage, "public_eligible");
  assert.equal(r.confirmer_machine_id, "machine-b");
  assert.equal(r.payout_eligible, false);
  assert.equal(isPublicEligible(r), true);
});

test("fail-closed: missing submitter identity on wire submit", () => {
  const r = createLadderDraft({ id: "v1", kind: "sensor" });
  const res = submitToWire(r, "  ");
  assert.equal(res.ok, false);
  assert.equal(res.record.stage, "refused");
  assert.match(res.reason, /submitter_identity/);
});

test("fail-closed: foreign confirmer cannot be submitter", () => {
  let r = createLadderDraft({ id: "v1", kind: "idea", submitter_machine_id: "a" });
  r = submitToWire(r, "a").record;
  r = markSelfClean(r, "a").record;
  r = advanceLadder(r).record;
  const res = confirmForeign(r, "a");
  assert.equal(res.ok, false);
  assert.equal(res.record.stage, "refused");
  assert.match(res.reason, /foreign_confirmer_must_differ/);
});

test("fail-closed: non-submitter cannot mark self-clean", () => {
  let r = createLadderDraft({ id: "v1", kind: "idea" });
  r = submitToWire(r, "machine-a").record;
  const res = markSelfClean(r, "machine-b");
  assert.equal(res.ok, false);
  assert.match(res.reason, /self_clean_must_be_submitter/);
});

test("refuse is terminal", () => {
  const r = createLadderDraft({ id: "v1", kind: "idea" });
  const refused = refuseLadder(r, "operator_kill");
  assert.equal(refused.ok, false);
  assert.equal(refused.record.stage, "refused");
  const again = advanceLadder(refused.record, { actor_machine_id: "x" });
  assert.equal(again.ok, false);
  assert.match(again.reason, /terminal/);
});

test("enqueue stub never claims live write or payout", () => {
  const stub = buildEnqueueStub({
    kind: "idea",
    id: "v0.14-idea-x",
    title: "x",
    submitter_machine_id: "m1",
    body: { hypothesis: "faster reclaim" },
  });
  assert.match(stub, /"live_ledger_write": false/);
  assert.match(stub, /"payout_eligible": false/);
  assert.match(stub, /signed_proposer_rail/);
  assert.match(stub, /"ladder_stage": "self_pending"/);
});

test("nextStage walks the ladder", () => {
  assert.equal(nextStage("draft"), "self_pending");
  assert.equal(nextStage("foreign_pending"), "public_eligible");
  assert.equal(nextStage("public_eligible"), null);
  assert.equal(nextStage("refused"), null);
});
