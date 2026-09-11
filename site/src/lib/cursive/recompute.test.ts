import assert from "node:assert/strict";
import { test } from "node:test";
import { recomputeBundle, REQUIRED_ARTIFACT_KINDS, sha256Hex } from "./recompute.ts";
import { CANONICAL_LAPTOP, CANONICAL_STARDUST } from "./identity.ts";

async function artifactsFor(payloads: Record<string, string>) {
  const artifacts = [];
  const parts: string[] = [];
  for (const kind of REQUIRED_ARTIFACT_KINDS) {
    const payload = payloads[kind] ?? `${kind}-body`;
    const sha256 = await sha256Hex(payload);
    artifacts.push({ kind, sha256, bytes: payload.length, payload, claimed_digest: sha256 });
    parts.push(`${kind}:${sha256}`);
  }
  const bundle_hash = await sha256Hex(parts.sort().join("|"));
  return { artifacts, bundle_hash };
}

test("missing payload fails closed and never pays", async () => {
  const report = await recomputeBundle({
    bundle_hash: "abc",
    variant_id: "v0.13",
    parent_variant_id: "v0.12",
    candidate_variant_id: "v0.13-watermark200",
    claimed_metrics: { coldstart_pct: -2 },
    expected_channels: ["coldstart_pct"],
    artifacts: REQUIRED_ARTIFACT_KINDS.map((kind) => ({
      kind,
      sha256: "dead",
      bytes: 1,
      payload: null,
    })),
    witnesses: [{ machine_id: CANONICAL_LAPTOP }],
    aliases: [],
    fleet_size: 3,
  });
  assert.equal(report.recompute_ok, false);
  assert.equal(report.payout_eligible, false);
  assert.ok(report.reasons.some((r) => r.startsWith("payload_missing")));
});

test("origin hash of payloads must match claimed digests", async () => {
  const { artifacts, bundle_hash } = await artifactsFor({});
  const ok = await recomputeBundle({
    bundle_hash,
    variant_id: "v",
    parent_variant_id: "v0.12",
    candidate_variant_id: "v0.13-x",
    claimed_metrics: { coldstart_pct: -1, memory_pct: -4 },
    expected_channels: ["coldstart_pct", "memory_pct"],
    artifacts,
    witnesses: [
      { machine_id: CANONICAL_LAPTOP, wallet: "a", identity_public_key: "k1" },
      { machine_id: CANONICAL_STARDUST, wallet: "b", identity_public_key: "k2" },
    ],
    aliases: [],
    fleet_size: 3,
  });
  assert.equal(ok.recompute_ok, true);
  assert.equal(ok.replay_ok, true);
  assert.equal(ok.independent_aggregation_ok, true);
  assert.equal(ok.payout_eligible, false);

  const bad = await recomputeBundle({
    ...{
      bundle_hash,
      variant_id: "v",
      parent_variant_id: "v0.12",
      candidate_variant_id: "v0.13-x",
      claimed_metrics: { coldstart_pct: -1, memory_pct: -4 },
      expected_channels: ["coldstart_pct", "memory_pct"],
      witnesses: ok.independent_aggregation_ok
        ? [
            { machine_id: CANONICAL_LAPTOP, wallet: "a", identity_public_key: "k1" },
            { machine_id: CANONICAL_STARDUST, wallet: "b", identity_public_key: "k2" },
          ]
        : [],
      aliases: [],
      fleet_size: 3,
    },
    artifacts: artifacts.map((a, i) => (i === 0 ? { ...a, sha256: "00".repeat(32) } : a)),
  });
  assert.equal(bad.recompute_ok, false);
  assert.ok(bad.reasons.some((r) => r.startsWith("hash_mismatch")));
});

test("replay index catches the same bundle", async () => {
  const { artifacts, bundle_hash } = await artifactsFor({ raw_metrics: "metrics-1" });
  const replayed = await recomputeBundle({
    bundle_hash,
    variant_id: "v",
    parent_variant_id: "v0.12",
    candidate_variant_id: "v0.13-x",
    claimed_metrics: {},
    expected_channels: [],
    artifacts,
    witnesses: [{ machine_id: CANONICAL_LAPTOP }],
    aliases: [],
    fleet_size: 1,
    replay_index: [{ bundle_hash, artifact_sha256s: artifacts.map((a) => a.sha256) }],
  });
  assert.equal(replayed.replay_ok, false);
  assert.equal(replayed.payout_eligible, false);
});
