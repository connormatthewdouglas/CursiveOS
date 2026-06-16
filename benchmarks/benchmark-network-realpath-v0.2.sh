#!/usr/bin/env bash
# Real-path network A/B (3 conditions) — does the loopback gain transfer to a
# real NIC path? Run iperf3 -s on a SECOND machine, then here:
#   ./benchmark-network-realpath-v0.2.sh <server-ip> [passes]
#
# Measures, client-side (this host = sender), over the real path:
#   1. CUBIC + host-default buffers   (real-world default)
#   2. BBR   + host-default buffers   (algorithm only)
#   3. BBR   + CursiveOS buffer stack (algorithm + our tuning = full)
# Reports (2 vs 1) algorithm gain, (3 vs 2) our-stack gain, (3 vs 1) total.
#
# Optional: NETEM="delay 25ms loss 0.25%" emulates WAN latency over the real
# NIC egress (raises BDP) to test whether our stack helps once the path is fat.
# Settings are restored at the end.

set -uo pipefail
SERVER="${1:-}"; PASSES="${2:-5}"
[[ -z "$SERVER" ]] && { echo "Usage: $0 <iperf3-server-ip> [passes]"; exit 1; }
command -v iperf3 >/dev/null || { echo "iperf3 required"; exit 1; }
SP="${TAO_SUDO_PASS:-}"
s() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S "$@" 2>/dev/null; else sudo "$@"; fi; }
NETEM="${NETEM:-}"
IFACE="${IFACE:-$(ip route get "$SERVER" 2>/dev/null | grep -oP 'dev \K\S+' | head -1)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/network-realpath2-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR/logs"

declare -A ORIG
for k in net.ipv4.tcp_congestion_control net.core.rmem_max net.core.wmem_max \
         net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.default_qdisc \
         net.ipv4.tcp_slow_start_after_idle net.core.netdev_max_backlog net.core.somaxconn; do
    ORIG[$k]="$(sysctl -n "$k" 2>/dev/null)"
done
restore_all() {
    for k in "${!ORIG[@]}"; do s sysctl -w "$k=${ORIG[$k]}" >/dev/null 2>&1 || true; done
    [[ -n "$NETEM" && -n "$IFACE" ]] && s tc qdisc del dev "$IFACE" root 2>/dev/null || true
}
trap restore_all EXIT

reset_buffers() {
    s sysctl -w net.core.rmem_max="${ORIG[net.core.rmem_max]}" net.core.wmem_max="${ORIG[net.core.wmem_max]}" \
        net.ipv4.tcp_rmem="${ORIG[net.ipv4.tcp_rmem]}" net.ipv4.tcp_wmem="${ORIG[net.ipv4.tcp_wmem]}" \
        net.core.default_qdisc="${ORIG[net.core.default_qdisc]}" \
        net.ipv4.tcp_slow_start_after_idle="${ORIG[net.ipv4.tcp_slow_start_after_idle]}" \
        net.core.netdev_max_backlog="${ORIG[net.core.netdev_max_backlog]}" \
        net.core.somaxconn="${ORIG[net.core.somaxconn]}" >/dev/null
}
apply_stack() {
    s sysctl -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 \
        net.ipv4.tcp_rmem="4096 262144 16777216" net.ipv4.tcp_wmem="4096 262144 16777216" \
        net.core.default_qdisc=fq net.ipv4.tcp_slow_start_after_idle=0 \
        net.core.netdev_max_backlog=5000 net.core.somaxconn=4096 >/dev/null
}

s modprobe tcp_bbr 2>/dev/null || true
echo "Real-path v0.2  server=$SERVER iface=${IFACE:-?} passes=$PASSES netem='${NETEM:-none}'" | tee "$LOG"
if [[ -n "$NETEM" && -n "$IFACE" ]]; then
    s tc qdisc del dev "$IFACE" root 2>/dev/null || true
    s tc qdisc add dev "$IFACE" root netem $NETEM && echo "netem applied on $IFACE: $NETEM" | tee -a "$LOG" \
        || echo "WARN netem failed on $IFACE" | tee -a "$LOG"
fi

measure() {  # $1 label
    local label="$1" rates=() i r
    echo "-- $label" | tee -a "$LOG"
    for ((i=1;i<=PASSES;i++)); do
        r=$(iperf3 -c "$SERVER" -t 10 -J 2>>"$LOG" | python3 -c \
          "import json,sys;print(round(json.load(sys.stdin)['end']['sum_sent']['bits_per_second']/1e6,1))" 2>>"$LOG" || echo "")
        [[ -n "$r" ]] && { rates+=("$r"); echo "   pass $i: $r Mbit/s" | tee -a "$LOG"; } || echo "   pass $i: FAIL" | tee -a "$LOG"
        sleep 2
    done
    python3 -c "import statistics,sys;v=[float(x) for x in sys.argv[1:]];print(f'{statistics.median(v):.1f}' if v else 'NA')" "${rates[@]}"
}

reset_buffers; s sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
C1=$(measure "1: CUBIC + host-default buffers")
reset_buffers; s sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null
C2=$(measure "2: BBR + host-default buffers")
apply_stack; s sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null
C3=$(measure "3: BBR + CursiveOS stack")
restore_all; trap - EXIT

python3 - "$C1" "$C2" "$C3" "${NETEM:-none}" <<'PY' | tee -a "$LOG"
import sys
c1,c2,c3,netem=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
def f(x):
    try: return float(x)
    except: return None
a,b,c=f(c1),f(c2),f(c3)
def d(x,y): return f"{(y-x)/x*100:+.1f}%" if (x and y) else "NA"
print("\n=== REAL-PATH VERDICT (netem="+netem+") ===")
print(f"1 CUBIC default : {c1} Mbit/s")
print(f"2 BBR default   : {c2} Mbit/s   (algorithm gain vs 1: {d(a,b)})")
print(f"3 BBR + stack   : {c3} Mbit/s   (our-stack gain vs 2: {d(b,c)})")
print(f"total 3 vs 1    : {d(a,c)}")
print("Low-BDP real LAN: expect small stack gain. If netem raised BDP and the")
print("stack gain reappears, the loopback mechanism is real but path-BDP-dependent.")
PY
echo "Log: $LOG"
