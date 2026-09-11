import assert from "node:assert/strict";
import { test } from "node:test";
import {
  GENESIS_SPLIT_CURRENT,
  allocateSats,
  closeCycle,
  metabolicR,
  newWeight,
  nextSplit,
  returningWeight,
} from "./economics.ts";

test("new_weight matches v3.3 examples", () => {
  assert.equal(newWeight(0), 1);
  assert.equal(newWeight(1), 0.5);
  assert.equal(newWeight(3), 0.25);
  assert.equal(newWeight(9), 0.1);
  assert.equal(returningWeight(0), 0);
});

test("metabolic R is infinite on first-time-only merges and null when empty", () => {
  assert.equal(metabolicR([]), null);
  const r = metabolicR([
    { contributor_wallet: "a", variant_id: "v1", fitness_delta: 0.1, prior_merge_count: 0 },
  ]);
  assert.equal(r, Number.POSITIVE_INFINITY);
});

test("split movement is capped at 2.5 points per cycle", () => {
  const nxt = nextSplit({
    splitCurrent: GENESIS_SPLIT_CURRENT,
    rMeta: Number.POSITIVE_INFINITY,
  });
  assert.ok(Math.abs(nxt.delta_applied) <= 0.025 + 1e-12);
  assert.ok(nxt.split_current > GENESIS_SPLIT_CURRENT);
  assert.ok(Math.abs(nxt.split_current + nxt.split_lifetime - 1) < 1e-12);
});

test("allocateSats is lossless", () => {
  const out = allocateSats(100, [
    { id: "a", weight: 1 },
    { id: "b", weight: 1 },
    { id: "c", weight: 1 },
  ]);
  assert.equal(out.a + out.b + out.c, 100);
});

test("zero revenue produces no accruals and still updates lifetime", () => {
  const closed = closeCycle({
    cycle_id: 7,
    revenue_sats: 0,
    split_current: 0.2,
    merges: [
      { contributor_wallet: "founder", variant_id: "v0.11", fitness_delta: 0.1, prior_merge_count: 1 },
    ],
    lifetime: [{ contributor_wallet: "founder", fitness: 0.0148 }],
    now_iso: "2026-09-10T00:00:00.000Z",
  });
  assert.equal(closed.zero_revenue, true);
  assert.equal(closed.accruals.length, 0);
  assert.ok(closed.updated_lifetime[0].fitness > 0.1);
});

test("cycle close splits 20/80 and testers are not in the lifetime stream", () => {
  const closed = closeCycle({
    cycle_id: 3,
    revenue_sats: 100_000,
    split_current: 0.2,
    merges: [
      {
        contributor_wallet: "founder",
        variant_id: "v0.11",
        fitness_delta: 0.10037807,
        prior_merge_count: 1,
      },
    ],
    lifetime: [{ contributor_wallet: "founder", fitness: 0.01480931 }],
    now_iso: "2026-06-26T20:07:28.000Z",
  });
  assert.equal(closed.current_stream_sats, 20_000);
  assert.equal(closed.lifetime_stream_sats, 80_000);
  const founder = closed.accruals
    .filter((a) => a.contributor_wallet === "founder")
    .reduce((s, a) => s + a.amount_sats, 0);
  assert.equal(founder, 100_000);
  assert.ok(closed.accruals.every((a) => a.contributor_wallet !== "tester-wallet"));
  assert.ok(closed.accruals[0].claim_deadline.startsWith("2028-"));
});

test("expired accruals redistribute only to active claimants", () => {
  const closed = closeCycle({
    cycle_id: 8,
    revenue_sats: 10,
    split_current: 0.2,
    merges: [
      { contributor_wallet: "a", variant_id: "x", fitness_delta: 1, prior_merge_count: 2 },
    ],
    lifetime: [
      { contributor_wallet: "a", fitness: 1 },
      { contributor_wallet: "b", fitness: 1 },
    ],
    now_iso: "2026-09-10T00:00:00.000Z",
    expired_accruals: [
      {
        accrual_id: "old",
        contributor_wallet: "ghost",
        cycle_id: 1,
        stream_type: "lifetime",
        amount_sats: 50,
        created_at: "2023-01-01T00:00:00.000Z",
        claim_deadline: "2025-01-01T00:00:00.000Z",
        claimed_at: null,
        claim_tx_id: null,
      },
    ],
    recent_claims: [{ wallet: "a", claimed_at: "2026-08-01T00:00:00.000Z" }],
  });
  const redist = closed.accruals.filter((a) => a.stream_type === "redistribution");
  assert.equal(redist.length, 1);
  assert.equal(redist[0].contributor_wallet, "a");
  assert.equal(redist[0].amount_sats, 50);
});
