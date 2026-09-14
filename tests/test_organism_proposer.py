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
    def test_library_exhausted_after_cycle7(self) -> None:
        # Honest-nulls + cycle-7 rejects mine out the audited library.
        knob = prop.select_proposal("v0.12", taken=set())
        self.assertIsNone(knob)

    def test_exhaustion_returns_none(self) -> None:
        all_ids = {k.candidate_id for k in prop.KNOB_LIBRARY}
        self.assertIsNone(prop.select_proposal("v0.12", taken=all_ids))

    def test_unknown_parent_raises(self) -> None:
        with self.assertRaises(FileNotFoundError):
            prop.select_proposal("v9.99-does-not-exist", taken=set())

    def test_skips_mined_out_honest_nulls_and_cycle7(self) -> None:
        for slug in (
            "pagecluster0",
            "vfscache50",
            "watermark200",
            "dirtyexpire1500",
            "migcost5ms",
            "notsentlowat16k",
        ):
            self.assertIn(slug, prop.MINED_OUT_SLUGS)


class ProposerMaterializationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.knob = prop.KNOB_LIBRARY[0]  # pagecluster0

    def test_variant_json_is_valid_for_seed_organism(self) -> None:
        data = json.loads(prop.render_variant_json(self.knob, "v0.12"))
        validated = seed_organism.validate_variant(data)
        self.assertEqual(validated["variant_id"], "candidate-v0.13-pagecluster0")
        self.assertTrue(validated["fitness_eligible"])
        self.assertEqual(validated["knobs_removed_vs_parent"], 0)
        self.assertEqual(validated["preset_path"], "presets/cursiveos-presets-v0.13-pagecluster0.sh")

    def test_preset_is_reversible_and_delegates_to_parent(self) -> None:
        sh = prop.render_preset_sh(self.knob, "v0.12")
        for token in ("--apply-temp", "--undo", "--dry-run"):
            self.assertIn(token, sh)
        self.assertIn("cursiveos-presets-v0.12.sh", sh)
        self.assertIn("sysctl -n", sh)
        self.assertIn('sysctl -w "$KEY=$SAVED"', sh)
        self.assertIn("vm.page-cluster", sh)

    def test_enqueue_sql_is_scoped_and_gated(self) -> None:
        sql = prop.enqueue_sql(self.knob, "v0.12", cycle_id=5, screen_order="normal")
        self.assertIn("insert into public.measurement_requests", sql)
        self.assertIn("simulated_not_payout_eligible", sql)
        self.assertIn("linux_bare_metal", sql)
        self.assertIn(", 0, 'organism-proposer'", sql)
        self.assertIn("on conflict (request_key) do nothing", sql)
        self.assertIn("references/seed-organism/variant.v0.13-pagecluster0.json", sql)
        self.assertIn("references/seed-organism/variant.v0.12.json", sql)

    def test_every_library_knob_materializes_valid_variant(self) -> None:
        for knob in prop.KNOB_LIBRARY:
            data = json.loads(prop.render_variant_json(knob, "v0.12"))
            seed_organism.validate_variant(data)
            sh = prop.render_preset_sh(knob, "v0.12")
            self.assertIn("--undo", sh)
            self.assertIn(knob.key, sh)


if __name__ == "__main__":
    unittest.main()
