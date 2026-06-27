#!/usr/bin/env bash
# Load-time power during parallel Ollama inference (observe-only).
#
# Samples CPU RAPL + GPU energy counter watts each second while N parallel
# workers run. Complements idle-power probe; targets perf/watt under load (Ch23).
#
# Usage: ./benchmark-inference-load-power-v0.1.sh [--dry-run] [streams] [model]
# Env: CURSIVEOS_CONC_STREAMS, CURSIVEOS_CONC_PROMPT

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON="${PYTHON:-python3}"

PROMPT="${CURSIVEOS_CONC_PROMPT:-Write a short paragraph about Linux kernel scheduling under load.}"
STREAMS="${1:-${CURSIVEOS_CONC_STREAMS:-4}}"
MODEL="${2:-}"

if [[ "${1:-}" == "--dry-run" ]]; then
    shift
    STREAMS="${1:-4}"
    MODEL="${2:-mistral}"
    echo "DRY-RUN: load-power probe streams=$STREAMS model=$MODEL"
    exit 0
fi

if [[ "$STREAMS" =~ ^[0-9]+$ ]] && [[ -z "$MODEL" ]]; then
    MODEL="${2:-}"
fi
if [[ -z "$MODEL" ]]; then
    for m in mistral phi3 tinyllama llama3.2; do
        if ollama list 2>/dev/null | grep -q "^${m}:"; then MODEL="$m"; break; fi
    done
fi
[[ -n "$MODEL" ]] || { echo "No model"; exit 1; }

sc() { sudo bash -c "$1" 2>/dev/null; }
rd() { sudo cat "$1" 2>/dev/null; }

CPU_E="/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/energy_uj"
AMD_E="$(ls /sys/devices/virtual/powercap/*/energy_uj 2>/dev/null | head -1)"
[[ -f "$CPU_E" ]] || CPU_E="${AMD_E:-}"
GPU_E="$(ls /sys/class/drm/card*/device/hwmon/hwmon*/energy1_input 2>/dev/null | head -1)"

read_pair() {
    local c1 c2 g1 g2 cw="NA" gw="NA"
    [[ -n "$CPU_E" && -f "$CPU_E" ]] && c1=$(rd "$CPU_E")
    [[ -n "$GPU_E" ]] && g1=$(cat "$GPU_E" 2>/dev/null || true)
    sleep 1
    [[ -n "$CPU_E" && -f "$CPU_E" ]] && c2=$(rd "$CPU_E")
    [[ -n "$GPU_E" ]] && g2=$(cat "$GPU_E" 2>/dev/null || true)
    [[ "${c1:-}" =~ ^[0-9]+$ && "${c2:-}" =~ ^[0-9]+$ ]] && cw=$("$PYTHON" -c "print(f'{($c2-$c1)/1e6:.3f}')")
    [[ "${g1:-}" =~ ^[0-9]+$ && "${g2:-}" =~ ^[0-9]+$ ]] && gw=$("$PYTHON" -c "print(f'{($g2-$g1)/1e6:.3f}')")
    echo "$cw $gw"
}

worker() {
    local id="$1" out="$2"
    curl -s --max-time 180 http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\", \"stream\": false, \"options\": {\"num_predict\": 80, \"num_ctx\": 1024, \"num_batch\": 128}}" \
        >"$out" 2>/dev/null || echo '{}' >"$out"
}

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

echo "=== LOAD-POWER INFERENCE SENSOR (v0.1) ==="
echo "model=$MODEL streams=$STREAMS time=$(date -Iseconds)"
echo "cpu_energy=${CPU_E:-none} gpu_energy=${GPU_E:-none}"

curl -s http://localhost:11434/api/generate -H "Content-Type: application/json" \
    -d "{\"model\": \"$MODEL\", \"prompt\": \"hi\", \"stream\": false, \"options\": {\"num_predict\": 1}}" >/dev/null 2>&1 || true

START_NS=$(date +%s%N)
cpus=() gpus=() totals=()
for i in $(seq 1 "$STREAMS"); do worker "$i" "$TMPDIR_WORK/worker_${i}.json" & done

while true; do
    pair=$(read_pair)
    cw=${pair%% *}; gw=${pair##* }
    if [[ "$cw" != "NA" ]]; then cpus+=("$cw"); fi
    if [[ "$gw" != "NA" ]]; then gpus+=("$gw"); fi
    if [[ "$cw" != "NA" || "$gw" != "NA" ]]; then
        tw=$("$PYTHON" -c "c='$cw';g='$gw';cs=0 if c=='NA' else float(c);gs=0 if g=='NA' else float(g);print(f'{cs+gs:.3f}')")
        totals+=("$tw")
    fi
    if ! jobs -r >/dev/null 2>&1; then break; fi
done
wait
END_NS=$(date +%s%N)
WALL_S=$("$PYTHON" -c "print(round(($END_NS - $START_NS) / 1e9, 3))")

TOTAL_TOKENS=0
for f in "$TMPDIR_WORK"/worker_*.json; do
    TOTAL_TOKENS=$("$PYTHON" -c "import json; d=json.load(open('$f')); print($TOTAL_TOKENS + int(d.get('eval_count') or 0))")
done

"$PYTHON" - "$WALL_S" "$TOTAL_TOKENS" "$STREAMS" "$MODEL" "${cpus[@]}" "__SEP__" "${gpus[@]}" "__SEP2__" "${totals[@]}" <<'PY'
import json, statistics, sys

args = sys.argv[1:]
wall_s = float(args[0])
tokens = int(args[1])
streams = int(args[2])
model = args[3]
rest = args[4:]
sep = rest.index("__SEP__")
sep2 = rest.index("__SEP2__")
cpus = [float(x) for x in rest[:sep] if x != "NA"]
gpus = [float(x) for x in rest[sep + 1 : sep2] if x != "NA"]
totals = [float(x) for x in rest[sep2 + 1 :] if x != "NA"]

def med(a):
    return round(statistics.median(a), 3) if a else None

cpu_m = med(cpus)
gpu_m = med(gpus)
total_m = med(totals)
j_per_tok = round((total_m or 0) * wall_s / tokens, 6) if tokens and total_m else None
agg_tok_s = round(tokens / wall_s, 2) if wall_s > 0 else 0.0

metrics = {
    "sensor": "inference_load_power",
    "version": "v0.1",
    "model": model,
    "streams": streams,
    "wall_s": wall_s,
    "total_tokens": tokens,
    "aggregate_tok_s": agg_tok_s,
    "cpu_w_median": cpu_m,
    "gpu_w_median": gpu_m,
    "total_w_median": total_m,
    "joules_per_token": j_per_tok,
    "power_samples": len(totals),
    "power_source": "rapl_pkg+gpu_energy" if cpus and gpus else ("rapl_pkg" if cpus else ("gpu_energy" if gpus else "none")),
}
print(f"wall_s={wall_s} tokens={tokens} aggregate_tok_s={agg_tok_s}")
print(f"cpu_w_median={cpu_m} gpu_w_median={gpu_m} total_w_median={total_m} joules_per_token={j_per_tok}")
print(f"power_samples={len(totals)} power_source={metrics['power_source']}")
print("note: observe-only load-power channel; not wired to fitness.")
print("METRIC_JSON " + json.dumps(metrics, sort_keys=True))
PY