from __future__ import annotations

import subprocess
import sys
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import contributor_daemon as daemon  # noqa: E402


CANONICAL_LAPTOP = "42e7c7257af11f46"
OLD_DAEMON_LAPTOP = "7ba4f665a3bb4fb8"
CANONICAL_STARDUST = "3e6b165ddf112a75"
LENOVO_HW_TUPLE = "11th Gen Intel(R) Core(TM) i5-11300H @ 3.10GHz|LENOVO|LNVNB161216|[10de:1f9d][8086:9a49]"


class WrapperDaemonIdentityContractTest(unittest.TestCase):
    def test_wrapper_and_daemon_share_fingerprint_v2_newline_hash_contract(self) -> None:
        wrapper = (ROOT / "cursiveos-full-test-v1.4.sh").read_text(encoding="utf-8")
        self.assertIn('HW_FINGERPRINT=$(echo "$HW_ID_TUPLE" | sha256sum | cut -c1-16)', wrapper)
        self.assertIn("FINGERPRINT_VERSION=2", wrapper)

        shell = subprocess.run(
            ["bash", "-lc", 'printf "%s\\n" "$1" | sha256sum | cut -c1-16', "bash", LENOVO_HW_TUPLE],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()

        self.assertEqual(CANONICAL_LAPTOP, shell)
        self.assertEqual(shell, daemon.full_test_fingerprint(LENOVO_HW_TUPLE)[:16])
        self.assertNotEqual(OLD_DAEMON_LAPTOP, shell)


class DashboardIdentityContractTest(unittest.TestCase):
    def test_dashboard_canonicalizes_aliases_heartbeats_and_active_job_counts(self) -> None:
        node_script = textwrap.dedent(
            r'''
            const assert = require("assert");
            const fs = require("fs");
            const path = require("path");
            const vm = require("vm");

            const root = process.argv[1];
            const html = fs.readFileSync(path.join(root, "dashboard", "index.html"), "utf8");
            const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
            const pureScript = script.split(/\nmain\(\)\.catch/)[0];
            const context = { console };
            vm.createContext(context);
            vm.runInContext(pureScript + `\nthis.contract = { canonicalizer, physicalMachines, fingerprintCount, activeJobCount, collapseCapabilities, renderJobs, renderHeartbeats };`, context);

            const c = context.contract;
            const canonicalLaptop = "42e7c7257af11f46";
            const oldDaemonLaptop = "7ba4f665a3bb4fb8";
            const canonicalStardust = "3e6b165ddf112a75";
            const aliases = [{
              alias: oldDaemonLaptop,
              machine_id: canonicalLaptop,
              alias_kind: "daemon_pre_b52df82_no_newline_fingerprint"
            }];
            const canon = c.canonicalizer(aliases);

            assert.strictEqual(canon(oldDaemonLaptop), canonicalLaptop);
            assert.strictEqual(canon(canonicalStardust), canonicalStardust);
            assert.deepStrictEqual(
              c.physicalMachines([
                { machine_id: canonicalLaptop },
                { machine_id: oldDaemonLaptop },
                { machine_id: canonicalStardust }
              ], aliases).map(m => m.machine_id),
              [canonicalLaptop, canonicalStardust]
            );
            assert.strictEqual(c.fingerprintCount(canonicalLaptop, aliases), 2);
            assert.strictEqual(c.activeJobCount([
              { status: "planned" },
              { status: "claimed" },
              { status: "running" },
              { status: "complete" },
              { status: "ineligible" }
            ]), 2);

            const collapsed = c.collapseCapabilities([
              { machine_id: oldDaemonLaptop, daemon_version: "pre-fix", last_seen_at: "2026-07-01T15:00:00Z" },
              { machine_id: canonicalLaptop, daemon_version: "post-fix", last_seen_at: "2026-07-01T15:05:00Z" },
              { machine_id: canonicalStardust, daemon_version: "stardust", last_seen_at: "2026-07-01T15:02:00Z" }
            ], canon);
            assert.strictEqual(collapsed.length, 2);
            const laptop = collapsed.find(row => row.canonical_machine_id === canonicalLaptop);
            assert.strictEqual(laptop.machine_id, canonicalLaptop);
            assert.strictEqual(laptop.alias_machine_id, null);

            const aliasNewest = c.collapseCapabilities([
              { machine_id: canonicalLaptop, daemon_version: "post-fix", last_seen_at: "2026-07-01T15:00:00Z" },
              { machine_id: oldDaemonLaptop, daemon_version: "pre-fix", last_seen_at: "2026-07-01T15:06:00Z" }
            ], canon)[0];
            assert.strictEqual(aliasNewest.canonical_machine_id, canonicalLaptop);
            assert.strictEqual(aliasNewest.alias_machine_id, oldDaemonLaptop);

            const jobHtml = c.renderJobs([
              { job_id: "job-123456789", machine_id: oldDaemonLaptop, status: "complete", result_bundle_hash: "abcdef1234567890", last_heartbeat_at: "2026-07-01T15:02:00Z" }
            ], canon);
            assert(jobHtml.includes("machine 42e7c7257af1"), jobHtml);
            assert(jobHtml.includes("alias 7ba4f665"), jobHtml);
            '''
        )
        subprocess.run(["node", "-e", node_script, str(ROOT)], cwd=ROOT, text=True, capture_output=True, check=True)


if __name__ == "__main__":
    unittest.main()
