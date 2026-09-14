import type { Accrual, LifetimeRow, MergeEvent, StreamType } from "./types";

/** Layer 5 Economics v3.3 — decision engine. No rail execution lives here. */

export const GENESIS_SPLIT_CURRENT = 0.2;
export const GENESIS_SPLIT_LIFETIME = 0.8;
export const MAX_SPLIT_DELTA = 0.025;
export const CLAIM_WINDOW_MS = 2 * 365.25 * 24 * 60 * 60 * 1000;
export const ACTIVE_CLAIMANT_MS = 24 * 30.4375 * 24 * 60 * 60 * 1000;
export const FAST_TIER_USD = 2;
export const STABLE_TIER_USD = 0;

export function newWeight(priorMergeCount: number) {
  const n = Math.max(0, priorMergeCount);
  return 1 / (1 + n);
}

export function returningWeight(priorMergeCount: number) {
  return 1 - newWeight(priorMergeCount);
}

/**
 * R_meta = Σ(new_weight × fitness) / Σ(returning_weight × fitness)
 * Over a rolling window of merges. Returns null when the denominator is 0
 * (founder-only bootstrap: no returning-contributor signal yet).
 */
export function metabolicR(merges: MergeEvent[]): number | null {
  let newSum = 0;
  let retSum = 0;
  for (const m of merges) {
    const f = Math.max(0, m.fitness_delta);
    newSum += newWeight(m.prior_merge_count) * f;
    retSum += returningWeight(m.prior_merge_count) * f;
  }
  if (retSum <= 0) return newSum > 0 ? Number.POSITIVE_INFINITY : null;
  return newSum / retSum;
}

/**
 * Soft restoring force toward genesis. No hard floor/ceiling.
 * Extreme splits are mechanically hard to reach and easy to move back from.
 */
export function restoringFactor(splitCurrent: number, neutral = GENESIS_SPLIT_CURRENT) {
  const distance = splitCurrent - neutral;
  return 1 / (1 + (distance / 0.3) ** 2);
}

export function targetSplitCurrent(rMeta: number | null, neutral = GENESIS_SPLIT_CURRENT) {
  if (rMeta == null) return neutral;
  if (!Number.isFinite(rMeta)) return Math.min(0.95, neutral + 0.35);
  const logR = Math.log(Math.max(rMeta, 1e-9));
  return neutral + 0.25 * Math.tanh(logR);
}

export function nextSplit(opts: {
  splitCurrent: number;
  rMeta: number | null;
  maxDelta?: number;
  neutral?: number;
}) {
  const maxDelta = opts.maxDelta ?? MAX_SPLIT_DELTA;
  const target = targetSplitCurrent(opts.rMeta, opts.neutral);
  const restoring = restoringFactor(opts.splitCurrent, opts.neutral);
  const raw = target - opts.splitCurrent;
  const step = Math.sign(raw) * Math.min(maxDelta, Math.abs(raw)) * restoring;
  const splitCurrent = clamp01(opts.splitCurrent + step);
  return {
    split_current: splitCurrent,
    split_lifetime: 1 - splitCurrent,
    s_target: clamp01(target),
    r_meta: opts.rMeta,
    delta_applied: step,
  };
}

function clamp01(n: number) {
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}

/** Largest-remainder integer allocation so sats never leak or over-issue. */
export function allocateSats(
  total: number,
  weights: Array<{ id: string; weight: number }>,
): Record<string, number> {
  const out: Record<string, number> = {};
  const eligible = weights.filter((w) => w.weight > 0);
  const sum = eligible.reduce((a, w) => a + w.weight, 0);
  if (total <= 0 || sum <= 0 || eligible.length === 0) {
    for (const w of weights) out[w.id] = 0;
    return out;
  }
  const floors: Array<{ id: string; floor: number; frac: number }> = [];
  let used = 0;
  for (const w of eligible) {
    const exact = (total * w.weight) / sum;
    const floor = Math.floor(exact);
    floors.push({ id: w.id, floor, frac: exact - floor });
    used += floor;
  }
  floors.sort((a, b) => b.frac - a.frac);
  let remainder = total - used;
  for (const row of floors) {
    const extra = remainder > 0 ? 1 : 0;
    out[row.id] = row.floor + extra;
    remainder -= extra;
  }
  for (const w of weights) if (out[w.id] == null) out[w.id] = 0;
  return out;
}

export type CycleCloseInput = {
  cycle_id: number;
  revenue_sats: number;
  split_current: number;
  merges: MergeEvent[];
  lifetime: LifetimeRow[];
  now_iso: string;
  expired_accruals?: Accrual[];
  recent_claims?: Array<{ wallet: string; claimed_at: string }>;
};

export type CycleCloseResult = {
  cycle_id: number;
  revenue_sats: number;
  split_current: number;
  split_lifetime: number;
  r_meta: number | null;
  next_split_current: number;
  next_split_lifetime: number;
  current_stream_sats: number;
  lifetime_stream_sats: number;
  redistribution_sats: number;
  accruals: Accrual[];
  updated_lifetime: LifetimeRow[];
  zero_revenue: boolean;
};

function deadlineIso(nowIso: string) {
  const t = Date.parse(nowIso);
  return new Date(t + CLAIM_WINDOW_MS).toISOString();
}

function accrual(
  cycle_id: number,
  wallet: string,
  stream: StreamType,
  amount: number,
  nowIso: string,
): Accrual {
  return {
    accrual_id: `${cycle_id}:${stream}:${wallet}`,
    contributor_wallet: wallet,
    cycle_id,
    stream_type: stream,
    amount_sats: amount,
    created_at: nowIso,
    claim_deadline: deadlineIso(nowIso),
    claimed_at: null,
    claim_tx_id: null,
  };
}

export function isActiveClaimant(
  wallet: string,
  recentClaims: Array<{ wallet: string; claimed_at: string }>,
  nowIso: string,
) {
  const now = Date.parse(nowIso);
  return recentClaims.some((c) => {
    if (c.wallet !== wallet) return false;
    const t = Date.parse(c.claimed_at);
    return Number.isFinite(t) && now - t <= ACTIVE_CLAIMANT_MS;
  });
}

/**
 * Cycle close per v3.3 §2 / §5.
 * Zero revenue → no accruals, split still updates from metabolic signal.
 * Testers are not an input: they never receive lifetime fitness.
 */
export function closeCycle(input: CycleCloseInput): CycleCloseResult {
  const splitCurrent = clamp01(input.split_current);
  const splitLifetime = 1 - splitCurrent;
  const rMeta = metabolicR(input.merges);
  const nxt = nextSplit({ splitCurrent, rMeta });

  const merged = input.merges.filter((m) => m.fitness_delta > 0);
  const lifetimeMap = new Map(input.lifetime.map((r) => [r.contributor_wallet, r.fitness]));
  for (const m of merged) {
    lifetimeMap.set(
      m.contributor_wallet,
      (lifetimeMap.get(m.contributor_wallet) ?? 0) + m.fitness_delta,
    );
  }
  const updated_lifetime = [...lifetimeMap.entries()].map(([contributor_wallet, fitness]) => ({
    contributor_wallet,
    fitness,
  }));

  if (input.revenue_sats <= 0) {
    return {
      cycle_id: input.cycle_id,
      revenue_sats: 0,
      split_current: splitCurrent,
      split_lifetime: splitLifetime,
      r_meta: rMeta,
      next_split_current: nxt.split_current,
      next_split_lifetime: nxt.split_lifetime,
      current_stream_sats: 0,
      lifetime_stream_sats: 0,
      redistribution_sats: 0,
      accruals: [],
      updated_lifetime,
      zero_revenue: true,
    };
  }

  const current_stream_sats = Math.floor(input.revenue_sats * splitCurrent);
  const lifetime_stream_sats = input.revenue_sats - current_stream_sats;

  const currentAlloc = allocateSats(
    current_stream_sats,
    merged.map((m) => ({ id: m.contributor_wallet, weight: m.fitness_delta })),
  );
  const lifeAlloc = allocateSats(
    lifetime_stream_sats,
    updated_lifetime.map((r) => ({ id: r.contributor_wallet, weight: r.fitness })),
  );

  const accruals: Accrual[] = [];
  for (const [wallet, amount] of Object.entries(currentAlloc)) {
    if (amount > 0) accruals.push(accrual(input.cycle_id, wallet, "current", amount, input.now_iso));
  }
  for (const [wallet, amount] of Object.entries(lifeAlloc)) {
    if (amount > 0) accruals.push(accrual(input.cycle_id, wallet, "lifetime", amount, input.now_iso));
  }

  const expired = (input.expired_accruals ?? []).filter((a) => !a.claimed_at && a.amount_sats > 0);
  const redistribution_sats = expired.reduce((s, a) => s + a.amount_sats, 0);
  if (redistribution_sats > 0) {
    const claimants = updated_lifetime
      .map((r) => r.contributor_wallet)
      .filter((w) => isActiveClaimant(w, input.recent_claims ?? [], input.now_iso));
    const redistAlloc = allocateSats(
      redistribution_sats,
      claimants.map((id) => ({
        id,
        weight: lifetimeMap.get(id) ?? 0,
      })),
    );
    for (const [wallet, amount] of Object.entries(redistAlloc)) {
      if (amount > 0) {
        accruals.push(accrual(input.cycle_id, wallet, "redistribution", amount, input.now_iso));
      }
    }
  }

  return {
    cycle_id: input.cycle_id,
    revenue_sats: input.revenue_sats,
    split_current: splitCurrent,
    split_lifetime: splitLifetime,
    r_meta: rMeta,
    next_split_current: nxt.split_current,
    next_split_lifetime: nxt.split_lifetime,
    current_stream_sats,
    lifetime_stream_sats,
    redistribution_sats,
    accruals,
    updated_lifetime,
    zero_revenue: false,
  };
}

export function usdToSats(usd: number, btcPriceUsd: number) {
  if (btcPriceUsd <= 0 || usd <= 0) return 0;
  return Math.round((usd / btcPriceUsd) * 100_000_000);
}

export function testerRebateSats(fastUserWouldHavePaidUsd: number, btcPriceUsd: number) {
  return usdToSats(fastUserWouldHavePaidUsd, btcPriceUsd);
}
