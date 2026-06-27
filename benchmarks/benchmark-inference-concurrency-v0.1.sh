#!/usr/bin/env bash
# CursiveOS benchmark-inference-concurrency-v0.1.sh
# Measures aggregate sustained throughput under N parallel Ollama inference streams.
#
# WHY: single-stream sustained tok/s sits below the selection noise floor on
# current hardware (see docs/action-plan.md). Scheduler and memory-class tweaks
# may only show under parallel load. This probe stress-tests concurrent inference
# without replacing the existing single-stream sustained channel.
#
# Usage: ./benchmark-inference-concurrency-v0.1.sh [streams] [model]
#   streams : parallel workers (default 4)
#   model   : ollama model tag (default: largest available mistral/phi3/tinyllama)
# Env: CURSIVEOS_CONC_STREAMS, CURSIVEOS_CONC_PROMPT (override prompt text)
#
# Output: human summary + METRIC_JSON line for harness ingestion (observe-only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
METRICS_PY="$ROOT_DIR/tools/concurrency_metrics.py"
PYTHON="${PYTHON:-python3}"

PROMPT="${CURSIVEOS_CONC_PROMPT:-Write a short paragraph about Linux kernel scheduling under load.}"

usage() {
    cat <<EOF
Usage: $0 [--help|--dry-run|--fixture-dir DIR] [streams] [model] [wall_s]
  --help         Show this message
  --dry-run      Print planned invocation without calling Ollama
  --fixture-dir  Aggregate worker_*.json from DIR (no Ollama; for tests)
  streams        Parallel inference workers (default 4)
  model          Ollama model name (auto-detected if omitted)
  wall_s         Wall seconds for --fixture-dir (default 48.0)
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--dry-run" ]]; then
    shift
    _s="${1:-${CURSIVEOS_CONC_STREAMS:-4}}"
    _m="${2:-auto}"
    echo "DRY-RUN: would run ${_s} parallel ollama /api/generate workers on model=${_m}"
    echo "DRY-RUN: prompt length=${#PROMPT} chars; aggregate tok/s = sum(eval_count)/wall_s"
    exit 0
fi

if [[ "${1:-}" == "--fixture-dir" ]]; then
    shift
    FIXDIR="${1:?--fixture-dir requires directory}"
    STREAMS="${2:-${CURSIVEOS_CONC_STREAMS:-4}}"
    MODEL="${3:-fixture}"
    WALL_S="${4:-48.0}"
    echo "=== CONCURRENCY INFERENCE SENSOR (v0.1) ==="
    echo "model=$MODEL streams=$STREAMS time=$(date -Iseconds) fixture_dir=$FIXDIR"
    "$PYTHON" "$METRICS_PY" --tmpdir "$FIXDIR" --streams "$STREAMS" --wall-s "$WALL_S" --model "$MODEL"
    exit 0
fi

STREAMS="${1:-${CURSIVEOS_CONC_STREAMS:-4}}"
MODEL="${2:-}"

if [[ "$STREAMS" =~ ^[0-9]+$ ]] && [[ "$STREAMS" -lt 1 ]]; then
    echo "streams must be >= 1"; exit 1
fi

if [[ -z "$MODEL" ]]; then
    for m in mistral phi3 tinyllama llama3.2; do
        if ollama list 2>/dev/null | grep -q "^${m}:"; then
            MODEL="$m"
            break
        fi
    done
fi
if [[ -z "$MODEL" ]]; then
    echo "No ollama model found. Pull one first: ollama pull tinyllama"
    exit 1
fi

if ! ollama list 2>/dev/null | grep -q "^${MODEL}:"; then
    echo "Model '$MODEL' not found. Pull it first: ollama pull $MODEL"
    exit 1
fi

LOG_DIR="${HOME}/CursiveOS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/concurrency-$(date +%Y%m%d-%H%M%S).log"

_run_probe() {
echo "=== CONCURRENCY INFERENCE SENSOR (v0.1) ==="
echo "model=$MODEL streams=$STREAMS time=$(date -Iseconds)"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

worker() {
    local id="$1"
    local out="$TMPDIR_WORK/worker_${id}.json"
    curl -s --max-time 180 http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\", \"stream\": false, \"options\": {\"num_predict\": 80, \"num_ctx\": 1024, \"num_batch\": 128}}" \
        > "$out" 2>/dev/null || echo '{}' > "$out"
}

echo "Warming up (1 call)..."
worker 0 >/dev/null 2>&1 || true
rm -f "$TMPDIR_WORK"/worker_0.json

echo "Launching $STREAMS parallel workers..."
START_NS=$(date +%s%N)
for i in $(seq 1 "$STREAMS"); do
    worker "$i" &
done
wait
END_NS=$(date +%s%N)
WALL_S=$("$PYTHON" -c "print(round(($END_NS - $START_NS) / 1e9, 3))")

"$PYTHON" "$METRICS_PY" --tmpdir "$TMPDIR_WORK" --streams "$STREAMS" --wall-s "$WALL_S" --model "$MODEL"
}

# Nohup-safe: capture once, emit stdout, append log; Log line once after METRIC_JSON block.
_PROBE_OUT="$(_run_probe 2>&1)" || true
printf '%s\n' "$_PROBE_OUT"
printf '%s\n' "$_PROBE_OUT" >>"$LOG_FILE"
echo "Log: $LOG_FILE"