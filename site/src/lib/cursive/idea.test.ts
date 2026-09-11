import assert from "node:assert/strict";
import { test } from "node:test";
import { reviewIdea, slugIdea } from "./idea.ts";

test("refuses mined-out vfs cache pressure", () => {
  const r = reviewIdea({
    title: "vfs again",
    key: "vm.vfs_cache_pressure",
    value: "50",
    undo: "100",
    channel: "memory",
    hypothesis: "maybe this time",
  });
  assert.equal(r.ok, false);
  assert.equal(r.preset_sh, null);
  assert.ok(r.reasons.some((x) => /already tested/i.test(x)));
  assert.equal(r.payout_eligible, false);
});

test("refuses missing undo", () => {
  const r = reviewIdea({
    title: "watermark",
    key: "vm.watermark_scale_factor",
    value: "200",
    undo: "",
    channel: "memory",
    hypothesis: "start reclaim earlier",
  });
  assert.equal(r.ok, false);
  assert.ok(r.reasons.some((x) => /undo/i.test(x)));
});

test("materializes a reversible community idea without origin write", () => {
  const r = reviewIdea({
    title: "Earlier reclaim",
    key: "vm.watermark_scale_factor",
    value: "200",
    undo: "10",
    channel: "memory",
    hypothesis: "Start reclaiming memory sooner under pressure.",
  });
  assert.equal(r.ok, true);
  assert.equal(r.variant_id, "v0.14-idea-earlier-reclaim");
  assert.match(r.json ?? "", /payout_eligible": false/);
  assert.match(r.json ?? "", /origin_write": false/);
  assert.match(r.preset_sh ?? "", /sysctl -w "\$KEY=\$VAL"/);
  assert.match(r.preset_sh ?? "", /UNDO="10"/);
});

test("slug strips junk", () => {
  assert.equal(slugIdea("  Hello, World!! "), "hello-world");
});
