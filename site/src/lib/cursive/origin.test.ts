import assert from "node:assert/strict";
import { test } from "node:test";
import { authorizeOriginRequest, originMutate } from "./origin.ts";

test("GET live CursiveRoot is allowed", () => {
  const d = authorizeOriginRequest({ method: "GET", table: "seed_bundles" });
  assert.equal(d.allowed, true);
  assert.deepEqual(d.reasons, []);
});

test("POST / PATCH / DELETE are denied even if RLS is USING(true)", () => {
  for (const method of ["POST", "PATCH", "PUT", "DELETE"]) {
    const d = authorizeOriginRequest({
      method,
      table: "measurement_requests",
      using_true: true,
    });
    assert.equal(d.allowed, false);
    assert.ok(d.reasons.includes("origin_writes_disabled_in_operator_console"));
    assert.ok(d.reasons.includes("using_true_denied"));
  }
});

test("payout_eligible cannot be flipped from the console", () => {
  const d = authorizeOriginRequest({
    method: "PATCH",
    table: "os0_trust_evaluations",
    payout_eligible: true,
  });
  assert.equal(d.allowed, false);
  assert.ok(d.reasons.includes("payout_eligible_hard_false"));
});

test("originMutate never calls fetch on a write", async () => {
  let called = 0;
  const fake = (async () => {
    called += 1;
    return new Response("nope", { status: 500 });
  }) as unknown as typeof fetch;
  const d = await originMutate(
    { method: "POST", table: "measurement_requests" },
    fake,
  );
  assert.equal(d.allowed, false);
  assert.equal(called, 0);
});
