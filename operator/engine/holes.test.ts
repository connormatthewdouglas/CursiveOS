import assert from "node:assert/strict";
import { test } from "node:test";
import { LIVE_RLS_HOLES, openWriteHoles } from "./holes.ts";

test("capabilities and jobs USING(true) updates are named open holes", () => {
  const open = openWriteHoles();
  assert.ok(open.some((h) => h.table === "machine_capabilities" && h.action === "update"));
  assert.ok(open.some((h) => h.table === "measurement_jobs" && h.action === "update"));
  assert.ok(LIVE_RLS_HOLES.every((h) => h.clause.length > 0));
});
