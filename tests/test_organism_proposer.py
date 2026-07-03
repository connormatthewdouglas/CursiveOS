#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import organism_proposer as prop  # noqa: E402
import seed_organism  # noqa: E402


class ProposerSelectionTest(unittest.TestCase):
    def test_selects_highest_priority_available(self) -> None:
        knob = prop.select_proposal("v0.12", taken=set())
        self.assertIsNotNone(knob)
        # priority-100 memory knob (zram companion) should be proposed first
        self.assertEqual(knob.candidate_id, "v0.13-pagecluster0")

    def test_skips_already_proposed_candidates(self) -> None:
        first = prop.select_proposal("v0.12", taken=set())
        # once the top candidate exists, the next-highest untried knob is chosen
        nxt = prop.select_proposal("v0.12", taken={first.candidate_id})
        self.assertIsNotNone(nxt)
        self.assertNotEqual(nxt.candidate_id, first.candidate_id)
        self.assertLessEqual(nxt.priority, first.priority)

    def test_exhaustion_returns_none(self) -> None:
        all_ids = {k.candidate_id for k in prop.KNOB_LIBRARY}
        self.assertIsNone(prop.select_proposal("v0.12", taken=all_ids))

    def test_unknown_parent_raises(self) -> None:
        with self.assertRaises(FileNotFoundError):
            prop.select_proposal("v9.99-does-not-exist", taken=set())


class ProposerMaterializationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.knob = prop.KNOB_LIBRARY[0]  # pagecluster0

    def test_variant_json_is_valid_for_seed_organism(self) -> None:
        data = json.loads(prop.render_variant_json(self.knob, "v0.12"))
        # must survive the real validator the screen path uses
        validated = seed_organism.validate_variant(data)
        self.assertEqual(validated["variant_id"], "candidate-v0.13-pagecluster0")
        self.assertTrue(validated["fitness_eligible"])
        self.assertEqual(validated["knobs_removed_vs_parent"], 0)
        self.assertEqual(validated["preset_path"], "presets/cursiveos-presets-v0.13-pagecluster0.sh")

    def test_preset_is_reversible_and_delegates_to_parent(self) -> None:
        sh = prop.render_preset_sh(self.knob, "v0.12")
        for token in ("--apply-temp", "--undo", "--dry-run"):
            self.assertIn(token, sh)
        # delegates the rest of apply/undo to the parent preset
        self.assertIn("cursiveos-presets-v0.12.sh", sh)
        # captures prior value on apply and restores it on undo (reversibility)
        self.assertIn("sysctl -n", sh)
        self.assertIn('sysctl -w "$KEY=$SAVED"', sh)
        self.assertIn("vm.page-cluster", sh)

    def test_enqueue_sql_is_scoped_and_gated(self) -> None:
        sql = prop.enqueue_sql(self.knob, "v0.12", cycle_id=5, screen_order="normal")
        self.assertIn("insert into public.measurement_requests", sql)
        self.assertIn("simulated_not_payout_eligible", sql)
        self.assertIn("linux_bare_metal", sql)
        self.assertIn(", 0, 'organism-proposer'", sql)  # reward_sats_placeholder = 0
        self.assertIn("on conflict (request_key) do nothing", sql)
        # candidate + parent paths match the daemon's variant-path convention
        self.assertIn("references/seed-organism/variant.v0.13-pagecluster0.json", sql)
        self.assertIn("references/seed-organism/variant.v0.12.json", sql)

    def test_every_library_knob_materializes_valid_variant(self) -> None:
        # no audited knob may produce an invalid variant or a non-reversible preset
        for knob in prop.KNOB_LIBRARY:
            data = json.loads(prop.render_variant_json(knob, "v0.12"))
            seed_organism.validate_variant(data)
            sh = prop.render_preset_sh(knob, "v0.12")
            self.assertIn("--undo", sh)
            self.assertIn(knob.key, sh)


if __name__ == "__main__":
    unittest.main()
