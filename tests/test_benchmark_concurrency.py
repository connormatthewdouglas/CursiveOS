#!/usr/bin/env python3
"""Drive benchmark-inference-concurrency-v0.1.sh entrypoints (no Ollama required)."""

from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "benchmarks" / "benchmark-inference-concurrency-v0.1.sh"


def run_bench(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
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


class ConcurrencyBenchmarkEntrypointTest(unittest.TestCase):
    def test_script_exists(self) -> None:
        self.assertTrue(BENCH.is_file(), f"missing shipped benchmark: {BENCH}")

    def test_help_exits_zero(self) -> None:
        proc = run_bench("--help")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Usage:", proc.stdout)
        self.assertIn("--dry-run", proc.stdout)

    def test_dry_run_streams_and_model_args(self) -> None:
        proc = run_bench("--dry-run", "4", "mistral")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("model=mistral", proc.stdout)
        self.assertIn("would run 4 parallel", proc.stdout)

    def test_dry_run_env_stream_override(self) -> None:
        proc = run_bench("--dry-run", env={"CURSIVEOS_CONC_STREAMS": "6"})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("would run 6 parallel", proc.stdout)
        self.assertIn("model=auto", proc.stdout)

    def test_dry_run_prompt_length_reported(self) -> None:
        proc = run_bench("--dry-run", "2", "phi3")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertRegex(proc.stdout, r"prompt length=\d+ chars")

    def test_invalid_streams_rejected_before_ollama(self) -> None:
        proc = run_bench("0")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("streams must be >= 1", proc.stdout + proc.stderr)


class ConcurrencyMetricJsonShapeTest(unittest.TestCase):
    """Static check: METRIC_JSON builder fields match harness expectations."""

    def test_metric_json_fields_documented_in_script(self) -> None:
        text = BENCH.read_text(encoding="utf-8")
        for field in (
            '"sensor": "inference_concurrency"',
            '"aggregate_tok_s"',
            '"per_worker_mean_tok_s"',
            '"streams"',
        ):
            self.assertIn(field, text)

    def test_sample_metric_json_roundtrip(self) -> None:
        sample = {
            "sensor": "inference_concurrency",
            "version": "v0.1",
            "model": "mistral",
            "streams": 4,
            "wall_s": 47.8,
            "total_tokens": 320,
            "aggregate_tok_s": 6.7,
            "per_worker_mean_tok_s": 6.8,
            "failures": 0,
        }
        line = "METRIC_JSON " + json.dumps(sample)
        parsed = json.loads(line.split("METRIC_JSON ", 1)[1])
        self.assertEqual(parsed["aggregate_tok_s"], 6.7)
        self.assertEqual(parsed["streams"], 4)


if __name__ == "__main__":
    unittest.main()