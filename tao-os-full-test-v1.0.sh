#!/usr/bin/env bash
# TAO-OS Full Test v1.0
# Single command for Bittensor miners to measure their system's baseline
# and the impact of TAO-OS performance presets.
#
# Runs three paired benchmarks (baseline → presets → baseline restored):
#   1. Network throughput  — BBR vs CUBIC on simulated WAN (50ms RTT, 0.5% loss)
#   2. Inference cold-start — model load + TTFT with GPU freq pinned vs idle
#   3. Inference sustained  — steady-state tok/s (GPU-bound baseline)
#
# Requirements: ollama installed, tinyllama pulled (ollama pull tinyllama)
# Usage: ./tao-os-full-test-v1.0.sh
#
# All changes are TEMPORARY. Presets revert after each test.
# Logs saved to ~/TAO-OS/logs/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET="$SCRIPT_DIR/tao-os-presets-v0.5.sh"
MODEL="tinyllama"

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
SUMMARY_LOG="$LOG_DIR/tao-os-full-test-$(date +%Y%m%d-%H%M%S).log"

# ── Sudo prompt (once — exported so child scripts skip re-prompting) ──────────
if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[TAO-OS] sudo password: " TAO_SUDO_PASS && echo
fi
export TAO_SUDO_PASS

# ── Preflight checks ──────────────────────────────────────────────────────────
echo ""
echo "TAO-OS Full Test v1.0"
echo "======================================"

if [[ ! -f "$PRESET" ]]; then
    echo "ERROR: preset script not found: $PRESET"
    exit 1
fi

if ! command -v ollama &>/dev/null; then
    echo "ERROR: ollama not installed. Run ./setup-intel-arc.sh first."
    exit 1
fi

if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo "Pulling $MODEL..."
    ollama pull "$MODEL"
fi

if ! command -v iperf3 &>/dev/null; then
    echo "Installing iperf3..."
    echo "$TAO_SUDO_PASS" | sudo -S apt-get install -y iperf3 -qq 2>/dev/null
fi

echo "Hardware:"
echo "  CPU: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)"
echo "  GPU: $(lspci 2>/dev/null | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'N/A')"
echo "  Kernel: $(uname -r)"
echo "  Date: $(date)"
echo ""
echo "Running 3 benchmarks. Total time: ~10 minutes."
echo "All presets are TEMPORARY — reverted after each test."
echo "======================================"

# ── Capture key metrics from child benchmark logs ─────────────────────────────
# Each benchmark writes its own log. We read the result line at the end.

NET_BASELINE=""
NET_TUNED=""
NET_DELTA=""
COLD_BASELINE=""
COLD_TUNED=""
COLD_DELTA=""
WARM_BASELINE=""
WARM_TUNED=""
WARM_DELTA=""

extract_network() {
    local log="$1"
    NET_BASELINE=$(grep "Baseline (CUBIC):" "$log" | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "?")
    NET_TUNED=$(grep "Tuned (BBR):" "$log"         | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "?")
    NET_DELTA=$(grep "Delta:" "$log"               | grep -oP '[+\-]?[0-9]+\.[0-9]+' | head -1 || echo "?")
}

extract_coldstart() {
    local log="$1"
    COLD_BASELINE=$(grep "Baseline latency:" "$log" | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "?")
    COLD_TUNED=$(grep "Tuned latency:" "$log"       | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "?")
    COLD_DELTA=$(grep "Delta:" "$log"               | grep -oP '[+\-]?[0-9]+\.[0-9]+' | head -1 || echo "?")
}

extract_sustained() {
    local log="$1"
    WARM_BASELINE=$(grep "Baseline:" "$log" | grep -oP '[0-9]+\.[0-9]+ tok/s' | head -1 || echo "?")
    WARM_TUNED=$(grep "Tuned:" "$log"       | grep -oP '[0-9]+\.[0-9]+ tok/s' | head -1 || echo "?")
    WARM_DELTA=$(grep "Delta:" "$log"       | grep -oP '[+\-]?[0-9]*\.[0-9]+%' | head -1 || echo "?")
}

# ── Benchmark 1: Network ──────────────────────────────────────────────────────
echo ""
echo "[1/3] Network throughput benchmark (BBR vs CUBIC, WAN simulation)..."
NET_LOG=$(ls -t "$LOG_DIR"/tao-os-network-*.log 2>/dev/null | head -1 || true)
bash "$SCRIPT_DIR/benchmark-network-v0.1.sh" "$PRESET" 2>&1
NET_LOG_NEW=$(ls -t "$LOG_DIR"/tao-os-network-*.log 2>/dev/null | head -1)
extract_network "$NET_LOG_NEW"
echo "  → Network done."

# ── Benchmark 2: Cold-start latency ──────────────────────────────────────────
echo ""
echo "[2/3] Cold-start latency benchmark (GPU freq: idle vs pinned)..."
bash "$SCRIPT_DIR/benchmark-inference-v0.2.sh" "$PRESET" "$MODEL" 2>&1
COLD_LOG=$(ls -t "$LOG_DIR"/tao-os-coldstart-*.log 2>/dev/null | head -1)
extract_coldstart "$COLD_LOG"
echo "  → Cold-start done."

# ── Benchmark 3: Sustained inference ─────────────────────────────────────────
echo ""
echo "[3/3] Sustained inference benchmark (steady-state tok/s)..."
bash "$SCRIPT_DIR/benchmark-inference-v0.1.sh" "$PRESET" "$MODEL" 2>&1
WARM_LOG=$(ls -t "$LOG_DIR"/tao-os-inference-*.log 2>/dev/null | head -1)
extract_sustained "$WARM_LOG"
echo "  → Sustained inference done."

# ── Summary table ─────────────────────────────────────────────────────────────
SUMMARY=$(cat <<EOF

======================================================
TAO-OS FULL TEST RESULTS — $(date +%Y-%m-%d)
======================================================
Hardware: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)
          $(lspci 2>/dev/null | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'GPU: N/A')

Benchmark              Baseline          Tuned             Delta
------------------------------------------------------
Network throughput     ${NET_BASELINE} Mbit/s      ${NET_TUNED} Mbit/s      ${NET_DELTA}%
Cold-start latency     ${COLD_BASELINE}ms           ${COLD_TUNED}ms            ${COLD_DELTA}%
Sustained inference    ${WARM_BASELINE}     ${WARM_TUNED}   ${WARM_DELTA}

Note: Presets reverted — system is back to defaults.
Logs: $LOG_DIR/
======================================================
EOF
)

echo "$SUMMARY"
echo "$SUMMARY" >> "$SUMMARY_LOG"
echo ""
echo "Full summary saved: $SUMMARY_LOG"
echo ""
echo "If these results are useful, share your logs:"
echo "  https://github.com/connormatthewdouglas/TAO-OS"
