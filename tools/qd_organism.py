#!/usr/bin/env python3
"""
Quality-diversity evolutionary archive + autonomous proposer for seed-organism variants.

Pure domain logic: descriptor binning, archive, mutations, synthetic metrics, and a
closed simulation loop. Every candidate routes through seed_organism.score_performance,
evaluate_regression, and verdict unchanged.
"""

from __future__ import annotations

import copy
import json
import random
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import seed_organism


DEFAULT_BASELINE_METRICS = {
    "network_mbps": 930.0,
    "coldstart_ms": 1820.0,
    "sustained_tokps": 41.0,
    "idle_watts": 71.0,
}

DEFAULT_NOISE_PROFILE = {
    "coldstart_ms": 0.005,
    "sustained_tokps": 0.012,
    "idle_watts": 0.010,
    "network_mbps": 0.040,
}

KNOB_NAMES = (
    "cpu_governor_boost",
    "gpu_idle_pin_mhz",
    "scheduler_aggressive",
    "power_cap_relief",
)

MUTATION_OPERATORS = ("knob_tweak", "knob_remove", "scale_profile")

KNOB_ACTIVE_THRESHOLD = 0.05


def bin_descriptor_pct(value: float | None, *, neutral_band: float = 1.0) -> int:
    """0=negative, 1=neutral, 2=positive."""
    if value is None:
        return 1
    if value < -neutral_band:
        return 0
    if value > neutral_band:
        return 2
    return 1


def descriptor_cell_key(sensor: dict[str, Any], variant: dict[str, Any]) -> tuple[int, ...]:
    deltas = sensor.get("delta", {})
    knobs_removed = int(variant.get("knobs_removed_vs_parent", 0) or 0)
    idle_cost = deltas.get("idle_power_pct")
    idle_behavior = None if idle_cost is None else -float(idle_cost)
    parsimony_bin = min(knobs_removed, 2)
    return (
        bin_descriptor_pct(deltas.get("coldstart_pct")),
        bin_descriptor_pct(deltas.get("sustained_pct")),
        bin_descriptor_pct(idle_behavior),
        parsimony_bin,
    )


@dataclass
class ArchiveElite:
    variant: dict[str, Any]
    sensor: dict[str, Any]
    regression: dict[str, Any]
    metrics: dict[str, Any]
    cell_key: tuple[int, ...]
    fitness_score: float
    generation: int
    decision: str
    reason: str


@dataclass
class QualityDiversityArchive:
    """MAP-Elites-style archive: one elite per behavioral cell, replaced by higher fitness."""

    cells: dict[tuple[int, ...], ArchiveElite] = field(default_factory=dict)
    rejected_regressions: int = 0
    rejected_negative: int = 0
    inconclusive: int = 0

    def insert(self, elite: ArchiveElite) -> bool:
        current = self.cells.get(elite.cell_key)
        if current is None or elite.fitness_score > current.fitness_score:
            self.cells[elite.cell_key] = elite
            return True
        return False

    def occupied_cell_count(self) -> int:
        return len(self.cells)

    def elite_count(self) -> int:
        return len(self.cells)

    def elites(self) -> list[ArchiveElite]:
        return list(self.cells.values())

    def max_fitness(self) -> float:
        if not self.cells:
            return 0.0
        return max(e.fitness_score for e in self.cells.values())

    def select_parents(self, rng: random.Random, count: int = 2) -> list[ArchiveElite]:
        pool = self.elites()
        if not pool:
            return []
        if len(pool) <= count:
            return pool
        by_fitness = sorted(pool, key=lambda e: e.fitness_score, reverse=True)
        parents: list[ArchiveElite] = [by_fitness[0]]
        used_cells = {by_fitness[0].cell_key}
        for elite in by_fitness[1:]:
            if elite.cell_key not in used_cells:
                parents.append(elite)
                used_cells.add(elite.cell_key)
            if len(parents) >= count:
                break
        while len(parents) < count:
            pick = by_fitness[rng.randrange(min(3, len(by_fitness)))]
            if pick not in parents:
                parents.append(pick)
        return parents[:count]


def default_knobs() -> dict[str, float]:
    return {name: 0.0 for name in KNOB_NAMES}


def knobs_from_variant(variant: dict[str, Any]) -> dict[str, float]:
    raw = variant.get("genome_knobs", {})
    knobs = default_knobs()
    if isinstance(raw, dict):
        for key in KNOB_NAMES:
            if key in raw:
                knobs[key] = float(raw[key])
    return knobs


def knob_is_active(value: float) -> bool:
    return float(value) > KNOB_ACTIVE_THRESHOLD


def count_knobs_removed_vs_parent(
    parent_knobs: dict[str, float],
    child_knobs: dict[str, float],
) -> int:
    """Count knobs that were active in parent and inactive in child (immediate parent only)."""
    removed = 0
    for key in KNOB_NAMES:
        if knob_is_active(parent_knobs.get(key, 0.0)) and not knob_is_active(child_knobs.get(key, 0.0)):
            removed += 1
    return removed


def sync_parsimony_from_genome(variant: dict[str, Any]) -> int:
    """
    Overwrite knobs_removed_vs_parent from genome truth vs stored parent snapshot.
    Prevents declared-over-actual parsimony gaming before score_performance runs.
    """
    parent_knobs = variant.get("parent_genome_knobs")
    child_knobs = knobs_from_variant(variant)
    if not isinstance(parent_knobs, dict):
        variant["knobs_removed_vs_parent"] = 0
        return 0
    removed = count_knobs_removed_vs_parent(parent_knobs, child_knobs)
    variant["knobs_removed_vs_parent"] = removed
    return removed


def make_variant(
    *,
    variant_id: str,
    parent: dict[str, Any] | None,
    knobs: dict[str, float],
    generation: int = 0,
    mutation_operator: str | None = None,
) -> dict[str, Any]:
    child_knobs = dict(knobs)
    knobs_removed = 0
    if parent is not None:
        parent_knobs = knobs_from_variant(parent)
        knobs_removed = count_knobs_removed_vs_parent(parent_knobs, child_knobs)
    variant = {
        "schema_version": "seed-organism.variant.qd-sim.v0.1",
        "variant_id": variant_id,
        "contributor_id": "qd-simulator",
        "commit_ref": "qd-sim",
        "preset_version": "qd-sim",
        "declared_scope": "quality-diversity simulation only",
        "rollback_method": "simulation discard",
        "fitness_eligible": True,
        "genome_knobs": child_knobs,
        "knobs_removed_vs_parent": knobs_removed,
        "qd_generation": generation,
    }
    if mutation_operator:
        variant["mutation_operator"] = mutation_operator
    if parent is not None:
        variant["parent_variant_id"] = parent.get("variant_id")
        variant["parent_genome_knobs"] = knobs_from_variant(parent)
    return variant


def apply_knob_tweak(knobs: dict[str, float], rng: random.Random) -> dict[str, float]:
    out = dict(knobs)
    key = rng.choice(KNOB_NAMES)
    step = rng.choice([-0.15, -0.10, 0.10, 0.15, 0.20])
    out[key] = max(0.0, min(1.5, out[key] + step))
    return out


def apply_knob_remove(knobs: dict[str, float], rng: random.Random) -> tuple[dict[str, float], bool]:
    out = dict(knobs)
    active = [k for k in KNOB_NAMES if knob_is_active(out[k])]
    if not active:
        return apply_knob_tweak(out, rng), False
    key = rng.choice(active)
    out[key] = 0.0
    return out, True


def apply_scale_profile(knobs: dict[str, float], rng: random.Random) -> dict[str, float]:
    factor = rng.choice([0.85, 0.9, 1.1, 1.15])
    return {k: max(0.0, min(1.5, v * factor)) for k, v in knobs.items()}


def mutate_genome(
    parent_variant: dict[str, Any],
    *,
    rng: random.Random,
    variant_id: str,
    generation: int,
) -> dict[str, Any]:
    knobs = knobs_from_variant(parent_variant)
    op = rng.choice(MUTATION_OPERATORS)
    if op == "knob_tweak":
        knobs = apply_knob_tweak(knobs, rng)
    elif op == "knob_remove":
        knobs, _removed = apply_knob_remove(knobs, rng)
    else:
        knobs = apply_scale_profile(knobs, rng)
    return make_variant(
        variant_id=variant_id,
        parent=parent_variant,
        knobs=knobs,
        generation=generation,
        mutation_operator=op,
    )


def propose_offspring(
    archive: QualityDiversityArchive,
    *,
    rng: random.Random,
    generation: int,
    variant_counter: int,
) -> dict[str, Any]:
    parents = archive.select_parents(rng, count=2)
    if not parents:
        raise seed_organism.SeedError("QD archive empty; cannot propose offspring")
    parent = parents[rng.randrange(len(parents))]
    return mutate_genome(
        parent.variant,
        rng=rng,
        variant_id=f"qd-sim-g{generation:03d}-{variant_counter:04d}",
        generation=generation,
    )


def apply_knobs_to_metrics(
    baseline: dict[str, float],
    knobs: dict[str, float],
) -> dict[str, float]:
    cold_factor = 1.0 - (0.035 * knobs["cpu_governor_boost"] + 0.025 * knobs["gpu_idle_pin_mhz"])
    sustained_factor = 1.0 + (0.018 * knobs["scheduler_aggressive"])
    idle_factor = 1.0 + (
        0.022 * knobs["cpu_governor_boost"]
        + 0.015 * knobs["scheduler_aggressive"]
        - 0.030 * knobs["power_cap_relief"]
    )
    network_factor = 1.0 + (0.008 * knobs["scheduler_aggressive"])
    return {
        "network_mbps": baseline["network_mbps"] * network_factor,
        "coldstart_ms": max(400.0, baseline["coldstart_ms"] * cold_factor),
        "sustained_tokps": baseline["sustained_tokps"] * sustained_factor,
        "idle_watts": max(50.0, baseline["idle_watts"] * idle_factor),
    }


def apply_noise(value: float, rel_noise: float, rng: random.Random) -> float:
    if rel_noise <= 0:
        return value
    draw = rng.gauss(0.0, rel_noise)
    return value * (1.0 + draw)


def synthesize_metrics(
    variant: dict[str, Any],
    *,
    baseline_metrics: dict[str, float] | None = None,
    noise_profile: dict[str, float] | None = None,
    rng: random.Random,
    machine_id: str = "qd-sim-host",
    force_regression: bool = False,
) -> dict[str, Any]:
    baseline = dict(baseline_metrics or DEFAULT_BASELINE_METRICS)
    noise = dict(noise_profile or DEFAULT_NOISE_PROFILE)
    knobs = knobs_from_variant(variant)
    tuned = apply_knobs_to_metrics(baseline, knobs)
    variant_metrics = {
        key: apply_noise(tuned[key], noise.get(key, 0.01), rng)
        for key in baseline
    }
    regression = {
        "full_test_passed": True,
        "reverted_cleanly": not force_regression,
        "host_safety_passed": True,
        "failures": [] if not force_regression else ["simulated dirty revert"],
    }
    return {
        "schema_version": "seed-organism.metrics.qd-sim.v0.1",
        "machine_id": machine_id,
        "preset_version": variant.get("preset_version", "qd-sim"),
        "baseline": dict(baseline),
        "variant": variant_metrics,
        "sample_counts": {"network": 3, "coldstart": 3, "sustained": 3, "idle_power": 5},
        "regression": regression,
        "simulation": {
            "genome_knobs": knobs,
            "noise_profile": noise,
        },
    }


def evaluate_variant(
    variant: dict[str, Any],
    metrics: dict[str, Any],
    config: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any], str, str]:
    sync_parsimony_from_genome(variant)
    sensor = seed_organism.score_performance(variant=variant, metrics=metrics, config=config)
    regression = seed_organism.evaluate_regression(variant, metrics)
    decision, reason = seed_organism.verdict(variant, sensor, regression, config)
    return sensor, regression, decision, reason


@dataclass
class SimulationStepResult:
    generation: int
    variant_id: str
    decision: str
    reason: str
    fitness_score: float
    cell_key: tuple[int, ...] | None
    archived: bool
    mutation_operator: str | None


@dataclass
class SimulationReport:
    seed: int
    generations: int
    proposals: int
    accepted_count: int
    archive_size: int
    occupied_cells: int
    max_fitness: float
    rejected_regressions: int
    rejected_negative: int
    inconclusive: int
    elites: list[dict[str, Any]]
    steps: list[dict[str, Any]]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": "seed-organism.qd-simulation-report.v0.1",
            "seed": self.seed,
            "generations": self.generations,
            "proposals": self.proposals,
            "accepted_count": self.accepted_count,
            "archive_size": self.archive_size,
            "occupied_cells": self.occupied_cells,
            "max_fitness": round(self.max_fitness, 8),
            "rejected_regressions": self.rejected_regressions,
            "rejected_negative": self.rejected_negative,
            "inconclusive": self.inconclusive,
            "elites": self.elites,
            "steps": self.steps,
        }


def seed_archive(
    archive: QualityDiversityArchive,
    config: dict[str, Any],
    *,
    rng: random.Random,
) -> ArchiveElite | None:
    """Bootstrap archive with a cold-start-focused accepted elite."""
    knobs = {
        "cpu_governor_boost": 0.35,
        "gpu_idle_pin_mhz": 0.20,
        "scheduler_aggressive": 0.05,
        "power_cap_relief": 0.10,
    }
    variant = make_variant(
        variant_id="qd-sim-seed-coldstart",
        parent=None,
        knobs=knobs,
        generation=0,
        mutation_operator="seed",
    )
    zero_noise = {k: 0.0 for k in DEFAULT_NOISE_PROFILE}
    metrics = synthesize_metrics(variant, rng=rng, noise_profile=zero_noise)
    sensor, regression, decision, reason = evaluate_variant(variant, metrics, config)
    if decision != "accepted":
        raise seed_organism.SeedError(
            f"QD seed bootstrap failed: {decision} ({reason}); fitness={sensor['fitness_score']}"
        )
    cell_key = descriptor_cell_key(sensor, variant)
    elite = ArchiveElite(
        variant=variant,
        sensor=sensor,
        regression=regression,
        metrics=metrics,
        cell_key=cell_key,
        fitness_score=float(sensor["fitness_score"]),
        generation=0,
        decision=decision,
        reason=reason,
    )
    archive.insert(elite)
    return elite


def run_qd_simulation(
    *,
    generations: int,
    seed: int,
    config: dict[str, Any] | None = None,
    baseline_metrics: dict[str, float] | None = None,
    noise_profile: dict[str, float] | None = None,
    proposals_per_generation: int = 4,
    regression_probe_generation: int | None = None,
) -> SimulationReport:
    cfg = dict(config or seed_organism.DEFAULT_CONFIG)
    rng = random.Random(seed)
    archive = QualityDiversityArchive()
    steps: list[dict[str, Any]] = []
    accepted_count = 0
    variant_counter = 0

    seed_archive(archive, cfg, rng=rng)

    for generation in range(1, generations + 1):
        for _ in range(proposals_per_generation):
            variant_counter += 1
            variant = propose_offspring(archive, rng=rng, generation=generation, variant_counter=variant_counter)
            force_regression = (
                regression_probe_generation is not None and generation == regression_probe_generation
            )
            metrics = synthesize_metrics(
                variant,
                baseline_metrics=baseline_metrics,
                noise_profile=noise_profile,
                rng=rng,
                force_regression=force_regression,
            )
            sensor, regression, decision, reason = evaluate_variant(variant, metrics, cfg)

            archived = False
            cell_key: tuple[int, ...] | None = None
            if decision == "accepted":
                cell_key = descriptor_cell_key(sensor, variant)
                elite = ArchiveElite(
                    variant=variant,
                    sensor=sensor,
                    regression=regression,
                    metrics=metrics,
                    cell_key=cell_key,
                    fitness_score=float(sensor["fitness_score"]),
                    generation=generation,
                    decision=decision,
                    reason=reason,
                )
                archived = archive.insert(elite)
                accepted_count += 1
            elif decision == "rejected_regression":
                archive.rejected_regressions += 1
            elif decision in ("rejected_negative_fitness", "invalid"):
                archive.rejected_negative += 1
            else:
                archive.inconclusive += 1

            steps.append(
                {
                    "generation": generation,
                    "variant_id": variant["variant_id"],
                    "decision": decision,
                    "reason": reason,
                    "fitness_score": float(sensor["fitness_score"]),
                    "cell_key": list(cell_key) if cell_key else None,
                    "archived": archived,
                    "mutation_operator": variant.get("mutation_operator"),
                    "forced_regression_probe": force_regression,
                    "knobs_removed_vs_parent": variant.get("knobs_removed_vs_parent", 0),
                }
            )

    elites = [
        {
            "variant_id": e.variant["variant_id"],
            "fitness_score": e.fitness_score,
            "cell_key": list(e.cell_key),
            "generation": e.generation,
            "delta": e.sensor.get("delta"),
            "knobs_removed_vs_parent": e.variant.get("knobs_removed_vs_parent", 0),
        }
        for e in sorted(archive.elites(), key=lambda x: x.fitness_score, reverse=True)
    ]

    return SimulationReport(
        seed=seed,
        generations=generations,
        proposals=len(steps),
        accepted_count=accepted_count,
        archive_size=archive.elite_count(),
        occupied_cells=archive.occupied_cell_count(),
        max_fitness=archive.max_fitness(),
        rejected_regressions=archive.rejected_regressions,
        rejected_negative=archive.rejected_negative,
        inconclusive=archive.inconclusive,
        elites=elites,
        steps=steps,
    )


def write_simulation_report(report: SimulationReport, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report.to_dict(), indent=2, sort_keys=True) + "\n", encoding="utf-8")


def format_summary(report: SimulationReport) -> str:
    lines = [
        "QD seed-organism simulation summary",
        f"seed: {report.seed}",
        f"generations: {report.generations}",
        f"proposals: {report.proposals}",
        f"accepted outcomes: {report.accepted_count}",
        f"archive elites: {report.archive_size}",
        f"descriptor cells occupied: {report.occupied_cells}",
        f"max fitness_score: {report.max_fitness:.6f}",
        f"rejected_regression: {report.rejected_regressions}",
        f"rejected_negative_fitness: {report.rejected_negative}",
        f"inconclusive: {report.inconclusive}",
    ]
    if report.elites:
        lines.append("top elites:")
        for elite in report.elites[:5]:
            lines.append(
                f"  {elite['variant_id']} fitness={elite['fitness_score']:.6f} "
                f"cell={elite['cell_key']}"
            )
    return "\n".join(lines)