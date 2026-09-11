#!/usr/bin/env python3
"""Founder closed loop: propose leftover -> screen on this box -> upload -> stack if kept.

CursiveRoot anon cannot INSERT measurement_requests (RLS). This driver is the work
wire on the founder machine. Results still upload as seed_bundles. Heartbeat is
merged into machine_capabilities.capabilities.sprint_loop for the dashboard.

Stop:  touch /home/elizabeth/CursiveOS/.cursiveos/closed-loop/STOP
"""
from __future__ import annotations

import json
import os
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

from organism_proposer import (  # noqa: E402
    KNOB_LIBRARY,
    materialize,
    existing_candidate_ids,
    parent_variant,
)
from contributor_daemon import (  # noqa: E402
    collect_capabilities,
    execute_request,
    now_iso,
    upsert_machine_capabilities,
)
from cursive_desk import mark_busy, mark_free  # noqa: E402

MINED_SLUGS = {"pagecluster0", "vfscache50"}
MAX_CYCLES = 4
STATE_DIR = ROOT / ".cursiveos" / "closed-loop"
STATE_PATH = STATE_DIR / "state.json"
STOP_PATH = STATE_DIR / "STOP"
LOG_PATH = ROOT / "logs" / "closed-loop.log"
PARENT_DEFAULT = "v0.12"


def log(msg: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    line = f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} {msg}"
    print(line, flush=True)
    with LOG_PATH.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def load_state() -> dict:
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    return {
        "running": False,
        "phase": "idle",
        "cycle": 0,
        "max_cycles": MAX_CYCLES,
        "parent": PARENT_DEFAULT,
        "current_candidate": None,
        "kept": [PARENT_DEFAULT],
        "history": [],
        "last_decision": None,
        "last_fitness": None,
        "note": "not started",
        "updated_at": now_iso(),
        "payout_eligible": False,
    }


def save_state(state: dict) -> None:
    state["updated_at"] = now_iso()
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    # Occupancy stays on this machine (Desktop window). Do not publish "this PC is busy"
    # onto the public ledger.


def stopped() -> bool:
    return STOP_PATH.exists()


def pick_knob(parent: str):
    parent_variant(parent)
    taken = existing_candidate_ids()
    for knob in sorted(KNOB_LIBRARY, key=lambda k: k.priority, reverse=True):
        if knob.slug in MINED_SLUGS:
            continue
        if knob.candidate_id in taken:
            continue
        return knob
    return None


def parse_screen(stdout: str) -> tuple[str | None, float | None]:
    decision = None
    fitness = None
    for line in (stdout or "").splitlines():
        if line.startswith("decision:"):
            decision = line.split(":", 1)[1].strip() or decision
        if line.startswith("last_decision:") and "->" in line:
            try:
                right = line.split("->", 1)[1].strip()
                decision = right.split()[0]
                if "fitness=" in right:
                    fitness = float(right.split("fitness=", 1)[1].split()[0])
            except (IndexError, ValueError):
                pass
        if line.startswith("fitness_score:") or line.startswith("fitness:"):
            try:
                fitness = float(line.split(":", 1)[1].strip().split()[0])
            except ValueError:
                pass
    return decision, fitness


def kept_decision(decision: str | None) -> bool:
    return (decision or "") == "accepted"


def undo_stack(candidate_id: str | None, parent: str) -> None:
    presets = ROOT / "presets"
    for name in (
        f"cursiveos-presets-{candidate_id}.sh" if candidate_id else None,
        f"cursiveos-presets-{parent}.sh",
        "cursiveos-presets-v0.12.sh",
    ):
        if not name:
            continue
        path = presets / name
        if path.exists():
            os.system(f"bash {path} --undo >/dev/null 2>&1 || true")


def run() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    (ROOT / "logs").mkdir(parents=True, exist_ok=True)
    state = load_state()
    if state.get("cycle") and state.get("phase") in {"done", "stopped"}:
        # restart a finished loop from zero unless STOP remains
        if not stopped():
            state = load_state.__defaults__ and {}  # type: ignore
    state = {
        "running": True,
        "phase": "starting",
        "cycle": int(state.get("cycle") or 0) if state.get("phase") not in {"done", "stopped", "idle", None} else 0,
        "max_cycles": MAX_CYCLES,
        "parent": state.get("parent") or PARENT_DEFAULT if state.get("phase") not in {"done", "stopped", "idle", None} else PARENT_DEFAULT,
        "current_candidate": None,
        "kept": state.get("kept") or [PARENT_DEFAULT],
        "history": state.get("history") or [],
        "last_decision": state.get("last_decision"),
        "last_fitness": state.get("last_fitness"),
        "note": "closed loop awake",
        "updated_at": now_iso(),
        "payout_eligible": False,
    }
    if state["cycle"] >= MAX_CYCLES:
        state["cycle"] = 0
        state["parent"] = PARENT_DEFAULT
        state["kept"] = [PARENT_DEFAULT]
        state["history"] = []
    save_state(state)
    log("closed loop start")

    try:
        while state["cycle"] < MAX_CYCLES:
            if stopped():
                state["phase"] = "stopped"
                state["note"] = "STOP file present"
                state["running"] = False
                save_state(state)
                log("stopped by STOP file")
                undo_stack(state.get("current_candidate"), state["parent"])
                mark_free("Stopped. You can use this computer.")
                return 0

            parent = state["parent"] or PARENT_DEFAULT
            state["phase"] = "proposing"
            save_state(state)
            knob = pick_knob(parent)
            if knob is None:
                state["phase"] = "done"
                state["note"] = "no reversible leftovers left to screen"
                state["running"] = False
                save_state(state)
                log("library exhausted")
                break

            log(f"cycle {state['cycle']+1}: parent={parent} candidate={knob.candidate_id} {knob.key}={knob.value}")
            state["phase"] = "materializing"
            state["current_candidate"] = knob.candidate_id
            state["note"] = f"drafting {knob.candidate_id}"
            save_state(state)
            materialize(knob, parent)

            req = {
                "schema_version": "cursiveos.measurement-request.v0.1",
                "request_id": f"closed-loop-{knob.candidate_id}-vs-{parent}",
                "status": "open",
                "parent_variant_id": parent,
                "parent_variant_path": f"references/seed-organism/variant.{parent}.json",
                "candidate_variant_id": knob.candidate_id,
                "candidate_variant_path": f"references/seed-organism/variant.{knob.candidate_id}.json",
                "cycle_id": 7,
                "screen_order": "normal",
                "selection_scope": "linux_bare_metal",
                "trust_scope": "simulated_not_payout_eligible",
                "required_capabilities": [
                    "linux_bare_metal",
                    "sudo_noninteractive",
                    "bash",
                    "python3",
                    "git",
                    "curl",
                ],
                "reward_sats_placeholder": 0,
                "requested_by": "organism-proposer",
                "notes": (
                    f"Closed-loop screen {parent} vs {knob.candidate_id} "
                    f"({knob.key}={knob.value}). Simulated, not payout eligible."
                ),
            }
            req_path = STATE_DIR / f"request-{knob.candidate_id}.json"
            req_path.write_text(json.dumps(req, indent=2) + "\n", encoding="utf-8")

            state["phase"] = "screening"
            state["note"] = f"measuring {knob.candidate_id} against {parent}"
            save_state(state)
            mark_busy(f"measuring {knob.candidate_id} against {parent}")
            job_dir = ROOT / ".cursiveos" / "contributor-daemon"
            job_dir.mkdir(parents=True, exist_ok=True)
            job = execute_request(req, dry_run=False, state=job_dir)
            stdout = str(job.get("stdout") or "")
            decision, fitness = parse_screen(stdout)
            if not decision:
                decision = "inconclusive" if job.get("status") == "complete" else f"job_{job.get('status')}"

            state["cycle"] = int(state["cycle"]) + 1
            state["last_decision"] = decision
            state["last_fitness"] = fitness
            state["history"].append(
                {
                    "cycle": state["cycle"],
                    "parent": parent,
                    "candidate": knob.candidate_id,
                    "knob": f"{knob.key}={knob.value}",
                    "decision": decision,
                    "fitness": fitness,
                    "job_status": job.get("status"),
                    "bundle_hash": job.get("result_bundle_hash"),
                    "at": now_iso(),
                }
            )
            if kept_decision(decision):
                kept = list(state.get("kept") or [PARENT_DEFAULT])
                if knob.candidate_id not in kept:
                    kept.append(knob.candidate_id)
                state["kept"] = kept
                state["parent"] = knob.candidate_id
                state["note"] = f"kept {knob.candidate_id}; it is now the genome"
            else:
                state["note"] = f"{knob.candidate_id} did not stick ({decision})"
            state["phase"] = "between"
            state["current_candidate"] = None
            save_state(state)
            log(f"cycle {state['cycle']} done decision={decision} fitness={fitness} job={job.get('status')}")
            undo_stack(knob.candidate_id, parent)
            mark_free(f"{knob.candidate_id}: {decision}. Between screens — computer is yours for a moment." if state["cycle"] < MAX_CYCLES else f"{knob.candidate_id}: {decision}.")

        state["phase"] = "done"
        state["running"] = False
        state["note"] = f"finished {state['cycle']} of {MAX_CYCLES} screens"
        save_state(state)
        undo_stack(None, state.get("parent") or PARENT_DEFAULT)
        mark_free("Loop finished. You can use this computer.")
        log("closed loop finished")
        return 0
    except Exception:
        log(traceback.format_exc())
        state["phase"] = "failed"
        state["running"] = False
        state["note"] = "loop crashed; see closed-loop.log"
        save_state(state)
        undo_stack(state.get("current_candidate"), state.get("parent") or PARENT_DEFAULT)
        mark_free("Loop crashed. Settings put back. You can use this computer.")
        return 1


if __name__ == "__main__":
    raise SystemExit(run())
