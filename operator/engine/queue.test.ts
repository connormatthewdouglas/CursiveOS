import assert from "node:assert/strict";
import { test } from "node:test";
import { canClaim, enqueueLocal, nextJobStatus, validateEnqueue } from "./queue.ts";

const good = {
  request_key: "os0-proposed-v0.14-vs-v0.12",
  parent_variant_id: "v0.12",
  candidate_variant_id: "v0.14-qd",
  cycle_id: 7,
  selection_scope: "linux_bare_metal",
  trust_scope: "simulated_not_payout_eligible",
  requested_by: "local-operator",
  notes: "draft",
  payout_eligible: false,
};

test("fail-closed enqueue rejects payout, equal variants, and non-linux scope", () => {
  assert.deepEqual(validateEnqueue(good), []);
  assert.ok(validateEnqueue({ ...good, parent_variant_id: "v0.14-qd" }).includes("parent_equals_candidate"));
  assert.ok(validateEnqueue({ ...good, payout_eligible: true }).includes("payout_eligible_must_be_false"));
  assert.ok(
    validateEnqueue({ ...good, selection_scope: "windows_wsl_observe_only" }).includes(
      "selection_scope_must_be_linux",
    ),
  );
  assert.ok(
    validateEnqueue({ ...good, trust_scope: "payout_eligible" }).includes(
      "trust_scope_must_be_simulated_or_observe_only",
    ),
  );
});

test("local enqueue never writes a live request id", () => {
  const res = enqueueLocal(good, "2026-09-10T00:00:00.000Z", []);
  assert.equal(res.ok, true);
  if (!res.ok) return;
  assert.ok(res.request.request_id.startsWith("local-"));
  assert.equal(res.request.status, "open");
});

test("daemons cannot claim non-linux or non-open requests", () => {
  const open = {
    ...good,
    request_id: "x",
    status: "open" as const,
    reward_sats_placeholder: 0,
    created_at: "",
    updated_at: "",
  };
  assert.equal(canClaim(open, "linux").ok, true);
  assert.equal(canClaim(open, "win32").ok, false);
  assert.equal(canClaim({ ...open, status: "complete" }, "linux").ok, false);
});

test("job status machine is one-way", () => {
  assert.equal(nextJobStatus("open", "claim"), "claimed");
  assert.equal(nextJobStatus("claimed", "start"), "running");
  assert.equal(nextJobStatus("running", "complete"), "complete");
  assert.equal(nextJobStatus("complete", "claim"), null);
});
