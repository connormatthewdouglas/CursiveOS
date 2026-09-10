import type { Accrual, RailMode, TransferIntent } from "./types";

/**
 * Payment rail — separate from the economics decision engine.
 * Signing keys never live in the browser. Mainnet is hard-blocked until the
 * trust spine sets production payout eligibility (it currently cannot).
 */

export const BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

export type RailsPolicy = {
  rail_mode: RailMode;
  paused: boolean;
  per_cycle_cap_sats: number;
  payout_eligible_production: boolean;
  settlement_address: string;
};

export const DEFAULT_RAILS_POLICY: RailsPolicy = {
  rail_mode: "internal_credits",
  paused: false,
  per_cycle_cap_sats: 100_000,
  payout_eligible_production: false,
  settlement_address: "bc1qorganismsettlementplaceholder000000000",
};

export function isBech32Address(value: string, network: "main" | "test" | "any" = "any") {
  const s = value.trim().toLowerCase();
  const prefixes =
    network === "main" ? ["bc1"] : network === "test" ? ["tb1"] : ["bc1", "tb1"];
  const prefix = prefixes.find((p) => s.startsWith(p));
  if (!prefix) return false;
  const rest = s.slice(prefix.length);
  if (rest.length < 14 || rest.length > 87) return false;
  const sep = rest.indexOf("1");
  // witness version is a single bech32 char after prefix; body must be charset
  return [...rest].every((c) => BECH32_CHARSET.includes(c) || c === "1") && sep !== 0;
}

export function railNetwork(mode: RailMode): "main" | "test" | "any" {
  if (mode === "crypto_mainnet") return "main";
  if (mode === "crypto_testnet") return "test";
  return "any";
}

export type ClaimRequest = {
  accrual: Accrual;
  destination_wallet: string;
  now_iso: string;
  policy: RailsPolicy;
  spent_this_cycle_sats: number;
};

export type ClaimResult =
  | { ok: true; intent: TransferIntent }
  | { ok: false; code: string; message: string };

export function claimAccrual(req: ClaimRequest): ClaimResult {
  const { accrual, destination_wallet, now_iso, policy, spent_this_cycle_sats } = req;

  if (accrual.claimed_at) {
    return { ok: false, code: "already_claimed", message: "Accrual already claimed." };
  }
  const now = Date.parse(now_iso);
  const deadline = Date.parse(accrual.claim_deadline);
  if (Number.isFinite(deadline) && now > deadline) {
    return {
      ok: false,
      code: "claim_window_expired",
      message: "Two-year claim window closed. Accrual enters redistribution.",
    };
  }
  if (policy.paused) {
    return { ok: false, code: "rails_paused", message: "Emergency pause is engaged." };
  }
  if (destination_wallet !== accrual.contributor_wallet) {
    return {
      ok: false,
      code: "wallet_mismatch",
      message: "Claim wallet must match the bound contributor wallet.",
    };
  }
  if (policy.rail_mode !== "internal_credits") {
    const net = railNetwork(policy.rail_mode);
    if (!isBech32Address(destination_wallet, net === "any" ? "main" : net)) {
      return {
        ok: false,
        code: "invalid_address",
        message: "Destination is not a valid bech32 address for this rail.",
      };
    }
  }
  if (policy.rail_mode === "crypto_mainnet" && !policy.payout_eligible_production) {
    return {
      ok: false,
      code: "mainnet_hard_gated",
      message:
        "Mainnet is hard-gated until origin-side recompute, key rotation, and hardware/wallet independence land.",
    };
  }
  if (spent_this_cycle_sats + accrual.amount_sats > policy.per_cycle_cap_sats) {
    return {
      ok: false,
      code: "cycle_cap",
      message: `Per-cycle payout cap of ${policy.per_cycle_cap_sats} sats would be exceeded.`,
    };
  }

  const blocked =
    policy.rail_mode !== "internal_credits" && !policy.payout_eligible_production;
  const intent: TransferIntent = {
    payout_id: `pay:${accrual.accrual_id}`,
    accrual_id: accrual.accrual_id,
    rail_mode: policy.rail_mode,
    destination_wallet,
    amount_sats: accrual.amount_sats,
    tx_status: blocked ? "blocked" : "queued",
    tx_hash: null,
    retries: 0,
    last_error: null,
    blocked_reason: blocked
      ? "payout_eligible is hard-false; rail may queue but must not sign or broadcast."
      : null,
    created_at: now_iso,
  };

  return { ok: true, intent };
}

export function simulateConfirm(intent: TransferIntent, nowIso: string): TransferIntent {
  if (intent.tx_status === "blocked") return intent;
  if (intent.rail_mode === "crypto_mainnet") {
    return {
      ...intent,
      tx_status: "blocked",
      blocked_reason: "Refusing to fabricate a mainnet tx hash.",
      last_error: "mainnet_hard_gated",
    };
  }
  const seed = `${intent.payout_id}:${nowIso}`;
  const hash = fakeHash(seed);
  return {
    ...intent,
    tx_status: "confirmed",
    tx_hash:
      intent.rail_mode === "internal_credits" ? `sim:${hash}` : `testnet:${hash}`,
  };
}

function fakeHash(s: string) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0).toString(16).padStart(8, "0");
}

export function railLabel(mode: RailMode) {
  if (mode === "crypto_mainnet") return "BTC mainnet";
  if (mode === "crypto_testnet") return "BTC testnet";
  return "internal credits";
}
