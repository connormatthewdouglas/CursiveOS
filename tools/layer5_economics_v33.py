#!/usr/bin/env python3
"""Layer 5 Economics v3.3 — decision engine. No rail execution lives here.

Port of operator/engine/economics.ts. Testers never receive lifetime fitness.
Zero revenue produces zero accruals. Sats are allocated losslessly.
"""
from __future__ import annotations

import argparse
import json
import math
from typing import Any


GENESIS_SPLIT_CURRENT = 0.2
GENESIS_SPLIT_LIFETIME = 0.8
MAX_SPLIT_DELTA = 0.025
CLAIM_WINDOW_MS = 2 * 365.25 * 24 * 60 * 60 * 1000


def new_weight(prior_merge_count: int) -> float:
    n = max(0, prior_merge_count)
    return 1 / (1 + n)


def returning_weight(prior_merge_count: int) -> float:
    return 1 - new_weight(prior_merge_count)


def metabolic_r(merges: list[dict[str, Any]]) -> float | None:
    new_sum = 0.0
    ret_sum = 0.0
    for m in merges:
        f = max(0.0, float(m.get("fitness_delta", 0)))
        n = int(m.get("prior_merge_count", 0))
        new_sum += new_weight(n) * f
        ret_sum += returning_weight(n) * f
    if ret_sum <= 0:
        return math.inf if new_sum > 0 else None
    return new_sum / ret_sum


def restoring_factor(split_current: float, neutral: float = GENESIS_SPLIT_CURRENT) -> float:
    distance = split_current - neutral
    return 1 / (1 + (distance / 0.3) ** 2)


def target_split_current(r_meta: float | None, neutral: float = GENESIS_SPLIT_CURRENT) -> float:
    if r_meta is None:
        return neutral
    if not math.isfinite(r_meta):
        return min(0.95, neutral + 0.35)
    log_r = math.log(max(r_meta, 1e-9))
    return neutral + 0.25 * math.tanh(log_r)


def clamp01(n: float) -> float:
    return 0.0 if n < 0 else 1.0 if n > 1 else n


def next_split(split_current: float, r_meta: float | None) -> dict[str, float | None]:
    target = target_split_current(r_meta)
    restoring = restoring_factor(split_current)
    raw = target - split_current
    step = math.copysign(min(MAX_SPLIT_DELTA, abs(raw)), raw) * restoring
    s = clamp01(split_current + step)
    return {
        "split_current": s,
        "split_lifetime": 1 - s,
        "s_target": clamp01(target),
        "r_meta": r_meta,
        "delta_applied": step,
    }


def allocate_sats(total: int, weights: list[tuple[str, float]]) -> dict[str, int]:
    out: dict[str, int] = {wid: 0 for wid, _ in weights}
    eligible = [(wid, w) for wid, w in weights if w > 0]
    s = sum(w for _, w in eligible)
    if total <= 0 or s <= 0 or not eligible:
        return out
    floors: list[tuple[str, int, float]] = []
    used = 0
    for wid, w in eligible:
        exact = (total * w) / s
        floor = math.floor(exact)
        floors.append((wid, floor, exact - floor))
        used += floor
    floors.sort(key=lambda row: row[2], reverse=True)
    remainder = total - used
    for wid, floor, _ in floors:
        extra = 1 if remainder > 0 else 0
        out[wid] = floor + extra
        remainder -= extra
    return out


def close_cycle(
    *,
    cycle_id: int,
    revenue_sats: int,
    split_current: float,
    merges: list[dict[str, Any]],
    lifetime: list[dict[str, Any]],
) -> dict[str, Any]:
    split_current = clamp01(split_current)
    split_lifetime = 1 - split_current
    r_meta = metabolic_r(merges)
    nxt = next_split(split_current, r_meta)
    merged = [m for m in merges if float(m.get("fitness_delta", 0)) > 0]
    life_map: dict[str, float] = {r["contributor_wallet"]: float(r["fitness"]) for r in lifetime}
    for m in merged:
        w = m["contributor_wallet"]
        life_map[w] = life_map.get(w, 0.0) + float(m["fitness_delta"])
    if revenue_sats <= 0:
        return {
            "cycle_id": cycle_id,
            "revenue_sats": 0,
            "split_current": split_current,
            "split_lifetime": split_lifetime,
            "r_meta": r_meta,
            "next_split_current": nxt["split_current"],
            "accruals": [],
            "zero_revenue": True,
            "updated_lifetime": life_map,
        }
    current_stream = math.floor(revenue_sats * split_current)
    lifetime_stream = revenue_sats - current_stream
    current_alloc = allocate_sats(
        current_stream, [(m["contributor_wallet"], float(m["fitness_delta"])) for m in merged]
    )
    life_alloc = allocate_sats(lifetime_stream, list(life_map.items()))
    accruals = []
    for wallet, amount in current_alloc.items():
        if amount > 0:
            accruals.append({"wallet": wallet, "stream": "current", "amount_sats": amount})
    for wallet, amount in life_alloc.items():
        if amount > 0:
            accruals.append({"wallet": wallet, "stream": "lifetime", "amount_sats": amount})
    return {
        "cycle_id": cycle_id,
        "revenue_sats": revenue_sats,
        "split_current": split_current,
        "split_lifetime": split_lifetime,
        "r_meta": r_meta,
        "next_split_current": nxt["split_current"],
        "current_stream_sats": current_stream,
        "lifetime_stream_sats": lifetime_stream,
        "accruals": accruals,
        "zero_revenue": False,
        "updated_lifetime": life_map,
        "note": "Testers are not an input. payout_eligible remains false.",
    }


def main() -> int:
    p = argparse.ArgumentParser(description="CursiveOS Layer 5 economics v3.3")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("close", help="close a simulated cycle")
    c.add_argument("--revenue-sats", type=int, default=0)
    c.add_argument("--split-current", type=float, default=GENESIS_SPLIT_CURRENT)
    c.add_argument("--cycle-id", type=int, default=7)
    c.add_argument("--wallet", default="founder")
    c.add_argument("--fitness", type=float, default=0.1)
    args = p.parse_args()
    if args.cmd == "close":
        result = close_cycle(
            cycle_id=args.cycle_id,
            revenue_sats=args.revenue_sats,
            split_current=args.split_current,
            merges=[
                {
                    "contributor_wallet": args.wallet,
                    "variant_id": "preview",
                    "fitness_delta": args.fitness,
                    "prior_merge_count": 1,
                }
            ],
            lifetime=[{"contributor_wallet": args.wallet, "fitness": 0.0148}],
        )
        print(json.dumps(result, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
