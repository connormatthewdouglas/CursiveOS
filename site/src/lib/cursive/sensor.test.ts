import assert from "node:assert/strict";
import { test } from "node:test";
import { reviewSensor, slugSensor } from "./sensor.ts";

test("refuses performance sensor marked pass/fail", () => {
  const r = reviewSensor({
    name: "Cold start",
    family: "performance",
    measures: "GPU idle to first token",
    how_to_run: "./benchmarks/benchmark-inference-v0.1.sh --cold",
    score_mode: "pass_fail",
    hardware_needs: "GPU + Ollama",
    hypothesis: "Detect C-state impact",
    package_notes: "",
  });
  assert.equal(r.ok, false);
  assert.ok(r.reasons.some((x) => /numeric/i.test(x)));
  assert.equal(r.payout_eligible, false);
});

test("refuses regression sensor marked numeric", () => {
  const r = reviewSensor({
    name: "Full test gate",
    family: "regression",
    measures: "cursiveos-full-test pass/fail",
    how_to_run: "./cursiveos-full-test-v1.4.sh",
    score_mode: "numeric",
    hardware_needs: "any Linux",
    hypothesis: "Block breaking changes",
    package_notes: "",
  });
  assert.equal(r.ok, false);
  assert.ok(r.reasons.some((x) => /pass\/fail/i.test(x)));
});

test("refuses missing how to run", () => {
  const r = reviewSensor({
    name: "Idle watts",
    family: "performance",
    measures: "Package power at idle",
    how_to_run: "",
    score_mode: "numeric",
    hardware_needs: "RAPL or equivalent",
    hypothesis: "Catch C-state disable cost",
    package_notes: "",
  });
  assert.equal(r.ok, false);
  assert.ok(r.reasons.some((x) => /how to run/i.test(x)));
});

test("materializes a sensor draft without origin write or payout", () => {
  const r = reviewSensor({
    name: "Sustained tok/s",
    family: "performance",
    measures: "Steady-state tokens per second on a warm model",
    how_to_run: "./benchmarks/benchmark-inference-v0.1.sh --sustained",
    score_mode: "numeric",
    hardware_needs: "GPU with local inference",
    hypothesis: "Detect scheduler and cache effects once warm.",
    package_notes: "Needs Ollama on 127.0.0.1",
  });
  assert.equal(r.ok, true);
  assert.equal(r.sensor_id, "sensor-sustained-tok-s");
  assert.match(r.json ?? "", /"payout_eligible": false/);
  assert.match(r.json ?? "", /"origin_write": false/);
  assert.match(r.json ?? "", /"live_ledger_write": false/);
  assert.match(r.json ?? "", /"family": "performance"/);
});

test("slug strips junk", () => {
  assert.equal(slugSensor("  Idle Power!! "), "idle-power");
});
