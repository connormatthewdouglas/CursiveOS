#!/usr/bin/env bash
# Network STACK DECOMPOSITION: which single knob drives the stack delta?
#
# benchmark-network-stackdelta showed that, with BBR held constant, our whole
# buffer/qdisc bundle adds ~+246% on a high-BDP loopback path. This script
# isolates the contribution of EACH knob: with BBR constant on both sides and
# the same netem condition, it measures BBR+host-defaults (baseline), then
# BBR+defaults+ONE knob at a time, reverting between conditions. Each knob's
# delta vs the baseline tells you whether one setting dominates or the gain is
# spread across several.
#
# Usage: ./benchmark-network-decompose-v0.1.sh [passes]   (default 4)

set -uo pipefail
PASSES="${1:-4}"
command -v iperf3 >/dev/null || { echo "iperf3 required"; exit 1; }
SP="${TAO_SUDO_PASS:-}"
s() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S "$@" 2>/dev/null; else sudo "$@"; fi; }
sc() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S bash -c "$1" 2>/dev/null; else sudo bash -c "$1"; fi; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/network-decompose-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR/logs"

# Save original state for all knobs we touch
declare -A ORIG
for k in net.ipv4.tcp_congestion_control net.core.rmem_max net.core.wmem_max \
         net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.default_qdisc \
         net.ipv4.tcp_slow_start_after_idle net.core.netdev_max_backlog net.core.somaxconn; do
    ORIG[$k]="$(sysctl -n "$k" 2>/dev/null)"
done

restore_all() {
    for k in "${!ORIG[@]}"; do s sysctl -w "$k=${ORIG[$k]}" >/dev/null 2>&1 || true; done
    s tc qdisc del dev lo root 2>/dev/null || true
    pkill -f "iperf3 -s -p 5216" 2>/dev/null || true
}
trap restore_all EXIT

# BBR constant + netem (~50ms RTT, ~0.5% loss round-trip on loopback), verified
s modprobe tcp_bbr 2>/dev/null || true
s sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null
s tc qdisc del dev lo root 2>/dev/null || true
s tc qdisc add dev lo root netem delay 25ms loss 0.25% || { echo "netem setup failed"; exit 1; }
echo "netem verified: $(tc qdisc show dev lo | grep -c netem) rule(s) on lo; cc=bbr" | tee "$LOG"

iperf3 -s -p 5216 -D 2>/dev/null || true
sleep 1

measure() {  # $1 = label; prints median Mbit/s
    local label="$1" rates=() i r
    for ((i=1;i<=PASSES;i++)); do
        r=$(iperf3 -c 127.0.0.1 -p 5216 -t 10 -J 2>>"$LOG" | python3 -c \
            "import json,sys;print(round(json.load(sys.stdin)['end']['sum_sent']['bits_per_second']/1e6,1))" 2>>"$LOG" || echo "")
        [[ -n "$r" ]] && rates+=("$r")
        sleep 1
    done
    python3 - "$label" "${rates[@]}" <<'PY'
import statistics,sys
label=sys.argv[1]; v=[float(x) for x in sys.argv[2:]]
print(f"{statistics.median(v):.1f}" if v else "NA")
PY
}

# reset buffers to host defaults (keep BBR + netem)
reset_buffers() {
    s sysctl -w net.core.rmem_max="${ORIG[net.core.rmem_max]}" net.core.wmem_max="${ORIG[net.core.wmem_max]}" >/dev/null
    s sysctl -w net.ipv4.tcp_rmem="${ORIG[net.ipv4.tcp_rmem]}" net.ipv4.tcp_wmem="${ORIG[net.ipv4.tcp_wmem]}" >/dev/null
    s sysctl -w net.core.default_qdisc="${ORIG[net.core.default_qdisc]}" >/dev/null
    s sysctl -w net.ipv4.tcp_slow_start_after_idle="${ORIG[net.ipv4.tcp_slow_start_after_idle]}" >/dev/null
    s sysctl -w net.core.netdev_max_backlog="${ORIG[net.core.netdev_max_backlog]}" net.core.somaxconn="${ORIG[net.core.somaxconn]}" >/dev/null
}

declare -A RESULT
reset_buffers
RESULT[A_baseline]=$(measure "A baseline (BBR + host defaults)")

reset_buffers; s sysctl -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 >/dev/null
RESULT[B_coremax]=$(measure "B + core rmem/wmem_max")

reset_buffers; s sysctl -w net.ipv4.tcp_rmem="4096 262144 16777216" net.ipv4.tcp_wmem="4096 262144 16777216" >/dev/null
RESULT[C_tcpautotune]=$(measure "C + tcp_rmem/wmem autotune")

reset_buffers; s sysctl -w net.core.default_qdisc=fq >/dev/null
RESULT[D_fq]=$(measure "D + fq qdisc")

reset_buffers; s sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null
RESULT[E_ssai]=$(measure "E + slow_start_after_idle=0")

reset_buffers; s sysctl -w net.core.netdev_max_backlog=5000 >/dev/null
RESULT[F_backlog]=$(measure "F + netdev_max_backlog")

reset_buffers; s sysctl -w net.core.somaxconn=4096 >/dev/null
RESULT[G_somaxconn]=$(measure "G + somaxconn")

# ALL together (= stack-delta condition B)
reset_buffers
s sysctl -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 >/dev/null
s sysctl -w net.ipv4.tcp_rmem="4096 262144 16777216" net.ipv4.tcp_wmem="4096 262144 16777216" >/dev/null
s sysctl -w net.core.default_qdisc=fq net.ipv4.tcp_slow_start_after_idle=0 >/dev/null
s sysctl -w net.core.netdev_max_backlog=5000 net.core.somaxconn=4096 >/dev/null
RESULT[H_full]=$(measure "H + full stack")

restore_all; trap - EXIT

{
echo ""
echo "=== DECOMPOSITION (BBR constant; each knob vs baseline A) ==="
base="${RESULT[A_baseline]}"
printf "%-28s %10s %12s\n" "condition" "Mbit/s" "vs baseline"
for key in A_baseline B_coremax C_tcpautotune D_fq E_ssai F_backlog G_somaxconn H_full; do
    val="${RESULT[$key]}"
    if [[ "$base" != "NA" && "$val" != "NA" ]]; then
        d=$(python3 -c "b=$base;v=$val;print(f'{(v-b)/b*100:+.1f}%')")
    else d="NA"; fi
    printf "%-28s %10s %12s\n" "$key" "$val" "$d"
done
echo ""
echo "Read: a knob that alone reproduces most of H's gain is the lever; if no single"
echo "knob does and only H is high, the effect is interaction (BDP needs buffers AND fq)."
} | tee -a "$LOG"
echo "Log: $LOG"
