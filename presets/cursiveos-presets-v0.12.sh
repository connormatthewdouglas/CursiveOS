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

force_stock_network() {
    # sysctl is not on the user PATH, and the v0.8 backup is often empty, so
    # --undo must not trust the saved snapshot. Exit on the canonical reference.
    local SYSCTL="/usr/sbin/sysctl"
    [[ -x "$SYSCTL" ]] || SYSCTL="sysctl"
    sudo -n "$SYSCTL" -w net.ipv4.tcp_congestion_control=cubic >/dev/null
    sudo -n "$SYSCTL" -w net.core.default_qdisc=pfifo_fast >/dev/null
    sudo -n "$SYSCTL" -w net.ipv4.tcp_slow_start_after_idle=1 >/dev/null
    sudo -n "$SYSCTL" -w net.core.rmem_max=212992 >/dev/null
    sudo -n "$SYSCTL" -w net.core.wmem_max=212992 >/dev/null
    sudo -n "$SYSCTL" -w net.ipv4.tcp_rmem="4096 87380 6291456" >/dev/null
    sudo -n "$SYSCTL" -w net.ipv4.tcp_wmem="4096 16384 4194304" >/dev/null
}
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
    if [[ "$ACTION" == "--undo" ]]; then
        force_stock_network
    fi
    bash "$V11" "$ACTION" </dev/null
    if [[ "$ACTION" == "--undo" ]]; then
        force_stock_network
        echo "stock network: $(/usr/sbin/sysctl -n net.ipv4.tcp_congestion_control) $(/usr/sbin/sysctl -n net.core.default_qdisc) rmem=$(/usr/sbin/sysctl -n net.core.rmem_max)"
    fi
    ;;
  *)
    echo "Unknown option: $ACTION"; exit 1 ;;
esac