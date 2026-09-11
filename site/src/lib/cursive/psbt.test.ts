import assert from "node:assert/strict";
import { test } from "node:test";
import { DEFAULT_RAILS_POLICY } from "./rails.ts";
import { buildPsbtIntent } from "./psbt.ts";
import type { Accrual } from "./types.ts";

const accrual: Accrual = {
  accrual_id: "7:lifetime:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
  contributor_wallet: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
  cycle_id: 7,
  stream_type: "lifetime",
  amount_sats: 80_000,
  created_at: "2026-09-10T00:00:00.000Z",
  claim_deadline: "2028-09-10T00:00:00.000Z",
  claimed_at: null,
  claim_tx_id: null,
};

test("internal credits produce an unsigned, non-broadcastable intent", () => {
  const res = buildPsbtIntent({
    accrual,
    destination: accrual.contributor_wallet,
    policy: DEFAULT_RAILS_POLICY,
    now_iso: "2026-09-10T00:00:00.000Z",
  });
  assert.equal(res.ok, true);
  if (!res.ok) return;
  assert.equal(res.intent.unsigned, true);
  assert.equal(res.intent.signing_key_present, false);
  assert.equal(res.intent.broadcastable, false);
  assert.equal(res.intent.network, "internal");
});

test("mainnet PSBT construction is hard-gated", () => {
  const res = buildPsbtIntent({
    accrual,
    destination: accrual.contributor_wallet,
    policy: { ...DEFAULT_RAILS_POLICY, rail_mode: "crypto_mainnet" },
    now_iso: "2026-09-10T00:00:00.000Z",
  });
  assert.equal(res.ok, false);
  if (!res.ok) assert.equal(res.code, "mainnet_hard_gated");
});
