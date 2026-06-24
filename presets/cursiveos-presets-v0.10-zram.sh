#!/usr/bin/env bash
# CursiveOS v0.10-zram candidate (cycle 2 — first NEW genetic material)
#
# = the v0.9 parent stack PLUS a compressed-RAM (zram) swap device. Rationale:
# on RAM-constrained machines, zram trades a little CPU for effective memory,
# reducing pressure and disk swapping. This is the organism's first ADDED
# optimization (not a v0.8 subset).
#
# HONEST SCOPE: the current benchmark suite does not stress memory, so this
# screen mainly verifies zram applies + reverts cleanly and does not regress
# cold-start/network/power. Proving zram's actual benefit needs a
# memory-pressure sensor (next on the roadmap).
#
# Fully reversible: removes only the zram device it created, then delegates to
# the v0.9 preset's own undo.

set -uo pipefail
ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V09="$SCRIPT_DIR/cursiveos-presets-v0.9.sh"
STATE="$HOME/CursiveOS/preset_state_zram.txt"

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
fi
export TAO_SUDO_PASS
s() { echo "$TAO_SUDO_PASS" | sudo -S "$@" 2>/dev/null; }

ZRAM_SIZE="${CURSIVEOS_ZRAM_SIZE:-4G}"

echo "CursiveOS Candidate v0.10-zram (v0.9 stack + ${ZRAM_SIZE} zram swap)"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: v0.9 parent stack plus a ${ZRAM_SIZE} compressed-RAM swap device."
    ;;
  --dry-run)
    bash "$V09" --dry-run
    echo "  + zram: create a ${ZRAM_SIZE} compressed swap device (zstd/lz4), swapon priority 100"
    ;;
  --apply-temp)
    bash "$V09" --apply-temp
    s modprobe zram >/dev/null 2>&1 || true
    DEV=""
    if command -v zramctl >/dev/null 2>&1; then
        DEV=$(s zramctl --find --size "$ZRAM_SIZE" --algorithm zstd 2>/dev/null \
              || s zramctl --find --size "$ZRAM_SIZE" 2>/dev/null || true)
    fi
    if [[ -z "$DEV" ]]; then
        echo "  zram unavailable on this host — skipping (v0.9 stack still applied)"; exit 0
    fi
    s mkswap "$DEV" >/dev/null 2>&1
    if s swapon -p 100 "$DEV" >/dev/null 2>&1; then
        echo "$DEV" > "$STATE"
        echo "OK zram swap active on $DEV (${ZRAM_SIZE})"
    else
        s zramctl --reset "$DEV" >/dev/null 2>&1 || true
        echo "  zram swapon failed — reverted zram (v0.9 stack still applied)"
    fi
    echo "OK Applied v0.10-zram temporarily."
    ;;
  --undo)
    if [[ -f "$STATE" ]]; then
        DEV=$(cat "$STATE")
        [[ -n "$DEV" ]] && s swapoff "$DEV" >/dev/null 2>&1 || true
        [[ -n "$DEV" ]] && s zramctl --reset "$DEV" >/dev/null 2>&1 || true
        rm -f "$STATE"
        echo "OK zram device removed."
    fi
    bash "$V09" --undo
    echo "OK v0.10-zram reverted (zram + v0.9 stack)."
    ;;
  *) echo "Unknown option: $ACTION"; exit 1 ;;
esac
