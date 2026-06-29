#!/usr/bin/env python3
"""H2 adversarial/dishonest tester experiment runner.

This intentionally does *not* harden acceptance logic. It generates malicious
seed-organism submissions and routes them through the current real code paths so
we can see which fabricated bundles are rejected, accepted, and payout-eligible.
"""

from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import qd_organism  # noqa: E402
import seed_organism  # noqa: E402

RESULTS_JSON = ROOT / "docs" / "experiments" / "H2-adversarial-tester-results.json"
STATE_ROOT = ROOT / ".cursiveos" / "h2-adversarial-tester"


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise TypeError(f"expected JSON object in {path}")
    return data


def rel(path: Path | None) -> str | None:
    if path is None:
        return None
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def clean_state(name: str) -> Path:
    state = STATE_ROOT / name
    if state.exists():
        shutil.rmtree(state)
    seed_organism.ensure_state(state)
    return state


def run_seed_cli(state: Path, args: list[str]) -> dict[str, Any]:
    cmd = [
        sys.executable,
        str(ROOT / "tools" / "seed_organism.py"),
        "--state-dir",
        str(state),
        *args,
    ]
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    return {
        "cmd": cmd,
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "parsed_stdout": parse_seed_stdout(proc.stdout),
    }


def parse_seed_stdout(stdout: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for line in stdout.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        parsed[key.strip()] = value.strip()
    return parsed


def bundle_from_cli_result(cli: dict[str, Any]) -> dict[str, Any]:
    parsed = cli.get("parsed_stdout", {})
    bundle_path_raw = parsed.get("bundle")
    bundle_dir = (ROOT / bundle_path_raw).resolve() if bundle_path_raw else None
    bundle: dict[str, Any] = {
        "path": rel(bundle_dir),
        "bundle_hash": parsed.get("bundle_hash"),
        "decision": parsed.get("decision"),
        "reason": parsed.get("reason"),
        "fitness_score": as_float(parsed.get("fitness_score")),
        "confidence": as_float(parsed.get("confidence")),
    }
    if bundle_dir and bundle_dir.exists():
        bundle["manifest"] = read_json(bundle_dir / "bundle-manifest.json")
        bundle["variant"] = read_json(bundle_dir / "variant.json")
        bundle["metrics"] = read_json(bundle_dir / "metrics.json")
        bundle["sensor_result"] = read_json(bundle_dir / "sensor-result.json")
        bundle["regression_result"] = read_json(bundle_dir / "regression-result.json")
    return bundle


def as_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def good_regression() -> dict[str, Any]:
    return {
        "full_test_passed": True,
        "reverted_cleanly": True,
        "host_safety_passed": True,
        "failures": [],
    }


def base_metrics(machine_id: str = "h2-honest-source-rig") -> dict[str, Any]:
    baseline = {
        "network_mbps": 930.0,
        "coldstart_ms": 1820.0,
        "sustained_tokps": 41.0,
        "idle_watts": 71.0,
        "memory_refault_s": 10.0,
    }
    return {
        "schema_version": "seed-organism.metrics.h2.v0.1",
        "machine_id": machine_id,
        "preset_version": "h2-test",
        "baseline": dict(baseline),
        "variant": dict(baseline),
        "sample_counts": {"network": 3, "coldstart": 3, "sustained": 3, "idle_power": 3},
        "regression": good_regression(),
    }


def inflated_metrics(machine_id: str = "h2-malicious-rig") -> dict[str, Any]:
    metrics = base_metrics(machine_id)
    # Fabricated candidate improvement: no corresponding measurement/provenance is
    # supplied, but current scoring trusts the submitted numbers.
    metrics["variant"] = {
        "network_mbps": 930.0,
        "coldstart_ms": 1638.0,  # claimed +10% lower-is-better
        "sustained_tokps": 42.0,
        "idle_watts": 71.0,
        "memory_refault_s": 10.0,
    }
    metrics["adversarial_claim"] = "candidate metrics are inflated/fabricated from a real baseline"
    return metrics


def full_test_result(
    *,
    machine_id: str,
    tuned: dict[str, float],
    preset_version: str,
    source: str,
) -> dict[str, Any]:
    baseline = {
        "network_mbps": 930.0,
        "coldstart_ms": 1820.0,
        "sustained_tokps": 41.0,
        "idle_watts": 71.0,
        "memory_refault_s": 10.0,
    }
    return {
        "schema_version": "cursiveos.full-test-result.h2.v0.1",
        "created_at": "2026-06-29T00:00:00+00:00",
        "machine_id": machine_id,
        "hardware_fingerprint_hash": machine_id,
        "preset_version": preset_version,
        "wrapper_version": "h2-adversarial",
        "source_provenance": source,
        "baseline": baseline,
        "variant": tuned,
        "sample_counts": {"network": 3, "coldstart": 3, "sustained": 3, "idle_power": 3},
        "regression": good_regression(),
    }


def attack_variant(variant_id: str, contributor_id: str = "h2-malicious-contributor") -> dict[str, Any]:
    return {
        "schema_version": "seed-organism.variant.v0.1",
        "variant_id": variant_id,
        "parent_variant_id": "parent-baseline-v0.12",
        "contributor_id": contributor_id,
        "commit_ref": "h2-adversarial-untrusted-submission",
        "preset_version": variant_id,
        "fitness_eligible": True,
        "declared_scope": "H2 adversarial submission; should not be trusted as measured evidence",
        "rollback_method": "none; synthetic adversarial test fixture",
    }


def close_cycle(state: Path, cycle_id: int, revenue_sats: int = 100_000) -> dict[str, Any]:
    cli = run_seed_cli(
        state,
        ["close-cycle", "--cycle-id", str(cycle_id), "--revenue-sats", str(revenue_sats)],
    )
    parsed = cli["parsed_stdout"]
    report_path = (ROOT / parsed["report"]).resolve() if parsed.get("report") else None
    report = read_json(report_path) if report_path and report_path.exists() else {}
    contributors = report.get("contributors", []) if isinstance(report, dict) else []
    payout_triggered = any(float(c.get("total_payout_sats", 0) or 0) > 0 for c in contributors if isinstance(c, dict))
    return {
        "cli": cli,
        "report_path": rel(report_path),
        "report_hash": parsed.get("report_hash"),
        "contributors": contributors,
        "payout_triggered": payout_triggered,
    }


def classify_gate(bundle: dict[str, Any], *, extra_gate: str | None = None) -> str | None:
    if extra_gate:
        return extra_gate
    decision = bundle.get("decision")
    reason = str(bundle.get("reason") or "")
    if decision == "invalid":
        return "schema/core-metric gate"
    if decision == "rejected_regression":
        return "regression gate"
    if decision == "inconclusive":
        return "confidence gate"
    if decision == "rejected_negative_fitness":
        if "regression" in reason or "cost" in reason:
            return "severe-regression gate"
        return "minimum_accept_fitness gate"
    if decision == "accepted":
        return None
    return decision


def result_record(
    *,
    mode: str,
    name: str,
    attack: str,
    pipeline: str,
    state: Path,
    cycle_id: int,
    variant_path: Path | None,
    metrics_path: Path | None,
    cli: dict[str, Any] | None,
    bundle: dict[str, Any],
    extra: dict[str, Any] | None = None,
    deferred_to_trust_layer: bool = False,
    extra_gate: str | None = None,
) -> dict[str, Any]:
    payout = close_cycle(state, cycle_id)
    accepted = bundle.get("decision") == "accepted"
    record = {
        "mode": mode,
        "name": name,
        "attack": attack,
        "pipeline": pipeline,
        "state_dir": rel(state),
        "cycle_id": cycle_id,
        "submitted_variant_file": rel(variant_path),
        "submitted_metrics_file": rel(metrics_path),
        "cli": cli,
        "submitted_bundle": bundle,
        "pipeline_verdict": bundle.get("decision"),
        "reason": bundle.get("reason"),
        "gate_triggered": classify_gate(bundle, extra_gate=extra_gate),
        "accepted": accepted,
        "payout_triggered": bool(payout["payout_triggered"]),
        "payout_report": payout,
        "deferred_to_trust_layer": deferred_to_trust_layer,
    }
    if extra:
        record["extra"] = extra
    return record


def mode_a() -> dict[str, Any]:
    state = clean_state("mode-a-inflated-delta")
    cycle_id = 201
    inputs = state / "inputs"
    variant_path = inputs / "variant-mode-a.json"
    metrics_path = inputs / "metrics-mode-a-inflated.json"
    write_json(variant_path, attack_variant("h2-a-inflated-delta"))
    write_json(metrics_path, inflated_metrics("h2-a-malicious-rig"))
    cli = run_seed_cli(
        state,
        ["run-variant", "--variant", str(variant_path), "--metrics", str(metrics_path), "--cycle-id", str(cycle_id)],
    )
    bundle = bundle_from_cli_result(cli)
    return result_record(
        mode="A",
        name="inflated delta",
        attack="Real baseline values with fabricated candidate improvement that clears minimum_accept_fitness.",
        pipeline="seed_organism.py CLI: run-variant -> record_evaluation -> verdict -> bundle/ledger",
        state=state,
        cycle_id=cycle_id,
        variant_path=variant_path,
        metrics_path=metrics_path,
        cli=cli,
        bundle=bundle,
    )


def mode_b() -> dict[str, Any]:
    source_state = clean_state("mode-b-source-genuine")
    attack_state = clean_state("mode-b-replay")
    source_cycle = 210
    attack_cycle = 211
    source_inputs = source_state / "inputs"
    source_variant_path = source_inputs / "variant-mode-b-source.json"
    source_metrics_path = source_inputs / "metrics-mode-b-source.json"
    source_metrics = inflated_metrics("h2-b-source-stardust")
    source_metrics["source_provenance"] = "treated_as_genuine_winning_measurement_for_replay_source"
    write_json(source_variant_path, attack_variant("h2-b-genuine-winning-source", "h2-honest-contributor"))
    write_json(source_metrics_path, source_metrics)
    source_cli = run_seed_cli(
        source_state,
        [
            "run-variant",
            "--variant",
            str(source_variant_path),
            "--metrics",
            str(source_metrics_path),
            "--cycle-id",
            str(source_cycle),
        ],
    )
    source_bundle = bundle_from_cli_result(source_cli)

    attack_inputs = attack_state / "inputs"
    attack_variant_path = attack_inputs / "variant-mode-b-replay.json"
    attack_metrics_path = attack_inputs / "metrics-mode-b-replay.json"
    replayed = copy.deepcopy(source_metrics)
    replayed["machine_id"] = "h2-b-fake-independent-laptop"
    replayed["hardware_fingerprint_hash"] = "h2-b-fake-independent-laptop"
    replayed["replay_attack"] = {
        "copied_from_bundle_hash": source_bundle.get("bundle_hash"),
        "claim": "same winning metrics resubmitted as a different machine/session",
    }
    write_json(attack_variant_path, attack_variant("h2-b-replay-as-independent"))
    write_json(attack_metrics_path, replayed)
    attack_cli = run_seed_cli(
        attack_state,
        [
            "run-variant",
            "--variant",
            str(attack_variant_path),
            "--metrics",
            str(attack_metrics_path),
            "--cycle-id",
            str(attack_cycle),
        ],
    )
    attack_bundle = bundle_from_cli_result(attack_cli)
    return result_record(
        mode="B",
        name="replay as independent machine/session",
        attack="Copied a winning measurement and resubmitted it under a different machine/session identity.",
        pipeline="seed_organism.py CLI: run-variant -> record_evaluation -> verdict -> bundle/ledger",
        state=attack_state,
        cycle_id=attack_cycle,
        variant_path=attack_variant_path,
        metrics_path=attack_metrics_path,
        cli=attack_cli,
        bundle=attack_bundle,
        extra={
            "source_state_dir": rel(source_state),
            "source_bundle": source_bundle,
            "source_cli": source_cli,
        },
    )


def qd_guard_probe(state: Path, cycle_id: int) -> dict[str, Any]:
    parent = qd_organism.make_variant(
        variant_id="h2-c-qD-parent-active-knobs".lower(),
        parent=None,
        knobs={
            "cpu_governor_boost": 0.4,
            "gpu_idle_pin_mhz": 0.2,
            "scheduler_aggressive": 0.1,
            "power_cap_relief": 0.0,
        },
    )
    child = qd_organism.make_variant(
        variant_id="h2-c-qd-overdeclared-parsimony",
        parent=parent,
        knobs={
            "cpu_governor_boost": 0.4,
            "gpu_idle_pin_mhz": 0.2,
            "scheduler_aggressive": 0.1,
            "power_cap_relief": 0.0,
        },
    )
    claimed = 5
    child["knobs_removed_vs_parent"] = claimed
    child["contributor_id"] = "h2-malicious-contributor"
    child["commit_ref"] = "h2-adversarial-untrusted-submission"
    metrics = base_metrics("h2-c-qd-source")
    before = int(child.get("knobs_removed_vs_parent", 0))
    sensor, regression, decision, reason = qd_organism.evaluate_variant(child, metrics, seed_organism.DEFAULT_CONFIG)
    after = int(child.get("knobs_removed_vs_parent", 0))
    # Write the guarded submission through the normal seed bundle writer so H2 has
    # an audit bundle for the real guarded path. record_evaluation recomputes the
    # same verdict from the now-synced variant.
    seed_organism.record_evaluation(state, seed_organism.DEFAULT_CONFIG, child, metrics, cycle_id)
    latest_manifest = sorted((state / "runs").glob(f"cycle-{cycle_id}/*/bundle-manifest.json"))[-1]
    bundle_dir = latest_manifest.parent
    bundle = {
        "path": rel(bundle_dir),
        "bundle_hash": read_json(bundle_dir / "bundle-manifest.json")["bundle_hash"],
        "decision": decision,
        "reason": reason,
        "fitness_score": sensor.get("fitness_score"),
        "confidence": sensor.get("confidence"),
        "manifest": read_json(bundle_dir / "bundle-manifest.json"),
        "variant": read_json(bundle_dir / "variant.json"),
        "metrics": read_json(bundle_dir / "metrics.json"),
        "sensor_result": read_json(bundle_dir / "sensor-result.json"),
        "regression_result": read_json(bundle_dir / "regression-result.json"),
    }
    return {
        "bundle": bundle,
        "guard_effect": {
            "claimed_knobs_removed_vs_parent": claimed,
            "before_qd_guard": before,
            "after_qd_guard": after,
            "guard_caught_overclaim": after < claimed,
        },
    }


def mode_c() -> dict[str, Any]:
    qd_state = clean_state("mode-c-qd-guarded")
    direct_state = clean_state("mode-c-direct-seed-bypass")
    qd_cycle = 220
    direct_cycle = 221
    qd = qd_guard_probe(qd_state, qd_cycle)

    inputs = direct_state / "inputs"
    variant_path = inputs / "variant-mode-c-direct-overclaim.json"
    metrics_path = inputs / "metrics-mode-c-neutral.json"
    parent_knobs = {
        "cpu_governor_boost": 0.4,
        "gpu_idle_pin_mhz": 0.2,
        "scheduler_aggressive": 0.1,
        "power_cap_relief": 0.0,
    }
    malicious = attack_variant("h2-c-direct-overdeclared-parsimony")
    malicious.update(
        {
            "schema_version": "seed-organism.variant.qd-sim.v0.1",
            "parent_genome_knobs": parent_knobs,
            "genome_knobs": dict(parent_knobs),
            "knobs_removed_vs_parent": 5,
            "mutation_operator": "malicious_parsimony_overclaim",
        }
    )
    write_json(variant_path, malicious)
    write_json(metrics_path, base_metrics("h2-c-direct-source"))
    direct_cli = run_seed_cli(
        direct_state,
        [
            "run-variant",
            "--variant",
            str(variant_path),
            "--metrics",
            str(metrics_path),
            "--cycle-id",
            str(direct_cycle),
        ],
    )
    direct_bundle = bundle_from_cli_result(direct_cli)
    direct_record = result_record(
        mode="C-direct",
        name="direct seed parsimony overclaim bypass",
        attack="Claimed knob removals that the submitted genome did not actually reflect, through run-variant.",
        pipeline="seed_organism.py CLI: run-variant direct acceptance path",
        state=direct_state,
        cycle_id=direct_cycle,
        variant_path=variant_path,
        metrics_path=metrics_path,
        cli=direct_cli,
        bundle=direct_bundle,
    )
    qd_payout = close_cycle(qd_state, qd_cycle)
    accepted = bool(direct_record["accepted"])
    return {
        "mode": "C",
        "name": "parsimony gaming",
        "attack": "Claimed knob removals that the genome does not actually reflect.",
        "pipeline": "QD guarded path plus direct seed CLI path probe",
        "pipeline_verdict": "accepted" if accepted else qd["bundle"].get("decision"),
        "reason": (
            "QD path caught overclaim, but direct seed run-variant accepted it"
            if accepted
            else qd["bundle"].get("reason")
        ),
        "gate_triggered": None if accepted else "QD genome-derived parsimony guard -> minimum_accept_fitness gate",
        "accepted": accepted,
        "payout_triggered": bool(direct_record["payout_triggered"]),
        "deferred_to_trust_layer": False,
        "submitted_bundle": direct_bundle if accepted else qd["bundle"],
        "subtests": {
            "qd_guarded_submission": {
                "state_dir": rel(qd_state),
                "cycle_id": qd_cycle,
                "submitted_bundle": qd["bundle"],
                "pipeline_verdict": qd["bundle"].get("decision"),
                "gate_triggered": "QD genome-derived parsimony guard -> minimum_accept_fitness gate",
                "accepted": qd["bundle"].get("decision") == "accepted",
                "payout_report": qd_payout,
                **qd["guard_effect"],
            },
            "direct_seed_submission": direct_record,
        },
    }


def mode_d() -> dict[str, Any]:
    state = clean_state("mode-d-confirmation-sybil")
    cycle_id = 230
    inputs = state / "inputs"
    parent_variant_path = ROOT / "references" / "seed-organism" / "variant.v0.12.json"
    candidate_variant_path = inputs / "variant-mode-d-sybil-candidate.json"
    parent_result_path = inputs / "mode-d-parent-result.json"
    candidate_result_path = inputs / "mode-d-candidate-result.json"
    same_source = "h2_same_source_near_identical_sybil_sessions"
    parent_tuned = {
        "network_mbps": 930.0,
        "coldstart_ms": 1820.0,
        "sustained_tokps": 41.0,
        "idle_watts": 71.0,
        "memory_refault_s": 10.0,
    }
    candidate_tuned = {
        "network_mbps": 930.0,
        "coldstart_ms": 1638.0,
        "sustained_tokps": 42.0,
        "idle_watts": 71.0,
        "memory_refault_s": 10.0,
    }
    write_json(candidate_variant_path, attack_variant("h2-d-confirmation-sybil"))
    write_json(
        parent_result_path,
        full_test_result(
            machine_id="h2-d-single-source-rig",
            tuned=parent_tuned,
            preset_version="parent-v0.12",
            source=same_source,
        ),
    )
    write_json(
        candidate_result_path,
        full_test_result(
            machine_id="h2-d-single-source-rig",
            tuned=candidate_tuned,
            preset_version="h2-d-confirmation-sybil",
            source=same_source,
        ),
    )
    cli = run_seed_cli(
        state,
        [
            "screen-variant",
            "--parent-variant",
            str(parent_variant_path),
            "--candidate-variant",
            str(candidate_variant_path),
            "--parent-result-json",
            str(parent_result_path),
            "--candidate-result-json",
            str(candidate_result_path),
            "--confirmations",
            "3",
            "--cycle-id",
            str(cycle_id),
        ],
    )
    bundle = bundle_from_cli_result(cli)
    return result_record(
        mode="D",
        name="confirmation Sybil",
        attack="Asserted three independent confirmations for near-identical same-source measurements via --confirmations 3.",
        pipeline="seed_organism.py CLI: screen-variant -> comparison_metrics(--confirmations) -> record_evaluation",
        state=state,
        cycle_id=cycle_id,
        variant_path=candidate_variant_path,
        metrics_path=candidate_result_path,
        cli=cli,
        bundle=bundle,
        deferred_to_trust_layer=True,
        extra={
            "parent_result_json": rel(parent_result_path),
            "candidate_result_json": rel(candidate_result_path),
            "asserted_confirmations": 3,
            "current_code_limitation": "confirmation_count is an asserted integer; current code does not auto-count independent machine/session bundles",
        },
    )


def h2_status(results: list[dict[str, Any]]) -> str:
    non_d_failures = [r for r in results if r.get("accepted") and not r.get("deferred_to_trust_layer")]
    if non_d_failures:
        return "FAILED"
    deferred = [r for r in results if r.get("deferred_to_trust_layer")]
    if deferred:
        return "PASSED_EXCEPT_MODE_D_DEFERRED_TO_TRUST_LAYER"
    return "PASSED"


def main() -> int:
    results = [mode_a(), mode_b(), mode_c(), mode_d()]
    report = {
        "schema_version": "cursiveos.experiment.h2-adversarial-tester-results.v0.1",
        "experiment": "H2 adversarial/dishonest tester",
        "pre_registered_doc": "docs/experiments/H2-adversarial-tester-results.md",
        "results_json": rel(RESULTS_JSON),
        "state_root": rel(STATE_ROOT),
        "thresholds": {
            "pass": "zero fabricated bundles reach accepted state or trigger payout across all attack modes; every rejection logs the gate",
            "fail_kill": "any fabricated-delta bundle reaches accepted",
            "mode_d_exception": "if confirmation Sybil is not defendable without a trust layer, mark deferred to trust layer; real BTC must stay gated",
        },
        "overall_h2_status": h2_status(results),
        "results": results,
    }
    write_json(RESULTS_JSON, report)
    print(json.dumps({
        "overall_h2_status": report["overall_h2_status"],
        "results_json": rel(RESULTS_JSON),
        "modes": [
            {
                "mode": r["mode"],
                "verdict": r.get("pipeline_verdict"),
                "accepted": r.get("accepted"),
                "payout_triggered": r.get("payout_triggered"),
                "gate_triggered": r.get("gate_triggered"),
                "deferred_to_trust_layer": r.get("deferred_to_trust_layer"),
            }
            for r in results
        ],
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
