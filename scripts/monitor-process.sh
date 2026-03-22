#!/usr/bin/env bash
# monitor-process.sh — Zero-LLM process monitor for TAO-OS benchmarks
#
# Polls a PID until the process exits, then extracts results from the log
# and notifies Copper via openclaw agent. No tokens burned while waiting.
#
# Usage:
#   ./monitor-process.sh --pid <PID> --log <logfile> [options]
#
# Options:
#   --pid <PID>           Process to watch (required)
#   --log <logfile>       Log file to extract results from (required)
#   --name <label>        Human-readable job name (default: "process")
#   --grep <pattern>      Grep pattern for result extraction
#                         (default: covers common benchmark output fields)
#   --tail <n>            How many lines to extract from grep output (default: 40)
#   --poll <seconds>      Poll interval in seconds (default: 30)
#   --notify-start        Send Copper a message when monitoring begins
#
# Examples:
#   ./monitor-process.sh --pid 12345 --log ~/TAO-OS/logs/foo.log --name "inference benchmark"
#   ./monitor-process.sh --pid 12345 --log ~/TAO-OS/logs/foo.log --grep "RESULT|delta|tuned" --notify-start

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
PID=""
LOG=""
NAME="process"
GREP_PATTERN="PASS|RESULT|SUMMARY|improvement|delta|baseline|tuned|cold_total|Gbits|Mbits|throughput|error|Error|failed|Failed"
TAIL_N=40
POLL=30
NOTIFY_START=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pid)         PID="$2";          shift 2 ;;
        --log)         LOG="$2";          shift 2 ;;
        --name)        NAME="$2";         shift 2 ;;
        --grep)        GREP_PATTERN="$2"; shift 2 ;;
        --tail)        TAIL_N="$2";       shift 2 ;;
        --poll)        POLL="$2";         shift 2 ;;
        --notify-start) NOTIFY_START=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PID" || -z "$LOG" ]]; then
    echo "Usage: $0 --pid <PID> --log <logfile> [--name <label>] [--grep <pattern>] [--tail <n>] [--poll <seconds>] [--notify-start]" >&2
    exit 1
fi

notify() {
    openclaw agent -m "$1" 2>/dev/null || true
}

# ── Notify start ──────────────────────────────────────────────────────────────
if $NOTIFY_START; then
    notify "Monitor started: watching '$NAME' (PID $PID). Will notify when done. Log: $LOG"
fi

echo "[monitor] Watching PID $PID ($NAME) — polling every ${POLL}s"

# ── Poll loop ─────────────────────────────────────────────────────────────────
while kill -0 "$PID" 2>/dev/null; do
    sleep "$POLL"
done

echo "[monitor] PID $PID exited. Extracting results from $LOG"

# ── Extract results ───────────────────────────────────────────────────────────
if [[ ! -f "$LOG" ]]; then
    notify "Monitor: '$NAME' (PID $PID) finished but log file not found at $LOG"
    exit 0
fi

RESULTS=$(grep -E "$GREP_PATTERN" "$LOG" 2>/dev/null | tail -"$TAIL_N" || true)

if [[ -z "$RESULTS" ]]; then
    notify "Monitor: '$NAME' finished (PID $PID). No summary lines matched in log — check manually: $LOG"
    exit 0
fi

notify "$(printf '%s finished. Results:\n\n%s\n\nFull log: %s' "$NAME" "$RESULTS" "$LOG")"

echo "[monitor] Done. Results sent to Copper."
