import { isBech32Address, railNetwork, type RailsPolicy } from "./rails.ts";
import type { Accrual, TransferIntent } from "./types.ts";

/**
 * Unsigned payment intent. Not a Bitcoin Core PSBT, and never a signing key.
 * Mainnet cannot produce an intent that looks broadcastable.
 */

export type PsbtOutput = {
  address: string;
  amount_sats: number;
};

export type PsbtIntent = {
  version: "cursiveos-psbt-intent-v0";
  network: "main" | "test" | "internal";
  accrual_id: string;
  outputs: PsbtOutput[];
  unsigned: true;
  signing_key_present: false;
  broadcastable: false;
  blocked_reason: string | null;
  created_at: string;
};

export type PsbtResult =
  | { ok: true; intent: PsbtIntent }
  | { ok: false; code: string; message: string };

export function buildPsbtIntent(opts: {
  accrual: Accrual;
  destination: string;
  policy: RailsPolicy;
  now_iso: string;
  organism_settlement?: string;
}): PsbtResult {
  const { accrual, destination, policy, now_iso } = opts;
  if (policy.paused) return { ok: false, code: "rails_paused", message: "Emergency pause is engaged." };
  if (accrual.claimed_at) return { ok: false, code: "already_claimed", message: "Accrual already claimed." };
  if (policy.rail_mode === "crypto_mainnet" && !policy.payout_eligible_production) {
    return {
      ok: false,
      code: "mainnet_hard_gated",
      message: "Refusing to build a mainnet-shaped PSBT while payout_eligible is hard-false.",
    };
  }
  if (policy.rail_mode !== "internal_credits") {
    const net = railNetwork(policy.rail_mode);
    if (!isBech32Address(destination, net === "any" ? "main" : net)) {
      return { ok: false, code: "invalid_address", message: "Destination is not bech32 for this rail." };
    }
  }

  const network: PsbtIntent["network"] =
    policy.rail_mode === "crypto_mainnet" ? "main" : policy.rail_mode === "crypto_testnet" ? "test" : "internal";

  return {
    ok: true,
    intent: {
      version: "cursiveos-psbt-intent-v0",
      network,
      accrual_id: accrual.accrual_id,
      outputs: [{ address: destination, amount_sats: accrual.amount_sats }],
      unsigned: true,
      signing_key_present: false,
      broadcastable: false,
      blocked_reason:
        policy.rail_mode === "internal_credits"
          ? "internal credits — no Bitcoin transaction exists"
          : "unsigned intent only; organism settlement key is not in this console",
      created_at: now_iso,
    },
  };
}

export function intentFromTransfer(t: TransferIntent, now_iso: string): PsbtIntent {
  return {
    version: "cursiveos-psbt-intent-v0",
    network: t.rail_mode === "crypto_mainnet" ? "main" : t.rail_mode === "crypto_testnet" ? "test" : "internal",
    accrual_id: t.accrual_id,
    outputs: [{ address: t.destination_wallet, amount_sats: t.amount_sats }],
    unsigned: true,
    signing_key_present: false,
    broadcastable: false,
    blocked_reason: t.blocked_reason ?? "unsigned",
    created_at: now_iso,
  };
}
