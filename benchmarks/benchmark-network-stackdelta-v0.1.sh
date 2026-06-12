#!/usr/bin/env bash
# Network STACK DELTA: what do our buffer/qdisc/backlog tweaks add beyond BBR?
#
# The legacy network benchmark compares CUBIC (default) vs BBR (tuned) under
# lossy netem — a comparison dominated by the well-documented algorithm swap.
# This benchmark holds the congestion control CONSTANT (BBR on both sides)
# and toggles only the rest of the CursiveOS network stack (rmem/wmem, tcp
# autotune buffers, fq qdisc, slow-start-after-idle, backlog, somaxconn).
# The resulting delta is attributable to OUR tuning, not to BBR-vs-CUBIC.
#
# Usage: ./benchmark-network-stackdelta-v0.1.sh [passes]   (default 5)
# Runs on loopback with the same netem condition as the legacy benchmark
# (50ms RTT, 0.5% loss) so results are comparable to historical data.

set -uo pipefail
PASSES="${1:-5}"
command -v iperf3 >/dev/null || { echo "iperf3 required"; exit 1; }
SP="${TAO_SUDO_PASS:-}"
sudo_cmd() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S "$@" 2>/dev/null; else sudo "$@"; fi; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/network-stackdelta-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR/logs"

# Save current state
SAVE=$(sysctl -n net.ipv4.tcp_congestion_control net.core.rmem_max net.core.wmem_max net.core.default_qdisc net.ipv4.tcp_slow_start_after_idle net.core.netdev_max_backlog 2>/dev/null | tr '\n' '|')
restore() {
    IFS='|' read -r cc rmem wmem qdisc ssai backlog <<< "$SAVE"
    sudo_cmd sysctl -w net.ipv4.tcp_congestion_control="$cc" net.core.rmem_max="$rmem" net.core.wmem_max="$wmem" net.core.default_qdisc="$qdisc" net.ipv4.tcp_slow_start_after_idle="$ssai" net.core.netdev_max_backlog="$backlog" >/dev/null || true
    sudo_cmd tc qdisc del dev lo root 2>/dev/null || true
    pkill -f "iperf3 -s -p 5215" 2>/dev/null || true
}
trap restore EXIT

# Both sides use BBR — the algorithm is held constant.
sudo_cmd modprobe tcp_bbr || true
sudo_cmd sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null

# Same netem condition as the legacy benchmark, with verification (Ch16 item 7)
sudo_cmd tc qdisc del dev lo root 2>/dev/null || true
sudo_cmd tc qdisc add dev lo root netem delay 25ms loss 0.25% || { echo "netem setup failed"; exit 1; }
NETEM_ACTIVE=$(tc qdisc show dev lo | grep -c netem || true)
echo "netem verified active on lo: $NETEM_ACTIVE rule(s)" | tee "$LOG"

iperf3 -s -p 5215 -D 2>/dev/null || true
sleep 1

side() {
    local label="$1" rates=()
    echo "── $label (BBR, $PASSES x 10s, loopback netem 50ms RTT 0.5% loss)" | tee -a "$LOG"
    for ((i=1;i<=PASSES;i++)); do
        r=$(iperf3 -c 127.0.0.1 -p 5215 -t 10 -J 2>>"$LOG" | python3 -c \
            "import json,sys; print(round(json.load(sys.stdin)['end']['sum_sent']['bits_per_second']/1e6,1))" 2>>"$LOG" || echo "")
        [[ -n "$r" ]] && { rates+=("$r"); echo "  pass $i: ${r} Mbit/s" | tee -a "$LOG"; } \
                      || echo "  pass $i: FAILED (see log)" | tee -a "$LOG"
        sleep 1
    done
    echo "${rates[*]}"
}

# Condition A: default buffers/qdisc (whatever the host has), BBR only
A_RATES=$(side "A: BBR + host-default stack" | tail -1)

# Condition B: BBR + the CursiveOS stack tuning (buffers, fq, ssai, backlog)
sudo_cmd sysctl -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 >/dev/null
sudo_cmd sysctl -w net.ipv4.tcp_rmem="4096 262144 16777216" net.ipv4.tcp_wmem="4096 262144 16777216" >/dev/null
sudo_cmd sysctl -w net.core.default_qdisc=fq net.ipv4.tcp_slow_start_after_idle=0 net.core.netdev_max_backlog=5000 >/dev/null
B_RATES=$(side "B: BBR + CursiveOS stack tuning" | tail -1)

restore
trap - EXIT

python3 - "$A_RATES" "$B_RATES" <<'PY' | tee -a "$LOG"
import statistics, sys
def med(s):
    v = [float(x) for x in s.split()] if s.strip() else []
    return (statistics.median(v), len(v)) if v else (None, 0)
a, na = med(sys.argv[1]); b, nb = med(sys.argv[2])
print("\n=== STACK DELTA VERDICT (BBR held constant) ===")
if a and b:
    print(f"A (BBR only):        {a:.1f} Mbit/s  n={na}")
    print(f"B (BBR + our stack): {b:.1f} Mbit/s  n={nb}")
    print(f"Stack delta:         {(b-a)/a*100:+.1f}%  <- attributable to CursiveOS tuning beyond BBR")
else:
    print("Insufficient passes; see log.")
PY
echo "Log: $LOG"
