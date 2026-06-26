#!/usr/bin/env bash
# CursiveOS v0.11 candidate (cycle 3) — swappiness-aware zram.
#
# = the v0.9 parent stack PLUS a compressed-RAM (zram) swap device PLUS raising
# vm.swappiness from v0.9's 0 back to 60. Rationale: cycle-3 measurement showed
# zram alone (v0.10) does NOTHING under memory pressure because v0.9 pins
# swappiness=0, so the kernel refuses to push pages to swap and the workload
# throttles to a standstill (capped) whether zram is present or not. zram only
# pays off when the kernel is actually allowed to swap. v0.11 re-enables swapping
# so reclaim lands in fast compressed RAM instead of stalling.
#
# TRADEOFF (the organism will measure it): v0.9 set swappiness=0 to keep model
# weights resident for inference. Raising it could let weights swap to zram.
# That is exactly why this is screened on all channels — cold-start/sustained
# catch any inference regression; the memory channel catches the pressure win.
#
# Fully reversible: removes the zram device it created, then delegates to the
# v0.9 preset's own undo (which restores the original swappiness it saved).

set -uo pipefail
ACTION="${1:---help}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V09="$SCRIPT_DIR/cursiveos-presets-v0.9.sh"
STATE="$HOME/CursiveOS/preset_state_zram_swappiness.txt"

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
fi
export TAO_SUDO_PASS
s() { echo "$TAO_SUDO_PASS" | sudo -S "$@" 2>/dev/null; }

ZRAM_SIZE="${CURSIVEOS_ZRAM_SIZE:-4G}"
SWAPPINESS="${CURSIVEOS_SWAPPINESS:-60}"

echo "CursiveOS Candidate v0.11 (v0.9 stack + ${ZRAM_SIZE} zram + swappiness=${SWAPPINESS})"

case "$ACTION" in
  --help)
    echo "Usage: $0 --apply-temp | --undo | --dry-run"
    echo "Scope: v0.9 parent stack plus a ${ZRAM_SIZE} zram swap device and vm.swappiness=${SWAPPINESS}."
    ;;
  --dry-run)
    bash "$V09" --dry-run
    echo "  + zram: create a ${ZRAM_SIZE} compressed swap device (zstd/lz4), swapon priority 100"
    echo "  + vm.swappiness: ${SWAPPINESS} (v0.9 pins 0; raise so reclaim reaches zram)"
    ;;
  --apply-temp)
    bash "$V09" --apply-temp
    # Re-enable swapping so the zram device is actually used under pressure.
    s sysctl -w vm.swappiness="$SWAPPINESS" >/dev/null 2>&1 \
        && echo "OK vm.swappiness=${SWAPPINESS}" || echo "  swappiness set failed"
    s modprobe zram >/dev/null 2>&1 || true
    DEV=""
    if command -v zramctl >/dev/null 2>&1; then
        DEV=$(s zramctl --find --size "$ZRAM_SIZE" --algorithm zstd 2>/dev/null \
              || s zramctl --find --size "$ZRAM_SIZE" 2>/dev/null || true)
    fi
    if [[ -z "$DEV" ]]; then
        echo "  zram unavailable on this host — skipping zram (v0.9 stack + swappiness still applied)"; exit 0
    fi
    s mkswap "$DEV" >/dev/null 2>&1
    if s swapon -p 100 "$DEV" >/dev/null 2>&1; then
        echo "$DEV" > "$STATE"
        echo "OK zram swap active on $DEV (${ZRAM_SIZE}, priority 100)"
    else
        s zramctl --reset "$DEV" >/dev/null 2>&1 || true
        echo "  zram swapon failed — reverted zram (v0.9 stack + swappiness still applied)"
    fi
    echo "OK Applied v0.11 temporarily."
    ;;
  --undo)
    if [[ -f "$STATE" ]]; then
        DEV=$(cat "$STATE")
        [[ -n "$DEV" ]] && s swapoff "$DEV" >/dev/null 2>&1 || true
        [[ -n "$DEV" ]] && s zramctl --reset "$DEV" >/dev/null 2>&1 || true
        rm -f "$STATE"
        echo "OK zram device removed."
    fi
    # v0.9 undo restores the original swappiness it saved before pinning 0.
    bash "$V09" --undo
    echo "OK v0.11 reverted (zram + swappiness + v0.9 stack)."
    ;;
  *) echo "Unknown option: $ACTION"; exit 1 ;;
esac
