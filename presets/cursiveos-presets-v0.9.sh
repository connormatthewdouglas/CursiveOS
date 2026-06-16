#!/usr/bin/env bash
# CursiveOS v0.9 — canonical parent preset
#
# Lineage: v0.8 (genesis) -> v0.9 (accepted 2026-06-16).
# v0.9 is the accepted, promoted form of the v0.9c-cpu-retained candidate:
# the full v0.8 network + CPU tuning with the Arc GPU frequency pin REMOVED.
#
# Evidence for promotion (CursiveResearch Chapter 16 §5):
#   - v0.9b (GPU pin only, verified active at 2000MHz) gave ~0% cold-start gain.
#   - v0.9c (v0.8 minus the GPU pin) retained the full -51% cold-start win on
#     the Arc desktop, both run orders, with equivalent network and package
#     power — i.e. the GPU pin was dead weight.
# Dropping it removes an invasive knob and its unmeasured GPU-side power cost
# at no measured performance loss. Promoted to the parent baseline.
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

echo "CursiveOS v0.9 (canonical parent: v0.8 stack, GPU frequency pin removed)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: full v0.8 network + CPU stack with GPU frequency controls left at driver defaults."
    ;;
  --dry-run)
    bash "$V08" --dry-run
    [[ -n "$GPU_GT" ]] && echo "  (v0.9: GPU SLPC/min/boost changes will be reverted immediately after apply)"
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
        echo "OK v0.9: GPU frequency controls restored to pre-apply values (min=$G_MIN boost=$G_BOOST slpc=$G_SLPC)"
    fi
    echo "OK Applied v0.9 temporarily."
    ;;
  --undo)
    bash "$V08" --undo
    echo "OK v0.9 undo delegated to v0.8 state restore."
    ;;
  *)
    echo "Unknown option: $ACTION"; exit 1 ;;
esac
