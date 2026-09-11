#!/usr/bin/env bash
# CursiveOS v0.13-notsentlowat16k candidate — AUTONOMOUSLY PROPOSED by organism_proposer.
#
# = the v0.12 parent stack PLUS one reversible sysctl knob: net.ipv4.tcp_notsent_lowat=16384.
# Primary sensor channel: network.
#
# Hypothesis (pre-registered): Capping unsent bytes (tcp_notsent_lowat=16384) lowers head-of-line latency on the network path. Network is gate-only in fitness, so this is expected to read neutral for scoring and is proposed mainly to map the axis.
#
# Safety: exactly one audited sysctl is changed. The prior value is captured on apply
# and restored on undo before delegating the rest of the revert to the parent preset.
# Nothing here is free-form or destructive; fully reversible.

set -uo pipefail
ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT="$SCRIPT_DIR/cursiveos-presets-v0.12.sh"
STATE="$HOME/CursiveOS/preset_state_v0.13-notsentlowat16k.txt"
KEY="net.ipv4.tcp_notsent_lowat"
VAL="16384"

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

echo "CursiveOS Candidate v0.13-notsentlowat16k (v0.12 stack + $KEY=$VAL)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: v0.12 parent stack plus reversible sysctl $KEY=$VAL."
    ;;
  --dry-run)
    bash "$PARENT" --dry-run
    echo "  + sysctl: $KEY=$VAL (channel network; prior value captured for undo)"
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
    echo "OK Applied v0.13-notsentlowat16k temporarily."
    ;;
  --undo)
    if [[ -f "$STATE" ]]; then
        SAVED="$(cut -d= -f2- < "$STATE")"
        [[ -n "$SAVED" ]] && s sysctl -w "$KEY=$SAVED" >/dev/null 2>&1 && echo "OK $KEY restored to $SAVED"
        rm -f "$STATE"
    fi
    bash "$PARENT" --undo
    echo "OK v0.13-notsentlowat16k reverted (sysctl + v0.12 stack)."
    ;;
  *) echo "Unknown option: $ACTION"; exit 1 ;;
esac
