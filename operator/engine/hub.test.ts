import assert from "node:assert/strict";
import { test } from "node:test";
import { economicsInterface, inspectHubSurface } from "./hub.ts";

test("v3.1 pool and governance shapes are frozen", () => {
  const r = inspectHubSurface({ path: "/hub/governance/appeals", body: { pool: true } });
  assert.equal(r.frozen, true);
  assert.equal(r.allowed, false);
  assert.ok(r.reasons.some((x) => x.includes("governance")));
  assert.equal(economicsInterface(), "cursive-root-operator");
});

test("operator surface is not a v3.1 path", () => {
  const r = inspectHubSurface({ path: "/rails", notes: "v3.3 accruals" });
  assert.equal(r.allowed, true);
});
