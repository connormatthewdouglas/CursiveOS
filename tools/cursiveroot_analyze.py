#!/usr/bin/env python3
"""
Decision-grade CursiveRoot analyzer.

This tool reads the live CursiveRoot benchmark tables and prints an operator
report oriented around selection quality, not just impressive deltas.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import statistics
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from typing import Any

import seed_organism


DEFAULT_LIMIT = 200
HW_RE = re.compile(r"\bhw:([A-Za-z0-9_.:-]+)")


class AnalyzeError(RuntimeError):
    pass


def num(value: Any) -> float | None:
    if value is None:
        return None
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(n) or math.isinf(n):
        return None
    return n


def median(values: list[float]) -> float | None:
    clean = [v for v in values if num(v) is not None]
    if not clean:
        return None
    return float(statistics.median(clean))


def mean(values: list[float]) -> float | None:
    clean = [v for v in values if num(v) is not None]
    if not clean:
        return None
    return float(statistics.mean(clean))


def stdev(values: list[float]) -> float | None:
    clean = [v for v in values if num(v) is not None]
    if len(clean) < 2:
        return None
    return float(statistics.stdev(clean))


def fmt_pct(value: float | None, *, signed: bool = True) -> str:
    if value is None:
        return "N/A"
    return f"{value:+.2f}%" if signed else f"{value:.2f}%"


def fmt_num(value: float | None, suffix: str = "", digits: int = 2, *, signed: bool = False) -> str:
    if value is None:
        return "N/A"
    sign = "+" if signed else ""
    return f"{value:{sign}.{digits}f}{suffix}"


def public_supabase_url() -> str:
    return os.environ.get("CURSIVEOS_SUPABASE_URL") or os.environ.get("SUPABASE_URL") or seed_organism.DEFAULT_SUPABASE_URL


def public_supabase_key() -> str:
    return os.environ.get("CURSIVEOS_SUPABASE_KEY") or os.environ.get("SUPABASE_KEY") or seed_organism.DEFAULT_SUPABASE_KEY


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
        raise AnalyzeError(f"CursiveRoot read failed: HTTP {exc.code} {details}") from exc
    except urllib.error.URLError as exc:
        raise AnalyzeError(f"CursiveRoot read failed: {exc.reason}") from exc
    if not isinstance(data, list):
        raise AnalyzeError("CursiveRoot returned an unexpected response")
    return [row for row in data if isinstance(row, dict)]


def optional_postgrest_get(endpoint: str) -> list[dict[str, Any]]:
    try:
        return postgrest_get(endpoint)
    except AnalyzeError:
        return []


def canonical_machine_id(run: dict[str, Any]) -> str:
    notes = str(run.get("notes") or "")
    match = HW_RE.search(notes)
    if match:
        return match.group(1)
    return str(run.get("machine_id") or "unknown")


def row_is_stable(run: dict[str, Any]) -> bool | None:
    notes = str(run.get("notes") or "").lower()
    if "stability:true" in notes:
        return True
    if "stability:false" in notes:
        return False
    return None


def pct_improvement_for(metric: str, run: dict[str, Any]) -> float | None:
    if metric == "network":
        return num(run.get("network_delta_pct"))
    if metric == "coldstart":
        raw = num(run.get("coldstart_delta_pct"))
        return -raw if raw is not None else None
    if metric == "sustained":
        return num(run.get("sustained_delta_pct"))
    raise ValueError(metric)


def cohort_stats(runs: list[dict[str, Any]]) -> dict[str, Any]:
    network = [v for r in runs if (v := pct_improvement_for("network", r)) is not None]
    cold = [v for r in runs if (v := pct_improvement_for("coldstart", r)) is not None]
    sustained = [v for r in runs if (v := pct_improvement_for("sustained", r)) is not None]
    power_w = [v for r in runs if (v := num(r.get("power_delta_w"))) is not None]
    stable = [row_is_stable(r) for r in runs]
    unstable_count = sum(1 for v in stable if v is False)
    known_stability = sum(1 for v in stable if v is not None)
    return {
        "run_count": len(runs),
        "network_improvement_pct": summarize_values(network),
        "coldstart_improvement_pct": summarize_values(cold),
        "sustained_improvement_pct": summarize_values(sustained),
        "idle_power_delta_w": summarize_values(power_w),
        "known_stability_count": known_stability,
        "unstable_count": unstable_count,
    }


def summarize_values(values: list[float]) -> dict[str, Any]:
    return {
        "count": len(values),
        "median": median(values),
        "mean": mean(values),
        "stdev": stdev(values),
        "min": min(values) if values else None,
        "max": max(values) if values else None,
    }


def machine_hygiene(runs: list[dict[str, Any]], machines: list[dict[str, Any]]) -> dict[str, Any]:
    alias_pairs = []
    for run in runs:
        hw = canonical_machine_id(run)
        mid = str(run.get("machine_id") or "")
        if hw and mid and hw != mid:
            alias_pairs.append({"machine_id": mid, "hardware_fingerprint": hw})

    machine_missing_fields = []
    for machine in machines:
        missing = [field for field in ("os", "kernel") if not machine.get(field)]
        if missing:
            machine_missing_fields.append({
                "machine_id": machine.get("machine_id"),
                "missing": missing,
            })

    return {
        "run_alias_count": len(alias_pairs),
        "run_alias_examples": alias_pairs[:5],
        "machine_rows_missing_fields": machine_missing_fields,
    }


def decision_readiness(runs: list[dict[str, Any]], bundles: list[dict[str, Any]]) -> dict[str, Any]:
    accepted = [b for b in bundles if b.get("decision") == "accepted"]
    inconclusive = [b for b in bundles if b.get("decision") == "inconclusive"]
    measured_baseline = [b for b in bundles if b.get("decision") == "measured_baseline"]
    candidate_screens = [
        b for b in bundles
        if b.get("decision") in {"inconclusive", "accepted", "rejected_negative_fitness"}
        and "genesis" not in str(b.get("variant_id") or "")
    ]

    v08 = [r for r in runs if str(r.get("preset_version") or "") == "v0.8"]
    stats = cohort_stats(v08)
    network_median = stats["network_improvement_pct"]["median"]
    cold_median = stats["coldstart_improvement_pct"]["median"]
    sustained_median = stats["sustained_improvement_pct"]["median"]
    power_median = stats["idle_power_delta_w"]["median"]

    verdicts: list[str] = []
    if network_median is not None and network_median > 100 and stats["network_improvement_pct"]["count"] >= 3:
        verdicts.append("network signal is strong under the canonical loopback WAN simulation")
    else:
        verdicts.append("network signal needs more comparable rows before selection use")

    if cold_median is not None and cold_median > 5:
        verdicts.append("cold-start signal is promising but should be separated into load, TTFT, and GPU-frequency components")
    else:
        verdicts.append("cold-start signal is weak or hardware-dependent in the current cohort")

    if sustained_median is None or abs(sustained_median) < 3:
        verdicts.append("sustained inference deltas are currently too small/noisy to drive inheritance")
    else:
        verdicts.append("sustained inference has a visible signal, but needs counterbalanced confirmation")

    if power_median is not None and power_median > 1.0:
        verdicts.append("idle power cost is material and should remain an active fitness penalty")
    else:
        verdicts.append("idle power cost is not yet a fleet-level blocker")

    if not accepted:
        verdicts.append("no accepted seed mutation is present; organism is still in characterization/screening mode")
    if not candidate_screens:
        verdicts.append("no candidate screen bundle is visible in CursiveRoot yet")

    return {
        "accepted_seed_mutations": len(accepted),
        "inconclusive_seed_bundles": len(inconclusive),
        "measured_baselines": len(measured_baseline),
        "candidate_screen_bundles": len(candidate_screens),
        "v0_8_stats": stats,
        "verdicts": verdicts,
    }


def fetch_snapshot(limit: int) -> dict[str, Any]:
    run_cols = ",".join([
        "id",
        "machine_id",
        "run_date",
        "created_at",
        "preset_version",
        "wrapper_version",
        "network_baseline_mbit",
        "network_tuned_mbit",
        "network_delta_pct",
        "coldstart_baseline_ms",
        "coldstart_tuned_ms",
        "coldstart_delta_pct",
        "sustained_baseline_toks",
        "sustained_tuned_toks",
        "sustained_delta_pct",
        "power_idle_baseline_w",
        "power_idle_tuned_w",
        "power_delta_w",
        "notes",
    ])
    machine_cols = "machine_id,cpu,gpu,os,kernel,created_at"
    bundle_cols = "id,bundle_hash,variant_id,decision,machine_id,fitness_score,confidence,created_at,reason"
    detail_cols = "source_hash,machine_id,preset_version,created_at"
    safe_run_cols = urllib.parse.quote(run_cols, safe=",")
    safe_machine_cols = urllib.parse.quote(machine_cols, safe=",")
    safe_bundle_cols = urllib.parse.quote(bundle_cols, safe=",")
    safe_detail_cols = urllib.parse.quote(detail_cols, safe=",")
    return {
        "runs": postgrest_get(f"runs?select={safe_run_cols}&order=created_at.desc&limit={limit}"),
        "machines": postgrest_get(f"machines?select={safe_machine_cols}&order=created_at.desc&limit={limit}"),
        "seed_bundles": optional_postgrest_get(
            f"seed_bundles?select={safe_bundle_cols}&order=created_at.desc&limit={limit}"
        ),
        "run_detail_bundles": optional_postgrest_get(
            f"run_detail_bundles?select={safe_detail_cols}&order=created_at.desc&limit={limit}"
        ),
    }


def analyze(snapshot: dict[str, Any]) -> dict[str, Any]:
    runs = snapshot["runs"]
    machines = snapshot["machines"]
    bundles = snapshot["seed_bundles"]
    canonical_groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for run in runs:
        canonical_groups[canonical_machine_id(run)].append(run)

    return {
        "counts": {
            "runs": len(runs),
            "machine_rows": len(machines),
            "canonical_machines_from_runs": len(canonical_groups),
            "seed_bundles": len(bundles),
            "run_detail_bundles": len(snapshot["run_detail_bundles"]),
        },
        "latest_run": runs[0] if runs else None,
        "latest_seed_bundle": bundles[0] if bundles else None,
        "cohort_by_preset": {
            preset: cohort_stats([r for r in runs if str(r.get("preset_version") or "unknown") == preset])
            for preset in sorted({str(r.get("preset_version") or "unknown") for r in runs})
        },
        "cohort_by_machine": {
            machine_id: cohort_stats(rows)
            for machine_id, rows in sorted(canonical_groups.items())
        },
        "hygiene": machine_hygiene(runs, machines),
        "decision_readiness": decision_readiness(runs, bundles),
    }


def print_metric_summary(name: str, summary: dict[str, Any], suffix: str = "%") -> None:
    if summary["count"] == 0:
        print(f"  {name:<18} n=0")
        return
    unit = suffix
    print(
        f"  {name:<18} n={summary['count']:<3} "
        f"median={fmt_num(summary['median'], unit, signed=True)} "
        f"mean={fmt_num(summary['mean'], unit, signed=True)} "
        f"range={fmt_num(summary['min'], unit, signed=True)}..{fmt_num(summary['max'], unit, signed=True)}"
    )


def print_report(snapshot: dict[str, Any], result: dict[str, Any], latest: int) -> None:
    counts = result["counts"]
    print("CursiveRoot Decision-Grade Sensor Report")
    print("========================================")
    print(f"runs_visible:              {counts['runs']}")
    print(f"machine_rows:              {counts['machine_rows']}")
    print(f"canonical_machines:         {counts['canonical_machines_from_runs']}")
    print(f"seed_bundles:              {counts['seed_bundles']}")
    print(f"run_detail_bundles:         {counts['run_detail_bundles']}")

    latest_run = result["latest_run"]
    if latest_run:
        print("")
        print("Latest Run")
        print("----------")
        print(f"created_at:   {latest_run.get('created_at')}")
        print(f"machine_id:   {latest_run.get('machine_id')}")
        print(f"preset:       {latest_run.get('preset_version')} ({latest_run.get('wrapper_version')})")
        print(
            "metrics:      "
            f"net {fmt_pct(num(latest_run.get('network_delta_pct')))}, "
            f"cold {fmt_pct(num(latest_run.get('coldstart_delta_pct')))}, "
            f"sustained {fmt_pct(num(latest_run.get('sustained_delta_pct')))}, "
            f"power {fmt_num(num(latest_run.get('power_delta_w')), 'W', digits=1, signed=True)}"
        )
        print(f"notes:        {latest_run.get('notes') or ''}")

    print("")
    print("v0.8 Cohort Signal")
    print("------------------")
    v08 = result["decision_readiness"]["v0_8_stats"]
    print_metric_summary("network gain", v08["network_improvement_pct"])
    print_metric_summary("coldstart gain", v08["coldstart_improvement_pct"])
    print_metric_summary("sustained gain", v08["sustained_improvement_pct"])
    print_metric_summary("idle power", v08["idle_power_delta_w"], suffix="W")
    print(f"  unstable rows       {v08['unstable_count']} of {v08['known_stability_count']} with known stability")

    print("")
    print("Organism State")
    print("--------------")
    readiness = result["decision_readiness"]
    print(f"accepted_seed_mutations:   {readiness['accepted_seed_mutations']}")
    print(f"candidate_screen_bundles:  {readiness['candidate_screen_bundles']}")
    print(f"measured_baselines:        {readiness['measured_baselines']}")
    latest_bundle = result["latest_seed_bundle"]
    if latest_bundle:
        print(
            "latest_seed_bundle:       "
            f"{latest_bundle.get('variant_id')} -> {latest_bundle.get('decision')} "
            f"confidence={latest_bundle.get('confidence')}"
        )

    print("")
    print("Decision Notes")
    print("--------------")
    for note in readiness["verdicts"]:
        print(f"- {note}")

    hygiene = result["hygiene"]
    if hygiene["run_alias_count"] or hygiene["machine_rows_missing_fields"]:
        print("")
        print("Data Hygiene")
        print("------------")
        if hygiene["run_alias_count"]:
            print(f"- {hygiene['run_alias_count']} run rows use a machine id that differs from the hardware fingerprint in notes.")
            for pair in hygiene["run_alias_examples"]:
                print(f"  {pair['machine_id']} -> {pair['hardware_fingerprint']}")
        for row in hygiene["machine_rows_missing_fields"][:5]:
            print(f"- machine {row['machine_id']} missing fields: {', '.join(row['missing'])}")

    if snapshot["runs"]:
        print("")
        print(f"Latest {min(latest, len(snapshot['runs']))} Runs")
        print("----------------")
        print(f"{'created_at':<25} {'machine':<18} {'preset':<8} {'net':>9} {'cold':>9} {'sust':>9} {'power':>8}")
        for run in snapshot["runs"][:latest]:
            print(
                f"{str(run.get('created_at') or '')[:24]:<25} "
                f"{canonical_machine_id(run)[:18]:<18} "
                f"{str(run.get('preset_version') or '')[:8]:<8} "
                f"{fmt_pct(num(run.get('network_delta_pct'))):>9} "
                f"{fmt_pct(num(run.get('coldstart_delta_pct'))):>9} "
                f"{fmt_pct(num(run.get('sustained_delta_pct'))):>9} "
                f"{fmt_num(num(run.get('power_delta_w')), 'W', digits=1, signed=True):>8}"
            )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Analyze live CursiveRoot benchmark data for organism readiness.")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="maximum rows to fetch from each table")
    parser.add_argument("--latest", type=int, default=8, help="latest run rows to print")
    parser.add_argument("--json", action="store_true", help="print machine-readable analysis JSON")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        snapshot = fetch_snapshot(max(1, int(args.limit)))
        result = analyze(snapshot)
    except AnalyzeError as exc:
        print(f"cursiveroot-analyze error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps({"snapshot_counts": result["counts"], "analysis": result}, indent=2, sort_keys=True))
    else:
        print_report(snapshot, result, latest=max(1, int(args.latest)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
