#!/usr/bin/env bash
# setup-stardust.sh — Pre-run setup for Stardust (AMD FX-8350 + RX 580)
# Loads amd_energy kernel module so power readings are attempted on every run.
#
# Note: amd_energy targets Zen architecture (Ryzen/EPYC). FX-8350 is Piledriver
# (pre-Zen) and may not expose RAPL counters — power field will land as null.
# Load attempt is still correct: the wrapper falls back gracefully to N/A.
#
# Usage: ./setup-stardust.sh  (prompts for sudo)
#   OR:  TAO_SUDO_PASS=<pin> ./setup-stardust.sh

set -euo pipefail

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[setup-stardust] sudo password: " TAO_SUDO_PASS && echo
fi
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS

echo "=== Stardust Pre-Run Setup ==="
echo "Machine: AMD FX-8350 + RX 580"
echo ""

# ── Load amd_energy for RAPL power reading ────────────────────────────────────
echo "Loading amd_energy module..."
if echo "$SP" | sudo -S modprobe amd_energy 2>/dev/null; then
    echo "  ✓ amd_energy loaded"
else
    echo "  ✗ amd_energy not available (expected on pre-Zen hardware)"
fi

# ── Verify powercap sysfs path ────────────────────────────────────────────────
RAPL_PATH=$(ls /sys/devices/virtual/powercap/*/energy_uj 2>/dev/null | head -1 || true)
if [[ -n "$RAPL_PATH" ]]; then
    echo "  ✓ Power path: $RAPL_PATH"
    E1=$(echo "$SP" | sudo -S cat "$RAPL_PATH" 2>/dev/null || true)
    sleep 1
    E2=$(echo "$SP" | sudo -S cat "$RAPL_PATH" 2>/dev/null || true)
    if [[ -n "$E1" && -n "$E2" && "$E1" =~ ^[0-9]+$ && "$E2" =~ ^[0-9]+$ ]]; then
        WATTS=$(python3 -c "print(f'{($E2-$E1)/1_000_000:.1f}W')" 2>/dev/null || echo "?")
        echo "  ✓ Power reading: ~${WATTS} (sanity check)"
    else
        echo "  ✗ Power read returned empty — power fields will be null in this run"
    fi
else
    echo "  ✗ No powercap path found — power fields will be null in this run"
fi

echo ""

# ── Confirm ollama is running ─────────────────────────────────────────────────
if systemctl is-active --quiet ollama 2>/dev/null; then
    echo "  ✓ ollama running"
else
    echo "  Starting ollama..."
    echo "$SP" | sudo -S systemctl start ollama 2>/dev/null && sleep 3 && echo "  ✓ ollama started" || echo "  ✗ ollama start failed"
fi

echo ""
echo "Setup complete. Run: ./cursiveos-full-test-v1.4.sh"
