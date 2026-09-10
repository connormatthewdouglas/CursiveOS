import assert from "node:assert/strict";
import { test } from "node:test";
import { loopStatus } from "./loop.ts";

test("july heartbeats and empty queue are stale idle", () => {
  const r = loopStatus({
    requests: [
      {
        request_id: "1",
        request_key: "k",
        status: "complete",
        parent_variant_id: "v0.12",
        candidate_variant_id: "v0.13",
        cycle_id: 6,
        selection_scope: "linux_bare_metal",
        trust_scope: "simulated_not_payout_eligible",
        reward_sats_placeholder: 0,
        requested_by: "organism-proposer",
        notes: "",
        created_at: "2026-07-07T00:00:00Z",
        updated_at: "2026-07-07T00:00:00Z",
      },
    ],
    jobs: [],
    capabilities: [
      {
        machine_id: "42e7c7257af11f46",
        daemon_version: "os0",
        platform: "linux",
        os_name: "Linux Mint",
        kernel: "6",
        cpu: "i5",
        gpu: "1650",
        selection_scopes: ["linux_bare_metal"],
        last_seen_at: "2026-07-07T01:23:33Z",
      },
    ],
    now_iso: "2026-09-10T18:00:00Z",
    independent_aggregation_ok: false,
  });
  assert.equal(r.state, "stale");
  assert.ok(r.reasons.includes("queue_empty"));
  assert.ok(r.reasons.includes("daemon_heartbeat_stale"));
  assert.equal(r.playbook[0].ready, false);
});

test("fresh heartbeat plus open request is queued", () => {
  const r = loopStatus({
    requests: [
      {
        request_id: "1",
        request_key: "k",
        status: "open",
        parent_variant_id: "v0.12",
        candidate_variant_id: "v0.14",
        cycle_id: 7,
        selection_scope: "linux_bare_metal",
        trust_scope: "simulated_not_payout_eligible",
        reward_sats_placeholder: 0,
        requested_by: "local",
        notes: "",
        created_at: "2026-09-10T00:00:00Z",
        updated_at: "2026-09-10T00:00:00Z",
      },
    ],
    jobs: [],
    capabilities: [
      {
        machine_id: "m",
        daemon_version: "os0",
        platform: "linux",
        os_name: "linux",
        kernel: "6",
        cpu: "x",
        gpu: "y",
        selection_scopes: ["linux_bare_metal"],
        last_seen_at: "2026-09-10T17:00:00Z",
      },
    ],
    now_iso: "2026-09-10T18:00:00Z",
    independent_aggregation_ok: false,
  });
  assert.equal(r.state, "queued");
  assert.equal(r.open_requests, 1);
});
