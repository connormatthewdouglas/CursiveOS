#!/usr/bin/env bash
# Total-power probe: what does the v0.8 GPU frequency pin actually COST?
#
# v0.9 dropped v0.8's Arc GPU pin (slpc_ignore_eff + rps_min 2000 + rps_boost
# max) as "dead weight" because it produced no cold-start gain. But its GPU-side
# wattage was invisible until the v1.4.3 sensor. This probe measures TOTAL idle
# power (CPU RAPL package + GPU energy counter) with the GPU UNPINNED (v0.9
# default) vs PINNED (v0.8 behavior), many samples each, to quantify the pin's
# real cost and confirm dropping it was a genuine power win, not just inert.
#
# Usage: ./benchmark-power-gpu-pin-v0.1.sh [samples] [settle_s]   (default 12, 2)

set -uo pipefail
N="${1:-12}"; SETTLE="${2:-2}"
SP="${TAO_SUDO_PASS:-}"
sc() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S bash -c "$1" 2>/dev/null; else sudo bash -c "$1"; fi; }
rd() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S cat "$1" 2>/dev/null; else sudo cat "$1" 2>/dev/null; fi; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/power-gpu-pin-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR/logs"

CPU_E="/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/energy_uj"
GPU_E="$(ls /sys/class/drm/card*/device/hwmon/hwmon*/energy1_input 2>/dev/null | head -1)"
GPU_GT=""; for c in /sys/class/drm/card*/gt/gt0; do [[ -f "$c/rps_min_freq_mhz" ]] && { GPU_GT="$c"; break; }; done

echo "Power probe  N=$N settle=${SETTLE}s  cpu_e=$([[ -f $CPU_E ]] && echo yes||echo no) gpu_e=${GPU_E:-none} gt=${GPU_GT:-none}" | tee "$LOG"
[[ -z "$GPU_GT" ]] && { echo "No Arc GT path; this probe targets Intel Arc. Aborting."; exit 1; }

# one 1-second power reading -> "cpu_w gpu_w total_w"
read_pair() {
    local c1 c2 g1 g2 cw="" gw=""
    [[ -f "$CPU_E" ]] && c1=$(rd "$CPU_E")
    [[ -n "$GPU_E" ]] && g1=$(cat "$GPU_E" 2>/dev/null)
    sleep 1
    [[ -f "$CPU_E" ]] && c2=$(rd "$CPU_E")
    [[ -n "$GPU_E" ]] && g2=$(cat "$GPU_E" 2>/dev/null)
    [[ "$c1" =~ ^[0-9]+$ && "$c2" =~ ^[0-9]+$ ]] && cw=$(python3 -c "print(f'{($c2-$c1)/1e6:.2f}')")
    [[ "$g1" =~ ^[0-9]+$ && "$g2" =~ ^[0-9]+$ ]] && gw=$(python3 -c "print(f'{($g2-$g1)/1e6:.2f}')")
    echo "${cw:-NA} ${gw:-NA}"
}

sample_state() {  # $1 label -> prints "cpu_med gpu_med total_med n"
    local label="$1" cpus=() gpus=() i pair cw gw
    echo "-- sampling: $label" | tee -a "$LOG"
    for ((i=1;i<=N;i++)); do
        sleep "$SETTLE"
        pair=$(read_pair); cw=${pair%% *}; gw=${pair##* }
        [[ "$cw" != "NA" ]] && cpus+=("$cw"); [[ "$gw" != "NA" ]] && gpus+=("$gw")
        echo "   s$i: cpu=${cw}W gpu=${gw}W" | tee -a "$LOG"
    done
    python3 - "${cpus[@]}" "__SEP__" "${gpus[@]}" <<'PY'
import statistics,sys
a=sys.argv[1:]; sep=a.index("__SEP__"); cpu=[float(x) for x in a[:sep]]; gpu=[float(x) for x in a[sep+1:]]
cm=statistics.median(cpu) if cpu else 0.0; gm=statistics.median(gpu) if gpu else 0.0
print(f"{cm:.2f} {gm:.2f} {cm+gm:.2f} {min(len(cpu),len(gpu))}")
PY
}

# capture + restore GPU pin state
G_MIN=$(cat "$GPU_GT/rps_min_freq_mhz" 2>/dev/null); G_BOOST=$(cat "$GPU_GT/rps_boost_freq_mhz" 2>/dev/null); G_SLPC=$(cat "$GPU_GT/slpc_ignore_eff_freq" 2>/dev/null)
restore_gpu() { sc "echo $G_MIN > $GPU_GT/rps_min_freq_mhz"; sc "echo $G_BOOST > $GPU_GT/rps_boost_freq_mhz"; sc "echo $G_SLPC > $GPU_GT/slpc_ignore_eff_freq"; }
trap restore_gpu EXIT

# State A: UNPINNED (v0.9 default) — ensure defaults
restore_gpu; sleep 3
A=$(sample_state "A UNPINNED (v0.9 default, GPU ~$(cat $GPU_GT/rps_cur_freq_mhz 2>/dev/null)MHz)")

# State B: PINNED (v0.8 behavior)
MAXF=$(cat "$GPU_GT/rps_RP0_freq_mhz" 2>/dev/null || echo 2400)
sc "echo 1 > $GPU_GT/slpc_ignore_eff_freq"; sc "echo 2000 > $GPU_GT/rps_min_freq_mhz"; sc "echo $MAXF > $GPU_GT/rps_boost_freq_mhz"; sleep 3
B=$(sample_state "B PINNED (v0.8: min=2000 boost=$MAXF slpc=1)")

restore_gpu; trap - EXIT

read -r ac ag at an <<<"$A"; read -r bc bg bt bn <<<"$B"
{
echo ""
echo "=== GPU-PIN POWER VERDICT (median W, n=$an/$bn) ==="
printf "%-22s cpu=%6sW  gpu=%6sW  total=%6sW\n" "A unpinned (v0.9)" "$ac" "$ag" "$at"
printf "%-22s cpu=%6sW  gpu=%6sW  total=%6sW\n" "B pinned (v0.8)" "$bc" "$bg" "$bt"
python3 -c "print(f'GPU pin cost: +{float('$bg')-float('$ag'):.2f}W gpu, +{float('$bt')-float('$at'):.2f}W total -> this is what v0.9 SAVES by dropping the pin')"
} | tee -a "$LOG"
echo "Log: $LOG"
