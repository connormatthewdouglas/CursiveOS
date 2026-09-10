import { closeCycle, testerRebateSats, type CycleCloseInput, type CycleCloseResult } from "./economics.ts";
import type { Accrual, LifetimeRow } from "./types.ts";

/** v3.3 ledger — the tables CursiveRoot does not have yet. Engine-only. */

export type CycleRecord = {
  cycle_id: number;
  cycle_opened_at: string;
  cycle_closed_at: string | null;
  revenue_sats: number;
  split_current: number;
  split_lifetime: number;
  metabolic_R: number | null;
  status: "open" | "closing" | "closed";
};

export type LifetimeFitnessEntry = {
  contributor_wallet: string;
  variant_id: string;
  cycle_id: number;
  fitness_score: number;
  sensor_set_version: string;
  recorded_at: string;
};

export type TesterRebate = {
  rebate_id: string;
  tester_wallet: string;
  cycle_id: number;
  rebate_sats: number;
  created_at: string;
};

export type Ledger = {
  cycles: CycleRecord[];
  lifetime: LifetimeFitnessEntry[];
  accruals: Accrual[];
  rebates: TesterRebate[];
};

export const EMPTY_LEDGER: Ledger = {
  cycles: [],
  lifetime: [],
  accruals: [],
  rebates: [],
};

export function openCycle(ledger: Ledger, cycle_id: number, opened_at: string, split_current: number): Ledger {
  if (ledger.cycles.some((c) => c.cycle_id === cycle_id)) return ledger;
  const row: CycleRecord = {
    cycle_id,
    cycle_opened_at: opened_at,
    cycle_closed_at: null,
    revenue_sats: 0,
    split_current,
    split_lifetime: 1 - split_current,
    metabolic_R: null,
    status: "open",
  };
  return { ...ledger, cycles: [row, ...ledger.cycles] };
}

export function lifetimeSum(ledger: Ledger): LifetimeRow[] {
  const map = new Map<string, number>();
  for (const row of ledger.lifetime) {
    map.set(row.contributor_wallet, (map.get(row.contributor_wallet) ?? 0) + row.fitness_score);
  }
  return [...map.entries()].map(([contributor_wallet, fitness]) => ({ contributor_wallet, fitness }));
}

export function closeIntoLedger(
  ledger: Ledger,
  input: CycleCloseInput,
  merges: Array<{ contributor_wallet: string; variant_id: string; fitness_delta: number }>,
  testers: Array<{ wallet: string; would_have_paid_usd: number }>,
  btcUsd: number,
  sensor_set_version = "v1.4.5",
): { ledger: Ledger; closed: CycleCloseResult } {
  const closed = closeCycle({ ...input, lifetime: lifetimeSum(ledger) });
  const lifetimeRows: LifetimeFitnessEntry[] = merges
    .filter((m) => m.fitness_delta > 0)
    .map((m) => ({
      contributor_wallet: m.contributor_wallet,
      variant_id: m.variant_id,
      cycle_id: input.cycle_id,
      fitness_score: m.fitness_delta,
      sensor_set_version,
      recorded_at: input.now_iso,
    }));

  const rebates: TesterRebate[] = testers.map((t) => ({
    rebate_id: `${input.cycle_id}:rebate:${t.wallet}`,
    tester_wallet: t.wallet,
    cycle_id: input.cycle_id,
    rebate_sats: testerRebateSats(t.would_have_paid_usd, btcUsd),
    created_at: input.now_iso,
  }));

  const cycle: CycleRecord = {
    cycle_id: input.cycle_id,
    cycle_opened_at:
      ledger.cycles.find((c) => c.cycle_id === input.cycle_id)?.cycle_opened_at ?? input.now_iso,
    cycle_closed_at: input.now_iso,
    revenue_sats: closed.revenue_sats,
    split_current: closed.split_current,
    split_lifetime: closed.split_lifetime,
    metabolic_R: closed.r_meta,
    status: "closed",
  };

  return {
    closed,
    ledger: {
      cycles: [cycle, ...ledger.cycles.filter((c) => c.cycle_id !== input.cycle_id)],
      lifetime: [...lifetimeRows, ...ledger.lifetime],
      accruals: [...closed.accruals, ...ledger.accruals],
      rebates: [...rebates, ...ledger.rebates],
    },
  };
}

export function testerHasFitness(ledger: Ledger, wallet: string) {
  return ledger.lifetime.some((r) => r.contributor_wallet === wallet);
}
