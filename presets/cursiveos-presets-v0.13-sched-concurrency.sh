#!/usr/bin/env bash
# CursiveOS v0.13 candidate — scheduler-aggressive stack for parallel inference.
#
# = v0.12 parent stack PLUS tighter CFS granularity and higher sched_util_clamp_min.
# Rationale: concurrency sensor H3 showed 0% delta for memory-class presets (v0.8 vs
# v0.12); scheduler knobs may only move aggregate tok/s under N parallel streams.
#
# Knobs (on top of v0.12 / v0.8 baseline):
#   sched_util_clamp_min: 128 -> 256 (faster freq floor under bursty parallel load)
#   sched_min_granularity_ns: 1ms -> 0.5ms
#   sched_wakeup_granularity_ns: 1.5ms -> 0.75ms
#
# Fully reversible via saved sysctl state + v0.12 --undo.

set -uo pipefail
ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V12="$SCRIPT_DIR/cursiveos-presets-v0.12.sh"
STATE="$HOME/CursiveOS/preset_state_v0.13_sched.txt"

s() { sudo "$@" 2>/dev/null; }

echo "CursiveOS Candidate v0.13 (v0.12 + aggressive scheduler for concurrency)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: v0.12 parent plus sched_util_clamp_min=256, min/wakeup granularity tightened."
    ;;
  --dry-run)
    bash "$V12" --dry-run
    echo "  + sched_util_clamp_min: 256 (parent uses 128)"
    echo "  + sched_min_granularity_ns: 500000"
    echo "  + sched_wakeup_granularity_ns: 750000"
    ;;
  --apply-temp)
    : >"$STATE"
    echo "sched_util_clamp_min: $(sysctl -n kernel.sched_util_clamp_min 2>/dev/null || echo N/A)" >>"$STATE"
    echo "sched_min_granularity_ns: $(sysctl -n kernel.sched_min_granularity_ns 2>/dev/null || echo N/A)" >>"$STATE"
    echo "sched_wakeup_granularity_ns: $(sysctl -n kernel.sched_wakeup_granularity_ns 2>/dev/null || echo N/A)" >>"$STATE"

    bash "$V12" --apply-temp

    s sysctl -w kernel.sched_util_clamp_min=256 \
        && echo "OK sched_util_clamp_min=256" \
        || echo "WARN sched_util_clamp_min not available"
    s sysctl -w kernel.sched_min_granularity_ns=500000 \
        && echo "OK sched_min_granularity_ns=500000" \
        || echo "WARN sched_min_granularity_ns not available"
    s sysctl -w kernel.sched_wakeup_granularity_ns=750000 \
        && echo "OK sched_wakeup_granularity_ns=750000" \
        || echo "WARN sched_wakeup_granularity_ns not available"
    ;;
  --undo)
    bash "$V12" --undo 2>/dev/null || true
    if [[ -f "$STATE" ]]; then
      get_val() { grep "^${1}:" "$STATE" | cut -d: -f2- | xargs; }
      SUCM=$(get_val sched_util_clamp_min)
      SGN=$(get_val sched_min_granularity_ns)
      SWG=$(get_val sched_wakeup_granularity_ns)
      [[ -n "$SUCM" && "$SUCM" != "N/A" ]] && s sysctl -w kernel.sched_util_clamp_min="$SUCM" || true
      [[ -n "$SGN" && "$SGN" != "N/A" ]] && s sysctl -w kernel.sched_min_granularity_ns="$SGN" || true
      [[ -n "$SWG" && "$SWG" != "N/A" ]] && s sysctl -w kernel.sched_wakeup_granularity_ns="$SWG" || true
      rm -f "$STATE"
    fi
    echo "OK v0.13 scheduler knobs reverted."
    ;;
  *)
    echo "Unknown option: $ACTION"; exit 1 ;;
esac