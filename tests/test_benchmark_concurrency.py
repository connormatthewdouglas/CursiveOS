#!/usr/bin/env python3
"""Drive shipped concurrency benchmark + metrics aggregation on real paths."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "benchmark-inference-concurrency-v0.1.sh"
FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures" / "concurrency"

sys.path.insert(0, str(ROOT / "tools"))
import concurrency_metrics  # noqa: E402


def run_bench(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    merged["PYTHON"] = sys.executable
    if env:
        merged.update(env)
    return subprocess.run(
        ["bash", str(BENCH), *args],
        cwd=ROOT,
        env=merged,
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )


def expected_aggregate_from_fixtures(fixdir: Path, wall_s: float) -> float:
    total_tokens = 0
    for path in sorted(fixdir.glob("worker_*.json")):
        total_tokens += int(json.loads(path.read_text(encoding="utf-8"))["eval_count"])
    return round(total_tokens / wall_s, 2) if wall_s > 0 else 0.0


class ConcurrencyMetricsModuleTest(unittest.TestCase):
    def test_aggregate_worker_metrics_from_fixtures(self) -> None:
        wall_s = 48.0
        expected_agg = expected_aggregate_from_fixtures(FIXTURE_DIR, wall_s)
        metrics = concurrency_metrics.aggregate_worker_metrics(
            str(FIXTURE_DIR),
            streams=4,
            wall_s=wall_s,
            model="mistral",
        )
        self.assertEqual(metrics["total_tokens"], 320)
        self.assertEqual(metrics["aggregate_tok_s"], expected_agg)
        self.assertEqual(metrics["failures"], 0)
        self.assertGreater(metrics["per_worker_mean_tok_s"], 0.0)

    def test_format_probe_lines_ends_with_metric_json(self) -> None:
        metrics = concurrency_metrics.aggregate_worker_metrics(
            str(FIXTURE_DIR), streams=4, wall_s=48.0, model="mistral"
        )
        lines = concurrency_metrics.format_probe_lines(metrics)
        self.assertTrue(lines[-1].startswith("METRIC_JSON "))
        parsed = concurrency_metrics.parse_metric_json_line("\n".join(lines))
        self.assertEqual(parsed["sensor"], "inference_concurrency")
        self.assertEqual(parsed["streams"], 4)

    def test_failure_worker_counted(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            (tmp_path / "worker_1.json").write_text(
                json.dumps({"eval_count": 0, "eval_duration": 0}), encoding="utf-8"
            )
            metrics = concurrency_metrics.aggregate_worker_metrics(
                str(tmp_path), streams=1, wall_s=10.0, model="x"
            )
            self.assertEqual(metrics["failures"], 1)
            self.assertEqual(metrics["aggregate_tok_s"], 0.0)


class ConcurrencyBenchmarkFixturePathTest(unittest.TestCase):
    """--fixture-dir drives the same METRICS_PY entrypoint as live probe tail."""

    def test_fixture_dir_emits_metric_json(self) -> None:
        wall_s = 48.0
        expected_agg = expected_aggregate_from_fixtures(FIXTURE_DIR, wall_s)
        proc = run_bench(
            "--fixture-dir",
            str(FIXTURE_DIR),
            "4",
            "mistral",
            str(wall_s),
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        metric = concurrency_metrics.parse_metric_json_line(proc.stdout)
        self.assertEqual(metric["aggregate_tok_s"], expected_agg)
        self.assertEqual(metric["total_tokens"], 320)
        self.assertIn("aggregate_tok_s=", proc.stdout)

    def test_fixture_dir_metric_before_log_line(self) -> None:
        """Live path appends Log after probe block; fixture-dir has no Log (no Ollama)."""
        proc = run_bench("--fixture-dir", str(FIXTURE_DIR), "4", "mistral", "48.0")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
        metric_idx = next(i for i, ln in enumerate(lines) if ln.startswith("METRIC_JSON "))
        self.assertGreater(metric_idx, 0)
        self.assertNotIn("Log:", proc.stdout)


class ConcurrencyBenchmarkEntrypointTest(unittest.TestCase):
    def test_help_exits_zero(self) -> None:
        proc = run_bench("--help")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("--fixture-dir", proc.stdout)

    def test_dry_run_streams_and_model_args(self) -> None:
        proc = run_bench("--dry-run", "4", "mistral")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("model=mistral", proc.stdout)

    def test_invalid_streams_rejected_before_ollama(self) -> None:
        proc = run_bench("0")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("streams must be >= 1", proc.stdout + proc.stderr)


class H1CvComputationTest(unittest.TestCase):
    """CV helper used in scratch H1 scripts — stdev/mean on tok/s series."""

    @staticmethod
    def cv(values: list[float]) -> float:
        import statistics

        mean = statistics.mean(values)
        stdev = statistics.stdev(values) if len(values) > 1 else 0.0
        return stdev / mean if mean else float("inf")

    def test_stardust_h1_values_pass_gate(self) -> None:
        values = [6.66, 6.67, 6.67]
        self.assertLessEqual(self.cv(values), 0.15)

    def test_laptop_h1_values_pass_gate(self) -> None:
        values = [33.22, 33.22, 33.23]
        self.assertLessEqual(self.cv(values), 0.15)


if __name__ == "__main__":
    unittest.main()