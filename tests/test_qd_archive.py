import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from qd_archive import build_archive, cell_key, descriptor  # noqa: E402


class QdArchiveTest(unittest.TestCase):
    def test_v11_memory_positive_and_empty_neighbors(self):
        v11 = {
            "variant_id": "candidate-v0.11-zram-swappiness",
            "decision": "accepted",
            "fitness_score": 0.10037807,
            "result_bundle": {
                "metrics": {
                    "variant": {
                        "idle_watts": 2.77,
                        "coldstart_ms": 626.0,
                        "sustained_tokps": 33.58,
                        "memory_refault_s": 6.169,
                    },
                    "baseline": {
                        "idle_watts": 2.79,
                        "coldstart_ms": 624.4,
                        "sustained_tokps": 33.81,
                        "memory_refault_s": 45.017,
                    },
                }
            },
        }
        vfs = {
            "variant_id": "candidate-v0.13-vfscache50",
            "decision": "inconclusive",
            "fitness_score": 0.002,
            "result_bundle": {
                "metrics": {
                    "variant": {
                        "idle_watts": 3.95,
                        "coldstart_ms": 1783.9,
                        "sustained_tokps": 45.89,
                        "memory_refault_s": 6.073,
                    },
                    "baseline": {
                        "idle_watts": 3.96,
                        "coldstart_ms": 1787.2,
                        "sustained_tokps": 45.94,
                        "memory_refault_s": 6.094,
                    },
                }
            },
        }
        d = descriptor(v11)
        self.assertEqual(d["key"], "cneu-sneu-ineu-mpos")
        archive = build_archive([v11, vfs])
        self.assertEqual(archive["parent_cell"], "cneu-sneu-ineu-mpos")
        self.assertTrue(archive["empty_neighbors"])
        self.assertNotIn("cneu-sneu-ineu-mneu", archive["empty_neighbors"])
        self.assertIn("cpos-sneu-ineu-mpos", archive["empty_neighbors"])

    def test_cell_key(self):
        self.assertEqual(cell_key((1, 1, 1, 2)), "cneu-sneu-ineu-mpos")


if __name__ == "__main__":
    unittest.main()
