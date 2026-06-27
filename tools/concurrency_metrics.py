#!/usr/bin/env python3
"""Aggregate concurrency probe worker JSON into METRIC_JSON (shipped path)."""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from typing import Any


def aggregate_worker_metrics(
    tmpdir: str,
    *,
    streams: int,
    wall_s: float,
    model: str,
) -> dict[str, Any]:
    """Read worker_*.json under tmpdir; same logic as benchmark-inference-concurrency-v0.1.sh."""
    total_tokens = 0
    per_worker_tps: list[float] = []
    failures = 0
    for path in sorted(glob.glob(os.path.join(tmpdir, "worker_*.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            eval_count = int(data.get("eval_count") or 0)
            eval_duration = float(data.get("eval_duration") or 0)
            total_tokens += eval_count
            if eval_duration > 0 and eval_count > 0:
                per_worker_tps.append(eval_count / (eval_duration / 1e9))
            elif eval_count == 0:
                failures += 1
        except (OSError, json.JSONDecodeError, TypeError, ValueError):
            failures += 1

    aggregate_tok_s = round(total_tokens / wall_s, 2) if wall_s > 0 else 0.0
    per_worker_mean = (
        round(sum(per_worker_tps) / len(per_worker_tps), 2) if per_worker_tps else 0.0
    )
    return {
        "sensor": "inference_concurrency",
        "version": "v0.1",
        "model": model,
        "streams": streams,
        "wall_s": wall_s,
        "total_tokens": total_tokens,
        "aggregate_tok_s": aggregate_tok_s,
        "per_worker_mean_tok_s": per_worker_mean,
        "failures": failures,
    }


def format_probe_lines(metrics: dict[str, Any]) -> list[str]:
    """Human-readable lines ending with METRIC_JSON (Log line emitted separately by benchmark)."""
    streams = int(metrics["streams"])
    failures = int(metrics["failures"])
    return [
        f"wall_s={metrics['wall_s']} total_tokens={metrics['total_tokens']} "
        f"aggregate_tok_s={metrics['aggregate_tok_s']}",
        f"per_worker_mean_tok_s={metrics['per_worker_mean_tok_s']} "
        f"failures={failures}/{streams}",
        "note: observe-only channel; not yet wired to fitness weight.",
        "METRIC_JSON " + json.dumps(metrics, sort_keys=True),
    ]


def parse_metric_json_line(stdout: str) -> dict[str, Any]:
    for line in stdout.splitlines():
        if line.startswith("METRIC_JSON "):
            return json.loads(line[len("METRIC_JSON ") :])
    raise ValueError("METRIC_JSON line not found in probe output")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Aggregate concurrency worker JSON metrics")
    parser.add_argument("--tmpdir", required=True)
    parser.add_argument("--streams", type=int, required=True)
    parser.add_argument("--wall-s", type=float, required=True)
    parser.add_argument("--model", required=True)
    args = parser.parse_args(argv)
    metrics = aggregate_worker_metrics(
        args.tmpdir,
        streams=args.streams,
        wall_s=args.wall_s,
        model=args.model,
    )
    for line in format_probe_lines(metrics):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())