#!/usr/bin/env python3
"""Local-only client status. Never uploaded to the public ledger."""
from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path("/home/elizabeth/CursiveOS")
STATE_DIR = ROOT / ".cursiveos" / "closed-loop"
STATUS_PATH = STATE_DIR / "panel.json"

STEPS = [
    ("idle power (baseline", "Resting power, parent"),
    ("memory refault (baseline", "Memory, parent"),
    ("[1/3] network", "Network, parent"),
    ("[2/3] cold-start", "Cold start, parent"),
    ("[3/3] sustained", "Sustained, parent"),
    ("idle power (tuned", "Resting power, candidate"),
    ("memory refault (tuned", "Memory, candidate"),
]

# A paired screen runs parent full-test then candidate full-test.
# The [1/3] markers repeat. We count how many times we have seen each family.
REPEATABLE = [
    ("[1/3] network", "Network"),
    ("[2/3] cold-start", "Cold start"),
    ("[3/3] sustained", "Sustained"),
    ("idle power (baseline", "Resting power"),
    ("memory refault (baseline", "Memory"),
]


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _read() -> dict:
    if not STATUS_PATH.exists():
        return {}
    try:
        return json.loads(STATUS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def write_status(**fields: object) -> dict:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    cur = _read()
    cur.update(fields)
    cur["updated_at"] = now_iso()
    STATUS_PATH.write_text(json.dumps(cur, indent=2) + "\n", encoding="utf-8")
    return cur


def read_status() -> dict:
    return _read()


def git_info(*, fetch: bool = False) -> dict:
    def _run(args: list[str]) -> str:
        r = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, check=False)
        return (r.stdout or "").strip()

    head = _run(["git", "rev-parse", "--short", "HEAD"])
    dirty = bool(_run(["git", "status", "--porcelain"]))
    behind_n, ahead_n = 0, 0
    if fetch:
        subprocess.run(["git", "fetch", "origin", "--quiet"], cwd=ROOT, check=False, capture_output=True)
        behind = _run(["git", "rev-list", "--count", "HEAD..origin/main"]) or "0"
        ahead = _run(["git", "rev-list", "--count", "origin/main..HEAD"]) or "0"
        try:
            behind_n, ahead_n = int(behind), int(ahead)
        except ValueError:
            behind_n, ahead_n = 0, 0
    return {
        "head": head or "unknown",
        "dirty": dirty,
        "behind": behind_n,
        "ahead": ahead_n,
    }


def git_update() -> str:
    """Pull origin/main when idle and clean. Returns a human note."""
    st = _read()
    if st.get("busy"):
        return "Can't update while a test is running. Stop it first."
    info = git_info(fetch=True)
    if info["dirty"]:
        return f"Not pulled — this machine has local edits ({info['head']})."
    if info["behind"] == 0:
        if info["ahead"]:
            return f"Already current with GitHub, plus {info['ahead']} local commit(s) ({info['head']})."
        return f"Already current ({info['head']})."
    r = subprocess.run(
        ["git", "pull", "--ff-only", "origin", "main"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if r.returncode != 0:
        return f"Update failed: {(r.stderr or r.stdout or 'git error').strip()[:240]}"
    new = git_info(fetch=False)
    return f"Updated to {new['head']}."


def next_from_ledger() -> dict | None:
    """Read-only: the next open ticket, if any. Never inserts."""
    try:
        from contributor_daemon import fetch_open_request
        req = fetch_open_request()
    except Exception:
        return None
    if not req:
        return None
    return {
        "parent": req.get("parent_variant_id"),
        "candidate": req.get("candidate_variant_id"),
        "source": "ledger",
    }


def next_from_library() -> dict | None:
    try:
        from organism_proposer import KNOB_LIBRARY, existing_candidate_ids
    except Exception:
        return None
    mined = {"pagecluster0", "vfscache50"}
    taken = existing_candidate_ids()
    for knob in sorted(KNOB_LIBRARY, key=lambda k: k.priority, reverse=True):
        if knob.slug in mined or knob.candidate_id in taken:
            continue
        return {
            "parent": "v0.12",
            "candidate": knob.candidate_id,
            "source": "library",
        }
    return None


def progress_from_line(line: str, current: dict) -> dict:
    """Advance a coarse phase bar from harness output. Honest steps, not a fake %."""
    low = line.lower()
    counts: dict = dict(current.get("counts") or {})
    label = current.get("label") or "Starting"
    for marker, name in REPEATABLE:
        if marker in low:
            counts[marker] = int(counts.get(marker) or 0) + 1
            which = "parent" if counts[marker] == 1 else "candidate"
            label = f"{name} ({which})"
            break
    if "bundle_hash:" in low or low.startswith("decision:"):
        label = "Finishing"
    step = min(sum(int(v) for v in counts.values()), 10)
    current.update({"counts": counts, "step": step, "total": 10, "label": label})
    return current
