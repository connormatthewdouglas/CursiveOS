#!/usr/bin/env bash
# CursiveOS v0.13-vfscache50 candidate — AUTONOMOUSLY PROPOSED by organism_proposer.
#
# = the v0.12 parent stack PLUS one reversible sysctl knob: vm.vfs_cache_pressure=50.
# Primary sensor channel: memory.
#
# Hypothesis (pre-registered): Halving vfs_cache_pressure (100->50) makes the kernel retain dentry/inode cache longer, which can lower cold-start and memory-refault cost on repeated access. Risk: on tight RAM it trades file-cache for metadata cache; the memory + cold-start channels adjudicate.
#
# Safety: exactly one audited sysctl is changed. The prior value is captured on apply
# and restored on undo before delegating the rest of the revert to the parent preset.
# Nothing here is free-form or destructive; fully reversible.

set -uo pipefail
ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT="$SCRIPT_DIR/cursiveos-presets-v0.12.sh"
STATE="$HOME/CursiveOS/preset_state_v0.13-vfscache50.txt"
KEY="vm.vfs_cache_pressure"
VAL="50"

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

echo "CursiveOS Candidate v0.13-vfscache50 (v0.12 stack + $KEY=$VAL)"

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
    echo "OK Applied v0.13-vfscache50 temporarily."
    ;;
  --undo)
    if [[ -f "$STATE" ]]; then
        SAVED="$(cut -d= -f2- < "$STATE")"
        [[ -n "$SAVED" ]] && s sysctl -w "$KEY=$SAVED" >/dev/null 2>&1 && echo "OK $KEY restored to $SAVED"
        rm -f "$STATE"
    fi
    bash "$PARENT" --undo
    echo "OK v0.13-vfscache50 reverted (sysctl + v0.12 stack)."
    ;;
  *) echo "Unknown option: $ACTION"; exit 1 ;;
esac
