#!/usr/bin/env python3
"""V verifier-hardening adversarial/dishonest tester experiment runner.

Generates malicious and honest-control seed-organism submissions and routes
them through the current real production code paths. The runner itself does not
soften thresholds or change acceptance logic; remediation belongs in the shared
seed/QD acceptance boundary.
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

RESULTS_JSON = ROOT / "docs" / "experiments" / "V-verifier-hardening-results.json"
STATE_ROOT = ROOT / ".cursiveos" / "v-verifier-hardening-tester"


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
    # supplied, so the hardened boundary should reject it before scoring/payout.
    metrics["variant"] = {
        "network_mbps": 930.0,
        "coldstart_ms": 1638.0,  # claimed +10% lower-is-better
        "sustained_tokps": 42.0,
        "idle_watts": 71.0,
        "memory_refault_s": 10.0,
    }
    metrics["adversarial_claim"] = "candidate metrics are inflated/fabricated from a real baseline"
    return metrics


def configure_global_index(*states: Path, name: str) -> Path:
    global_index = STATE_ROOT / f"{name}-accepted-fingerprints.jsonl"
    for state in states:
        config = seed_organism.DEFAULT_CONFIG | {"global_replay_index": str(global_index)}
        write_json(state / "config.json", config)
    return global_index


def write_detail_logs(run_dir: Path, baseline: dict[str, float], tuned: dict[str, float], *, cpu_only: bool = False) -> dict[str, str]:
    run_dir.mkdir(parents=True, exist_ok=True)
    network = run_dir / "network.log"
    network.write_text(
        f"""
--- BASELINE ---
  TCP CC:    cubic
  rmem_max:  212992 bytes (0.2 MB)
    Run 1: {baseline['network_mbps']:.3f} Mbit/s | retransmits: 1 | RTT: 51.0ms
  Avg: {baseline['network_mbps']:.3f} Mbit/s | retransmits: 1.0 | RTT: 51.0ms
  Range: {baseline['network_mbps']:.3f} - {baseline['network_mbps']:.3f} Mbit/s
--- TUNED ---
  TCP CC:    bbr
  rmem_max:  16777216 bytes (16.0 MB)
    Run 1: {tuned['network_mbps']:.3f} Mbit/s | retransmits: 0 | RTT: 50.0ms
  Avg: {tuned['network_mbps']:.3f} Mbit/s | retransmits: 0.0 | RTT: 50.0ms
  Range: {tuned['network_mbps']:.3f} - {tuned['network_mbps']:.3f} Mbit/s
""".strip()
        + "\n",
        encoding="utf-8",
    )
    coldstart = run_dir / "coldstart.log"
    coldstart.write_text(
        f"""
--- BASELINE ---
  CPU gov:   schedutil
  GPU freq:  300 MHz (idle)
    Call 1: GPU_before=300MHz | load=100.0ms | TTFT=20.0ms | cold_total={baseline['coldstart_ms']:.3f}ms | 40.00 tok/s | tokens:30
  Avg: load=100.0ms | TTFT=20.0ms | cold_total={baseline['coldstart_ms']:.3f}ms | 40.00 tok/s
  Load range: 100.0ms - 100.0ms | Cold range: {baseline['coldstart_ms']:.3f}ms - {baseline['coldstart_ms']:.3f}ms
--- TUNED ---
  CPU gov:   performance
  GPU freq:  2000 MHz (idle)
    Call 1: GPU_before=2000MHz | load=90.0ms | TTFT=10.0ms | cold_total={tuned['coldstart_ms']:.3f}ms | 42.00 tok/s | tokens:30
  Avg: load=90.0ms | TTFT=10.0ms | cold_total={tuned['coldstart_ms']:.3f}ms | 42.00 tok/s
  Load range: 90.0ms - 90.0ms | Cold range: {tuned['coldstart_ms']:.3f}ms - {tuned['coldstart_ms']:.3f}ms
""".strip()
        + "\n",
        encoding="utf-8",
    )
    processor = "100% CPU" if cpu_only else "100% GPU"
    sustained = run_dir / "sustained.log"
    sustained.write_text(
        f"""
--- BASELINE ---
  Governor: schedutil
  Processor: {processor}
    Pass 1: {baseline['sustained_tokps']:.3f} tok/s | TTFT: 0.100s | tokens: 100
  Avg: {baseline['sustained_tokps']:.3f} tok/s | TTFT avg: 0.100s | min: {baseline['sustained_tokps']:.3f} | max: {baseline['sustained_tokps']:.3f}
--- TUNED ---
  Governor: performance
  Processor: {processor}
    Pass 1: {tuned['sustained_tokps']:.3f} tok/s | TTFT: 0.090s | tokens: 100
  Avg: {tuned['sustained_tokps']:.3f} tok/s | TTFT avg: 0.090s | min: {tuned['sustained_tokps']:.3f} | max: {tuned['sustained_tokps']:.3f}
""".strip()
        + "\n",
        encoding="utf-8",
    )
    return {"network": network.name, "coldstart": coldstart.name, "sustained": sustained.name}


def full_test_result(
    *,
    machine_id: str,
    tuned: dict[str, float],
    preset_version: str,
    source: str = "native_full_test_json",
    sample_counts: dict[str, int] | None = None,
    benchmark_context: dict[str, Any] | None = None,
    hardware: dict[str, Any] | None = None,
) -> dict[str, Any]:
    baseline = {
        "network_mbps": 930.0,
        "coldstart_ms": 1820.0,
        "sustained_tokps": 41.0,
        "idle_watts": 71.0,
        "memory_refault_s": 10.0,
    }
    counts = dict(sample_counts or {"network": 3, "coldstart": 3, "sustained": 3, "idle_power": 3})
    counts.setdefault("idle_power", 3)
    return {
        "schema_version": "cursiveos.full-test-result.v-phase.v0.1",
        "created_at": "2026-06-29T00:00:00+00:00",
        "machine_id": machine_id,
        "hardware_fingerprint_hash": machine_id,
        "preset_version": preset_version,
        "wrapper_version": "v-verifier-hardening",
        "source_provenance": source,
        "baseline": baseline,
        "variant": tuned,
        "sample_counts": counts,
        "regression": good_regression(),
        "benchmark_context": dict(benchmark_context or {}),
        "hardware": dict(hardware or {}),
    }


def write_full_test_fixture(path: Path, result: dict[str, Any], *, cpu_only: bool = False) -> None:
    result = copy.deepcopy(result)
    logs = write_detail_logs(path.parent, result["baseline"], result["variant"], cpu_only=cpu_only)
    result["telemetry"] = {
        "detail_logs": logs,
        "idle_power": {"samples": [result["baseline"].get("idle_watts"), result["variant"].get("idle_watts")]},
    }
    write_json(path, result)


def load_attached_metrics(path: Path) -> dict[str, Any]:
    return seed_organism.attach_local_verifier_fields(seed_organism.load_full_test_metrics_json(path), path)


def acceptance_grade_metrics(
    machine_id: str = "h2-honest-source-rig",
    *,
    result_path: Path | None = None,
    tuned: dict[str, float] | None = None,
    cpu_only: bool = False,
    sample_counts: dict[str, int] | None = None,
    benchmark_context: dict[str, Any] | None = None,
    hardware: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Decision-grade full-test fixture used by replay and honest-control tests."""
    source = inflated_metrics(machine_id)
    tuned = dict(tuned or source["variant"])
    result_path = result_path or (STATE_ROOT / "fixtures" / f"{machine_id}.json")
    write_full_test_fixture(
        result_path,
        full_test_result(
            machine_id=machine_id,
            tuned=tuned,
            preset_version="v-phase-test",
            sample_counts=sample_counts,
            benchmark_context=benchmark_context,
            hardware=hardware,
        ),
        cpu_only=cpu_only,
    )
    metrics = load_attached_metrics(result_path)
    metrics["adversarial_claim"] = "decision-grade fixture derived from immutable raw full-test JSON"
    return metrics


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
        if "confirmation independence" in reason:
            return "confirmation independence gate"
        return "confidence gate"
    if decision == "rejected_negative_fitness":
        if "regression" in reason or "cost" in reason:
            return "severe-regression gate"
        return "minimum_accept_fitness gate"
    if decision == "rejected_unverified_evidence":
        return "evidence/provenance gate"
    if decision == "rejected_recompute_mismatch":
        return "verifier recompute gate"
    if decision == "rejected_unsigned_identity":
        return "signed identity gate"
    if decision == "rejected_replay":
        return "measurement replay gate"
    if decision == "rejected_replay_global":
        return "global replay gate"
    if decision == "rejected_independence_failure":
        return "confirmation independence gate"
    if decision == "rejected_funded_adversary_pattern":
        return "funded adversary pattern gate"
    if decision == "rejected_invariant":
        return "shared invariant gate"
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
    submitted_contributor = None
    submitted_variant = bundle.get("variant")
    if isinstance(submitted_variant, dict):
        submitted_contributor = submitted_variant.get("contributor_id")
    payout_rows = payout.get("contributors", [])
    attack_payout_triggered = any(
        isinstance(c, dict)
        and c.get("contributor_id") == submitted_contributor
        and float(c.get("total_payout_sats", 0) or 0) > 0
        for c in payout_rows
    )
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
        "payout_triggered": bool(attack_payout_triggered),
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
    source_state = clean_state("mode-b-global-replay-source")
    attack_state = clean_state("mode-b-global-replay-attack")
    configure_global_index(source_state, attack_state, name="mode-b-global-replay")
    source_cycle = 210
    attack_cycle = 211
    source_inputs = source_state / "inputs" / "source"
    source_variant_path = source_inputs / "variant-mode-b-source.json"
    source_metrics_path = source_inputs / "metrics-mode-b-source.json"
    source_metrics = acceptance_grade_metrics("v-b-source-stardust")
    source_metrics["adversarial_claim"] = "accepted source measurement for global replay duplicate test"
    write_json(source_variant_path, attack_variant("v-b-genuine-winning-source", "v-honest-contributor"))
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

    attack_inputs = attack_state / "inputs" / "attack"
    attack_variant_path = attack_inputs / "variant-mode-b-replay.json"
    attack_metrics_path = attack_inputs / "metrics-mode-b-replay.json"
    replayed = copy.deepcopy(source_metrics)
    replayed["replay_attack"] = {
        "copied_from_bundle_hash": source_bundle.get("bundle_hash"),
        "claim": "same immutable signed raw evidence resubmitted through a different state/account context",
    }
    write_json(attack_variant_path, attack_variant("v-b-global-replay-as-independent"))
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
        name="global replay as independent contribution",
        attack="Copied a winning immutable raw measurement and resubmitted it in a separate CursiveRoot state.",
        pipeline="seed_organism.py CLI: run-variant -> verdict -> replay_gate(local+global) -> bundle/ledger",
        state=attack_state,
        cycle_id=attack_cycle,
        variant_path=attack_variant_path,
        metrics_path=attack_metrics_path,
        cli=attack_cli,
        bundle=attack_bundle,
        extra={
            "source_state_dir": rel(source_state),
            "source_cycle_id": source_cycle,
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
        "pipeline_verdict": direct_record.get("pipeline_verdict"),
        "reason": direct_record.get("reason"),
        "gate_triggered": direct_record.get("gate_triggered"),
        "accepted": accepted,
        "payout_triggered": bool(direct_record["payout_triggered"]),
        "deferred_to_trust_layer": False,
        "submitted_bundle": direct_bundle,
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


def mode_d_funded() -> dict[str, Any]:
    state = clean_state("mode-d-funded-sybil")
    cycle_id = 230
    inputs = state / "inputs"
    variant_path = inputs / "variant-mode-d-funded.json"
    metrics_path = inputs / "metrics-mode-d-funded.json"
    write_json(variant_path, attack_variant("v-d-funded-confirmation-sybil"))

    tuned = {
        "network_mbps": 930.0,
        "coldstart_ms": 1638.0,
        "sustained_tokps": 42.0,
        "idle_watts": 71.0,
        "memory_refault_s": 10.0,
    }
    # Funded adversary buys/controls multiple identities and raw files, but all
    # confirmations derive from the same non-identity metric pattern.
    m1 = acceptance_grade_metrics("v-d-funded-rig-a", result_path=inputs / "funded-a.json", tuned=tuned)
    m2 = acceptance_grade_metrics("v-d-funded-rig-b", result_path=inputs / "funded-b.json", tuned=tuned)
    attack_metrics = copy.deepcopy(m1)
    attack_metrics.update(seed_organism.build_independent_confirmation_aggregation([m1, m2]))
    attack_metrics["adversarial_claim"] = "funded actor controls two signed identities with duplicated metric derivation"
    write_json(metrics_path, attack_metrics)

    cli = run_seed_cli(
        state,
        ["run-variant", "--variant", str(variant_path), "--metrics", str(metrics_path), "--cycle-id", str(cycle_id)],
    )
    bundle = bundle_from_cli_result(cli)
    return result_record(
        mode="D-funded",
        name="funded confirmation Sybil",
        attack="Multiple signed identities/raw artifacts share the same non-identity metric derivation pattern.",
        pipeline="seed_organism.py CLI: run-variant -> CursiveRoot aggregation verifier -> funded adversary pattern gate",
        state=state,
        cycle_id=cycle_id,
        variant_path=variant_path,
        metrics_path=metrics_path,
        cli=cli,
        bundle=bundle,
        extra={
            "confirmation_source": attack_metrics.get("confirmation_source"),
            "confirmation_count": attack_metrics.get("confirmation_count"),
            "policy_boundary": "V rejects duplicated derivation across bought identities/raw artifacts; real BTC remains simulated and gated.",
        },
    )


def mode_h() -> dict[str, Any]:
    state = clean_state("mode-h-honest-controls")
    configure_global_index(state, name="mode-h-honest-controls")
    noisy_cycle = 240
    weird_cycle = 241

    inputs = state / "inputs"

    noisy_variant_path = inputs / "variant-mode-h-noisy.json"
    noisy_metrics_path = inputs / "metrics-mode-h-noisy.json"
    noisy = acceptance_grade_metrics(
        "v-h-honest-noisy",
        result_path=inputs / "honest-noisy-result.json",
        sample_counts={"network": 2, "coldstart": 2, "sustained": 2, "idle_power": 3},
    )
    noisy["honest_control"] = "noisy but real lower-repeat measurement; acceptable outcome is accepted or inconclusive, not fraud rejected"
    write_json(noisy_variant_path, attack_variant("v-h-honest-noisy", "v-honest-control-contributor"))
    write_json(noisy_metrics_path, noisy)
    noisy_cli = run_seed_cli(
        state,
        ["run-variant", "--variant", str(noisy_variant_path), "--metrics", str(noisy_metrics_path), "--cycle-id", str(noisy_cycle)],
    )
    noisy_bundle = bundle_from_cli_result(noisy_cli)
    noisy_record = result_record(
        mode="H-noisy",
        name="honest noisy control",
        attack="Honest lower-repeat/noisy real measurement; should not be fraud rejected.",
        pipeline="seed_organism.py CLI: run-variant honest control",
        state=state,
        cycle_id=noisy_cycle,
        variant_path=noisy_variant_path,
        metrics_path=noisy_metrics_path,
        cli=noisy_cli,
        bundle=noisy_bundle,
    )

    weird_variant_path = inputs / "variant-mode-h-weird-hardware.json"
    weird_metrics_path = inputs / "metrics-mode-h-weird-hardware.json"
    weird = acceptance_grade_metrics(
        "v-h-legacy-cpu-only",
        result_path=inputs / "honest-weird-hardware-result.json",
        cpu_only=True,
        benchmark_context={"hardware_class": "legacy_cpu_only", "legacy_cpu_only_allowed": True},
        hardware={"hardware_class": "legacy_cpu_only"},
    )
    weird["honest_control"] = "honest legacy CPU-only hardware; should not be rejected as fraud solely for CPU-bound processor evidence"
    write_json(weird_variant_path, attack_variant("v-h-honest-weird-hardware", "v-honest-control-contributor"))
    write_json(weird_metrics_path, weird)
    weird_cli = run_seed_cli(
        state,
        ["run-variant", "--variant", str(weird_variant_path), "--metrics", str(weird_metrics_path), "--cycle-id", str(weird_cycle)],
    )
    weird_bundle = bundle_from_cli_result(weird_cli)
    weird_record = result_record(
        mode="H-weird-hardware",
        name="honest weird hardware control",
        attack="Honest legacy/CPU-only hardware evidence; should pass or be held inconclusive, not fraud rejected.",
        pipeline="seed_organism.py CLI: run-variant honest control",
        state=state,
        cycle_id=weird_cycle,
        variant_path=weird_variant_path,
        metrics_path=weird_metrics_path,
        cli=weird_cli,
        bundle=weird_bundle,
    )

    false_rejections = [
        r for r in [noisy_record, weird_record]
        if r.get("pipeline_verdict") not in {"accepted", "inconclusive"}
    ]
    return {
        "mode": "H",
        "name": "honest false-positive controls",
        "attack": "No attack: honest noisy and weird-hardware controls establish false-positive boundary.",
        "pipeline": "seed_organism.py CLI: run-variant honest controls",
        "pipeline_verdict": "pass" if not false_rejections else "fail",
        "reason": "honest controls accepted or held inconclusive" if not false_rejections else "honest controls fraud-rejected",
        "gate_triggered": None if not false_rejections else "false-positive guard",
        "accepted": not false_rejections,
        "payout_triggered": bool(noisy_record.get("payout_triggered") or weird_record.get("payout_triggered")),
        "deferred_to_trust_layer": False,
        "false_positive_rejections": false_rejections,
        "subtests": {
            "honest_noisy": noisy_record,
            "honest_weird_hardware": weird_record,
        },
    }


def v_status(results: list[dict[str, Any]]) -> str:
    fabricated_failures = [
        r for r in results
        if r.get("mode") != "H" and (r.get("accepted") or r.get("payout_triggered"))
    ]
    h = next((r for r in results if r.get("mode") == "H"), None)
    honest_failures = [] if h is None else list(h.get("false_positive_rejections") or [])
    if fabricated_failures or honest_failures:
        return "FAILED"
    return "PASSED"

def main() -> int:
    if STATE_ROOT.exists():
        shutil.rmtree(STATE_ROOT)
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    results = [mode_a(), mode_b(), mode_c(), mode_d_funded(), mode_h()]

    report = {
        "schema_version": "cursiveos.experiment.v-verifier-hardening-results.v0.1",
        "experiment": "V verifier-hardening adversarial tester",
        "pre_registered_doc": "docs/experiments/V-verifier-hardening-results.md",
        "results_json": rel(RESULTS_JSON),
        "state_root": rel(STATE_ROOT),
        "thresholds": {
            "pass": "Modes A/B/C and D-funded do not reach accepted or trigger payout; Mode H honest controls are accepted or held inconclusive, not fraud rejected",
            "fail_kill": "If any fabricated bundle reaches accepted, or if honest contributions are rejected above the registered false-positive rate, V fails. Do not reinterpret after seeing results.",
            "false_positive_rate_max": "0 of 2 honest controls may be fraud-rejected; inconclusive pending confirmation is allowed for noisy evidence",
            "real_btc_reward": "simulated and gated throughout",
        },
        "overall_v_status": v_status(results),
        "results": results,
    }
    write_json(RESULTS_JSON, report)
    print(json.dumps({
        "overall_v_status": report["overall_v_status"],
        "results_json": rel(RESULTS_JSON),
        "modes": [
            {
                "mode": r["mode"],
                "verdict": r.get("pipeline_verdict"),
                "accepted": r.get("accepted"),
                "payout_triggered": r.get("payout_triggered"),
                "gate_triggered": r.get("gate_triggered"),
                "deferred_to_trust_layer": r.get("deferred_to_trust_layer"),
                "reason": r.get("reason"),
            }
            for r in results
        ],
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
