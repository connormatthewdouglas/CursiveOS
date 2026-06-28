#!/usr/bin/env bash
# CursiveOS v0.12b — swappiness tune candidate (memory axis)
#
# Same stack as canonical parent v0.12 (v0.9 + zram + swappiness-aware reclaim)
# but raises vm.swappiness from 60 → 100 to test whether more aggressive swap
# reclaim improves the memory-pressure channel without load-power regression.
#
# Screen only — not promoted unless memory + load-power gates pass on target rig.

set -uo pipefail
ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V11="$SCRIPT_DIR/cursiveos-presets-v0.11-zram-swappiness.sh"
export CURSIVEOS_SWAPPINESS=100

echo "CursiveOS v0.12b (v0.12 stack with swappiness=100)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: v0.9 stack + zram + vm.swappiness=100 (parent v0.12 uses 60)."
    ;;
  --dry-run|--apply-temp|--undo)
    bash "$V11" "$ACTION"
    ;;
  *)
    echo "Unknown option: $ACTION"; exit 1 ;;
esac