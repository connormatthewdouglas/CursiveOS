#!/usr/bin/env bash
# Memory-pressure sensor PROTOTYPE (v0.2) -- the missing 5th genesis channel.
#
# Changes from v0.1: the zram engagement proof now uses a background sampler that
# captures PEAK zram usage during the reps. v0.1 read /sys/block/zram0/mm_stat
# only at the endpoints, but the transient cgroup scope frees swapped pages
# between reps, so the endpoint delta read ~0 even when zram was heavily used.
# The timing metric (the actual sensor output) is unchanged and was validated on
# the i5-11300H laptop 2026-06-25 (zram 5.78s vs disk-swap 14s, CV 0.006-0.019).
#
# WHY: the genesis suite (network/cold-start/sustained/idle-power) never stresses
# memory, so memory-class variants (zram, THP, swappiness) read as neutral and
# can never accumulate fitness. Cycle 2's candidate-v0.10-zram screened
# inconclusive for exactly this reason. This probe creates DETERMINISTIC memory
# pressure and measures how the system copes -- the channel where zram wins.
#
# WHAT IT MEASURES: wall-clock time to fault a fixed, compressible working set
# back in while that set is held under a cgroup-v2 `memory.high` ceiling smaller
# than the set. Pages above the ceiling get reclaimed to swap; reads fault them
# back. With a zram swap device the refault is a fast in-RAM (de)compress; with
# disk swap it is slow; with no swap it throttles. Lower median = better.
#
# WHY IT'S A FAIR, LOW-NOISE SENSOR:
#  * cgroup `memory.high` fixes the pressure point independent of total RAM, so
#    the same WS/HIGH numbers mean the same thing on a 16 GB laptop and a 64 GB
#    desktop (hardware-scoped comparability, Chapter 08).
#  * `memory.high` THROTTLES, it does not OOM-kill (that's `memory.max`); the
#    workload is also capped to a fraction of MemTotal as a backstop.
#  * cgroup-forced reclaim swaps anon pages even under v0.9's `swappiness=0`, so
#    this isolates zram's benefit BEFORE a swappiness-aware variant exists.
#  * fixed working set + compressible payload + median of REPS with CV reported.
#
# HONEST CAVEATS:
#  * The payload is synthetically compressible (~text-like). It probes the zram
#    path; it is NOT a claim about a specific real workload's compressibility.
#    The achieved ratio is reported from zram mm_stat so the number is auditable.
#  * PROTOTYPE: logs locally, does NOT upload, NOT wired into fitness. Validate a
#    noise floor across reps + machines, THEN integrate as a weighted channel.
#
# Usage: ./benchmark-memory-pressure-v0.2.sh [ws_mb] [high_mb] [passes] [reps]
#        defaults: 1536 512 3 5
# Progress -> stderr; final verdict + one JSON line -> stdout.

set -uo pipefail
WS_MB="${1:-1536}"; HIGH_MB="${2:-512}"; PASSES="${3:-3}"; REPS="${4:-5}"
# Per-rep wall-clock cap. Under a config that refuses to swap (e.g. swappiness=0
# with only disk swap), cgroup memory.high throttles the workload almost to a
# standstill; without a cap a rep can run for many minutes. A capped rep records
# the cap value -- which correctly reads as "this config handles pressure badly"
# -- and keeps the probe bounded. Default 45s; raise via CURSIVEOS_MEM_TIMEOUT.
TIMEOUT_S="${CURSIVEOS_MEM_TIMEOUT:-45}"
CAPPED=0
SP="${TAO_SUDO_PASS:-}"
sc() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S bash -c "$1" 2>/dev/null; else sudo bash -c "$1"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

MEMTOTAL_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 4096)
MAXWS=$(( MEMTOTAL_MB * 60 / 100 ))
if (( WS_MB > MAXWS )); then
    echo "memsensor: WS ${WS_MB}M exceeds 60% of MemTotal (${MEMTOTAL_MB}M); clamping to ${MAXWS}M" >&2
    WS_MB=$MAXWS
fi
(( HIGH_MB >= WS_MB )) && HIGH_MB=$(( WS_MB / 3 ))

CG2=no; [[ -f /sys/fs/cgroup/cgroup.controllers ]] && CG2=yes
SDRUN=no; have systemd-run && SDRUN=yes
ZSTAT="$(ls /sys/block/zram*/mm_stat 2>/dev/null | head -1)"
ZRAM=no; [[ -n "$ZSTAT" ]] && ZRAM=yes
ZSWAP=no; grep -qi zram /proc/swaps 2>/dev/null && ZSWAP=yes
MODE="uncapped"; [[ "$CG2" == yes && "$SDRUN" == yes ]] && MODE="cgroup-high"
echo "memsensor WS=${WS_MB}M high=${HIGH_MB}M passes=$PASSES reps=$REPS cg2=$CG2 systemd-run=$SDRUN zram=$ZRAM zram_swap=$ZSWAP zstat=${ZSTAT:-none} mode=$MODE" >&2
[[ "$MODE" == uncapped ]] && echo "  WARN: no cgroup-v2 + systemd-run; running WITHOUT a memory ceiling -> not pressure-bounded (low validity)." >&2

WORK=$(mktemp /tmp/memsensor.XXXXXX.py)
PEAK=$(mktemp /tmp/memsensor.XXXXXX.peak)
SAMP_PID=""
cleanup_tmp() {
    [[ -n "$SAMP_PID" ]] && kill "$SAMP_PID" 2>/dev/null
    # kill any workload child that a timeout left behind (transient scope payload)
    pkill -f "$(basename "$WORK")" 2>/dev/null
    rm -f "$WORK" "$PEAK"
}
trap cleanup_tmp EXIT
cat > "$WORK" <<'PY'
import sys
ws_mb = int(sys.argv[1]); passes = int(sys.argv[2])
base = (b"CursiveOS memory-pressure sensor v0.2 compressible payload block " * 64)
chunk = (base * 256)[:1024 * 1024]
buf = [bytearray(chunk) for _ in range(ws_mb)]
acc = 0
for _ in range(passes):
    for b in buf:
        for off in range(0, len(b), 4096):
            acc += b[off]
print(acc % 251)
PY

run_once() {
    local t0 t1 rc
    t0=$(date +%s.%N)
    # timeout -k: SIGTERM at TIMEOUT_S, SIGKILL 5s later if it ignores it.
    if [[ "$MODE" == "cgroup-high" ]]; then
        timeout -k 5 "${TIMEOUT_S}s" systemd-run --user --scope -q \
            -p MemoryHigh="${HIGH_MB}M" -p MemorySwapMax=infinity \
            python3 "$WORK" "$WS_MB" "$PASSES" >/dev/null 2>&1
        rc=$?
        if [[ $rc -ne 0 && $rc -ne 124 && -n "$SP" ]]; then
            timeout -k 5 "${TIMEOUT_S}s" \
                bash -c "echo '$SP' | sudo -S systemd-run --scope -q -p MemoryHigh=${HIGH_MB}M -p MemorySwapMax=infinity python3 '$WORK' $WS_MB $PASSES" >/dev/null 2>&1
            rc=$?
        fi
    else
        timeout -k 5 "${TIMEOUT_S}s" python3 "$WORK" "$WS_MB" "$PASSES" >/dev/null 2>&1
        rc=$?
    fi
    t1=$(date +%s.%N)
    # 124 = hit the wall-clock cap (config refused to service the pressure in time)
    [[ $rc -eq 124 ]] && CAPPED=$((CAPPED + 1))
    python3 -c "print(f'{$t1-$t0:.3f}')"
}

# Background peak sampler: track the max orig_data_size seen and the compr bytes
# at that moment, so a transient zram fill that is freed between reps is still
# captured. mm_stat fields: orig_data_size compr_data_size mem_used_total ...
start_peak_sampler() {
    [[ "$ZRAM" != yes ]] && return
    ( best_o=0; best_c=0
      echo "0 0" > "$PEAK"
      while :; do
          read -r o c _ < "$ZSTAT" 2>/dev/null || { sleep 0.1; continue; }
          if [[ "$o" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ ]] && (( o > best_o )); then
              best_o=$o; best_c=$c; echo "$best_o $best_c" > "$PEAK"
          fi
          sleep 0.1
      done ) &
    SAMP_PID=$!
}

# --- sample ---
start_peak_sampler
times=()
for ((i=1;i<=REPS;i++)); do
    sleep 1
    e=$(run_once); times+=("$e")
    echo "   rep$i: ${e}s" >&2
done
[[ -n "$SAMP_PID" ]] && { kill "$SAMP_PID" 2>/dev/null; SAMP_PID=""; }
read -r PK_O PK_C < "$PEAK" 2>/dev/null || { PK_O=0; PK_C=0; }

# --- summarize ---
python3 - "$WS_MB" "$HIGH_MB" "$MODE" "$ZRAM" "$ZSWAP" "$PK_O" "$PK_C" "$CAPPED" "$TIMEOUT_S" "${times[@]}" <<'PY'
import sys, statistics, json
ws, high, mode, zram, zswap = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
pk_o, pk_c = sys.argv[6], sys.argv[7]
capped, timeout_s = int(sys.argv[8]), float(sys.argv[9])
ts = [float(x) for x in sys.argv[10:]]
med = statistics.median(ts); mn = min(ts); mx = max(ts)
cv = (statistics.pstdev(ts) / med) if med and len(ts) > 1 else 0.0
ratio = None; peak_mib = None
try:
    po = int(pk_o); pc = int(pk_c)
    peak_mib = round(po / 1048576, 1)
    if pc > 0: ratio = round(po / pc, 2)
except Exception:
    pass
print("=== MEMORY-PRESSURE SENSOR (prototype v0.2) ===")
print(f"working_set={ws}M  ceiling={high}M  mode={mode}  zram={zram}  zram_swap={zswap}")
print(f"refault_time_s: median={med:.3f}  min={mn:.3f}  max={mx:.3f}  cv={cv:.3f}  n={len(ts)}")
if capped:
    print(f"capped_reps: {capped}/{len(ts)} hit the {timeout_s:.0f}s wall-clock cap "
          f"-> this config refuses to service the pressure (e.g. swappiness=0 + no fast swap)")
if zram == "yes" and peak_mib and peak_mib > 1:
    print(f"zram_engaged: yes  peak_orig={peak_mib}MiB  compression_ratio={ratio}x")
elif zram == "yes":
    print("zram_engaged: no measurable peak (pressure may not have reached zram; raise WS or lower ceiling)")
else:
    print("zram_engaged: n/a (no zram device)")
print("note: PROTOTYPE -- lower median = better; validate CV across reps+machines before fitness integration.")
print("METRIC_JSON " + json.dumps({
    "sensor": "memory_pressure", "version": "v0.2",
    "working_set_mb": int(ws), "ceiling_mb": int(high), "mode": mode,
    "zram": zram == "yes", "zram_swap": zswap == "yes",
    "refault_time_s_median": round(med, 3), "refault_time_s_cv": round(cv, 3),
    "capped_reps": capped, "timeout_s": timeout_s,
    "samples": [round(x, 3) for x in ts],
    "zram_peak_orig_mib": peak_mib,
    "zram_compression_ratio": ratio,
}))
PY
