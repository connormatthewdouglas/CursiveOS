#!/usr/bin/env bash
# Network STACK DECOMPOSITION: which single knob drives the stack delta?
#
# Fail closed: if tc cannot be executed, or netem is not actually on lo,
# exit before any measurement and never print a delta.
# Restore always lands on cubic/pfifo_fast/212992.

set -uo pipefail
PASSES="${1:-4}"

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
s() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S "$@" 2>/dev/null; else sudo -n "$@"; fi; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/network-decompose-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR/logs"

declare -A ORIG
for k in net.core.netdev_max_backlog net.core.somaxconn; do
    ORIG[$k]="$("$SYSCTL" -n "$k" 2>/dev/null || true)"
done

restore_all() {
    s "$SYSCTL" -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
    s "$SYSCTL" -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || true
    s "$SYSCTL" -w net.ipv4.tcp_slow_start_after_idle=1 >/dev/null 2>&1 || true
    s "$SYSCTL" -w net.core.rmem_max=212992 >/dev/null 2>&1 || true
    s "$SYSCTL" -w net.core.wmem_max=212992 >/dev/null 2>&1 || true
    s "$SYSCTL" -w net.ipv4.tcp_rmem="4096 87380 6291456" >/dev/null 2>&1 || true
    s "$SYSCTL" -w net.ipv4.tcp_wmem="4096 16384 4194304" >/dev/null 2>&1 || true
    for k in net.core.netdev_max_backlog net.core.somaxconn; do
        [[ -n "${ORIG[$k]:-}" ]] && s "$SYSCTL" -w "$k=${ORIG[$k]}" >/dev/null 2>&1 || true
    done
    s "$TC" qdisc del dev lo root >/dev/null 2>&1 || true
    pkill -f "iperf3 -s -p 5216" 2>/dev/null || true
}
trap restore_all EXIT

if ! "$TC" qdisc show dev lo >/dev/null 2>&1; then
    s "$TC" qdisc show dev lo >/dev/null 2>&1 || fail_closed
fi

s modprobe tcp_bbr 2>/dev/null || true
s "$SYSCTL" -w net.ipv4.tcp_congestion_control=bbr >/dev/null || fail_closed
s "$TC" qdisc del dev lo root >/dev/null 2>&1 || true
s "$TC" qdisc add dev lo root netem delay 25ms loss 0.25% || fail_closed
NETEM_ACTIVE=$(s "$TC" qdisc show dev lo | grep -c netem || true)
echo "netem verified: $NETEM_ACTIVE rule(s) on lo; cc=bbr" | tee "$LOG"
if [[ "${NETEM_ACTIVE:-0}" -lt 1 ]]; then
    echo "netem not active. Refusing to print a stack delta." | tee -a "$LOG" >&2
    restore_all
    trap - EXIT
    exit 1
fi

iperf3 -s -p 5216 -D 2>/dev/null || true
sleep 1

measure() {
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

reset_buffers() {
    s "$SYSCTL" -w net.core.rmem_max=212992 net.core.wmem_max=212992 >/dev/null
    s "$SYSCTL" -w net.ipv4.tcp_rmem="4096 87380 6291456" net.ipv4.tcp_wmem="4096 16384 4194304" >/dev/null
    s "$SYSCTL" -w net.core.default_qdisc=pfifo_fast >/dev/null
    s "$SYSCTL" -w net.ipv4.tcp_slow_start_after_idle=1 >/dev/null
    [[ -n "${ORIG[net.core.netdev_max_backlog]:-}" ]] && s "$SYSCTL" -w "net.core.netdev_max_backlog=${ORIG[net.core.netdev_max_backlog]}" >/dev/null
    [[ -n "${ORIG[net.core.somaxconn]:-}" ]] && s "$SYSCTL" -w "net.core.somaxconn=${ORIG[net.core.somaxconn]}" >/dev/null
}

declare -A RESULT
reset_buffers
RESULT[A_baseline]=$(measure "A baseline (BBR + host defaults)")

reset_buffers; s "$SYSCTL" -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 >/dev/null
RESULT[B_coremax]=$(measure "B + core rmem/wmem_max")

reset_buffers; s "$SYSCTL" -w net.ipv4.tcp_rmem="4096 262144 16777216" net.ipv4.tcp_wmem="4096 262144 16777216" >/dev/null
RESULT[C_tcpautotune]=$(measure "C + tcp_rmem/wmem autotune")

reset_buffers; s "$SYSCTL" -w net.core.default_qdisc=fq >/dev/null
RESULT[D_fq]=$(measure "D + fq qdisc")

reset_buffers; s "$SYSCTL" -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null
RESULT[E_ssai]=$(measure "E + slow_start_after_idle=0")

reset_buffers; s "$SYSCTL" -w net.core.netdev_max_backlog=5000 >/dev/null
RESULT[F_backlog]=$(measure "F + netdev_max_backlog")

reset_buffers; s "$SYSCTL" -w net.core.somaxconn=4096 >/dev/null
RESULT[G_somaxconn]=$(measure "G + somaxconn")

reset_buffers
s "$SYSCTL" -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 >/dev/null
s "$SYSCTL" -w net.ipv4.tcp_rmem="4096 262144 16777216" net.ipv4.tcp_wmem="4096 262144 16777216" >/dev/null
s "$SYSCTL" -w net.core.default_qdisc=fq net.ipv4.tcp_slow_start_after_idle=0 >/dev/null
s "$SYSCTL" -w net.core.netdev_max_backlog=5000 net.core.somaxconn=4096 >/dev/null
RESULT[H_full]=$(measure "H + full stack")

restore_all; trap - EXIT

{
echo ""
echo "=== DECOMPOSITION (BBR constant; each knob vs baseline A) ==="
base="${RESULT[A_baseline]}"
printf "%-28s %10s %12s\n" "condition" "Mbit/s" "vs baseline"
for key in A_baseline B_coremax C_tcpautotune D_fq E_ssai F_backlog G_somaxconn H_full; do
    val="${RESULT[$key]}"
    if [[ "$base" != "NA" && "$val" != "NA" && "$base" != "0.0" ]]; then
        d=$(python3 -c "b=$base;v=$val;print(f'{(v-b)/b*100:+.1f}%')")
    else d="NA"; fi
    printf "%-28s %10s %12s\n" "$key" "$val" "$d"
done
echo ""
echo "Read: a knob that alone reproduces most of H's gain is the lever; if no single"
echo "knob does and only H is high, the effect is interaction (BDP needs buffers AND fq)."
} | tee -a "$LOG"
echo "Log: $LOG"
