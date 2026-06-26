#!/usr/bin/env bash
# CursiveOS v0.12 — canonical parent preset
#
# Lineage: v0.9 (cycle 1 accept) -> v0.11-zram-swappiness (cycle 3 accept) -> v0.12.
# v0.12 is the promoted, settled form of accepted candidate v0.11-zram-swappiness:
# v0.9 stack + zram swap + vm.swappiness=60 (swappiness-aware memory win).
#
# Evidence for promotion (cycle 3, harness v1.4.5, 2026-06-26):
#   - Three confirming screens: Stardust normal +0.0954, laptop cross-machine
#     +0.1004, Stardust reversed +0.0947 -> confidence 0.875, accepted.
#   - Memory channel +75.4%; cold-start -0.5%, sustained 0.0% (no inference regression).
#   - First variant selected by the memory-pressure channel.
#
# Implementation: delegates entirely to v0.11-zram-swappiness.sh (same knobs).

set -uo pipefail
ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V11="$SCRIPT_DIR/cursiveos-presets-v0.11-zram-swappiness.sh"

echo "CursiveOS v0.12 (canonical parent: v0.11 swappiness-aware zram stack)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: canonical parent = v0.9 stack + zram + swappiness=60 (delegates to v0.11)."
    ;;
  --dry-run|--apply-temp|--undo)
    bash "$V11" "$ACTION"
    ;;
  *)
    echo "Unknown option: $ACTION"; exit 1 ;;
esac