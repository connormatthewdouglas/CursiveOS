#!/usr/bin/env bash
# CursiveOS benchmark-network-v0.1.sh
# Measures TCP throughput and latency under simulated WAN conditions.
#
# WHY THIS MATTERS FOR MINING:
#   Bittensor validators/miners communicate over the internet.
#   - BBR congestion control sustains higher throughput than CUBIC on lossy links
#   - 16MB socket buffers prevent drops during burst traffic (chain sync, weight pushes)
#   - tcp_slow_start_after_idle disabled: throughput doesn't drop after mining idle periods
#
# METHOD:
#   Uses tc netem on loopback to simulate WAN: 50ms RTT + 0.5% packet loss.
#   (50ms is typical inter-datacenter RTT; 0.5% loss is moderate internet conditions.)
#   Runs iperf3 client→server through this simulated link.
#   Paired: baseline (no presets) → tuned (BBR + buffers), same session.
#   Cleans up netem rules on exit.
#
# Usage: ./benchmark-network-v0.1.sh [preset-script]

set -euo pipefail

PRESET_SCRIPT="${1:-../presets/cursiveos-presets-v0.7.sh}"
if [[ -z "${TAO_SUDO_PASS:-}" ]] && ! sudo -n true 2>/dev/null; then
    read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
fi
TAO_SUDO_PASS="${TAO_SUDO_PASS:-}"
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null; }
sc() { echo "$SP" | sudo -S bash -c "$1" 2>/dev/null; }

DURATION=10      # iperf3 test duration per run (seconds)
RUNS=5           # runs per pass (averaged — more runs smooths CUBIC variance)
WAN_DELAY="25ms" # one-way delay → 50ms RTT
WAN_LOSS="0.5%"  # packet loss rate
IPERF_PORT=15201

TC=""
for c in /sbin/tc /usr/sbin/tc; do
    [[ -x "$c" ]] && TC="$c" && break
done
if [[ -z "$TC" ]]; then
    echo "tc missing. Refusing to print a network delta." >&2
    exit 1
fi
if ! command -v iperf3 >/dev/null 2>&1; then
    echo "iperf3 required. Refusing to print a network delta." >&2
    exit 1
fi

LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cursiveos-network-$(date +%Y%m%d-%H%M%S).log"
PASS_RESULT=""
ORIGINAL_NET_STATE="$(mktemp)"

log() { echo "$1" | tee -a "$LOG_FILE"; }

# ── Cleanup trap ──────────────────────────────────────────────
save_original_network() {
    local key
    for key in \
        net.ipv4.tcp_congestion_control net.core.default_qdisc \
        net.ipv4.tcp_slow_start_after_idle net.ipv4.tcp_tw_reuse \
        net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem \
        net.ipv4.tcp_wmem net.core.netdev_max_backlog net.core.somaxconn; do
        printf '%s|%s\n' "$key" "$(sysctl -n "$key" 2>/dev/null || echo N/A)" >> "$ORIGINAL_NET_STATE"
    done
}

restore_original_network() {
    local key value
    [[ -f "$ORIGINAL_NET_STATE" ]] || return
    while IFS='|' read -r key value; do
        [[ -z "$key" || "$value" == "N/A" ]] && continue
        echo "$SP" | sudo -S sysctl -w "$key=$value" >/dev/null 2>&1 || true
    done < "$ORIGINAL_NET_STATE"
    rm -f "$ORIGINAL_NET_STATE"
}

cleanup() {
    bash "$PRESET_SCRIPT" --undo >/dev/null 2>&1 || true
    sc "tc qdisc del dev lo root 2>/dev/null || true"
    pkill -f "iperf3 -s" 2>/dev/null || true
    restore_original_network
    force_stock_network || true
}
force_stock_network() {
    sudo -n /usr/sbin/sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
    sudo -n /usr/sbin/sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null
    sudo -n /usr/sbin/sysctl -w net.ipv4.tcp_slow_start_after_idle=1 >/dev/null
    sudo -n /usr/sbin/sysctl -w net.core.rmem_max=212992 >/dev/null
    sudo -n /usr/sbin/sysctl -w net.core.wmem_max=212992 >/dev/null
    sudo -n /usr/sbin/sysctl -w net.ipv4.tcp_rmem="4096 87380 6291456" >/dev/null
    sudo -n /usr/sbin/sysctl -w net.ipv4.tcp_wmem="4096 16384 4194304" >/dev/null
}
trap cleanup EXIT
