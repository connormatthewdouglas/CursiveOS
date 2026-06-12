#!/usr/bin/env bash
# CursiveOS v0.9c-cpu-retained candidate
#
# Hypothesis (from the 2026-06-12 v0.9b screen): the -51% Arc cold-start win
# is CPU-side (governor/C-state/EPP), not GPU-frequency-side — v0.9b kept the
# GPU pin (verified active at 2000MHz via phase telemetry) and got no
# cold-start improvement. v0.9c is therefore v0.8 WITHOUT the GPU frequency
# tweaks: full network + CPU tuning, GPU left at driver defaults. If the
# cold-start win survives, the GPU pin can be dropped from the lineage.
#
# Implementation: applies the canonical v0.8 preset, then immediately restores
# the GPU frequency controls to their pre-apply values. Undo delegates to the
# v0.8 preset's own state file, which restores everything.

set -uo pipefail

ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V08="$SCRIPT_DIR/cursiveos-presets-v0.8.sh"

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
fi
export TAO_SUDO_PASS
sc() { echo "$TAO_SUDO_PASS" | sudo -S bash -c "$1" 2>/dev/null; }

GPU_GT=""
for card in /sys/class/drm/card*/gt/gt0; do
    [[ -f "$card/rps_min_freq_mhz" ]] && { GPU_GT="$card"; break; }
done

echo "CursiveOS Candidate v0.9c-cpu-retained (v0.8 minus GPU frequency tweaks)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: full v0.8 stack with GPU frequency controls left at driver defaults."
    ;;
  --dry-run)
    bash "$V08" --dry-run
    [[ -n "$GPU_GT" ]] && echo "  (v0.9c: GPU SLPC/min/boost changes will be reverted immediately after apply)"
    ;;
  --apply-temp)
    # Capture GPU state before v0.8 touches it
    if [[ -n "$GPU_GT" ]]; then
        G_MIN=$(cat "$GPU_GT/rps_min_freq_mhz" 2>/dev/null || echo "")
        G_BOOST=$(cat "$GPU_GT/rps_boost_freq_mhz" 2>/dev/null || echo "")
        G_SLPC=$(cat "$GPU_GT/slpc_ignore_eff_freq" 2>/dev/null || echo "")
    fi
    bash "$V08" --apply-temp
    if [[ -n "$GPU_GT" ]]; then
        [[ -n "$G_MIN"   ]] && sc "echo $G_MIN > $GPU_GT/rps_min_freq_mhz"   || true
        [[ -n "$G_BOOST" ]] && sc "echo $G_BOOST > $GPU_GT/rps_boost_freq_mhz" || true
        [[ -n "$G_SLPC"  ]] && sc "echo $G_SLPC > $GPU_GT/slpc_ignore_eff_freq" || true
        echo "OK v0.9c: GPU frequency controls restored to pre-apply values (min=$G_MIN boost=$G_BOOST slpc=$G_SLPC)"
    fi
    echo "OK Applied v0.9c-cpu-retained temporarily."
    ;;
  --undo)
    bash "$V08" --undo
    echo "OK v0.9c undo delegated to v0.8 state restore."
    ;;
  *)
    echo "Unknown option: $ACTION"; exit 1 ;;
esac
