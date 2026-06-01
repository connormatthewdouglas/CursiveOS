#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import seed_organism  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
