import type { MergeEvent, SeedBundle } from "./types.ts";
import { isoMs } from "./format.ts";
import type { QdElite } from "./propose.ts";

/**
 * MAP-Elites archive from live CursiveRoot seed_bundles.
 *
 * Bins match tools/qd_organism.py: 0=neg, 1=neu, 2=pos, ±1% neutral band.
 * Lower-is-better channels (cold-start, idle watts, memory refault) are inverted
 * so "pos" always means improvement. The proposer mutates the accepted parent
 * toward an empty neighboring cell. Screened / mined-out cells are not targets.
 */

export type Bin = 0 | 1 | 2;
export const BIN_LABEL = ["neg", "neu", "pos"] as const;
export const QD_AXES = ["cold", "sustained", "idle", "memory"] as const;
export const QD_CELL_COUNT = 81;
export const NEUTRAL_BAND_PCT = 1;

export type Bins = [Bin, Bin, Bin, Bin];

export type Descriptor = {
  bins: Bins;
  key: string;
  deltas: {
    coldstart_pct: number | null;
    sustained_pct: number | null;
    idle_pct: number | null;
    memory_pct: number | null;
  };
};

export type CellCoverage = "empty" | "covered" | "mined-null" | "rejected" | "screened";

export type QdCell = {
  key: string;
  bins: Bins;
  coverage: CellCoverage;
  occupants: number;
  elite_variant_id: string | null;
  elite_fitness: number;
  elite_decision: string | null;
};

export type QdArchive = {
  occupied: number;
  covered: number;
  parent_variant_id: string;
  parent_fitness: number;
  parent_cell: string | null;
  cells: QdCell[];
  empty_neighbors: QdCell[];
  note: string;
};

const MINED_OUT_RE = /pagecluster0|vfscache50/;

export function isMinedOutVariant(variantId: string | null | undefined) {
  return MINED_OUT_RE.test(String(variantId ?? ""));
}

export function pctDelta(
  variant: number | null | undefined,
  baseline: number | null | undefined,
): number | null {
  if (variant == null || baseline == null) return null;
  const b = Number(baseline);
  const v = Number(variant);
  if (!Number.isFinite(v) || !Number.isFinite(b) || b === 0) return null;
  return ((v - b) / Math.abs(b)) * 100;
}

export function binPct(value: number | null, band = NEUTRAL_BAND_PCT): Bin {
  if (value == null || !Number.isFinite(value)) return 1;
  if (value < -band) return 0;
  if (value > band) return 2;
  return 1;
}

export function cellKey(bins: Bins) {
  return `c${BIN_LABEL[bins[0]]}-s${BIN_LABEL[bins[1]]}-i${BIN_LABEL[bins[2]]}-m${BIN_LABEL[bins[3]]}`;
}

export function parseCellKey(key: string): Bins | null {
  const m = /^c(neg|neu|pos)-s(neg|neu|pos)-i(neg|neu|pos)-m(neg|neu|pos)$/.exec(key);
  if (!m) return null;
  const idx = (label: string) => BIN_LABEL.indexOf(label as (typeof BIN_LABEL)[number]) as Bin;
  return [idx(m[1]), idx(m[2]), idx(m[3]), idx(m[4])];
}

function metricsOf(bundle: SeedBundle) {
  return bundle.result_bundle?.metrics ?? null;
}

/** Invert lower-is-better channels so pos = improvement. */
export function descriptorFromBundle(bundle: SeedBundle): Descriptor | null {
  const metrics = metricsOf(bundle);
  if (!metrics?.variant || !metrics?.baseline) return null;
  const v = metrics.variant;
  const b = metrics.baseline;
  const cold = pctDelta(v.coldstart_ms, b.coldstart_ms);
  const sust = pctDelta(v.sustained_tokps, b.sustained_tokps);
  const idle = pctDelta(v.idle_watts, b.idle_watts);
  const mem = pctDelta(v.memory_refault_s, b.memory_refault_s);
  const bins: Bins = [
    binPct(cold == null ? null : -cold),
    binPct(sust),
    binPct(idle == null ? null : -idle),
    binPct(mem == null ? null : -mem),
  ];
  return {
    bins,
    key: cellKey(bins),
    deltas: {
      coldstart_pct: cold,
      sustained_pct: sust,
      idle_pct: idle,
      memory_pct: mem,
    },
  };
}

export function neighborBins(bins: Bins): Bins[] {
  const out: Bins[] = [];
  for (let i = 0; i < 4; i++) {
    for (const d of [-1, 1] as const) {
      const n = bins[i] + d;
      if (n < 0 || n > 2) continue;
      const next: Bins = [bins[0], bins[1], bins[2], bins[3]];
      next[i] = n as Bin;
      out.push(next);
    }
  }
  return out;
}

function coverageOf(
  occupants: SeedBundle[],
): CellCoverage {
  if (occupants.length === 0) return "empty";
  if (occupants.some((b) => b.decision === "accepted")) return "covered";
  if (occupants.some((b) => isMinedOutVariant(b.variant_id))) return "mined-null";
  if (occupants.some((b) => (b.decision ?? "").startsWith("rejected"))) return "rejected";
  return "screened";
}

function bestOf(occupants: SeedBundle[]) {
  const accepted = occupants.filter((b) => b.decision === "accepted");
  const pool = accepted.length ? accepted : occupants;
  return [...pool].sort((a, b) => Number(b.fitness_score ?? 0) - Number(a.fitness_score ?? 0))[0];
}

export function buildArchive(bundles: SeedBundle[]): QdArchive {
  const byCell = new Map<string, SeedBundle[]>();
  const descByVariant = new Map<string, Descriptor>();
  for (const bundle of bundles) {
    const desc = descriptorFromBundle(bundle);
    if (!desc) continue;
    descByVariant.set(bundle.variant_id, desc);
    const list = byCell.get(desc.key) ?? [];
    list.push(bundle);
    byCell.set(desc.key, list);
  }

  const cells: QdCell[] = [...byCell.entries()].map(([key, occupants]) => {
    const elite = bestOf(occupants);
    const bins = parseCellKey(key) ?? [1, 1, 1, 1];
    return {
      key,
      bins,
      coverage: coverageOf(occupants),
      occupants: occupants.length,
      elite_variant_id: elite?.variant_id ?? null,
      elite_fitness: Number(elite?.fitness_score ?? 0),
      elite_decision: elite?.decision ?? null,
    };
  });

  const accepted = bundles
    .filter((b) => b.decision === "accepted" && Number(b.fitness_score ?? 0) > 0)
    .sort((a, b) => Number(b.fitness_score ?? 0) - Number(a.fitness_score ?? 0));
  const parent = accepted[0];
  const parentDesc = parent ? descByVariant.get(parent.variant_id) : undefined;

  const empty_neighbors: QdCell[] = [];
  if (parentDesc) {
    for (const bins of neighborBins(parentDesc.bins)) {
      const key = cellKey(bins);
      const existing = cells.find((c) => c.key === key);
      if (existing) {
        if (existing.coverage === "empty") empty_neighbors.push(existing);
        continue;
      }
      empty_neighbors.push({
        key,
        bins,
        coverage: "empty",
        occupants: 0,
        elite_variant_id: null,
        elite_fitness: 0,
        elite_decision: null,
      });
    }
  }

  empty_neighbors.sort((a, b) => {
    const parentMem = parentDesc?.bins[3] ?? 2;
    const keepA = a.bins[3] === parentMem ? 1 : 0;
    const keepB = b.bins[3] === parentMem ? 1 : 0;
    if (keepB !== keepA) return keepB - keepA;
    const pos = (c: QdCell) => c.bins.filter((x) => x === 2).length;
    if (pos(b) !== pos(a)) return pos(b) - pos(a);
    return a.key.localeCompare(b.key);
  });

  const covered = cells.filter((c) => c.coverage === "covered").length;
  const note = parent
    ? empty_neighbors.length
      ? `Mutate ${parent.variant_id} toward an empty neighbor. Do not re-enter mined-out or screened cells.`
      : `Neighborhood of ${parent.variant_id} is screened. Need a new descriptor axis, not another sysctl cousin.`
    : "No accepted elite with metrics. QD refuses rather than mining the library.";

  return {
    occupied: cells.length,
    covered,
    parent_variant_id: parent?.variant_id ?? "v0.12",
    parent_fitness: Number(parent?.fitness_score ?? 0),
    parent_cell: parentDesc?.key ?? null,
    cells,
    empty_neighbors,
    note,
  };
}

export function underCoveredElites(archive: QdArchive): QdElite[] {
  if (!archive.parent_fitness || archive.parent_fitness <= 0) return [];
  return archive.empty_neighbors
    .filter((c) => c.coverage === "empty" && !isMinedOutVariant(c.elite_variant_id))
    .map((c) => ({
      cell: c.key,
      variant_id: archive.parent_variant_id,
      fitness: archive.parent_fitness,
      coverage: "under" as const,
      knobs: [],
    }));
}

export function mergesFromAccepted(bundles: SeedBundle[]): MergeEvent[] {
  const rows = bundles
    .filter((b) => !b.decision || b.decision === "accepted")
    .filter((b) => Number(b.fitness_score ?? 0) > 0)
    .sort((a, b) => isoMs(a.created_at) - isoMs(b.created_at));
  return rows.map((b, i) => ({
    contributor_wallet: b.contributor_id || "local-founder",
    variant_id: b.variant_id,
    fitness_delta: Number(b.fitness_score),
    prior_merge_count: i,
  }));
}
