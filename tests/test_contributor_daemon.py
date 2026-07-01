from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import contributor_daemon as daemon  # noqa: E402


FAKE_CAPS = {
    "schema_version": daemon.CAPABILITY_SCHEMA,
    "daemon_version": daemon.DAEMON_VERSION,
    "machine_id": "fixture-linux-host",
    "platform": "linux",
    "capabilities": {
        "linux": True,
        "linux_bare_metal": True,
        "bare_metal_selection_truth_allowed": True,
        "sudo_noninteractive": True,
        "bash": True,
        "python3": True,
        "git": True,
        "curl": True,
    },
    "selection_scopes": ["linux_bare_metal", "linux_founder_fleet", "linux_observe_only"],
}


def fixture_request(**overrides):
    req = {
        "schema_version": daemon.REQUEST_SCHEMA,
        "request_id": "fixture-request",
        "status": "open",
        "parent_variant_id": "v0.12",
        "parent_variant_path": "references/seed-organism/variant.v0.12.json",
        "candidate_variant_id": "v0.12b-swappiness",
        "candidate_variant_path": "references/seed-organism/variant.v0.12b-swappiness.json",
        "cycle_id": 4,
        "screen_order": "normal",
        "selection_scope": "linux_bare_metal",
        "trust_scope": "simulated_not_payout_eligible",
        "required_capabilities": ["linux_bare_metal", "sudo_noninteractive", "bash", "python3", "git", "curl"],
    }
    req.update(overrides)
    return req


class ContributorDaemonContractTest(unittest.TestCase):
    def test_machine_fingerprint_matches_full_test_wrapper_v2_contract(self):
        cpu = "11th Gen Intel(R) Core(TM) i5-11300H @ 3.10GHz"
        board_vendor = "LENOVO"
        board_name = "LNVNB161216"
        gpu_ids = "[10de:1f9d][8086:9a49]"
        material = f"{cpu}|{board_vendor}|{board_name}|{gpu_ids}"

        machine_id, fingerprint_material = daemon.machine_fingerprint(cpu, board_vendor, board_name, gpu_ids)

        self.assertEqual(material, fingerprint_material)
        self.assertEqual("42e7c7257af11f46", machine_id)
        self.assertEqual(hashlib.sha256((material + "\n").encode()).hexdigest()[:16], machine_id)
        self.assertNotEqual(hashlib.sha256(material.encode()).hexdigest()[:16], machine_id)

    def test_machine_fingerprint_fallback_hashes_like_full_test_wrapper(self):
        with mock.patch.object(daemon, "first_existing_text", return_value="fixture-machine-id"):
            machine_id, material = daemon.machine_fingerprint("unknown", "unknown", "unknown", "nogpu")

        self.assertEqual("machineid|fixture-machine-id", material)
        self.assertEqual(hashlib.sha256((material + "\n").encode()).hexdigest()[:16], machine_id)

    def test_fixture_request_matches_linux_bare_metal_caps(self):
        ok, failures, normalized = daemon.request_match(FAKE_CAPS, fixture_request())
        self.assertTrue(ok, failures)
        self.assertEqual([], failures)
        self.assertEqual("v0.12", normalized["parent_variant_id"])
        self.assertEqual("v0.12b-swappiness", normalized["candidate_variant_id"])

    def test_rejects_implicit_candidate(self):
        req = fixture_request(candidate_variant_id="", candidate_variant_path="")
        ok, failures, _ = daemon.request_match(FAKE_CAPS, req)
        self.assertFalse(ok)
        self.assertTrue(any("candidate_variant_id is required" in f for f in failures))

    def test_rejects_payout_eligible_request_in_alpha(self):
        ok, failures, _ = daemon.request_match(FAKE_CAPS, fixture_request(trust_scope="payout_eligible"))
        self.assertFalse(ok)
        self.assertTrue(any("must not be payout-eligible" in f for f in failures))

    def test_rejects_windows_scope(self):
        ok, failures, _ = daemon.request_match(FAKE_CAPS, fixture_request(selection_scope="windows_native"))
        self.assertFalse(ok)
        self.assertTrue(any("Linux-scoped" in f for f in failures))

    def test_rejects_host_without_sudo(self):
        caps = json.loads(json.dumps(FAKE_CAPS))
        caps["capabilities"]["sudo_noninteractive"] = False
        ok, failures, _ = daemon.request_match(caps, fixture_request())
        self.assertFalse(ok)
        self.assertIn("missing required capability: sudo_noninteractive", failures)

    def test_build_screen_command_is_explicit_and_counterbalanceable(self):
        normal = daemon.build_screen_command(fixture_request())
        self.assertIn("screen-variant", normal)
        self.assertIn("--parent-variant", normal)
        self.assertIn("variant.v0.12.json", " ".join(normal))
        self.assertIn("variant.v0.12b-swappiness.json", " ".join(normal))
        self.assertNotIn("--reverse-order", normal)
        reversed_cmd = daemon.build_screen_command(fixture_request(screen_order="reversed"))
        self.assertIn("--reverse-order", reversed_cmd)

    def test_cli_capabilities_json_is_parseable_even_on_non_linux_hosts(self):
        res = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "contributor_daemon.py"), "capabilities", "--json"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=True,
        )
        caps = json.loads(res.stdout)
        self.assertEqual(daemon.CAPABILITY_SCHEMA, caps["schema_version"])
        self.assertIn("selection_scopes", caps)
        self.assertIn("capabilities", caps)

    def test_run_once_dry_run_records_ineligible_without_benchmarking(self):
        with tempfile.TemporaryDirectory() as td:
            req_path = Path(td) / "bad-request.json"
            req_path.write_text(json.dumps(fixture_request(selection_scope="windows_native")), encoding="utf-8")
            state = Path(td) / "state"
            res = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tools" / "contributor_daemon.py"),
                    "--state-dir",
                    str(state),
                    "run-once",
                    "--request-json",
                    str(req_path),
                    "--dry-run",
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, res.returncode)
            self.assertIn('"status": "ineligible"', res.stdout)
            self.assertTrue(list((state / "jobs").glob("*.json")))


if __name__ == "__main__":
    unittest.main()
