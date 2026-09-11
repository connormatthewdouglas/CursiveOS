import assert from "node:assert/strict";
import { test } from "node:test";
import { EMPTY_LEDGER, closeIntoLedger, testerHasFitness } from "./ledger.ts";

test("testers get a rebate and no lifetime fitness", () => {
  const { ledger, closed } = closeIntoLedger(
    EMPTY_LEDGER,
    {
      cycle_id: 7,
      revenue_sats: 100_000,
      split_current: 0.2,
      merges: [
        {
          contributor_wallet: "bc1qfounder",
          variant_id: "v0.11",
          fitness_delta: 0.1,
          prior_merge_count: 1,
        },
      ],
      lifetime: [],
      now_iso: "2026-09-10T00:00:00.000Z",
    },
    [{ contributor_wallet: "bc1qfounder", variant_id: "v0.11", fitness_delta: 0.1 }],
    [{ wallet: "bc1qtester", would_have_paid_usd: 2 }],
    100_000,
  );
  assert.equal(closed.accruals.every((a) => a.contributor_wallet !== "bc1qtester"), true);
  assert.equal(testerHasFitness(ledger, "bc1qtester"), false);
  assert.equal(testerHasFitness(ledger, "bc1qfounder"), true);
  assert.equal(ledger.rebates[0].tester_wallet, "bc1qtester");
  assert.ok(ledger.rebates[0].rebate_sats > 0);
  assert.equal(ledger.cycles[0].status, "closed");
  assert.equal(ledger.lifetime.length, 1);
});

test("zero revenue still records fitness, no accruals", () => {
  const { ledger, closed } = closeIntoLedger(
    EMPTY_LEDGER,
    {
      cycle_id: 8,
      revenue_sats: 0,
      split_current: 0.2,
      merges: [
        { contributor_wallet: "a", variant_id: "x", fitness_delta: 0.2, prior_merge_count: 0 },
      ],
      lifetime: [],
      now_iso: "2026-09-10T00:00:00.000Z",
    },
    [{ contributor_wallet: "a", variant_id: "x", fitness_delta: 0.2 }],
    [],
    100_000,
  );
  assert.equal(closed.zero_revenue, true);
  assert.equal(ledger.accruals.length, 0);
  assert.equal(ledger.lifetime[0].fitness_score, 0.2);
});
