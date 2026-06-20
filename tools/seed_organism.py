#!/usr/bin/env python3
"""
CursiveOS seed organism CLI.

Phase 0 intentionally runs as a local, append-only organism loop:
variant -> sensor result -> regression gate -> ledger entry -> fake payout.
The schemas are production-shaped so bundles can later be submitted to
CursiveRoot/Hub without redesigning the local machinery.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_STATE_DIR = ROOT / ".cursiveos" / "seed"
DEFAULT_SUPABASE_URL = "https://iovvktpuoinmjdgfxgvm.supabase.co"
DEFAULT_SUPABASE_KEY = "sb_publishable_4WefsfMl0sNNo9O2c_lxnA_q2VQ01jn"
DEFAULT_CONFIG = {
    "schema_version": "seed-organism.config.v0.1",
    "current_cycle_share": 0.20,
    "lifetime_share": 0.80,
    "minimum_confidence": 0.65,
    "minimum_accept_fitness": 0.01,
    # Weights retuned 2026-06-16 to match the measured reality (Chapter 16):
    #  - network GATE-ONLY (0.40->0.0): its magnitude is a loopback artifact
    #    (real-path A/B showed our buffers add ~0; the win is just BBR) AND it
    #    is the noisiest channel (CV 0.19). It no longer scores — it only
    #    rejects a real regression via the severe-regression gate below.
    #  - cold-start UP (0.30->0.55): the only rock-solid channel (CV 0.002).
    #  - sustained DOWN (0.20->0.10): single-stream signal is below its noise.
    #  - idle_power UP (0.10->0.35): now reliable after the v1.4.4 sampling fix
    #    (settled-idle CV ~0.01, was a 0.83 sampling artifact).
    "weights": {
        "network": 0.0,
        "coldstart": 0.55,
        "sustained": 0.10,
        "idle_power": 0.35,
    },
    # Parsimony: reward a variant that removes invasive knobs without losing
    # performance (e.g. v0.9 dropped the dead-weight Arc GPU pin at equal
    # performance). A capped bonus per removed knob applies ONLY when
    # performance is non-regressing, so it never lets a worse-but-simpler
    # variant through.
    "parsimony_weight_per_knob": 0.03,
    "parsimony_cap_knobs": 5,
    "parsimony_min_base_fitness": -0.05,  # tolerate within-noise wobble; real regressions still trip the gates
    "caps_pct": {
        "network": 50.0,
        "coldstart": 50.0,
        "sustained": 50.0,
        "idle_power": 50.0,
    },
    # Severe-regression thresholds sit OUTSIDE each channel's measured noise
    # floor (Chapter 16) so the gate rejects real regressions, not noise.
    "severe_regression_pct": {
        "network": -25.0,
        "coldstart": -8.0,
        "sustained": -15.0,
        "idle_power_cost": 25.0,
    },
}


class SeedError(RuntimeError):
    pass


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def read_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError as exc:
        raise SeedError(f"file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SeedError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SeedError(f"expected JSON object in {path}")
    return data


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def append_jsonl(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(data, sort_keys=True) + "\n")


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SeedError(f"invalid JSONL in {path}:{line_no}: {exc}") from exc
            if isinstance(row, dict):
                rows.append(row)
    return rows


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_json(data: dict[str, Any]) -> str:
    encoded = json.dumps(data, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(encoded)


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def state_path(args: argparse.Namespace) -> Path:
    return Path(args.state_dir).expanduser().resolve() if args.state_dir else DEFAULT_STATE_DIR


def ensure_state(state: Path) -> None:
    for name in ["runs", "ledger", "cycles", "exports", "variants"]:
        (state / name).mkdir(parents=True, exist_ok=True)
    config = state / "config.json"
    if not config.exists():
        write_json(config, DEFAULT_CONFIG)
    for name in ["variants.jsonl", "sensor-results.jsonl", "regression-results.jsonl", "ledger.jsonl", "payouts.jsonl"]:
        path = state / "ledger" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch(exist_ok=True)


def load_config(state: Path) -> dict[str, Any]:
    ensure_state(state)
    config = DEFAULT_CONFIG | read_json(state / "config.json")
    config["weights"] = DEFAULT_CONFIG["weights"] | config.get("weights", {})
    config["caps_pct"] = DEFAULT_CONFIG["caps_pct"] | config.get("caps_pct", {})
    config["severe_regression_pct"] = DEFAULT_CONFIG["severe_regression_pct"] | config.get("severe_regression_pct", {})
    return config


def git_commit_ref() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    except Exception:
        return "unknown"


def machine_id_from_metrics(metrics: dict[str, Any]) -> str:
    explicit = metrics.get("machine_id") or metrics.get("hardware_fingerprint_hash")
    if explicit:
        return str(explicit)
    host = {
        "system": platform.system(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "node": platform.node(),
    }
    return "local-" + sha256_json(host)[:16]


def num(obj: dict[str, Any], key: str) -> float | None:
    value = obj.get(key)
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def pct_higher_is_better(baseline: float | None, variant: float | None) -> float | None:
    if baseline is None or variant is None or baseline == 0:
        return None
    return ((variant - baseline) / baseline) * 100.0


def pct_lower_is_better(baseline: float | None, variant: float | None) -> float | None:
    if baseline is None or variant is None or baseline == 0:
        return None
    return ((baseline - variant) / baseline) * 100.0


def pct_cost(baseline: float | None, variant: float | None) -> float | None:
    if baseline is None or variant is None or baseline == 0:
        return None
    return ((variant - baseline) / baseline) * 100.0


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def normalize_pct(value: float | None, cap: float) -> float:
    if value is None:
        return 0.0
    if cap <= 0:
        return 0.0
    return clamp(value / cap, -1.0, 1.0)


def present_core_metrics(metrics: dict[str, Any]) -> list[str]:
    baseline = metrics.get("baseline", {})
    variant = metrics.get("variant", {})
    required = {
        "network_mbps": (baseline, variant),
        "coldstart_ms": (baseline, variant),
        "sustained_tokps": (baseline, variant),
    }
    missing = []
    for key, (left, right) in required.items():
        if num(left, key) is None or num(right, key) is None:
            missing.append(key)
    return missing


def derive_confidence(metrics: dict[str, Any], missing_core: list[str]) -> float:
    if "confidence" in metrics:
        try:
            return clamp(float(metrics["confidence"]), 0.0, 1.0)
        except (TypeError, ValueError):
            pass
    if missing_core:
        return 0.0
    repeats = metrics.get("sample_counts", {})
    if not isinstance(repeats, dict):
        repeats = {}
    core_counts = [
        int(repeats.get("network", 1) or 1),
        int(repeats.get("coldstart", 1) or 1),
        int(repeats.get("sustained", 1) or 1),
    ]
    min_repeat = min(core_counts)
    return clamp(0.50 + (0.10 * (min_repeat - 1)), 0.50, 0.90)


def score_performance(
    *,
    variant: dict[str, Any],
    metrics: dict[str, Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    baseline = metrics.get("baseline", {})
    candidate = metrics.get("variant", {})
    if not isinstance(baseline, dict) or not isinstance(candidate, dict):
        raise SeedError("metrics must contain baseline and variant objects")

    missing_core = present_core_metrics(metrics)
    deltas = {
        "network_pct": pct_higher_is_better(num(baseline, "network_mbps"), num(candidate, "network_mbps")),
        "coldstart_pct": pct_lower_is_better(num(baseline, "coldstart_ms"), num(candidate, "coldstart_ms")),
        "sustained_pct": pct_higher_is_better(num(baseline, "sustained_tokps"), num(candidate, "sustained_tokps")),
        "idle_power_pct": pct_cost(num(baseline, "idle_watts"), num(candidate, "idle_watts")),
    }

    weights = config["weights"]
    caps = config["caps_pct"]
    base_fitness = (
        weights["network"] * normalize_pct(deltas["network_pct"], caps["network"])
        + weights["coldstart"] * normalize_pct(deltas["coldstart_pct"], caps["coldstart"])
        + weights["sustained"] * normalize_pct(deltas["sustained_pct"], caps["sustained"])
        - weights["idle_power"] * normalize_pct(deltas["idle_power_pct"], caps["idle_power"])
    )

    severe = []
    thresholds = config["severe_regression_pct"]
    if deltas["network_pct"] is not None and deltas["network_pct"] < thresholds["network"]:
        severe.append(f"network regression {deltas['network_pct']:.2f}%")
    if deltas["coldstart_pct"] is not None and deltas["coldstart_pct"] < thresholds["coldstart"]:
        severe.append(f"cold-start regression {deltas['coldstart_pct']:.2f}%")
    if deltas["sustained_pct"] is not None and deltas["sustained_pct"] < thresholds["sustained"]:
        severe.append(f"sustained regression {deltas['sustained_pct']:.2f}%")
    if deltas["idle_power_pct"] is not None and deltas["idle_power_pct"] > thresholds["idle_power_cost"]:
        severe.append(f"idle power cost {deltas['idle_power_pct']:.2f}%")

    # Parsimony bonus: a variant that declares it removed N invasive knobs vs
    # its parent earns a small bonus, but ONLY when performance is non-regressing
    # (no severe regressions and base fitness ~neutral-or-better). This lets an
    # equal-performance-but-simpler variant clear the acceptance threshold.
    knobs_removed = int(variant.get("knobs_removed_vs_parent", 0) or 0)
    parsimony_bonus = 0.0
    if (
        knobs_removed > 0
        and not severe
        and base_fitness >= float(config.get("parsimony_min_base_fitness", -0.01))
    ):
        capped = min(knobs_removed, int(config.get("parsimony_cap_knobs", 5)))
        parsimony_bonus = capped * float(config.get("parsimony_weight_per_knob", 0.02))
    fitness = base_fitness + parsimony_bonus

    result = {
        "schema_version": "seed-organism.sensor-result.v0.1",
        "variant_id": variant["variant_id"],
        "sensor_id": "perf.genesis.v1",
        "machine_id": machine_id_from_metrics(metrics),
        "preset_version": variant.get("preset_version") or metrics.get("preset_version") or "unknown",
        "baseline": {
            "network_mbps": num(baseline, "network_mbps"),
            "coldstart_ms": num(baseline, "coldstart_ms"),
            "sustained_tokps": num(baseline, "sustained_tokps"),
            "idle_watts": num(baseline, "idle_watts"),
        },
        "variant": {
            "network_mbps": num(candidate, "network_mbps"),
            "coldstart_ms": num(candidate, "coldstart_ms"),
            "sustained_tokps": num(candidate, "sustained_tokps"),
            "idle_watts": num(candidate, "idle_watts"),
        },
        "delta": deltas,
        "confidence": derive_confidence(metrics, missing_core),
        "fitness_score": round(fitness, 8),
        "base_fitness": round(base_fitness, 8),
        "parsimony_bonus": round(parsimony_bonus, 8),
        "knobs_removed_vs_parent": knobs_removed,
        "missing_core_metrics": missing_core,
        "severe_regressions": severe,
        "timestamp": now_iso(),
    }
    result["sensor_result_hash"] = sha256_json(result)
    return result


def evaluate_regression(variant: dict[str, Any], metrics: dict[str, Any]) -> dict[str, Any]:
    regression = metrics.get("regression", {})
    if not isinstance(regression, dict):
        regression = {}

    failures = list(regression.get("failures", []) or [])
    full_test_passed = bool(regression.get("full_test_passed", True))
    reverted_cleanly = bool(regression.get("reverted_cleanly", True))
    host_safety_passed = bool(regression.get("host_safety_passed", True))

    if not full_test_passed:
        failures.append("full-test gate failed")
    if not reverted_cleanly:
        failures.append("reversibility gate failed")
    if not host_safety_passed:
        failures.append("host-safety gate failed")

    result = {
        "schema_version": "seed-organism.regression-result.v0.1",
        "variant_id": variant["variant_id"],
        "sensor_id": "regression.genesis.v1",
        "machine_id": machine_id_from_metrics(metrics),
        "passed": not failures,
        "failures": failures,
        "reverted_cleanly": reverted_cleanly,
        "full_test_passed": full_test_passed,
        "host_safety_passed": host_safety_passed,
        "timestamp": now_iso(),
    }
    result["regression_result_hash"] = sha256_json(result)
    return result


def verdict(
    variant: dict[str, Any],
    sensor: dict[str, Any],
    regression: dict[str, Any],
    config: dict[str, Any],
) -> tuple[str, str]:
    if sensor["missing_core_metrics"]:
        return "invalid", "missing core metrics: " + ", ".join(sensor["missing_core_metrics"])
    if not regression["passed"]:
        return "rejected_regression", "; ".join(regression["failures"])
    if not variant.get("fitness_eligible", True):
        return "measured_baseline", "genesis baseline characterization; not eligible for contributor fitness"
    if sensor["severe_regressions"]:
        return "rejected_negative_fitness", "; ".join(sensor["severe_regressions"])
    if sensor["confidence"] < float(config["minimum_confidence"]):
        return "inconclusive", f"confidence {sensor['confidence']:.2f} below minimum {config['minimum_confidence']:.2f}"
    if sensor["fitness_score"] <= float(config["minimum_accept_fitness"]):
        return "rejected_negative_fitness", f"fitness {sensor['fitness_score']:.4f} below acceptance threshold"
    return "accepted", "fitness positive and gates passed"


def validate_variant(data: dict[str, Any]) -> dict[str, Any]:
    if "variant_id" not in data:
        raise SeedError("variant is missing variant_id")
    data = dict(data)
    data.setdefault("schema_version", "seed-organism.variant.v0.1")
    data.setdefault("contributor_id", "local-founder")
    data.setdefault("commit_ref", git_commit_ref())
    data.setdefault("declared_scope", "local seed organism evaluation")
    data.setdefault("rollback_method", "preset --undo or benchmark harness cleanup")
    return data


def ledger_entry(
    *,
    cycle_id: int,
    variant: dict[str, Any],
    sensor: dict[str, Any],
    bundle_hash: str,
) -> dict[str, Any]:
    return {
        "schema_version": "seed-organism.ledger-entry.v0.1",
        "ledger_entry_id": "ledger-" + uuid.uuid4().hex,
        "cycle_id": str(cycle_id),
        "variant_id": variant["variant_id"],
        "contributor_id": variant["contributor_id"],
        "commit_ref": variant["commit_ref"],
        "sensor_result_refs": [bundle_hash, sensor["sensor_result_hash"]],
        "fitness_score": sensor["fitness_score"],
        "current_cycle_eligible": True,
        "lifetime_fitness_delta": sensor["fitness_score"],
        "created_at": now_iso(),
    }


def write_bundle(
    *,
    state: Path,
    cycle_id: int,
    variant: dict[str, Any],
    metrics: dict[str, Any],
    sensor: dict[str, Any],
    regression: dict[str, Any],
    decision: str,
    reason: str,
) -> tuple[Path, str]:
    ts = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_id = uuid.uuid4().hex[:8]
    run_dir = state / "runs" / f"cycle-{cycle_id}" / f"{variant['variant_id']}-{ts}-{run_id}"
    write_json(run_dir / "variant.json", variant)
    write_json(run_dir / "metrics.json", metrics)
    write_json(run_dir / "sensor-result.json", sensor)
    write_json(run_dir / "regression-result.json", regression)
    manifest = {
        "schema_version": "seed-organism.bundle-manifest.v0.1",
        "variant_id": variant["variant_id"],
        "run_id": run_id,
        "cycle_id": str(cycle_id),
        "decision": decision,
        "reason": reason,
        "created_at": now_iso(),
        "files": {},
    }
    for path in sorted(run_dir.glob("*.json")):
        manifest["files"][path.name] = sha256_bytes(path.read_bytes())
    manifest["bundle_hash"] = sha256_json(manifest)
    write_json(run_dir / "bundle-manifest.json", manifest)
    return run_dir, manifest["bundle_hash"]


def cmd_init(args: argparse.Namespace) -> None:
    state = state_path(args)
    ensure_state(state)
    print(f"seed organism state initialized: {rel(state)}")
    print(f"config: {rel(state / 'config.json')}")


def cmd_run_variant(args: argparse.Namespace) -> None:
    state = state_path(args)
    config = load_config(state)
    variant = validate_variant(read_json(Path(args.variant)))
    metrics = collect_metrics(args, variant)
    record_evaluation(state, config, variant, metrics, args.cycle_id)


def record_evaluation(
    state: Path,
    config: dict[str, Any],
    variant: dict[str, Any],
    metrics: dict[str, Any],
    cycle_id: int,
) -> tuple[str, str]:
    sensor = score_performance(variant=variant, metrics=metrics, config=config)
    regression = evaluate_regression(variant, metrics)
    decision, reason = verdict(variant, sensor, regression, config)
    run_dir, bundle_hash = write_bundle(
        state=state,
        cycle_id=cycle_id,
        variant=variant,
        metrics=metrics,
        sensor=sensor,
        regression=regression,
        decision=decision,
        reason=reason,
    )

    variant_record = dict(variant)
    variant_record.update({"cycle_id": str(cycle_id), "recorded_at": now_iso()})
    append_jsonl(state / "ledger" / "variants.jsonl", variant_record)
    append_jsonl(state / "ledger" / "sensor-results.jsonl", sensor | {"bundle_hash": bundle_hash, "decision": decision})
    append_jsonl(state / "ledger" / "regression-results.jsonl", regression | {"bundle_hash": bundle_hash, "decision": decision})

    if decision == "accepted":
        entry = ledger_entry(cycle_id=cycle_id, variant=variant, sensor=sensor, bundle_hash=bundle_hash)
        append_jsonl(state / "ledger" / "ledger.jsonl", entry)

    print(f"variant: {variant['variant_id']}")
    print(f"decision: {decision}")
    print(f"reason: {reason}")
    print(f"fitness_score: {sensor['fitness_score']:.6f}")
    print(f"confidence: {sensor['confidence']:.2f}")
    print(f"bundle_hash: {bundle_hash}")
    print(f"bundle: {rel(run_dir)}")
    return decision, bundle_hash


def collect_metrics(args: argparse.Namespace, variant: dict[str, Any]) -> dict[str, Any]:
    if args.metrics:
        return read_json(Path(args.metrics))
    if args.execute:
        return execute_linux_harness(variant)
    raise SeedError("provide --metrics for deterministic scoring, or --execute on a Linux test host")


def execute_linux_harness(variant: dict[str, Any]) -> dict[str, Any]:
    if platform.system() != "Linux":
        raise SeedError("--execute is only supported on Linux test hosts")
    preset = variant.get("preset_path")
    if not preset:
        raise SeedError("variant must include preset_path for --execute")
    preset_path = (ROOT / preset).resolve() if not Path(preset).is_absolute() else Path(preset)
    if not preset_path.exists():
        raise SeedError(f"preset_path not found: {preset_path}")
    harness = ROOT / "cursiveos-full-test-v1.4.sh"
    if not harness.exists():
        raise SeedError(f"full-test harness not found: {harness}")

    logs_dir = ROOT / "logs"
    before_logs = set(logs_dir.glob("cursiveos-full-test-*.log"))
    before_json = set(logs_dir.glob("cursiveos-full-test-*.json"))
    subprocess.run([str(harness), str(preset_path)], cwd=ROOT, check=True)
    after_json = set(logs_dir.glob("cursiveos-full-test-*.json"))
    new_json = sorted(after_json - before_json, key=lambda p: p.stat().st_mtime)
    if new_json:
        return load_full_test_metrics_json(new_json[-1])
    after_logs = set(logs_dir.glob("cursiveos-full-test-*.log"))
    new_logs = sorted(after_logs - before_logs, key=lambda p: p.stat().st_mtime)
    if not new_logs:
        raise SeedError("harness completed but no new result JSON or summary log was found")
    return parse_full_test_log(new_logs[-1])


def try_float(value: Any) -> float | None:
    if value in (None, "", "N/A", "?"):
        return None
    try:
        return float(str(value).replace("+", "").replace("%", "").strip())
    except (TypeError, ValueError):
        return None


def resolve_detail_log(result_path: Path, raw: Any) -> Path | None:
    if not raw:
        return None
    path = Path(str(raw))
    candidates = [path]
    if not path.is_absolute():
        candidates.extend([
            result_path.parent / path,
            ROOT / path,
            ROOT / "logs" / path.name,
        ])
    else:
        candidates.append(ROOT / "logs" / path.name)
    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


def section_key(line: str) -> str | None:
    if "--- BASELINE ---" in line or "PASS 1" in line and "BASELINE" in line:
        return "baseline"
    if "--- TUNED ---" in line or "PASS 2" in line and "TUNED" in line:
        return "tuned"
    return None


def parse_network_detail_log(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {"available": False, "reason": "detail log not found"}
    details: dict[str, Any] = {"available": True, "log": str(path), "baseline": {"runs": []}, "tuned": {"runs": []}}
    current: str | None = None
    run_re = re.compile(r"Run\s+(\d+):\s+([0-9.]+)\s+Mbit/s\s+\|\s+retransmits:\s+([0-9.]+)\s+\|\s+RTT:\s+([0-9.]+)ms")
    avg_re = re.compile(r"Avg:\s+([0-9.]+)\s+Mbit/s\s+\|\s+retransmits:\s+([0-9.]+)\s+\|\s+RTT:\s+([0-9.]+)ms")
    range_re = re.compile(r"Range:\s+([0-9.]+)\s+[–-]\s+([0-9.]+)\s+Mbit/s")
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        return {"available": False, "log": str(path), "reason": str(exc)}
    for line in lines:
        if key := section_key(line):
            current = key
            continue
        if current not in ("baseline", "tuned"):
            continue
        target = details[current]
        stripped = line.strip()
        if stripped.startswith("TCP CC:"):
            target["tcp_congestion_control"] = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("rmem_max:"):
            match = re.search(r"([0-9]+)", stripped)
            if match:
                target["rmem_max_bytes"] = int(match.group(1))
        elif match := run_re.search(stripped):
            target["runs"].append({
                "run": int(match.group(1)),
                "mbps": try_float(match.group(2)),
                "retransmits": try_float(match.group(3)),
                "rtt_ms": try_float(match.group(4)),
            })
        elif match := avg_re.search(stripped):
            target["avg_mbps"] = try_float(match.group(1))
            target["avg_retransmits"] = try_float(match.group(2))
            target["avg_rtt_ms"] = try_float(match.group(3))
        elif match := range_re.search(stripped):
            target["range_mbps"] = [try_float(match.group(1)), try_float(match.group(2))]
    return details


def parse_coldstart_detail_log(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {"available": False, "reason": "detail log not found"}
    details: dict[str, Any] = {"available": True, "log": str(path), "baseline": {"calls": []}, "tuned": {"calls": []}}
    current: str | None = None
    call_re = re.compile(
        r"Call\s+(\d+):\s+GPU_before=([^|]+)\|\s+load=([0-9.]+)ms\s+\|\s+TTFT=([0-9.]+)ms\s+\|\s+cold_total=([0-9.]+)ms\s+\|\s+([0-9.]+)\s+tok/s\s+\|\s+tokens:([0-9.]+)"
    )
    avg_re = re.compile(r"Avg:\s+load=([0-9.]+)ms\s+\|\s+TTFT=([0-9.]+)ms\s+\|\s+cold_total=([0-9.]+)ms\s+\|\s+([0-9.]+)\s+tok/s")
    range_re = re.compile(r"Load range:\s+([0-9.]+)ms\s+[–-]\s+([0-9.]+)ms\s+\|\s+Cold range:\s+([0-9.]+)ms\s+[–-]\s+([0-9.]+)ms")
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        return {"available": False, "log": str(path), "reason": str(exc)}
    for line in lines:
        if key := section_key(line):
            current = key
            continue
        if current not in ("baseline", "tuned"):
            continue
        target = details[current]
        stripped = line.strip()
        if stripped.startswith("CPU gov:"):
            target["cpu_governor"] = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("GPU freq:"):
            target["gpu_freq_before_pass_mhz"] = try_float(re.sub(r"[^0-9.]", "", stripped.split(":", 1)[1]))
        elif match := call_re.search(stripped):
            target["calls"].append({
                "call": int(match.group(1)),
                "gpu_before": match.group(2).strip(),
                "load_ms": try_float(match.group(3)),
                "ttft_ms": try_float(match.group(4)),
                "cold_total_ms": try_float(match.group(5)),
                "tokps": try_float(match.group(6)),
                "tokens": try_float(match.group(7)),
            })
        elif match := avg_re.search(stripped):
            target["avg_load_ms"] = try_float(match.group(1))
            target["avg_ttft_ms"] = try_float(match.group(2))
            target["avg_cold_total_ms"] = try_float(match.group(3))
            target["avg_tokps"] = try_float(match.group(4))
        elif match := range_re.search(stripped):
            target["load_range_ms"] = [try_float(match.group(1)), try_float(match.group(2))]
            target["cold_range_ms"] = [try_float(match.group(3)), try_float(match.group(4))]
    return details


def parse_sustained_detail_log(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {"available": False, "reason": "detail log not found"}
    details: dict[str, Any] = {"available": True, "log": str(path), "baseline": {"passes": []}, "tuned": {"passes": []}}
    current: str | None = None
    pass_re = re.compile(r"Pass\s+(\d+):\s+([0-9.]+)\s+tok/s\s+\|\s+TTFT:\s+([0-9.]+)s\s+\|\s+tokens:\s+([0-9.]+)")
    avg_re = re.compile(r"Avg:\s+([0-9.]+)\s+tok/s\s+\|\s+TTFT avg:\s+([0-9.]+)s\s+\|\s+min:\s+([0-9.]+)\s+\|\s+max:\s+([0-9.]+)")
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        return {"available": False, "log": str(path), "reason": str(exc)}
    for line in lines:
        if key := section_key(line):
            current = key
            continue
        if current not in ("baseline", "tuned"):
            continue
        target = details[current]
        stripped = line.strip()
        if stripped.startswith("Governor:"):
            target["cpu_governor"] = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("Processor:"):
            target["processor"] = stripped.split(":", 1)[1].strip()
        elif match := pass_re.search(stripped):
            target["passes"].append({
                "pass": int(match.group(1)),
                "tokps": try_float(match.group(2)),
                "ttft_s": try_float(match.group(3)),
                "tokens": try_float(match.group(4)),
            })
        elif match := avg_re.search(stripped):
            target["avg_tokps"] = try_float(match.group(1))
            target["avg_ttft_s"] = try_float(match.group(2))
            target["range_tokps"] = [try_float(match.group(3)), try_float(match.group(4))]
    return details


def extract_structured_telemetry(data: dict[str, Any], result_path: Path) -> dict[str, Any]:
    telemetry = data.get("telemetry", {})
    if not isinstance(telemetry, dict):
        telemetry = {}
    logs = telemetry.get("detail_logs", {})
    if not isinstance(logs, dict):
        logs = {}
    return {
        "schema_version": "cursiveos.structured-telemetry.v0.2",
        "network": parse_network_detail_log(resolve_detail_log(result_path, logs.get("network"))),
        "coldstart": parse_coldstart_detail_log(resolve_detail_log(result_path, logs.get("coldstart"))),
        "sustained": parse_sustained_detail_log(resolve_detail_log(result_path, logs.get("sustained"))),
        "idle_power": telemetry.get("idle_power", {}),
    }


def measurement_quality_flags(data: dict[str, Any], structured: dict[str, Any]) -> dict[str, Any]:
    flags: list[str] = []
    sample_counts = data.get("sample_counts", {})
    if not isinstance(sample_counts, dict):
        sample_counts = {}
    idle_samples = int(sample_counts.get("idle_power") or 0)
    if idle_samples < 3:
        flags.append("idle_power_has_fewer_than_3_samples")
    for name in ("network", "coldstart", "sustained"):
        details = structured.get(name, {})
        if not isinstance(details, dict) or not details.get("available"):
            flags.append(f"{name}_detail_log_missing")
    sustained = structured.get("sustained", {})
    if isinstance(sustained, dict):
        tuned_proc = str(sustained.get("tuned", {}).get("processor", "")).lower()
        if "cpu" in tuned_proc and "gpu" not in tuned_proc:
            flags.append("sustained_inference_cpu_bound")
    regression = data.get("regression", {})
    if isinstance(regression, dict) and not regression.get("full_test_passed", True):
        flags.append("full_test_regression_flag_false")
    return {
        "schema_version": "cursiveos.measurement-quality.v0.2",
        "flags": flags,
        "decision_grade": not flags,
        "note": "Detail pass counts are preserved for audit but do not by themselves create independent selection confidence.",
    }


def load_full_test_metrics_json(path: Path) -> dict[str, Any]:
    data = read_json(path)
    baseline = data.get("baseline", {})
    candidate = data.get("variant", {})
    regression = data.get("regression", {})
    if not isinstance(baseline, dict) or not isinstance(candidate, dict):
        raise SeedError(f"full-test result JSON missing baseline/variant objects: {path}")
    if not isinstance(regression, dict):
        regression = {}
    structured = extract_structured_telemetry(data, path)
    return {
        "schema_version": "seed-organism.metrics.from-full-test-json.v0.1",
        "source_result_json": str(path),
        "source_log": data.get("summary_log"),
        "source_provenance": data.get("source_provenance", "native_full_test_json"),
        "source_provenance_notes": data.get("source_provenance_notes"),
        "benchmark_context": data.get("benchmark_context", {}),
        "telemetry": data.get("telemetry", {}),
        "structured_telemetry": structured,
        "measurement_quality": measurement_quality_flags(data, structured),
        "machine_id": data.get("machine_id") or data.get("hardware_fingerprint_hash"),
        "hardware_fingerprint_hash": data.get("hardware_fingerprint_hash"),
        "preset_version": data.get("preset_version", "v0.8"),
        "baseline": {
            "network_mbps": num(baseline, "network_mbps"),
            "coldstart_ms": num(baseline, "coldstart_ms"),
            "sustained_tokps": num(baseline, "sustained_tokps"),
            "idle_watts": num(baseline, "idle_watts"),
        },
        "variant": {
            "network_mbps": num(candidate, "network_mbps"),
            "coldstart_ms": num(candidate, "coldstart_ms"),
            "sustained_tokps": num(candidate, "sustained_tokps"),
            "idle_watts": num(candidate, "idle_watts"),
        },
        "sample_counts": data.get("sample_counts", {"network": 1, "coldstart": 1, "sustained": 1}),
        "regression": {
            "full_test_passed": bool(regression.get("full_test_passed", True)),
            "reverted_cleanly": bool(regression.get("reverted_cleanly", True)),
            "host_safety_passed": bool(regression.get("host_safety_passed", True)),
            "failures": list(regression.get("failures", []) or []),
        },
    }


def parse_full_test_log(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    rows = {}
    fingerprint = None
    stability_passed = True
    stability_failures = []
    for line in text.splitlines():
        parts = line.split()
        if line.startswith("Fingerprint:"):
            fingerprint = line.split(":", 1)[1].strip()
        elif line.startswith("Stability"):
            stability_passed = " true " in f" {line.lower()} "
            if not stability_passed:
                stability_failures.append("stability flag false in full-test summary")
        if line.startswith("Network throughput") and len(parts) >= 7:
            rows["network"] = (parts[2], parts[4])
        elif line.startswith("Cold-start latency") and len(parts) >= 5:
            rows["coldstart"] = (parts[2].replace("ms", ""), parts[3].replace("ms", ""))
        elif line.startswith("Sustained inference") and len(parts) >= 4:
            rows["sustained"] = (parts[2], parts[3])
        elif line.startswith("Idle power draw") and len(parts) >= 5:
            rows["power"] = (parts[3].replace("W", ""), parts[4].replace("W", ""))
    try_float = lambda v: None if v in (None, "N/A") else float(str(v).replace("+", "").replace("%", ""))
    return {
        "schema_version": "seed-organism.metrics.from-full-test.v0.1",
        "source_log": str(path),
        "machine_id": fingerprint or "linux-" + sha256_bytes(text.encode("utf-8"))[:16],
        "preset_version": "v0.8",
        "baseline": {
            "network_mbps": try_float(rows.get("network", [None, None])[0]),
            "coldstart_ms": try_float(rows.get("coldstart", [None, None])[0]),
            "sustained_tokps": try_float(rows.get("sustained", [None, None])[0]),
            "idle_watts": try_float(rows.get("power", [None, None])[0]),
        },
        "variant": {
            "network_mbps": try_float(rows.get("network", [None, None])[1]),
            "coldstart_ms": try_float(rows.get("coldstart", [None, None])[1]),
            "sustained_tokps": try_float(rows.get("sustained", [None, None])[1]),
            "idle_watts": try_float(rows.get("power", [None, None])[1]),
        },
        "sample_counts": {"network": 1, "coldstart": 1, "sustained": 1},
        "regression": {
            "full_test_passed": stability_passed,
            "reverted_cleanly": "Presets reverted" in text,
            "host_safety_passed": True,
            "failures": stability_failures,
        },
    }


def comparison_metrics(
    *,
    parent_variant: dict[str, Any],
    candidate_variant: dict[str, Any],
    parent_metrics: dict[str, Any],
    candidate_metrics: dict[str, Any],
    confirmations: int = 1,
) -> dict[str, Any]:
    parent_machine = machine_id_from_metrics(parent_metrics)
    candidate_machine = machine_id_from_metrics(candidate_metrics)
    if parent_machine != candidate_machine:
        raise SeedError(
            "parent and candidate results are from different machines: "
            f"{parent_machine} != {candidate_machine}"
        )
    parent_tuned = parent_metrics.get("variant", {})
    candidate_tuned = candidate_metrics.get("variant", {})
    if not isinstance(parent_tuned, dict) or not isinstance(candidate_tuned, dict):
        raise SeedError("comparison inputs must include tuned variant results")

    parent_regression = parent_metrics.get("regression", {})
    candidate_regression = candidate_metrics.get("regression", {})
    failures = list(parent_regression.get("failures", []) or []) + list(candidate_regression.get("failures", []) or [])
    if not parent_regression.get("full_test_passed", True):
        failures.append("parent full-test gate failed")
    if not candidate_regression.get("full_test_passed", True):
        failures.append("candidate full-test gate failed")

    return {
        "schema_version": "seed-organism.metrics.parent-candidate-screen.v0.1",
        "source_provenance": "paired_full_test_screen",
        "comparison_role": "screening_only_single_session",
        "comparison": {
            "parent_variant_id": parent_variant["variant_id"],
            "candidate_variant_id": candidate_variant["variant_id"],
            "parent_preset_version": parent_variant.get("preset_version"),
            "candidate_preset_version": candidate_variant.get("preset_version"),
            "method": "compare tuned absolute outcomes from consecutive full-test runs on one host",
            "acceptance_limit": "one screening session is not sufficient to accept a candidate",
        },
        "machine_id": candidate_machine,
        "hardware_fingerprint_hash": candidate_metrics.get("hardware_fingerprint_hash"),
        "preset_version": candidate_variant.get("preset_version"),
        "baseline": {
            "network_mbps": num(parent_tuned, "network_mbps"),
            "coldstart_ms": num(parent_tuned, "coldstart_ms"),
            "sustained_tokps": num(parent_tuned, "sustained_tokps"),
            "idle_watts": num(parent_tuned, "idle_watts"),
        },
        "variant": {
            "network_mbps": num(candidate_tuned, "network_mbps"),
            "coldstart_ms": num(candidate_tuned, "coldstart_ms"),
            "sustained_tokps": num(candidate_tuned, "sustained_tokps"),
            "idle_watts": num(candidate_tuned, "idle_watts"),
        },
        # Confidence rises with the number of INDEPENDENT confirming sessions
        # (repeated + counterbalanced + multi-machine): 1->0.50, 2->0.75,
        # 3->0.875. A single screen stays diagnostic-only (0.50 < accept gate).
        # Phase 0: `confirmations` is founder-attested and recorded for audit;
        # pre-external-rollout this must be auto-counted from independent
        # confirming bundles in CursiveRoot rather than asserted.
        "confidence": round(min(0.95, 1.0 - 0.5 ** max(1, int(confirmations))), 4),
        "confirmation_count": max(1, int(confirmations)),
        "sample_counts": {"network": 1, "coldstart": 1, "sustained": 1, "idle_power": 1},
        "source_runs": {
            "parent": parent_metrics,
            "candidate": candidate_metrics,
        },
        "regression": {
            "full_test_passed": bool(parent_regression.get("full_test_passed", True))
            and bool(candidate_regression.get("full_test_passed", True)),
            "reverted_cleanly": bool(parent_regression.get("reverted_cleanly", True))
            and bool(candidate_regression.get("reverted_cleanly", True)),
            "host_safety_passed": bool(parent_regression.get("host_safety_passed", True))
            and bool(candidate_regression.get("host_safety_passed", True)),
            "failures": failures,
        },
    }


def cmd_screen_variant(args: argparse.Namespace) -> None:
    state = state_path(args)
    config = load_config(state)
    parent_variant = validate_variant(read_json(Path(args.parent_variant)))
    candidate_variant = validate_variant(read_json(Path(args.candidate_variant)))
    if args.execute:
        if getattr(args, "reverse_order", False):
            # Counterbalanced session: candidate measured first, parent second.
            # Metric labeling is unaffected; only execution order changes.
            candidate_metrics = execute_linux_harness(candidate_variant)
            parent_metrics = execute_linux_harness(parent_variant)
        else:
            parent_metrics = execute_linux_harness(parent_variant)
            candidate_metrics = execute_linux_harness(candidate_variant)
    else:
        if not args.parent_result_json or not args.candidate_result_json:
            raise SeedError("provide both result JSON files, or use --execute on a Linux test host")
        parent_metrics = load_full_test_metrics_json(Path(args.parent_result_json))
        candidate_metrics = load_full_test_metrics_json(Path(args.candidate_result_json))
    metrics = comparison_metrics(
        parent_variant=parent_variant,
        candidate_variant=candidate_variant,
        parent_metrics=parent_metrics,
        candidate_metrics=candidate_metrics,
        confirmations=int(getattr(args, "confirmations", 1) or 1),
    )
    record_evaluation(state, config, candidate_variant, metrics, args.cycle_id)


def cmd_close_cycle(args: argparse.Namespace) -> None:
    state = state_path(args)
    config = load_config(state)
    ledger = read_jsonl(state / "ledger" / "ledger.jsonl")
    cycle_id = str(args.cycle_id)
    revenue = int(args.revenue_sats)
    contributors: dict[str, dict[str, float]] = {}

    for entry in ledger:
        cid = str(entry["contributor_id"])
        contributors.setdefault(cid, {"cycle_fitness": 0.0, "lifetime_fitness": 0.0})
        contributors[cid]["lifetime_fitness"] += float(entry.get("lifetime_fitness_delta", 0.0))
        if str(entry.get("cycle_id")) == cycle_id and entry.get("current_cycle_eligible", True):
            contributors[cid]["cycle_fitness"] += float(entry.get("fitness_score", 0.0))

    current_share = float(config["current_cycle_share"])
    lifetime_share = float(config["lifetime_share"])
    current_pot = int(round(revenue * current_share))
    lifetime_pot = revenue - current_pot
    cycle_total = sum(v["cycle_fitness"] for v in contributors.values())
    lifetime_total = sum(v["lifetime_fitness"] for v in contributors.values())

    rows = []
    for cid, values in sorted(contributors.items()):
        cycle_fit = values["cycle_fitness"]
        lifetime_fit = values["lifetime_fitness"]
        current_payout = int(round(current_pot * (cycle_fit / cycle_total))) if cycle_total > 0 else 0
        lifetime_payout = int(round(lifetime_pot * (lifetime_fit / lifetime_total))) if lifetime_total > 0 else 0
        rows.append({
            "contributor_id": cid,
            "cycle_fitness": round(cycle_fit, 8),
            "lifetime_fitness": round(lifetime_fit, 8),
            "current_cycle_payout_sats": current_payout,
            "lifetime_payout_sats": lifetime_payout,
            "total_payout_sats": current_payout + lifetime_payout,
        })

    report = {
        "schema_version": "seed-organism.payout-report.v0.1",
        "cycle_id": cycle_id,
        "simulated_revenue_sats": revenue,
        "current_cycle_share": current_share,
        "lifetime_share": lifetime_share,
        "contributors": rows,
        "created_at": now_iso(),
    }
    report["payout_report_hash"] = sha256_json(report)
    out = state / "cycles" / f"cycle-{cycle_id}-payout.json"
    write_json(out, report)
    append_jsonl(state / "ledger" / "payouts.jsonl", report)
    print(f"cycle: {cycle_id}")
    print(f"contributors: {len(rows)}")
    print(f"report_hash: {report['payout_report_hash']}")
    print(f"report: {rel(out)}")


def cmd_status(args: argparse.Namespace) -> None:
    state = state_path(args)
    ensure_state(state)
    variants = read_jsonl(state / "ledger" / "variants.jsonl")
    sensors = read_jsonl(state / "ledger" / "sensor-results.jsonl")
    ledger = read_jsonl(state / "ledger" / "ledger.jsonl")
    payouts = read_jsonl(state / "ledger" / "payouts.jsonl")
    accepted = [r for r in sensors if r.get("decision") == "accepted"]
    print(f"state: {rel(state)}")
    print(f"variants_evaluated: {len(variants)}")
    print(f"accepted_variants: {len(accepted)}")
    print(f"ledger_entries: {len(ledger)}")
    print(f"payout_reports: {len(payouts)}")
    if sensors:
        last = sensors[-1]
        print(f"last_decision: {last.get('variant_id')} -> {last.get('decision')} fitness={last.get('fitness_score')}")


def cmd_export(args: argparse.Namespace) -> None:
    state = state_path(args)
    ensure_state(state)
    out = state / "exports" / f"seed-export-{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    shutil.copytree(state / "ledger", out / "ledger")
    if (state / "cycles").exists():
        shutil.copytree(state / "cycles", out / "cycles")
    manifest = {
        "schema_version": "seed-organism.export-manifest.v0.1",
        "created_at": now_iso(),
        "source_state": str(state),
        "files": {},
    }
    for path in sorted(out.rglob("*")):
        if path.is_file():
            manifest["files"][str(path.relative_to(out))] = sha256_bytes(path.read_bytes())
    manifest["export_hash"] = sha256_json(manifest)
    write_json(out / "export-manifest.json", manifest)
    print(f"export_hash: {manifest['export_hash']}")
    print(f"export: {rel(out)}")


def public_supabase_url() -> str:
    return os.environ.get("CURSIVEOS_SUPABASE_URL") or os.environ.get("SUPABASE_URL") or DEFAULT_SUPABASE_URL


def public_supabase_key() -> str:
    return os.environ.get("CURSIVEOS_SUPABASE_KEY") or os.environ.get("SUPABASE_KEY") or DEFAULT_SUPABASE_KEY


def postgrest_upsert(table: str, conflict_key: str, payload: dict[str, Any]) -> None:
    url = f"{public_supabase_url().rstrip('/')}/rest/v1/{table}?on_conflict={urllib.parse.quote(conflict_key)}"
    body = json.dumps(payload, sort_keys=True).encode("utf-8")
    key = public_supabase_key()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            if res.status not in (200, 201, 204):
                raise SeedError(f"Supabase upload returned HTTP {res.status}")
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise SeedError(f"Supabase upload failed for {table}: HTTP {exc.code} {details}") from exc
    except urllib.error.URLError as exc:
        raise SeedError(f"Supabase upload failed for {table}: {exc.reason}") from exc


def optional_postgrest_upsert(table: str, conflict_key: str, payload: dict[str, Any]) -> bool:
    try:
        postgrest_upsert(table, conflict_key, payload)
        return True
    except SeedError:
        return False


def postgrest_insert(table: str, payload: dict[str, Any]) -> None:
    url = f"{public_supabase_url().rstrip('/')}/rest/v1/{table}"
    body = json.dumps(payload, sort_keys=True).encode("utf-8")
    key = public_supabase_key()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            if res.status not in (200, 201, 204):
                raise SeedError(f"Supabase insert returned HTTP {res.status}")
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise SeedError(f"Supabase insert failed for {table}: HTTP {exc.code} {details}") from exc
    except urllib.error.URLError as exc:
        raise SeedError(f"Supabase insert failed for {table}: {exc.reason}") from exc


def load_bundle_dir(run_dir: Path) -> dict[str, Any]:
    manifest = read_json(run_dir / "bundle-manifest.json")
    variant = read_json(run_dir / "variant.json")
    metrics = read_json(run_dir / "metrics.json")
    sensor = read_json(run_dir / "sensor-result.json")
    regression = read_json(run_dir / "regression-result.json")
    return {
        "manifest": manifest,
        "variant": variant,
        "metrics": metrics,
        "sensor_result": sensor,
        "regression_result": regression,
    }


def seed_bundle_payload(bundle: dict[str, Any]) -> dict[str, Any]:
    manifest = bundle["manifest"]
    variant = bundle["variant"]
    sensor = bundle["sensor_result"]
    regression = bundle["regression_result"]
    return {
        "bundle_hash": manifest["bundle_hash"],
        "variant_id": manifest["variant_id"],
        "cycle_id": manifest.get("cycle_id"),
        "decision": manifest["decision"],
        "reason": manifest.get("reason"),
        "machine_id": sensor.get("machine_id") or regression.get("machine_id"),
        "contributor_id": variant.get("contributor_id"),
        "commit_ref": variant.get("commit_ref"),
        "fitness_score": sensor.get("fitness_score"),
        "confidence": sensor.get("confidence"),
        "sensor_result_hash": sensor.get("sensor_result_hash"),
        "regression_result_hash": regression.get("regression_result_hash"),
        "result_bundle": bundle,
        "source": "seed_organism.py",
    }


def payout_payload(report: dict[str, Any]) -> dict[str, Any]:
    return {
        "payout_report_hash": report["payout_report_hash"],
        "cycle_id": str(report["cycle_id"]),
        "simulated_revenue_sats": report.get("simulated_revenue_sats"),
        "contributor_count": len(report.get("contributors", []) or []),
        "report": report,
        "source": "seed_organism.py",
    }


def full_test_detail_payload(
    result: dict[str, Any],
    *,
    source_hash: str,
    result_path: Path | None = None,
) -> dict[str, Any]:
    structured = result.get("structured_telemetry")
    if not isinstance(structured, dict):
        structured = extract_structured_telemetry(result, result_path) if result_path else {}
    quality = result.get("measurement_quality")
    if not isinstance(quality, dict):
        quality = measurement_quality_flags(result, structured) if structured else {}
    baseline = result.get("baseline", {})
    candidate = result.get("variant", {})
    delta = result.get("delta", {})
    if not isinstance(baseline, dict):
        baseline = {}
    if not isinstance(candidate, dict):
        candidate = {}
    if not isinstance(delta, dict):
        delta = {}
    run_date = str(result.get("created_at", ""))[:10] or dt.date.today().isoformat()
    return {
        "source_hash": source_hash,
        "machine_id": result.get("machine_id") or result.get("hardware_fingerprint_hash"),
        "run_date": run_date,
        "preset_version": result.get("preset_version", "v0.8"),
        "wrapper_version": result.get("wrapper_version", "v1.4"),
        "structured_telemetry": structured,
        "measurement_quality": quality,
        "result_summary": {
            "baseline": baseline,
            "variant": candidate,
            "delta": delta,
            "benchmark_context": result.get("benchmark_context", {}),
            "regression": result.get("regression", {}),
        },
        "source": "seed_organism.py",
    }


def cmd_upload(args: argparse.Namespace) -> None:
    state = state_path(args)
    ensure_state(state)
    uploaded_bundles = 0
    uploaded_payouts = 0

    for manifest_path in sorted((state / "runs").glob("cycle-*/*/bundle-manifest.json")):
        bundle = load_bundle_dir(manifest_path.parent)
        postgrest_upsert("seed_bundles", "bundle_hash", seed_bundle_payload(bundle))
        uploaded_bundles += 1

    for report_path in sorted((state / "cycles").glob("cycle-*-payout.json")):
        report = read_json(report_path)
        postgrest_upsert("seed_payout_reports", "payout_report_hash", payout_payload(report))
        uploaded_payouts += 1

    print(f"uploaded_seed_bundles: {uploaded_bundles}")
    print(f"uploaded_payout_reports: {uploaded_payouts}")
    print("cursiveroot_upload: ok")


def postgrest_get(endpoint: str) -> list[dict[str, Any]]:
    url = f"{public_supabase_url().rstrip('/')}/rest/v1/{endpoint}"
    key = public_supabase_key()
    req = urllib.request.Request(
        url,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            data = json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise SeedError(f"CursiveRoot read failed: HTTP {exc.code} {details}") from exc
    except urllib.error.URLError as exc:
        raise SeedError(f"CursiveRoot read failed: {exc.reason}") from exc
    if not isinstance(data, list):
        raise SeedError("CursiveRoot returned an unexpected response")
    return [row for row in data if isinstance(row, dict)]


def upload_full_test_result(result: dict[str, Any], result_path: Path | None = None) -> str:
    machine_id = str(result.get("machine_id") or result.get("hardware_fingerprint_hash") or "").strip()
    if not machine_id:
        raise SeedError("full-test result is missing machine_id")
    hardware = result.get("hardware", {})
    if not isinstance(hardware, dict):
        hardware = {}
    machine_filter = urllib.parse.quote(machine_id, safe="")
    if not postgrest_get(f"machines?machine_id=eq.{machine_filter}&select=machine_id&limit=1"):
        postgrest_insert("machines", {
            "machine_id": machine_id,
            "label": "Auto-detected seed host",
            "cpu": hardware.get("cpu") or "unknown",
            "gpu": hardware.get("gpu") or "unknown",
            "os": hardware.get("distro"),
            "kernel": hardware.get("kernel"),
        })

    baseline = result.get("baseline", {})
    candidate = result.get("variant", {})
    delta = result.get("delta", {})
    regression = result.get("regression", {})
    if not all(isinstance(x, dict) for x in [baseline, candidate, delta, regression]):
        raise SeedError("full-test result has invalid metrics structure")
    run_date = str(result.get("created_at", ""))[:10] or dt.date.today().isoformat()
    source_hash = sha256_json(result)
    optional_postgrest_upsert(
        "run_detail_bundles",
        "source_hash",
        full_test_detail_payload(result, source_hash=source_hash, result_path=result_path),
    )
    net_baseline = num(baseline, "network_mbps")
    net_variant = num(candidate, "network_mbps")
    preset_version = str(result.get("preset_version", "v0.8"))
    duplicate_query = (
        f"runs?machine_id=eq.{machine_filter}&run_date=eq.{urllib.parse.quote(run_date)}"
        f"&preset_version=eq.{urllib.parse.quote(preset_version)}"
        f"&network_baseline_mbit=eq.{net_baseline}&network_tuned_mbit=eq.{net_variant}"
        "&select=id&limit=1"
    )
    if postgrest_get(duplicate_query):
        return "already_present"
    postgrest_insert("runs", {
        "machine_id": machine_id,
        "run_date": run_date,
        "preset_version": preset_version,
        "wrapper_version": result.get("wrapper_version", "v1.4"),
        "network_baseline_mbit": net_baseline,
        "network_tuned_mbit": net_variant,
        "network_delta_pct": num(delta, "network_pct"),
        "coldstart_baseline_ms": num(baseline, "coldstart_ms"),
        "coldstart_tuned_ms": num(candidate, "coldstart_ms"),
        "coldstart_delta_pct": num(delta, "coldstart_pct"),
        "sustained_baseline_toks": num(baseline, "sustained_tokps"),
        "sustained_tuned_toks": num(candidate, "sustained_tokps"),
        "sustained_delta_pct": num(delta, "sustained_pct"),
        "power_idle_baseline_w": num(baseline, "idle_watts"),
        "power_idle_tuned_w": num(candidate, "idle_watts"),
        "power_delta_w": num(delta, "idle_power_w"),
        "notes": f"seed-source:{source_hash} stability:{str(regression.get('full_test_passed', True)).lower()}",
    })
    return "uploaded"


def cmd_remote_status(args: argparse.Namespace) -> None:
    limit = max(1, min(int(args.limit), 50))
    bundle_cols = "bundle_hash,variant_id,decision,machine_id,fitness_score,confidence,created_at"
    payout_cols = "payout_report_hash,cycle_id,simulated_revenue_sats,contributor_count,created_at"
    bundles = postgrest_get(
        f"seed_bundles?select={urllib.parse.quote(bundle_cols, safe=',')}&order=created_at.desc&limit={limit}"
    )
    payouts = postgrest_get(
        f"seed_payout_reports?select={urllib.parse.quote(payout_cols, safe=',')}&order=created_at.desc&limit={limit}"
    )
    print("CursiveRoot seed organism status")
    print(f"latest_seed_bundles: {len(bundles)}")
    for row in bundles:
        print(
            f"  {row.get('created_at')}  {row.get('decision')}  "
            f"variant={row.get('variant_id')} machine={row.get('machine_id')} "
            f"fitness={row.get('fitness_score')}"
        )
    print(f"latest_payout_reports: {len(payouts)}")
    for row in payouts:
        print(
            f"  {row.get('created_at')}  cycle={row.get('cycle_id')} "
            f"revenue_sats={row.get('simulated_revenue_sats')} contributors={row.get('contributor_count')}"
        )


def cmd_recover_result(args: argparse.Namespace) -> None:
    state = state_path(args)
    config = load_config(state)
    result_path = Path(args.result_json)
    full_result = read_json(result_path)
    normal_status = upload_full_test_result(full_result, result_path=result_path)
    variant = validate_variant(read_json(Path(args.variant)))
    metrics = load_full_test_metrics_json(result_path)
    record_evaluation(state, config, variant, metrics, args.cycle_id)
    cmd_upload(args)
    print(f"cursiveroot_benchmark_result: {normal_status}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Run the CursiveOS Phase 0 seed organism loop")
    p.add_argument("--state-dir", default=None, help="local seed state directory (default: .cursiveos/seed)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init", help="initialize local seed organism state")

    run = sub.add_parser("run-variant", help="score a variant and write an audit bundle")
    run.add_argument("--variant", required=True, help="variant metadata JSON")
    run.add_argument("--metrics", help="deterministic metrics JSON")
    run.add_argument("--execute", action="store_true", help="run the Linux full-test harness for the variant preset")
    run.add_argument("--cycle-id", type=int, default=1)

    screen = sub.add_parser("screen-variant", help="screen a candidate against the current parent preset")
    screen.add_argument("--parent-variant", default="references/seed-organism/variant.genesis-linux.json")
    screen.add_argument("--candidate-variant", required=True, help="candidate variant metadata JSON")
    screen.add_argument("--parent-result-json", help="existing full-test JSON for the parent preset")
    screen.add_argument("--candidate-result-json", help="existing full-test JSON for the candidate preset")
    screen.add_argument("--execute", action="store_true", help="run parent then candidate full tests on a Linux host")
    screen.add_argument("--reverse-order", action="store_true", help="with --execute, measure candidate first then parent (counterbalancing)")
    screen.add_argument("--confirmations", type=int, default=1, help="count of independent confirming sessions (repeated + counterbalanced + multi-machine); raises confidence 1->0.50, 2->0.75, 3->0.875. Phase 0: founder-attested, recorded for audit.")
    screen.add_argument("--cycle-id", type=int, default=1)

    close = sub.add_parser("close-cycle", help="compute simulated payout report for accepted contributor fitness")
    close.add_argument("--cycle-id", type=int, required=True)
    close.add_argument("--revenue-sats", type=int, required=True)

    sub.add_parser("status", help="show local organism state")
    sub.add_parser("export", help="export ledger and cycle reports for CursiveRoot/Hub ingestion")
    sub.add_parser("upload", help="upload local seed bundles and payout reports to CursiveRoot")
    remote = sub.add_parser("remote-status", help="show latest seed uploads from CursiveRoot")
    remote.add_argument("--limit", type=int, default=10)
    recover = sub.add_parser("recover-result", help="ingest an existing full-test JSON after an interrupted upload")
    recover.add_argument("--result-json", required=True, help="saved full-test JSON from the Linux host")
    recover.add_argument("--variant", default="references/seed-organism/variant.genesis-linux.json")
    recover.add_argument("--cycle-id", type=int, default=1)
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        {
            "init": cmd_init,
            "run-variant": cmd_run_variant,
            "screen-variant": cmd_screen_variant,
            "close-cycle": cmd_close_cycle,
            "status": cmd_status,
            "export": cmd_export,
            "upload": cmd_upload,
            "remote-status": cmd_remote_status,
            "recover-result": cmd_recover_result,
        }[args.cmd](args)
    except SeedError as exc:
        print(f"seed-organism error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
