import assert from "node:assert/strict";
import { test } from "node:test";
import { LIVE_USING_TRUE_HOLES, authorizeWrite } from "./policy.ts";

test("anon cannot inject a measurement request", () => {
  const r = authorizeWrite({
    table: "measurement_requests",
    action: "insert",
    actor: { kind: "anon" },
  });
  assert.equal(r.ok, false);
  assert.equal(r.reason, "enqueue_is_privileged");
});

test("anon may only touch status and updated_at", () => {
  const ok = authorizeWrite({
    table: "measurement_requests",
    action: "update",
    actor: { kind: "anon" },
    fields: ["status", "updated_at"],
  });
  assert.equal(ok.ok, true);
  const bad = authorizeWrite({
    table: "measurement_requests",
    action: "update",
    actor: { kind: "anon" },
    fields: ["candidate_variant_id"],
  });
  assert.equal(bad.ok, false);
});

test("jobs and capabilities reject cross-machine and USING(true)", () => {
  const hole = authorizeWrite({
    table: "measurement_jobs",
    action: "update",
    actor: { kind: "anon" },
    row_machine_id: "42e7c7257af11f46",
  });
  assert.equal(hole.ok, false);
  assert.equal(hole.using_true, false);

  const own = authorizeWrite({
    table: "machine_capabilities",
    action: "update",
    actor: { kind: "claimed_machine", machine_id: "42e7c7257af11f46", key_status: "active" },
    row_machine_id: "42e7c7257af11f46",
  });
  assert.equal(own.ok, true);

  const cross = authorizeWrite({
    table: "measurement_jobs",
    action: "update",
    actor: { kind: "claimed_machine", machine_id: "42e7c7257af11f46", key_status: "active" },
    row_machine_id: "3e6b165ddf112a75",
  });
  assert.equal(cross.ok, false);
  assert.deepEqual([...LIVE_USING_TRUE_HOLES], ["machine_capabilities", "measurement_jobs"]);
});

test("accruals are origin-written", () => {
  const r = authorizeWrite({
    table: "l5_accruals",
    action: "insert",
    actor: { kind: "claimed_machine", machine_id: "x", key_status: "active" },
  });
  assert.equal(r.ok, false);
});
