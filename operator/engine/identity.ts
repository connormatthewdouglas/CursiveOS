import type { Machine, MachineAlias, MachineCapability, MeasurementJob } from "./types";
import { isoMs } from "./format.ts";

/** Founder-fleet canonical ids from docs/os0-machine-identity-contract.md */
export const CANONICAL_LAPTOP = "42e7c7257af11f46";
export const CANONICAL_STARDUST = "3e6b165ddf112a75";
export const HISTORICAL_FX_STARDUST =
  "amd-fxtm-8350-eight-core-processor-stardust";
export const OLD_DAEMON_LAPTOP = "7ba4f665a3bb4fb8";

export const LENOVO_HW_TUPLE =
  "11th Gen Intel(R) Core(TM) i5-11300H @ 3.10GHz|LENOVO|LNVNB161216|[10de:1f9d][8086:9a49]";

function toHex(bytes: ArrayBuffer | Uint8Array) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  return [...view].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Wrapper/daemon fingerprint v2.
 * machine_id = sha256(HW_ID_TUPLE + "\n").hexdigest()[:16]
 * Matches `echo "$HW_ID_TUPLE" | sha256sum | cut -c1-16`.
 */
export async function fullTestFingerprint(hwIdTuple: string): Promise<string> {
  const data = new TextEncoder().encode(`${hwIdTuple}\n`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return toHex(digest).slice(0, 16);
}

export function aliasLookup(aliases: MachineAlias[] | null | undefined) {
  return Object.fromEntries((aliases || []).map((a) => [a.alias, a.machine_id]));
}

export function aliasKeySet(aliases: MachineAlias[] | null | undefined) {
  return new Set((aliases || []).map((a) => a.alias));
}

export function canonicalizer(aliases: MachineAlias[] | null | undefined) {
  const aliasTo = aliasLookup(aliases);
  return (id: string | null | undefined) => aliasTo[id ?? ""] || id || "";
}

export function physicalMachines(
  machines: Machine[] | null | undefined,
  aliases: MachineAlias[] | null | undefined,
) {
  const aliasKeys = aliasKeySet(aliases);
  return (machines || []).filter((m) => !aliasKeys.has(m.machine_id));
}

export function fingerprintCount(
  machineId: string,
  aliases: MachineAlias[] | null | undefined,
) {
  return 1 + (aliases || []).filter((a) => a.machine_id === machineId).length;
}

export function activeJobCount(jobs: MeasurementJob[] | null | undefined) {
  return (jobs || []).filter((j) => j.status === "claimed" || j.status === "running")
    .length;
}

export function collapseCapabilities(
  caps: MachineCapability[] | null | undefined,
  canon: (id: string | null | undefined) => string,
) {
  const byMachine = new Map<
    string,
    MachineCapability & {
      canonical_machine_id: string;
      alias_machine_id: string | null;
    }
  >();
  for (const cap of caps || []) {
    const canonical = canon(cap.machine_id);
    const row = {
      ...cap,
      canonical_machine_id: canonical,
      alias_machine_id:
        canonical && cap.machine_id && canonical !== cap.machine_id
          ? cap.machine_id
          : null,
    };
    const prior = byMachine.get(canonical);
    if (!prior || isoMs(row.last_seen_at) >= isoMs(prior.last_seen_at)) {
      byMachine.set(canonical, row);
    }
  }
  return [...byMachine.values()].sort(
    (a, b) => isoMs(b.last_seen_at) - isoMs(a.last_seen_at),
  );
}

export function machineDisplayName(id: string) {
  if (id === CANONICAL_LAPTOP) return "Elizabeth laptop";
  if (id === CANONICAL_STARDUST) return "Stardust Arc";
  if (id === HISTORICAL_FX_STARDUST) return "Stardust FX (historical)";
  return id.slice(0, 12);
}

/**
 * Population confirmation N from economics v3.3 §6.3.
 * N = max(1, min(5, floor(sqrt(fleet_size))))
 */
export function confirmationThreshold(fleetSize: number) {
  if (!Number.isFinite(fleetSize) || fleetSize <= 0) return 1;
  return Math.max(1, Math.min(5, Math.floor(Math.sqrt(fleetSize))));
}

export type IndependenceWitness = {
  machine_id: string;
  wallet?: string | null;
  identity_public_key?: string | null;
};

export type IndependenceResult = {
  independent_count: number;
  unique_machines: string[];
  rejected: Array<{ witness: IndependenceWitness; reason: string }>;
  ok: boolean;
  required: number;
};

/**
 * Hardware/wallet independence: two confirmations do not count as independent
 * if they share a canonical machine, a wallet, or an identity key.
 */
export function independentConfirmations(
  witnesses: IndependenceWitness[],
  aliases: MachineAlias[],
  fleetSize: number,
): IndependenceResult {
  const canon = canonicalizer(aliases);
  const seenMachines = new Set<string>();
  const seenWallets = new Set<string>();
  const seenKeys = new Set<string>();
  const unique: string[] = [];
  const rejected: IndependenceResult["rejected"] = [];

  for (const w of witnesses) {
    const machine = canon(w.machine_id);
    if (!machine) {
      rejected.push({ witness: w, reason: "missing_machine_id" });
      continue;
    }
    if (seenMachines.has(machine)) {
      rejected.push({ witness: w, reason: "same_physical_machine" });
      continue;
    }
    if (w.wallet && seenWallets.has(w.wallet)) {
      rejected.push({ witness: w, reason: "same_wallet" });
      continue;
    }
    if (w.identity_public_key && seenKeys.has(w.identity_public_key)) {
      rejected.push({ witness: w, reason: "same_identity_key" });
      continue;
    }
    seenMachines.add(machine);
    if (w.wallet) seenWallets.add(w.wallet);
    if (w.identity_public_key) seenKeys.add(w.identity_public_key);
    unique.push(machine);
  }

  const required = confirmationThreshold(fleetSize);
  return {
    independent_count: unique.length,
    unique_machines: unique,
    rejected,
    ok: unique.length >= required,
    required,
  };
}
