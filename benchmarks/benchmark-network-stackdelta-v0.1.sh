#!/usr/bin/env bash
# Network STACK DELTA: what do our buffer/qdisc/backlog tweaks add beyond BBR?
#
# Fail closed: if tc cannot be executed, exit before any measurement and
# never print a stack delta. Restore always lands on cubic/pfifo_fast/212992.

set -uo pipefail
PASSES="${1:-5}"

TC=""
for c in /sbin/tc /usr/sbin/tc; do
    [[ -x "$c" ]] && TC="$c" && break
done
SYSCTL=""
for c in /usr/sbin/sysctl /sbin/sysctl; do
    [[ -x "$c" ]] && SYSCTL="$c" && break
done

fail_closed() {
    echo "tc missing or netem not applied. Refusing to print a stack delta." >&2
    exit 1
}

[[ -n "$TC" && -n "$SYSCTL" ]] || fail_closed
command -v iperf3 >/dev/null || { echo "iperf3 required"; exit 1; }

SP="${TAO_SUDO_PASS:-}"
sudo_cmd() {
    if [[ -n "$SP" ]]; then echo "$SP" | sudo -S "$@" 2>/dev/null
    else sudo -n "$@"; fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/network-stackdelta-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR/logs"

# Always land on known stock. Do not trust a saved sysctl snapshot:
# user PATH often lacks sysctl, so a snapshot can be empty and leave BBR.
restore() {
    sudo_cmd "$SYSCTL" -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
    sudo_cmd "$SYSCTL" -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || true
    sudo_cmd "$SYSCTL" -w net.ipv4.tcp_slow_start_after_idle=1 >/dev/null 2>&1 || true
    sudo_cmd "$SYSCTL" -w net.core.rmem_max=212992 >/dev/null 2>&1 || true
    sudo_cmd "$SYSCTL" -w net.core.wmem_max=212992 >/dev/null 2>&1 || true
    sudo_cmd "$SYSCTL" -w net.ipv4.tcp_rmem="4096 87380 6291456" >/dev/null 2>&1 || true
    sudo_cmd "$SYSCTL" -w net.ipv4.tcp_wmem="4096 16384 4194304" >/dev/null 2>&1 || true
    sudo_cmd "$TC" qdisc del dev lo root >/dev/null 2>&1 || true
    pkill -f "iperf3 -s -p 5215" 2>/dev/null || true
}
trap restore EXIT

# Refuse before mutating the stack if tc cannot show a qdisc.
if ! "$TC" qdisc show dev lo >/dev/null 2>&1; then
    sudo_cmd "$TC" qdisc show dev lo >/dev/null 2>&1 || fail_closed
fi

# Both sides use BBR — the algorithm is held constant.
sudo_cmd modprobe tcp_bbr || true
sudo_cmd "$SYSCTL" -w net.ipv4.tcp_congestion_control=bbr >/dev/null || fail_closed

# Same netem condition as the legacy benchmark, with verification
sudo_cmd "$TC" qdisc del dev lo root >/dev/null 2>&1 || true
sudo_cmd "$TC" qdisc add dev lo root netem delay 25ms loss 0.25% || fail_closed
NETEM_ACTIVE=$(sudo_cmd "$TC" qdisc show dev lo | grep -c netem || true)
echo "netem verified active on lo: $NETEM_ACTIVE rule(s)" | tee "$LOG"
if [[ "${NETEM_ACTIVE:-0}" -lt 1 ]]; then
    echo "netem not active. Refusing to print a stack delta." | tee -a "$LOG" >&2
    restore
    trap - EXIT
    exit 1
fi

iperf3 -s -p 5215 -D 2>/dev/null || true
sleep 1

side() {
    local label="$1" rates=()
    echo "── $label (BBR, $PASSES x 10s, loopback netem)" | tee -a "$LOG"
    for ((i=1;i<=PASSES;i++)); do
        r=$(iperf3 -c 127.0.0.1 -p 5215 -t 10 -J 2>>"$LOG" | python3 -c \
            "import json,sys; print(round(json.load(sys.stdin)['end']['sum_sent']['bits_per_second']/1e6,1))" 2>>"$LOG" || echo "")
        [[ -n "$r" ]] && { rates+=("$r"); echo "  pass $i: ${r} Mbit/s" | tee -a "$LOG"; } \
                      || echo "  pass $i: FAILED (see log)" | tee -a "$LOG"
        sleep 1
    done
    echo "${rates[*]}"
}

# Condition A: default buffers/qdisc, BBR only
A_RATES=$(side "A: BBR + host-default stack" | tail -1)

# Condition B: BBR + the CursiveOS stack tuning
sudo_cmd "$SYSCTL" -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 >/dev/null
sudo_cmd "$SYSCTL" -w net.ipv4.tcp_rmem="4096 262144 16777216" net.ipv4.tcp_wmem="4096 262144 16777216" >/dev/null
sudo_cmd "$SYSCTL" -w net.core.default_qdisc=fq net.ipv4.tcp_slow_start_after_idle=0 net.core.netdev_max_backlog=5000 >/dev/null
B_RATES=$(side "B: BBR + CursiveOS stack tuning" | tail -1)

restore
trap - EXIT

python3 - "$A_RATES" "$B_RATES" << 'PY' | tee -a "$LOG"
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
