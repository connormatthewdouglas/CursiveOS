#!/usr/bin/env python3
"""
Autonomous variant proposer for the CursiveOS seed organism (G3).

This is the "self" in self-improvement: instead of the founder hand-authoring every
candidate mutation, the proposer selects the next experiment from a measured history
and materializes a real, runnable, reversible candidate that a contributor daemon can
screen through the normal acceptance loop. It proposes; the sensors decide.

SAFETY MODEL (deliberate, and load-bearing):
  * The proposer composes ONLY from an audited library of reversible `sysctl` knobs
    (KNOB_LIBRARY). It never generates free-form shell. Each materialized preset
    captures the prior value, applies exactly one knob, and restores it on --undo
    before delegating the rest of the revert to the parent preset. This preserves the
    mutation-safety and reversibility invariants the whole project depends on, and it
    keeps the daemon's containment guarantee intact (it still only runs repo-contained,
    existing variant paths).
  * A materialized candidate is always Linux-scoped and `simulated_not_payout_eligible`.
  * ENQUEUE IS PRIVILEGED. Because measurement_requests is privileged-authored
    (anon INSERT is revoked by migration 20260702000000), the proposer does NOT insert
    a request with the public key. It prints a ready-to-apply SQL INSERT for the
    founder / service role to run. During bootstrap this keeps a human in the loop on
    exactly what daemons will execute with sudo, while the *proposal* itself is
    automated. Selection still never runs through discretion.

Grounding vs tools/qd_organism.py: qd_organism is a pure MAP-Elites *simulation* over
abstract knobs with a synthetic metric model. This module is the real-world bridge:
concrete reversible knobs, real preset/variant files, and the live queue. The QD
diversity machinery informs the priority ordering here (favor channels that are
producing measured wins); wiring the live QD archive to real fitness pulled from
CursiveRoot is a future extension, noted in docs/action-plan.md (G3).
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VARIANTS_DIR = ROOT / "references" / "seed-organism"
PRESETS_DIR = ROOT / "presets"

DEFAULT_PARENT_ID = "v0.12"  # current canonical parent (see variant.v0.12.json)


@dataclass(frozen=True)
class Knob:
    """One audited, reversible sysctl knob the proposer may add on top of the parent."""

    slug: str            # candidate id suffix, e.g. "pagecluster0" -> v0.13-pagecluster0
    key: str             # sysctl key, e.g. "vm.page-cluster"
    value: str           # value to set
    channel: str         # sensor channel it primarily targets (for diversity/priority)
    priority: int        # higher = proposed sooner
    hypothesis: str      # falsifiable expectation, recorded in the variant

    @property
    def candidate_id(self) -> str:
        return f"v0.13-{self.slug}"

    @property
    def variant_id(self) -> str:
        return f"candidate-{self.candidate_id}"

    @property
    def preset_filename(self) -> str:
        return f"cursiveos-presets-{self.candidate_id}.sh"

    @property
    def variant_filename(self) -> str:
        return f"variant.{self.candidate_id}.json"


# Audited reversible knobs. All are plain `sysctl` keys so apply/undo is uniform:
# capture `sysctl -n <key>`, set `sysctl -w <key>=<value>`, restore on undo. None are
# destructive, none persist across reboot when applied via --apply-temp, and each is a
# single well-understood axis not already set by the v0.12 parent stack.
#
# Priority favors the memory channel first, because that is where the lineage's most
# recent measured win came from (v0.11 zram+swappiness, +75.4%); vm.page-cluster=0 in
# particular is the standard companion tuning for a zram swap device (fault one page
# at a time on swap-in), which v0.12 does not yet set.
KNOB_LIBRARY: tuple[Knob, ...] = (
    Knob(
        slug="pagecluster0", key="vm.page-cluster", value="0", channel="memory", priority=100,
        hypothesis="With a zram swap device (present in v0.12), vm.page-cluster=0 faults a single "
                   "page per swap-in instead of a 8-page cluster, cutting wasted decompression under "
                   "memory pressure. Expect the memory-pressure refault channel to improve vs v0.12 "
                   "with no inference regression; other channels neutral.",
    ),
    Knob(
        slug="vfscache50", key="vm.vfs_cache_pressure", value="50", channel="memory", priority=80,
        hypothesis="Halving vfs_cache_pressure (100->50) makes the kernel retain dentry/inode cache "
                   "longer, which can lower cold-start and memory-refault cost on repeated access. "
                   "Risk: on tight RAM it trades file-cache for metadata cache; the memory + cold-start "
                   "channels adjudicate.",
    ),
    Knob(
        slug="watermark200", key="vm.watermark_scale_factor", value="200", channel="memory", priority=70,
        hypothesis="Raising watermark_scale_factor (10->200) starts reclaim earlier, reducing direct-"
                   "reclaim stalls under the memory-pressure probe. Expect steadier refault time; watch "
                   "idle power / neutral elsewhere.",
    ),
    Knob(
        slug="dirtyexpire1500", key="vm.dirty_expire_centisecs", value="1500", channel="memory", priority=55,
        hypothesis="Expiring dirty pages sooner (3000->1500 cs) smooths writeback bursts that can "
                   "interfere with reclaim under pressure. Expect memory channel neutral-to-better, "
                   "sustained neutral.",
    ),
    Knob(
        slug="migcost5ms", key="kernel.sched_migration_cost_ns", value="5000000", channel="sustained", priority=50,
        hypothesis="Raising sched_migration_cost_ns (0.5ms->5ms) makes the scheduler less eager to "
                   "migrate warm inference threads across cores, which can help sustained tok/s and "
                   "cold-start. Single-stream sustained is near its noise floor, so treat a small move "
                   "as inconclusive.",
    ),
    Knob(
        slug="notsentlowat16k", key="net.ipv4.tcp_notsent_lowat", value="16384", channel="network", priority=40,
        hypothesis="Capping unsent bytes (tcp_notsent_lowat=16384) lowers head-of-line latency on the "
                   "network path. Network is gate-only in fitness, so this is expected to read neutral "
                   "for scoring and is proposed mainly to map the axis.",
    ),
)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def existing_candidate_ids() -> set[str]:
    """Every candidate id that already has a variant file (proposed/screened before)."""
    ids: set[str] = set()
    for p in VARIANTS_DIR.glob("variant.*.json"):
        ids.add(p.name[len("variant.") : -len(".json")])
    return ids


def parent_variant(parent_id: str) -> dict:
    path = VARIANTS_DIR / f"variant.{parent_id}.json"
    if not path.exists():
        raise FileNotFoundError(f"parent variant not found: {path}")
    return load_json(path)


def select_proposal(parent_id: str = DEFAULT_PARENT_ID, taken: set[str] | None = None) -> Knob | None:
    """Highest-priority audited knob whose candidate does not already exist. None if exhausted."""
    parent_variant(parent_id)  # validate the parent exists before proposing against it
    if taken is None:
        taken = existing_candidate_ids()
    for knob in sorted(KNOB_LIBRARY, key=lambda k: k.priority, reverse=True):
        if knob.candidate_id not in taken:
            return knob
    return None


def render_variant_json(knob: Knob, parent_id: str) -> str:
    variant = {
        "schema_version": "seed-organism.variant.v0.1",
        "variant_id": knob.variant_id,
        "parent_variant_id": f"parent-baseline-{parent_id}",
        "contributor_id": "organism-proposer",
        "commit_ref": knob.variant_id,
        "preset_version": knob.candidate_id,
        "preset_path": f"presets/{knob.preset_filename}",
        "evaluation_role": "candidate_screen",
        "fitness_eligible": True,
        "knobs_removed_vs_parent": 0,
        "proposed_by": "organism_proposer.v0.1",
        "declared_scope": (
            f"The {parent_id} parent stack plus a single reversible sysctl: "
            f"{knob.key}={knob.value} (channel: {knob.channel}). Autonomously proposed; "
            f"one knob added, nothing removed."
        ),
        "hypothesis": knob.hypothesis,
        "rollback_method": (
            f"Restores the prior {knob.key} value captured at apply time, then delegates the rest of "
            f"the revert to the {parent_id} preset undo; harness reverts at run end."
        ),
    }
    return json.dumps(variant, indent=2) + "\n"


def render_preset_sh(knob: Knob, parent_id: str) -> str:
    parent_preset = f"cursiveos-presets-{parent_id}.sh"
    state_file = f"preset_state_{knob.candidate_id}.txt"
    return f"""#!/usr/bin/env bash
# CursiveOS {knob.candidate_id} candidate — AUTONOMOUSLY PROPOSED by organism_proposer.
#
# = the {parent_id} parent stack PLUS one reversible sysctl knob: {knob.key}={knob.value}.
# Primary sensor channel: {knob.channel}.
#
# Hypothesis (pre-registered): {knob.hypothesis}
#
# Safety: exactly one audited sysctl is changed. The prior value is captured on apply
# and restored on undo before delegating the rest of the revert to the parent preset.
# Nothing here is free-form or destructive; fully reversible.

set -uo pipefail
ACTION="${{1:---help}}"
SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
PARENT="$SCRIPT_DIR/{parent_preset}"
STATE="$HOME/CursiveOS/{state_file}"
KEY="{knob.key}"
VAL="{knob.value}"

if [[ -z "${{TAO_SUDO_PASS:-}}" ]]; then
    # non-interactive sudo if already granted; otherwise prompt once.
    if ! sudo -n true 2>/dev/null; then
        read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
    fi
fi
export TAO_SUDO_PASS
s() {{
    if [[ -n "${{TAO_SUDO_PASS:-}}" ]]; then echo "$TAO_SUDO_PASS" | sudo -S "$@" 2>/dev/null;
    else sudo -n "$@" 2>/dev/null; fi
}}

echo "CursiveOS Candidate {knob.candidate_id} ({parent_id} stack + $KEY=$VAL)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: {parent_id} parent stack plus reversible sysctl $KEY=$VAL."
    ;;
  --dry-run)
    bash "$PARENT" --dry-run
    echo "  + sysctl: $KEY=$VAL (channel {knob.channel}; prior value captured for undo)"
    ;;
  --apply-temp)
    bash "$PARENT" --apply-temp
    OLD="$(s sysctl -n "$KEY" 2>/dev/null || sysctl -n "$KEY" 2>/dev/null || true)"
    if [[ -n "$OLD" ]]; then
        mkdir -p "$(dirname "$STATE")"
        echo "$KEY=$OLD" > "$STATE"
    fi
    if s sysctl -w "$KEY=$VAL" >/dev/null 2>&1; then
        echo "OK $KEY set to $VAL (was ${{OLD:-unknown}})"
    else
        echo "  sysctl set failed for $KEY — parent stack still applied"
    fi
    echo "OK Applied {knob.candidate_id} temporarily."
    ;;
  --undo)
    if [[ -f "$STATE" ]]; then
        SAVED="$(cut -d= -f2- < "$STATE")"
        [[ -n "$SAVED" ]] && s sysctl -w "$KEY=$SAVED" >/dev/null 2>&1 && echo "OK $KEY restored to $SAVED"
        rm -f "$STATE"
    fi
    bash "$PARENT" --undo
    echo "OK {knob.candidate_id} reverted (sysctl + {parent_id} stack)."
    ;;
  *) echo "Unknown option: $ACTION"; exit 1 ;;
esac
"""


def enqueue_sql(knob: Knob, parent_id: str, *, cycle_id: int, screen_order: str) -> str:
    """Privileged INSERT for the founder/service-role to run. Never anon-inserted."""
    request_key = f"os0-proposed-{knob.candidate_id}-vs-{parent_id}-{screen_order}"
    notes = (
        f"Autonomously proposed by organism_proposer: screen {parent_id} parent against "
        f"{knob.candidate_id} ({knob.key}={knob.value}). Simulated reward only; not payout eligible."
    )
    return (
        "insert into public.measurement_requests\n"
        "  (request_key, status, priority, parent_variant_id, parent_variant_path,\n"
        "   candidate_variant_id, candidate_variant_path, cycle_id, screen_order,\n"
        "   selection_scope, trust_scope, reward_sats_placeholder, requested_by, notes)\n"
        "values\n"
        f"  ('{request_key}', 'open', {knob.priority}, '{parent_id}',\n"
        f"   'references/seed-organism/variant.{parent_id}.json',\n"
        f"   '{knob.candidate_id}', 'references/seed-organism/{knob.variant_filename}',\n"
        f"   {cycle_id}, '{screen_order}', 'linux_bare_metal',\n"
        f"   'simulated_not_payout_eligible', 0, 'organism-proposer',\n"
        f"   '{notes}')\n"
        "on conflict (request_key) do nothing;"
    )


def materialize(knob: Knob, parent_id: str) -> tuple[Path, Path]:
    variant_path = VARIANTS_DIR / knob.variant_filename
    preset_path = PRESETS_DIR / knob.preset_filename
    variant_path.write_text(render_variant_json(knob, parent_id), encoding="utf-8")
    preset_path.write_text(render_preset_sh(knob, parent_id), encoding="utf-8")
    return variant_path, preset_path


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)


def cmd_propose(args: argparse.Namespace) -> int:
    knob = select_proposal(args.parent)
    if knob is None:
        print("proposer: knob library exhausted for parent "
              f"{args.parent} — every audited candidate already has a variant file.")
        print("Add knobs to KNOB_LIBRARY or promote a new parent, then re-run.")
        return 0

    print(f"=== next proposed candidate: {knob.candidate_id} ===")
    print(f"parent        : {args.parent}")
    print(f"knob          : {knob.key}={knob.value}  (channel: {knob.channel}, priority {knob.priority})")
    print(f"hypothesis    : {knob.hypothesis}")
    print(f"variant file  : references/seed-organism/{knob.variant_filename}")
    print(f"preset file   : presets/{knob.preset_filename}")

    if not args.materialize:
        print("\n(dry run — no files written. Re-run with --materialize to write the candidate.)")
        return 0

    vpath, ppath = materialize(knob, args.parent)
    print(f"\nwrote {rel(vpath)}")
    print(f"wrote {rel(ppath)}")
    print("\nNext steps (privileged / founder-in-loop):")
    print("  1. review the two files above (single reversible sysctl; delegates to parent).")
    print("  2. commit them so daemons can pull the candidate.")
    print("  3. enqueue the screen with the SQL below (service role / migration — anon cannot insert):\n")
    print(enqueue_sql(knob, args.parent, cycle_id=args.cycle, screen_order=args.screen_order))
    return 0


def cmd_list_knobs(args: argparse.Namespace) -> int:
    taken = existing_candidate_ids()
    print("Audited knob library (priority order):")
    for knob in sorted(KNOB_LIBRARY, key=lambda k: k.priority, reverse=True):
        state = "proposed" if knob.candidate_id in taken else "available"
        print(f"  [{state:9}] {knob.candidate_id:22} {knob.key}={knob.value:<10} channel={knob.channel}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Autonomous seed-organism variant proposer (G3).")
    sub = p.add_subparsers(dest="cmd", required=True)

    pr = sub.add_parser("propose", help="select and (optionally) materialize the next candidate")
    pr.add_argument("--parent", default=DEFAULT_PARENT_ID, help="parent variant id (default: v0.12)")
    pr.add_argument("--materialize", action="store_true", help="write the variant.json + preset.sh files")
    pr.add_argument("--cycle", type=int, default=5, help="cycle_id for the enqueue SQL (default: 5)")
    pr.add_argument("--screen-order", default="normal", choices=["normal", "reversed"])
    pr.set_defaults(func=cmd_propose)

    lk = sub.add_parser("list-knobs", help="show the audited knob library and what's already proposed")
    lk.set_defaults(func=cmd_list_knobs)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
