"""Tests for rig-smoke.sh dispatch contract (path capture + poll patterns)."""
import pathlib
import re
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
RIG_SMOKE = ROOT / "tools" / "rig-smoke.sh"
REMOTE = ROOT / "tools" / "rig-smoke-remote.sh"


class RigSmokeContractTest(unittest.TestCase):
    def test_dispatcher_syntax(self):
        subprocess.run(["bash", "-n", str(RIG_SMOKE)], check=True)
        subprocess.run(["bash", "-n", str(REMOTE)], check=True)

    def test_rig_launch_stdout_is_path_only(self):
        text = RIG_SMOKE.read_text(encoding="utf-8")
        launch = text.split("rig_launch() {", 1)[1].split("}\n", 1)[0]
        self.assertIn("printf '%s' $out", launch)
        self.assertNotIn("echo LAUNCHED", launch)
        self.assertNotRegex(launch, r'echo\s+"\$out"')

    def test_poll_matches_lowercase_json_valid(self):
        line = "JSON_VALID=true schema=cursiveos.full-test-result.v1.4 idle_w=8.7"
        self.assertRegex(line, r"JSON_VALID=(true|True)")

    def test_remote_json_valid_lowercase(self):
        remote = REMOTE.read_text(encoding="utf-8")
        self.assertIn("JSON_VALID={'true' if ok else 'false'}", remote)


if __name__ == "__main__":
    unittest.main()