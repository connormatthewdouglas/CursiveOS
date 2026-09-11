#!/usr/bin/env python3
"""MAP-Elites archive from CursiveRoot seed_bundles.

Port of operator/engine/qd.ts. Bins match tools/qd_organism.py (±1% band,
lower-is-better channels inverted). Does not write CursiveRoot. Does not
propose pagecluster / vfs cousins.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from collections import defaultdict
from typing import Any


BIN_LABEL = ("neg", "neu", "pos")
AXES = ("cold", "sustained", "idle", "memory")
NEUTRAL_BAND = 1.0
MINED_OUT = ("pagecluster0", "vfscache50")
CELL_COUNT = 81


def pct_delta(variant: float | None, baseline: float | None) -> float | None:
    if variant is None or baseline in (None, 0):
        return None
    return (float(variant) - float(baseline)) / abs(float(baseline)) * 100


def bin_pct(value: float | None, band: float = NEUTRAL_BAND) -> int:
    if value is None:
        return 1
    if value < -band:
        return 0
    if value > band:
        return 2
    return 1


def cell_key(bins: tuple[int, int, int, int]) -> str:
    return "-".join(f"{a[0]}{BIN_LABEL[b]}" for a, b in zip(("c", "s", "i", "m"), bins))


def descriptor(bundle: dict[str, Any]) -> dict[str, Any] | None:
    metrics = ((bundle.get("result_bundle") or {}).get("metrics") or {})
    variant = metrics.get("variant") or {}
    baseline = metrics.get("baseline") or {}
    if not variant or not baseline:
        return None
    cold = pct_delta(variant.get("coldstart_ms"), baseline.get("coldstart_ms"))
    sust = pct_delta(variant.get("sustained_tokps"), baseline.get("sustained_tokps"))
    idle = pct_delta(variant.get("idle_watts"), baseline.get("idle_watts"))
    mem = pct_delta(variant.get("memory_refault_s"), baseline.get("memory_refault_s"))
    bins = (
        bin_pct(None if cold is None else -cold),
        bin_pct(sust),
        bin_pct(None if idle is None else -idle),
        bin_pct(None if mem is None else -mem),
    )
    return {"bins": bins, "key": cell_key(bins)}


def is_mined_out(variant_id: str | None) -> bool:
    v = variant_id or ""
    return any(s in v for s in MINED_OUT)


def neighbors(bins: tuple[int, int, int, int]) -> list[tuple[int, int, int, int]]:
    out: list[tuple[int, int, int, int]] = []
    for i in range(4):
        for d in (-1, 1):
            n = bins[i] + d
            if n < 0 or n > 2:
                continue
            nxt = list(bins)
            nxt[i] = n
            out.append(tuple(nxt))  # type: ignore[arg-type]
    return out


def build_archive(bundles: list[dict[str, Any]]) -> dict[str, Any]:
    by_cell: dict[str, list[dict[str, Any]]] = defaultdict(list)
    desc: dict[str, dict[str, Any]] = {}
    for b in bundles:
        d = descriptor(b)
        if not d:
            continue
        desc[b.get("variant_id") or ""] = d
        by_cell[d["key"]].append(b)

    def best(occupants: list[dict[str, Any]]) -> dict[str, Any]:
        accepted = [x for x in occupants if x.get("decision") == "accepted"]
        pool = accepted or occupants
        return max(pool, key=lambda x: float(x.get("fitness_score") or 0))

    cells = []
    for key, occupants in by_cell.items():
        elite = best(occupants)
        decisions = {x.get("decision") for x in occupants}
        if "accepted" in decisions:
            coverage = "covered"
        elif any(is_mined_out(x.get("variant_id")) for x in occupants):
            coverage = "mined-null"
        elif any(str(x.get("decision") or "").startswith("rejected") for x in occupants):
            coverage = "rejected"
        else:
            coverage = "screened"
        cells.append({
            "key": key,
            "coverage": coverage,
            "occupants": len(occupants),
            "elite_variant_id": elite.get("variant_id"),
            "elite_fitness": float(elite.get("fitness_score") or 0),
        })

    accepted = sorted(
        [b for b in bundles if b.get("decision") == "accepted" and float(b.get("fitness_score") or 0) > 0],
        key=lambda b: float(b.get("fitness_score") or 0),
        reverse=True,
    )
    parent = accepted[0] if accepted else None
    parent_desc = desc.get(parent["variant_id"]) if parent else None
    occupied_keys = {c["key"] for c in cells}
    empty = []
    if parent_desc:
        for bins in neighbors(tuple(parent_desc["bins"])):  # type: ignore[arg-type]
            key = cell_key(bins)  # type: ignore[arg-type]
            if key in occupied_keys:
                continue
            empty.append(key)

    return {
        "occupied": len(cells),
        "covered": sum(1 for c in cells if c["coverage"] == "covered"),
        "parent_variant_id": (parent or {}).get("variant_id", "v0.12"),
        "parent_cell": (parent_desc or {}).get("key"),
        "empty_neighbors": empty,
        "cells": cells,
        "note": (
            f"Mutate {parent['variant_id']} toward an empty neighbor."
            if parent and empty
            else "QD refuses rather than mining the library."
        ),
    }


def fetch_live(url: str, key: str) -> list[dict[str, Any]]:
    req = urllib.request.Request(
        f"{url}/seed_bundles?select=variant_id,decision,fitness_score,result_bundle,created_at,contributor_id&order=created_at.desc&limit=24",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(req, timeout=12) as res:
        return json.loads(res.read().decode("utf-8"))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="QD archive from seed_bundles (read-only).")
    p.add_argument("--from-json", help="path to a JSON array of seed_bundles")
    p.add_argument("--live", action="store_true", help="GET live CursiveRoot (read-only)")
    p.add_argument("--url", default="https://iovvktpuoinmjdgfxgvm.supabase.co/rest/v1")
    p.add_argument("--key", default="")
    args = p.parse_args(argv)
    if args.from_json:
        bundles = json.loads(open(args.from_json, encoding="utf-8").read())
    elif args.live:
        if not args.key:
            print("qd_archive: --live requires --key (publishable anon key)", file=sys.stderr)
            return 2
        bundles = fetch_live(args.url, args.key)
    else:
        print("qd_archive: pass --from-json or --live", file=sys.stderr)
        return 2
    archive = build_archive(bundles)
    json.dump(archive, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
