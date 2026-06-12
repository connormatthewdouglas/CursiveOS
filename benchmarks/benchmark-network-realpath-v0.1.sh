#!/usr/bin/env bash
# Real-path network A/B: CUBIC vs BBR over an actual network path.
#
# Purpose (CursiveResearch Chapter 16): bound how much of the loopback-netem
# +500-900% signal transfers to a real path. Loopback emulation never touches
# a NIC; this test does.
#
# Setup: on a SECOND machine run:  iperf3 -s
# Then on the test machine:        ./benchmark-network-realpath-v0.1.sh <server-ip> [passes]
#
# Each side runs N passes (default 5) of 10s iperf3 with CUBIC, then with BBR.
# Only the congestion control is switched; nothing else changes. Settings are
# restored at the end. Results are printed and saved to logs/.

set -uo pipefail

SERVER="${1:-}"
PASSES="${2:-5}"
[[ -z "$SERVER" ]] && { echo "Usage: $0 <iperf3-server-ip> [passes]   (run 'iperf3 -s' on the server first)"; exit 1; }
command -v iperf3 >/dev/null || { echo "iperf3 required: sudo apt-get install -y iperf3"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/network-realpath-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR/logs"

ORIG_CC=$(sysctl -n net.ipv4.tcp_congestion_control)
restore() { sudo sysctl -w net.ipv4.tcp_congestion_control="$ORIG_CC" >/dev/null 2>&1 || true; }
trap restore EXIT

run_side() {
    local cc="$1" rates=()
    sudo modprobe tcp_bbr 2>/dev/null || true
    sudo sysctl -w net.ipv4.tcp_congestion_control="$cc" >/dev/null || { echo "cannot set $cc"; return 1; }
    echo "── $cc: $PASSES x 10s to $SERVER" | tee -a "$LOG"
    for ((i=1;i<=PASSES;i++)); do
        r=$(iperf3 -c "$SERVER" ${IPERF_PORT:+-p $IPERF_PORT} -t 10 -J 2>/dev/null | python3 -c \
            "import json,sys; print(round(json.load(sys.stdin)['end']['sum_sent']['bits_per_second']/1e6,1))" 2>/dev/null || echo "")
        [[ -n "$r" ]] && { rates+=("$r"); echo "  pass $i: ${r} Mbit/s" | tee -a "$LOG"; } \
                      || echo "  pass $i: FAILED (server reachable?)" | tee -a "$LOG"
        sleep 2
    done
    python3 -c "
import statistics,sys
v=[float(x) for x in sys.argv[1:]]
print(f'  {sys.argv[0]}', end='')
print(f'median={statistics.median(v):.1f} mean={statistics.mean(v):.1f} min={min(v):.1f} max={max(v):.1f} n={len(v)}' if v else 'no successful passes')" \
        "${rates[@]}" 2>/dev/null | tee -a "$LOG"
    echo "${rates[*]}"
}

echo "Real-path network A/B  server=$SERVER  passes=$PASSES  original_cc=$ORIG_CC" | tee "$LOG"
CUBIC_RATES=$(run_side cubic | tail -1)
BBR_RATES=$(run_side bbr | tail -1)
restore

python3 - "$CUBIC_RATES" "$BBR_RATES" <<'PY' | tee -a "$LOG"
import statistics, sys
def med(s):
    v = [float(x) for x in s.split()] if s.strip() else []
    return statistics.median(v) if v else None
c, b = med(sys.argv[1]), med(sys.argv[2])
print("\n=== REAL-PATH VERDICT ===")
if c and b:
    print(f"CUBIC median: {c:.1f} Mbit/s   BBR median: {b:.1f} Mbit/s   delta: {(b-c)/c*100:+.1f}%")
    print("Compare this delta to the loopback-netem +500-900% to see how much transfers.")
else:
    print("Insufficient successful passes; check server and path.")
PY
echo "Log: $LOG"
