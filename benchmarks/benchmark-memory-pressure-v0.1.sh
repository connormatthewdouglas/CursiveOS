#!/usr/bin/env bash
# Memory-pressure sensor PROTOTYPE (v0.1) -- the missing 5th genesis channel.
#
# WHY: the genesis suite (network/cold-start/sustained/idle-power) never stresses
# memory, so memory-class variants (zram, THP, swappiness) correctly read as
# neutral and can never accumulate fitness. Cycle 2's candidate-v0.10-zram
# screened inconclusive for exactly this reason. This probe creates DETERMINISTIC
# memory pressure and measures how the system copes -- the channel where zram is
# supposed to win.
#
# WHAT IT MEASURES: wall-clock time to fault a fixed, compressible working set
# back in while that working set is held under a cgroup-v2 `memory.high` ceiling
# smaller than the set. Pages above the ceiling get reclaimed to swap; reads
# fault them back. With a zram swap device, reclaim/refault is a fast in-RAM
# (de)compress; with disk swap it is slow; with no swap it throttles. Lower time
# = the memory subsystem (e.g. zram) is coping better.
#
# WHY IT'S A FAIR, LOW-NOISE SENSOR:
#  * cgroup `memory.high` fixes the pressure point independent of total RAM, so
#    the same WS/HIGH numbers mean the same thing on a 16 GB laptop and a 64 GB
#    desktop (hardware-scoped comparability, per Chapter 08).
#  * `memory.high` THROTTLES, it does not OOM-kill (that's `memory.max`), so the
#    probe is safe to run unattended; the workload is also capped to a fraction
#    of MemTotal as a backstop when cgroups are unavailable.
#  * cgroup-forced reclaim swaps anon pages even under v0.9's `swappiness=0`, so
#    this isolates zram's compression benefit BEFORE a swappiness-aware variant
#    exists.
#  * fixed working set + compressible payload + median of REPS with CV reported,
#    matching the discipline that made cold-start the CV~0.002 reference channel.
#
# HONEST CAVEATS (read before trusting a number):
#  * The payload is synthetically compressible (~text-like). It probes the zram
#    path; it is NOT a claim about any specific real workload's compressibility.
#    The achieved ratio is reported from zram mm_stat so the number is auditable.
#  * This is a PROTOTYPE: it logs locally and does NOT upload to CursiveRoot and
#    is NOT wired into the fitness model. Collect a noise floor (CV across REPS,
#    across machines) FIRST, then integrate as a weighted channel -- same path
#    every other channel took.
#
# Usage: ./benchmark-memory-pressure-v0.1.sh [ws_mb] [high_mb] [passes] [reps]
#        defaults: 1536 512 3 5    (1.5 GB set, 512 MB ceiling, 3 read passes)
# Progress -> stderr; final verdict + one JSON line -> stdout.

set -uo pipefail
WS_MB="${1:-1536}"; HIGH_MB="${2:-512}"; PASSES="${3:-3}"; REPS="${4:-5}"
SP="${TAO_SUDO_PASS:-}"
sc() { if [[ -n "$SP" ]]; then echo "$SP" | sudo -S bash -c "$1" 2>/dev/null; else sudo bash -c "$1"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- safety backstop: cap WS to 60% of MemTotal so an un-cgrouped fallback run
#     cannot exhaust the host ---
MEMTOTAL_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 4096)
MAXWS=$(( MEMTOTAL_MB * 60 / 100 ))
if (( WS_MB > MAXWS )); then
    echo "memsensor: WS ${WS_MB}M exceeds 60% of MemTotal (${MEMTOTAL_MB}M); clamping to ${MAXWS}M" >&2
    WS_MB=$MAXWS
fi
(( HIGH_MB >= WS_MB )) && HIGH_MB=$(( WS_MB / 3 ))   # ceiling must be < set to cause pressure

# --- capability + environment detection ---
CG2=no; [[ -f /sys/fs/cgroup/cgroup.controllers ]] && CG2=yes
SDRUN=no; have systemd-run && SDRUN=yes
ZSTAT="/sys/block/zram0/mm_stat"
ZRAM=no; [[ -e "$ZSTAT" ]] && ZRAM=yes
ZSWAP=no; grep -qi zram /proc/swaps 2>/dev/null && ZSWAP=yes
MODE="uncapped"; [[ "$CG2" == yes && "$SDRUN" == yes ]] && MODE="cgroup-high"
echo "memsensor WS=${WS_MB}M high=${HIGH_MB}M passes=$PASSES reps=$REPS cg2=$CG2 systemd-run=$SDRUN zram=$ZRAM zram_swap=$ZSWAP mode=$MODE" >&2
[[ "$MODE" == uncapped ]] && echo "  WARN: no cgroup-v2 + systemd-run; running WITHOUT a memory ceiling -> result is not pressure-bounded (low validity). Reported for diagnostics only." >&2

# --- the working-set workload (compressible alloc, then refault read passes) ---
WORK=$(mktemp /tmp/memsensor.XXXXXX.py)
trap 'rm -f "$WORK"' EXIT
cat > "$WORK" <<'PY'
import sys
ws_mb = int(sys.argv[1]); passes = int(sys.argv[2])
# 1 MiB compressible chunk (repeating text -> zram-friendly, ratio reported separately)
base = (b"CursiveOS memory-pressure sensor v0.1 compressible payload block " * 64)
chunk = (base * 256)[:1024 * 1024]
buf = [bytearray(chunk) for _ in range(ws_mb)]   # allocate + touch ws_mb MiB
acc = 0
for _ in range(passes):
    for b in buf:                                 # sequential refault of every page
        for off in range(0, len(b), 4096):
            acc += b[off]
print(acc % 251)
PY

run_once() {  # echoes elapsed seconds (float)
    local t0 t1
    t0=$(date +%s.%N)
    if [[ "$MODE" == "cgroup-high" ]]; then
        systemd-run --user --scope -q \
            -p MemoryHigh="${HIGH_MB}M" -p MemorySwapMax=infinity \
            python3 "$WORK" "$WS_MB" "$PASSES" >/dev/null 2>&1 \
        || sc "systemd-run --scope -q -p MemoryHigh=${HIGH_MB}M -p MemorySwapMax=infinity python3 $WORK $WS_MB $PASSES" >/dev/null 2>&1
    else
        python3 "$WORK" "$WS_MB" "$PASSES" >/dev/null 2>&1
    fi
    t1=$(date +%s.%N)
    python3 -c "print(f'{$t1-$t0:.3f}')"
}

zram_orig_compr() {  # echoes "orig_bytes compr_bytes" or "NA NA"
    if [[ "$ZRAM" == yes ]]; then awk '{print $1, $2}' "$ZSTAT" 2>/dev/null || echo "NA NA"; else echo "NA NA"; fi
}

# --- sample ---
read -r Z0O Z0C < <(zram_orig_compr)
times=()
for ((i=1;i<=REPS;i++)); do
    sleep 1
    e=$(run_once); times+=("$e")
    echo "   rep$i: ${e}s" >&2
done
read -r Z1O Z1C < <(zram_orig_compr)

# --- summarize ---
python3 - "$WS_MB" "$HIGH_MB" "$MODE" "$ZRAM" "$ZSWAP" "$Z0O" "$Z0C" "$Z1O" "$Z1C" "${times[@]}" <<'PY'
import sys, statistics, json
ws, high, mode, zram, zswap = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
z0o, z0c, z1o, z1c = sys.argv[6:10]
ts = [float(x) for x in sys.argv[10:]]
med = statistics.median(ts); mn = min(ts); mx = max(ts)
cv = (statistics.pstdev(ts) / med) if med and len(ts) > 1 else 0.0
ratio = None; orig_delta = None
try:
    od = int(z1o) - int(z0o); cd = int(z1c) - int(z0c)
    if cd > 0: ratio = round(od / cd, 2)
    orig_delta = od
except Exception:
    pass
print("=== MEMORY-PRESSURE SENSOR (prototype v0.1) ===")
print(f"working_set={ws}M  ceiling={high}M  mode={mode}  zram={zram}  zram_swap={zswap}")
print(f"refault_time_s: median={med:.3f}  min={mn:.3f}  max={mx:.3f}  cv={cv:.3f}  n={len(ts)}")
if ratio is not None:
    print(f"zram_engaged: yes  orig_swapped={orig_delta/1048576:.0f}MiB  compression_ratio={ratio}x")
elif zram == "yes":
    print("zram_engaged: no measurable delta (pressure may not have reached swap; raise WS or lower ceiling)")
else:
    print("zram_engaged: n/a (no zram device)")
print("note: PROTOTYPE -- lower median = better; validate CV across reps+machines before fitness integration.")
print("METRIC_JSON " + json.dumps({
    "sensor": "memory_pressure", "version": "v0.1",
    "working_set_mb": int(ws), "ceiling_mb": int(high), "mode": mode,
    "zram": zram == "yes", "zram_swap": zswap == "yes",
    "refault_time_s_median": round(med, 3), "refault_time_s_cv": round(cv, 3),
    "samples": [round(x, 3) for x in ts],
    "zram_orig_swapped_mib": (round(orig_delta/1048576, 1) if orig_delta is not None else None),
    "zram_compression_ratio": ratio,
}))
PY
