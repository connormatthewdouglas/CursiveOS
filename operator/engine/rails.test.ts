import assert from "node:assert/strict";
import { test } from "node:test";
import { DEFAULT_RAILS_POLICY, claimAccrual, isBech32Address, simulateConfirm } from "./rails.ts";
import type { Accrual } from "./types.ts";

const accrual: Accrual = {
  accrual_id: "3:lifetime:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
  contributor_wallet: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
  cycle_id: 3,
  stream_type: "lifetime",
  amount_sats: 80_000,
  created_at: "2026-06-26T00:00:00.000Z",
  claim_deadline: "2028-06-26T00:00:00.000Z",
  claimed_at: null,
  claim_tx_id: null,
};

test("bech32 accepts mainnet and rejects garbage", () => {
  assert.equal(isBech32Address("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", "main"), true);
  assert.equal(isBech32Address("tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx", "test"), true);
  assert.equal(isBech32Address("not-an-address", "main"), false);
  assert.equal(isBech32Address("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", "test"), false);
});

test("claim is blocked when rails are paused or window expired", () => {
  const paused = claimAccrual({
    accrual,
    destination_wallet: accrual.contributor_wallet,
    now_iso: "2026-09-10T00:00:00.000Z",
    policy: { ...DEFAULT_RAILS_POLICY, paused: true },
    spent_this_cycle_sats: 0,
  });
  assert.equal(paused.ok, false);
  if (!paused.ok) assert.equal(paused.code, "rails_paused");

  const expired = claimAccrual({
    accrual,
    destination_wallet: accrual.contributor_wallet,
    now_iso: "2029-01-01T00:00:00.000Z",
    policy: DEFAULT_RAILS_POLICY,
    spent_this_cycle_sats: 0,
  });
  assert.equal(expired.ok, false);
  if (!expired.ok) assert.equal(expired.code, "claim_window_expired");
});

test("mainnet is hard-gated even with a valid address", () => {
  const res = claimAccrual({
    accrual,
    destination_wallet: accrual.contributor_wallet,
    now_iso: "2026-09-10T00:00:00.000Z",
    policy: {
      ...DEFAULT_RAILS_POLICY,
      rail_mode: "crypto_mainnet",
      payout_eligible_production: false,
    },
    spent_this_cycle_sats: 0,
  });
  assert.equal(res.ok, false);
  if (!res.ok) assert.equal(res.code, "mainnet_hard_gated");
});

test("internal credits queue a simulated intent and refuse to invent mainnet hashes", () => {
  const res = claimAccrual({
    accrual,
    destination_wallet: accrual.contributor_wallet,
    now_iso: "2026-09-10T00:00:00.000Z",
    policy: DEFAULT_RAILS_POLICY,
    spent_this_cycle_sats: 0,
  });
  assert.equal(res.ok, true);
  if (!res.ok) return;
  const confirmed = simulateConfirm(res.intent, "2026-09-10T00:00:00.000Z");
  assert.equal(confirmed.tx_status, "confirmed");
  assert.ok(confirmed.tx_hash?.startsWith("sim:"));

  const mainnetish = simulateConfirm(
    { ...res.intent, rail_mode: "crypto_mainnet", tx_status: "queued" },
    "2026-09-10T00:00:00.000Z",
  );
  assert.equal(mainnetish.tx_status, "blocked");
});

test("per-cycle cap is enforced", () => {
  const res = claimAccrual({
    accrual,
    destination_wallet: accrual.contributor_wallet,
    now_iso: "2026-09-10T00:00:00.000Z",
    policy: { ...DEFAULT_RAILS_POLICY, per_cycle_cap_sats: 10 },
    spent_this_cycle_sats: 0,
  });
  assert.equal(res.ok, false);
  if (!res.ok) assert.equal(res.code, "cycle_cap");
});
