#!/usr/bin/env bash
# CursiveOS v0.13-pagecluster0 candidate — AUTONOMOUSLY PROPOSED by organism_proposer.
#
# = the v0.12 parent stack PLUS one reversible sysctl knob: vm.page-cluster=0.
# Primary sensor channel: memory.
#
# Hypothesis (pre-registered): With a zram swap device (present in v0.12), vm.page-cluster=0 faults a single page per swap-in instead of a 8-page cluster, cutting wasted decompression under memory pressure. Expect the memory-pressure refault channel to improve vs v0.12 with no inference regression; other channels neutral.
#
# Safety: exactly one audited sysctl is changed. The prior value is captured on apply
# and restored on undo before delegating the rest of the revert to the parent preset.
# Nothing here is free-form or destructive; fully reversible.

set -uo pipefail
ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT="$SCRIPT_DIR/cursiveos-presets-v0.12.sh"
STATE="$HOME/CursiveOS/preset_state_v0.13-pagecluster0.txt"
KEY="vm.page-cluster"
VAL="0"

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    # non-interactive sudo if already granted; otherwise prompt once.
    if ! sudo -n true 2>/dev/null; then
        read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
    fi
fi
export TAO_SUDO_PASS
s() {
    if [[ -n "${TAO_SUDO_PASS:-}" ]]; then echo "$TAO_SUDO_PASS" | sudo -S "$@" 2>/dev/null;
    else sudo -n "$@" 2>/dev/null; fi
}

echo "CursiveOS Candidate v0.13-pagecluster0 (v0.12 stack + $KEY=$VAL)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: v0.12 parent stack plus reversible sysctl $KEY=$VAL."
    ;;
  --dry-run)
    bash "$PARENT" --dry-run
    echo "  + sysctl: $KEY=$VAL (channel memory; prior value captured for undo)"
    ;;
  --apply-temp)
    bash "$PARENT" --apply-temp
    OLD="$(s sysctl -n "$KEY" 2>/dev/null || sysctl -n "$KEY" 2>/dev/null || true)"
    if [[ -n "$OLD" ]]; then
        mkdir -p "$(dirname "$STATE")"
        echo "$KEY=$OLD" > "$STATE"
    fi
    if s sysctl -w "$KEY=$VAL" >/dev/null 2>&1; then
        echo "OK $KEY set to $VAL (was ${OLD:-unknown})"
    else
        echo "  sysctl set failed for $KEY — parent stack still applied"
    fi
    echo "OK Applied v0.13-pagecluster0 temporarily."
    ;;
  --undo)
    if [[ -f "$STATE" ]]; then
        SAVED="$(cut -d= -f2- < "$STATE")"
        [[ -n "$SAVED" ]] && s sysctl -w "$KEY=$SAVED" >/dev/null 2>&1 && echo "OK $KEY restored to $SAVED"
        rm -f "$STATE"
    fi
    bash "$PARENT" --undo
    echo "OK v0.13-pagecluster0 reverted (sysctl + v0.12 stack)."
    ;;
  *) echo "Unknown option: $ACTION"; exit 1 ;;
esac
