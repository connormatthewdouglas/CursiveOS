#!/usr/bin/env python3

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import qd_organism  # noqa: E402
import seed_organism  # noqa: E402


FIXTURE_VARIANT = {
    "schema_version": "seed-organism.variant.v0.1",
    "variant_id": "test-variant",
    "contributor_id": "tester",
    "commit_ref": "test",
    "preset_version": "v0.8",
    "fitness_eligible": True,
}

FIXTURE_BASELINE = {
    "network_mbps": 930.0,
    "coldstart_ms": 1820.0,
    "sustained_tokps": 41.0,
    "idle_watts": 71.0,
}


def metrics_from_variant(
    *,
    coldstart_pct: float = 0.0,
    sustained_pct: float = 0.0,
    idle_power_pct: float = 0.0,
    network_pct: float = 0.0,
    memory_pct: float = 0.0,
    sample_counts: dict | None = None,
    regression: dict | None = None,
) -> dict:
    baseline = dict(FIXTURE_BASELINE)
    baseline["memory_refault_s"] = 10.0
    variant = {
        "network_mbps": baseline["network_mbps"] * (1.0 + network_pct / 100.0),
        "coldstart_ms": baseline["coldstart_ms"] * (1.0 - coldstart_pct / 100.0),
        "sustained_tokps": baseline["sustained_tokps"] * (1.0 + sustained_pct / 100.0),
        "idle_watts": baseline["idle_watts"] * (1.0 + idle_power_pct / 100.0),
        # lower-is-better: positive memory_pct = faster refault (improvement)
        "memory_refault_s": baseline["memory_refault_s"] * (1.0 - memory_pct / 100.0),
    }
    return {
        "schema_version": "seed-organism.metrics.fixture.v0.1",
        "machine_id": "fixture-founder-rig",
        "preset_version": "v0.8",
        "baseline": baseline,
        "variant": variant,
        "sample_counts": sample_counts
        or {"network": 3, "coldstart": 3, "sustained": 3, "idle_power": 5},
        "regression": regression
        or {
            "full_test_passed": True,
            "reverted_cleanly": True,
            "host_safety_passed": True,
            "failures": [],
        },
    }


class CoreEvaluationTest(unittest.TestCase):
    def test_score_performance_positive_coldstart(self) -> None:
        metrics = metrics_from_variant(coldstart_pct=10.0, sustained_pct=2.0, idle_power_pct=1.0)
        sensor = seed_organism.score_performance(
            variant=FIXTURE_VARIANT,
            metrics=metrics,
            config=seed_organism.DEFAULT_CONFIG,
        )
        self.assertGreater(sensor["fitness_score"], seed_organism.DEFAULT_CONFIG["minimum_accept_fitness"])
        self.assertEqual(sensor["missing_core_metrics"], [])
        self.assertEqual(sensor["severe_regressions"], [])

    def test_score_performance_severe_coldstart_regression(self) -> None:
        metrics = metrics_from_variant(coldstart_pct=-12.0)
        sensor = seed_organism.score_performance(
            variant=FIXTURE_VARIANT,
            metrics=metrics,
            config=seed_organism.DEFAULT_CONFIG,
        )
        self.assertTrue(sensor["severe_regressions"])

    def test_evaluate_regression_failures(self) -> None:
        metrics = metrics_from_variant(
            regression={
                "full_test_passed": False,
                "reverted_cleanly": False,
                "host_safety_passed": True,
                "failures": ["dirty revert"],
            }
        )
        regression = seed_organism.evaluate_regression(FIXTURE_VARIANT, metrics)
        self.assertFalse(regression["passed"])
        self.assertIn("full-test gate failed", regression["failures"])
        self.assertIn("reversibility gate failed", regression["failures"])

    def test_verdict_paths(self) -> None:
        config = seed_organism.DEFAULT_CONFIG
        good_metrics = metrics_from_variant(coldstart_pct=8.0, sustained_pct=1.0)
        sensor = seed_organism.score_performance(
            variant=FIXTURE_VARIANT, metrics=good_metrics, config=config
        )
        regression = seed_organism.evaluate_regression(FIXTURE_VARIANT, good_metrics)
        decision, _ = seed_organism.verdict(FIXTURE_VARIANT, sensor, regression, config)
        self.assertEqual(decision, "accepted")

        bad_metrics = metrics_from_variant(
            regression={"full_test_passed": False, "reverted_cleanly": True, "host_safety_passed": True, "failures": []}
        )
        sensor_bad = seed_organism.score_performance(
            variant=FIXTURE_VARIANT, metrics=bad_metrics, config=config
        )
        regression_bad = seed_organism.evaluate_regression(FIXTURE_VARIANT, bad_metrics)
        decision_bad, _ = seed_organism.verdict(FIXTURE_VARIANT, sensor_bad, regression_bad, config)
        self.assertEqual(decision_bad, "rejected_regression")

        low_conf_metrics = metrics_from_variant(coldstart_pct=8.0, sample_counts={"network": 1, "coldstart": 1, "sustained": 1})
        sensor_low = seed_organism.score_performance(
            variant=FIXTURE_VARIANT, metrics=low_conf_metrics, config=config
        )
        regression_low = seed_organism.evaluate_regression(FIXTURE_VARIANT, low_conf_metrics)
        decision_low, _ = seed_organism.verdict(FIXTURE_VARIANT, sensor_low, regression_low, config)
        self.assertEqual(decision_low, "inconclusive")

        negative_metrics = metrics_from_variant(coldstart_pct=-15.0)
        sensor_neg = seed_organism.score_performance(
            variant=FIXTURE_VARIANT, metrics=negative_metrics, config=config
        )
        regression_neg = seed_organism.evaluate_regression(FIXTURE_VARIANT, negative_metrics)
        decision_neg, _ = seed_organism.verdict(FIXTURE_VARIANT, sensor_neg, regression_neg, config)
        self.assertEqual(decision_neg, "rejected_negative_fitness")

    def test_memory_channel_scores_rewards_gates_and_optional(self) -> None:
        cfg = seed_organism.DEFAULT_CONFIG
        # improvement (faster refault, e.g. zram vs disk swap) rewards fitness
        improved = seed_organism.score_performance(
            variant=FIXTURE_VARIANT, metrics=metrics_from_variant(memory_pct=50.0), config=cfg
        )
        self.assertGreater(improved["delta"]["memory_pct"], 0.0)
        self.assertGreater(improved["fitness_score"], 0.0)
        self.assertEqual(improved["severe_regressions"], [])
        # a real memory regression trips the severe gate
        regressed = seed_organism.score_performance(
            variant=FIXTURE_VARIANT, metrics=metrics_from_variant(memory_pct=-25.0), config=cfg
        )
        self.assertTrue(any("memory regression" in s for s in regressed["severe_regressions"]))
        # absent memory metric (runs predating the 5th channel) is neutral, no crash
        m = metrics_from_variant()
        del m["baseline"]["memory_refault_s"]
        del m["variant"]["memory_refault_s"]
        neutral = seed_organism.score_performance(variant=FIXTURE_VARIANT, metrics=m, config=cfg)
        self.assertIsNone(neutral["delta"]["memory_pct"])

    def test_parsimony_bonus_only_when_non_regressing(self) -> None:
        metrics = metrics_from_variant(coldstart_pct=0.5, sustained_pct=0.5)
        variant = dict(FIXTURE_VARIANT)
        variant["knobs_removed_vs_parent"] = 2
        sensor = seed_organism.score_performance(variant=variant, metrics=metrics, config=seed_organism.DEFAULT_CONFIG)
        self.assertGreater(sensor["parsimony_bonus"], 0.0)

    def test_overdeclared_parsimony_synced_before_qd_eval(self) -> None:
        parent = qd_organism.make_variant(
            variant_id="parent",
            parent=None,
            knobs={"cpu_governor_boost": 0.4, "gpu_idle_pin_mhz": 0.2, "scheduler_aggressive": 0.1, "power_cap_relief": 0.0},
        )
        child = qd_organism.make_variant(
            variant_id="child",
            parent=parent,
            knobs={"cpu_governor_boost": 0.4, "gpu_idle_pin_mhz": 0.2, "scheduler_aggressive": 0.1, "power_cap_relief": 0.0},
        )
        child["knobs_removed_vs_parent"] = 6
        metrics = metrics_from_variant(coldstart_pct=0.5, sustained_pct=0.5)
        sensor, _, _, _ = qd_organism.evaluate_variant(child, metrics, seed_organism.DEFAULT_CONFIG)
        self.assertEqual(child["knobs_removed_vs_parent"], 0)
        self.assertEqual(sensor["parsimony_bonus"], 0.0)


class FullTestTelemetryExtractionTest(unittest.TestCase):
    def test_load_full_test_metrics_extracts_detail_logs_without_confidence_side_effects(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            network = base / "network.log"
            coldstart = base / "coldstart.log"
            sustained = base / "sustained.log"
            result = base / "full-test.json"

            network.write_text(
                """
--- BASELINE ---
  TCP CC:    cubic
  rmem_max:  212992 bytes (0.2 MB)
    Run 1: 200.0 Mbit/s | retransmits: 1 | RTT: 51.0ms
    Run 2: 220.0 Mbit/s | retransmits: 2 | RTT: 52.0ms
  Avg: 210.0 Mbit/s | retransmits: 1.5 | RTT: 51.5ms
  Range: 200.0 - 220.0 Mbit/s
--- TUNED ---
  TCP CC:    bbr
  rmem_max:  16777216 bytes (16.0 MB)
    Run 1: 1200.0 Mbit/s | retransmits: 0 | RTT: 50.0ms
  Avg: 1200.0 Mbit/s | retransmits: 0.0 | RTT: 50.0ms
  Range: 1200.0 - 1200.0 Mbit/s
""".strip()
                + "\n",
                encoding="utf-8",
            )
            coldstart.write_text(
                """
--- BASELINE ---
  CPU gov:   schedutil
  GPU freq:  300 MHz (idle)
    Call 1: GPU_before=300MHz | load=100.0ms | TTFT=20.0ms | cold_total=120.0ms | 40.00 tok/s | tokens:30
  Avg: load=100.0ms | TTFT=20.0ms | cold_total=120.0ms | 40.00 tok/s
  Load range: 100.0ms - 100.0ms | Cold range: 120.0ms - 120.0ms
--- TUNED ---
  CPU gov:   performance
  GPU freq:  2000 MHz (idle)
    Call 1: GPU_before=2000MHz | load=90.0ms | TTFT=10.0ms | cold_total=100.0ms | 42.00 tok/s | tokens:30
  Avg: load=90.0ms | TTFT=10.0ms | cold_total=100.0ms | 42.00 tok/s
  Load range: 90.0ms - 90.0ms | Cold range: 100.0ms - 100.0ms
""".strip()
                + "\n",
                encoding="utf-8",
            )
            sustained.write_text(
                """
--- BASELINE ---
  Governor: schedutil
  Processor: 100% GPU
    Pass 1: 30.00 tok/s | TTFT: 0.100s | tokens: 100
  Avg: 30.00 tok/s | TTFT avg: 0.100s | min: 30.00 | max: 30.00
--- TUNED ---
  Governor: performance
  Processor: 100% GPU
    Pass 1: 31.00 tok/s | TTFT: 0.090s | tokens: 100
  Avg: 31.00 tok/s | TTFT avg: 0.090s | min: 31.00 | max: 31.00
""".strip()
                + "\n",
                encoding="utf-8",
            )
            result.write_text(
                json.dumps(
                    {
                        "schema_version": "cursiveos.full-test-result.v1.4",
                        "machine_id": "machine-a",
                        "hardware_fingerprint_hash": "machine-a",
                        "preset_version": "v0.8",
                        "baseline": {
                            "network_mbps": 210.0,
                            "coldstart_ms": 120.0,
                            "sustained_tokps": 30.0,
                            "idle_watts": 3.0,
                        },
                        "variant": {
                            "network_mbps": 1200.0,
                            "coldstart_ms": 100.0,
                            "sustained_tokps": 31.0,
                            "idle_watts": 4.0,
                        },
                        "sample_counts": {
                            "network": 1,
                            "coldstart": 1,
                            "sustained": 1,
                            "idle_power": 5,
                        },
                        "telemetry": {
                            "detail_logs": {
                                "network": str(network),
                                "coldstart": str(coldstart),
                                "sustained": str(sustained),
                            },
                            "idle_power": {
                                "baseline_samples_w": [3.0, 3.1, 2.9],
                                "tuned_samples_w": [4.0, 4.1, 3.9],
                            },
                        },
                        "regression": {
                            "full_test_passed": True,
                            "reverted_cleanly": True,
                            "host_safety_passed": True,
                            "failures": [],
                        },
                    },
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            metrics = seed_organism.load_full_test_metrics_json(result)

        self.assertEqual(metrics["sample_counts"]["network"], 1)
        self.assertTrue(metrics["measurement_quality"]["decision_grade"])
        self.assertEqual(metrics["structured_telemetry"]["network"]["baseline"]["runs"][0]["retransmits"], 1.0)
        self.assertEqual(metrics["structured_telemetry"]["coldstart"]["tuned"]["calls"][0]["gpu_before"], "2000MHz")
        self.assertEqual(metrics["structured_telemetry"]["sustained"]["baseline"]["processor"], "100% GPU")


class DescriptorArchiveTest(unittest.TestCase):
    def test_cell_key_bins_deltas_and_parsimony(self) -> None:
        sensor = {
            "delta": {
                "coldstart_pct": 5.0,
                "sustained_pct": -2.0,
                "idle_power_pct": 3.0,
            }
        }
        variant = {"knobs_removed_vs_parent": 1}
        key = qd_organism.descriptor_cell_key(sensor, variant)
        self.assertEqual(key, (2, 0, 0, 1))

    def test_archive_replaces_only_with_higher_fitness(self) -> None:
        archive = qd_organism.QualityDiversityArchive()
        cell = (2, 1, 1, 0)
        low = qd_organism.ArchiveElite(
            variant={"variant_id": "low"},
            sensor={"delta": {}},
            regression={},
            metrics={},
            cell_key=cell,
            fitness_score=0.05,
            generation=1,
            decision="accepted",
            reason="ok",
        )
        high = qd_organism.ArchiveElite(
            variant={"variant_id": "high"},
            sensor={"delta": {}},
            regression={},
            metrics={},
            cell_key=cell,
            fitness_score=0.12,
            generation=2,
            decision="accepted",
            reason="ok",
        )
        self.assertTrue(archive.insert(low))
        self.assertTrue(archive.insert(high))
        self.assertEqual(archive.cells[cell].variant["variant_id"], "high")
        worse = qd_organism.ArchiveElite(
            variant={"variant_id": "worse"},
            sensor={"delta": {}},
            regression={},
            metrics={},
            cell_key=cell,
            fitness_score=0.08,
            generation=3,
            decision="accepted",
            reason="ok",
        )
        self.assertFalse(archive.insert(worse))
        self.assertEqual(archive.cells[cell].variant["variant_id"], "high")

    def test_parent_selection_prefers_diverse_high_fitness(self) -> None:
        archive = qd_organism.QualityDiversityArchive()
        rng = __import__("random").Random(7)
        for idx, (fitness, cell) in enumerate(
            [(0.20, (2, 2, 2, 0)), (0.18, (1, 1, 1, 0)), (0.17, (0, 0, 0, 1))]
        ):
            archive.insert(
                qd_organism.ArchiveElite(
                    variant={"variant_id": f"v{idx}"},
                    sensor={"delta": {}},
                    regression={},
                    metrics={},
                    cell_key=cell,
                    fitness_score=fitness,
                    generation=idx,
                    decision="accepted",
                    reason="ok",
                )
            )
        parents = archive.select_parents(rng, count=2)
        self.assertEqual(len(parents), 2)
        self.assertEqual(parents[0].fitness_score, 0.20)
        self.assertNotEqual(parents[0].cell_key, parents[1].cell_key)


class MutationProposerTest(unittest.TestCase):
    def test_mutations_change_genome(self) -> None:
        parent = qd_organism.make_variant(
            variant_id="parent",
            parent=None,
            knobs={"cpu_governor_boost": 0.4, "gpu_idle_pin_mhz": 0.1, "scheduler_aggressive": 0.1, "power_cap_relief": 0.0},
        )
        rng = __import__("random").Random(99)
        child = qd_organism.mutate_genome(parent, rng=rng, variant_id="child", generation=1)
        self.assertNotEqual(qd_organism.knobs_from_variant(parent), qd_organism.knobs_from_variant(child))
        self.assertIn(child.get("mutation_operator"), qd_organism.MUTATION_OPERATORS)

    def test_knob_remove_does_not_count_inactive_as_removed(self) -> None:
        inactive = {k: 0.0 for k in qd_organism.KNOB_NAMES}
        rng = __import__("random").Random(1)
        out, removed = qd_organism.apply_knob_remove(inactive, rng)
        self.assertFalse(removed)
        self.assertEqual(qd_organism.count_knobs_removed_vs_parent(inactive, out), 0)

    def test_knobs_removed_matches_genome_diff(self) -> None:
        parent = qd_organism.make_variant(
            variant_id="parent",
            parent=None,
            knobs={"cpu_governor_boost": 0.5, "gpu_idle_pin_mhz": 0.3, "scheduler_aggressive": 0.2, "power_cap_relief": 0.1},
        )
        child_knobs = {"cpu_governor_boost": 0.0, "gpu_idle_pin_mhz": 0.3, "scheduler_aggressive": 0.0, "power_cap_relief": 0.1}
        child = qd_organism.make_variant(variant_id="child", parent=parent, knobs=child_knobs, generation=1)
        self.assertEqual(child["knobs_removed_vs_parent"], 2)
        self.assertLessEqual(child["knobs_removed_vs_parent"], len(qd_organism.KNOB_NAMES))

    def test_proposer_draws_from_archive(self) -> None:
        archive = qd_organism.QualityDiversityArchive()
        archive.insert(
            qd_organism.ArchiveElite(
                variant=qd_organism.make_variant(
                    variant_id="seed",
                    parent=None,
                    knobs={"cpu_governor_boost": 0.3, "gpu_idle_pin_mhz": 0.2, "scheduler_aggressive": 0.1, "power_cap_relief": 0.1},
                ),
                sensor={"delta": {}},
                regression={},
                metrics={},
                cell_key=(2, 1, 1, 0),
                fitness_score=0.1,
                generation=0,
                decision="accepted",
                reason="ok",
            )
        )
        rng = __import__("random").Random(5)
        child = qd_organism.propose_offspring(archive, rng=rng, generation=2, variant_counter=1)
        self.assertTrue(child["variant_id"].startswith("qd-sim-g002-"))


class SimulationLoopTest(unittest.TestCase):
    def test_loop_archives_only_accepted_non_regressed(self) -> None:
        report = qd_organism.run_qd_simulation(
            generations=12,
            seed=123,
            config=seed_organism.DEFAULT_CONFIG,
            proposals_per_generation=3,
            regression_probe_generation=5,
        )
        self.assertGreaterEqual(report.archive_size, 2)
        self.assertGreaterEqual(report.occupied_cells, 3)
        self.assertGreater(report.max_fitness, seed_organism.DEFAULT_CONFIG["minimum_accept_fitness"])
        self.assertGreaterEqual(report.rejected_regressions, 1)
        accepted_steps = [s for s in report.steps if s["decision"] == "accepted"]
        self.assertTrue(all(s["fitness_score"] > seed_organism.DEFAULT_CONFIG["minimum_accept_fitness"] for s in accepted_steps))
        archived_steps = [s for s in report.steps if s["archived"]]
        self.assertTrue(all(s["decision"] == "accepted" for s in archived_steps))
        for step in report.steps:
            self.assertLessEqual(step.get("knobs_removed_vs_parent", 0), len(qd_organism.KNOB_NAMES))
        probe_steps = [s for s in report.steps if s.get("forced_regression_probe")]
        self.assertTrue(probe_steps)
        self.assertTrue(all(s["decision"] == "rejected_regression" for s in probe_steps))

    def test_simulation_elites_parsimony_not_gamed(self) -> None:
        report = qd_organism.run_qd_simulation(generations=10, seed=77, proposals_per_generation=3)
        for elite in report.elites:
            removed = elite.get("knobs_removed_vs_parent", 0)
            self.assertLessEqual(removed, len(qd_organism.KNOB_NAMES))
            self.assertGreaterEqual(removed, 0)

    def test_simulation_uses_real_evaluation_functions(self) -> None:
        variant = qd_organism.make_variant(
            variant_id="direct",
            parent=None,
            knobs={"cpu_governor_boost": 0.5, "gpu_idle_pin_mhz": 0.3, "scheduler_aggressive": 0.2, "power_cap_relief": 0.2},
        )
        metrics = qd_organism.synthesize_metrics(variant, rng=__import__("random").Random(1))
        sensor, regression, decision, reason = qd_organism.evaluate_variant(
            variant, metrics, seed_organism.DEFAULT_CONFIG
        )
        self.assertEqual(sensor["schema_version"], "seed-organism.sensor-result.v0.1")
        self.assertEqual(regression["schema_version"], "seed-organism.regression-result.v0.1")
        self.assertIn(decision, {"accepted", "rejected_regression", "rejected_negative_fitness", "inconclusive", "invalid"})
        self.assertTrue(reason)


class SimulateQdCliTest(unittest.TestCase):
    def test_cli_simulate_qd_smoke(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            report_path = Path(tmp) / "qd-report.json"
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = seed_organism.main(
                    [
                        "simulate-qd",
                        "--generations",
                        "15",
                        "--seed",
                        "42",
                        "--proposals-per-generation",
                        "4",
                        "--report",
                        str(report_path),
                    ]
                )
            self.assertEqual(rc, 0)
            output = buf.getvalue()
            self.assertIn("archive elites:", output)
            self.assertIn("descriptor cells occupied:", output)
            self.assertTrue(report_path.exists())
            data = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertGreaterEqual(data["archive_size"], 2)
            self.assertGreaterEqual(data["occupied_cells"], 3)
            self.assertGreater(data["max_fitness"], seed_organism.DEFAULT_CONFIG["minimum_accept_fitness"])

    def test_cli_require_zero_regression_accepts_passes_when_probes_rejected(self) -> None:
        rc = seed_organism.main(
            [
                "simulate-qd",
                "--generations",
                "8",
                "--seed",
                "99",
                "--regression-probe-generation",
                "4",
                "--require-zero-regression-accepts",
            ]
        )
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()