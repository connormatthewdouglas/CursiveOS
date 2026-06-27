#!/usr/bin/env python3
"""Subprocess the shipped concurrency sprint contract verifier on real paths."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFY_PS1 = ROOT / "tools" / "run-concurrency-sprint-verify.ps1"
FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures" / "sprint"

REQUIRED_IN_EVIDENCE = [
    "benchmarks/benchmark-inference-concurrency-v0.1.sh",
    "tools/concurrency_metrics.py",
    "tests/test_benchmark_concurrency.py",
    "experiments/concurrency-inference-sensor-noise-floor-plan.md",
    "VALIDATION.md",
]


def run_verify(*, fixture_dir: Path, scratch_dir: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["CONCURRENCY_SPRINT_SCRATCH"] = str(scratch_dir)
    return subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(VERIFY_PS1),
            "-FixtureDir",
            str(fixture_dir),
            "-RepoRoot",
            str(ROOT),
        ],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=120,
    )


class ConcurrencySprintVerifyTest(unittest.TestCase):
    def test_contract_verifier_passes_with_fixtures_and_lists_modified_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            scratch = Path(tmp)
            proc = run_verify(fixture_dir=FIXTURE_DIR, scratch_dir=scratch)
            self.assertEqual(
                proc.returncode,
                0,
                msg=f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}",
            )
            evidence = scratch / "changed-files-evidence.txt"
            self.assertTrue(evidence.is_file(), "changed-files-evidence.txt missing")
            text = evidence.read_text(encoding="utf-8")
            self.assertIn("MODIFIED FILES", text)
            for needle in REQUIRED_IN_EVIDENCE:
                self.assertIn(needle, text, f"missing {needle} in changed-files-evidence.txt")
            self.assertTrue((scratch / "concurrency-sprint-verify-pass.txt").is_file())
            self.assertTrue((scratch / "dry-run-verify.txt").is_file())
            self.assertTrue((scratch / "unittest-verify.txt").is_file())


if __name__ == "__main__":
    unittest.main()