import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildArchive,
  cellKey,
  descriptorFromBundle,
  isMinedOutVariant,
  mergesFromAccepted,
  underCoveredElites,
} from "./qd.ts";
import { proposeNext } from "./propose.ts";
import { metabolicR } from "./economics.ts";
import type { SeedBundle } from "./types.ts";

const v11: SeedBundle = {
  variant_id: "candidate-v0.11-zram-swappiness",
  decision: "accepted",
  fitness_score: 0.10037807,
  confidence: 0.875,
  reason: "fitness positive",
  machine_id: "42e7c7257af11f46",
  created_at: "2026-06-26T20:07:28.000Z",
  contributor_id: "local-founder",
  result_bundle: {
    metrics: {
      variant: {
        idle_watts: 2.77,
        coldstart_ms: 626.0,
        network_mbps: 1229.2,
        sustained_tokps: 33.58,
        memory_refault_s: 6.169,
      },
      baseline: {
        idle_watts: 2.79,
        coldstart_ms: 624.4,
        network_mbps: 1235.0,
        sustained_tokps: 33.81,
        memory_refault_s: 45.017,
      },
    },
  },
};

const vfs: SeedBundle = {
  variant_id: "candidate-v0.13-vfscache50",
  decision: "inconclusive",
  fitness_score: 0.00231799,
  confidence: 0.5,
  reason: "honest null",
  machine_id: "42e7c7257af11f46",
  created_at: "2026-07-07T00:00:00.000Z",
  contributor_id: "organism-proposer",
  result_bundle: {
    metrics: {
      variant: {
        idle_watts: 3.95,
        coldstart_ms: 1783.9,
        network_mbps: 1213.0,
        sustained_tokps: 45.89,
        memory_refault_s: 6.073,
      },
      baseline: {
        idle_watts: 3.96,
        coldstart_ms: 1787.2,
        network_mbps: 1245.9,
        sustained_tokps: 45.94,
        memory_refault_s: 6.094,
      },
    },
  },
};

const v9c: SeedBundle = {
  variant_id: "candidate-v0.9c-cpu-retained",
  decision: "accepted",
  fitness_score: 0.01480931,
  confidence: 0.875,
  reason: "fitness positive",
  machine_id: "3e6b165ddf112a75",
  created_at: "2026-06-20T06:42:08.000Z",
  contributor_id: "local-founder",
};

test("v0.11 lands in the memory-positive cell", () => {
  const d = descriptorFromBundle(v11);
  assert.ok(d);
  assert.equal(d.key, "cneu-sneu-ineu-mpos");
  assert.ok((d.deltas.memory_pct ?? 0) < -80);
});

test("vfscache50 is a mined-out occupant of the all-neutral cell", () => {
  const d = descriptorFromBundle(vfs);
  assert.ok(d);
  assert.equal(d.key, "cneu-sneu-ineu-mneu");
  assert.equal(isMinedOutVariant(vfs.variant_id), true);
});

test("archive proposes empty neighbors of v0.11 and skips the mined-out cell", () => {
  const archive = buildArchive([v11, vfs, v9c]);
  assert.equal(archive.parent_variant_id, "candidate-v0.11-zram-swappiness");
  assert.equal(archive.parent_cell, "cneu-sneu-ineu-mpos");
  assert.ok(archive.empty_neighbors.length > 0);
  const elites = underCoveredElites(archive);
  assert.ok(elites.every((e) => e.coverage === "under"));
  assert.ok(!elites.some((e) => e.cell === "cneu-sneu-ineu-mneu"));
  assert.ok(elites.some((e) => e.cell === "cpos-sneu-ineu-mpos"));
  const p = proposeNext({
    parent_variant_id: "v0.12",
    taken: [],
    source: "qd",
    elites,
    cycle_id: 7,
  });
  assert.equal(p.source, "qd-archive");
  assert.match(p.candidate_variant_id, /^v0\.14-qd-/);
  assert.equal(p.payout_eligible, false);
});

test("empty archive refuses", () => {
  const archive = buildArchive([]);
  assert.equal(underCoveredElites(archive).length, 0);
  assert.match(archive.note, /refuses/);
});

test("founder-only accepted lineage produces a metabolic R, not a population signal", () => {
  const merges = mergesFromAccepted([v9c, v11]);
  assert.equal(merges.length, 2);
  assert.equal(merges[0].prior_merge_count, 0);
  assert.equal(merges[1].prior_merge_count, 1);
  const r = metabolicR(merges);
  assert.ok(r != null && Number.isFinite(r));
  assert.ok(r > 1);
});

test("cellKey round-trips", () => {
  assert.equal(cellKey([1, 1, 1, 2]), "cneu-sneu-ineu-mpos");
});

test("cell elite prefers an accepted occupant over a higher-fitness baseline", () => {
  const genesis: SeedBundle = {
    ...v9c,
    variant_id: "genesis-baseline-v0.8",
    decision: "measured_baseline",
    fitness_score: 0.6012012,
    result_bundle: v11.result_bundle,
  };
  const archive = buildArchive([genesis, v11]);
  const cell = archive.cells.find((c) => c.key === "cneu-sneu-ineu-mpos");
  assert.equal(cell?.coverage, "covered");
  assert.equal(cell?.elite_variant_id, "candidate-v0.11-zram-swappiness");
});
