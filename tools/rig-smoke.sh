#!/usr/bin/env bash
# Rig automation: SCP → nohup & → poll. No long SSH one-liners.
#
# Usage:
#   bash tools/rig-smoke.sh --dry-run
#   bash tools/rig-smoke.sh sync <stardust|laptop|all>
#   bash tools/rig-smoke.sh json-smoke <stardust|laptop|all>
#   bash tools/rig-smoke.sh screen-v012b stardust
#
# Env: CURSIVE_RIG_KEY (default ~/.ssh/cursive_rig), TAO_SUDO_PASS= (empty OK)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEY="${CURSIVE_RIG_KEY:-$HOME/.ssh/cursive_rig}"
REMOTE_SH="$SCRIPT_DIR/rig-smoke-remote.sh"
STAMP=$(date +%Y%m%d-%H%M%S)

log() { echo "[rig-smoke] $*"; }

rig_host() {
  case "$1" in
    stardust) echo "elizabeth@192.168.1.102" ;;
    laptop)   echo "elizabeth@192.168.1.210" ;;
    *) echo ""; return 1 ;;
  esac
}

rig_scp() {
  local host="$1"
  scp -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 \
    "$REMOTE_SH" "$(rig_host "$host"):/tmp/rig-smoke-remote.sh"
}

rig_launch() {
  local host="$1"
  local mode="$2"
  local out="/tmp/rig-smoke-${mode}-${host}-${STAMP}.out"
  local launcher="/tmp/rig-smoke-launcher-${host}-${STAMP}.out"
  rig_scp "$host"
  # stdout must be ONLY the remote log path (for out=$(rig_launch)); status → stderr
  ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$(rig_host "$host")" \
    "chmod +x /tmp/rig-smoke-remote.sh; export TAO_SUDO_PASS=; nohup bash /tmp/rig-smoke-remote.sh $mode $out > $launcher 2>&1 & printf '%s' $out" \
    | tr -d '\r\n'
  log "launched host=$host mode=$mode out=$out launcher=$launcher" >&2
}

rig_poll() {
  local host="$1" out="$2"
  local timeout_s="${3:-3600}"
  if [[ "${4:-}" == "json-smoke" ]]; then timeout_s=2400; fi
  if [[ "${4:-}" == "screen-v012b" ]]; then timeout_s=1800; fi
  local elapsed=0
  while [[ $elapsed -lt $timeout_s ]]; do
    if ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$(rig_host "$host")" \
      "grep -E 'SYNC_HEAD=|JSON_VALID=|SCREEN_V012B_DONE|JSON_SMOKE_RC=' $out 2>/dev/null | tail -3"; then
      if ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$(rig_host "$host")" \
        "grep -qE 'SYNC_HEAD=|JSON_VALID=(true|True)|SCREEN_V012B_DONE' $out 2>/dev/null"; then
        ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$(rig_host "$host")" "tail -30 $out"
        return 0
      fi
    fi
    sleep 30
    elapsed=$((elapsed + 30))
  done
  ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 "$(rig_host "$host")" "tail -40 $out 2>/dev/null || echo POLL_TIMEOUT"
  return 1
}

rig_fetch() {
  local host="$1" remote_out="$2" local_dir="$3"
  mkdir -p "$local_dir"
  scp -i "$KEY" -o BatchMode=yes "$(rig_host "$host"):$remote_out" "$local_dir/" 2>/dev/null || true
  scp -i "$KEY" -o BatchMode=yes "$(rig_host "$host"):/tmp/rig-smoke-launcher-${host}-${STAMP}.out" "$local_dir/rig-smoke-launcher-${host}-${STAMP}.out" 2>/dev/null || \
  scp -i "$KEY" -o BatchMode=yes "$(rig_host "$host"):/tmp/rig-smoke-launcher-${host}.out" "$local_dir/" 2>/dev/null || true
}

dispatch() {
  local mode="$1" target="$2"
  local hosts=()
  if [[ "$target" == "all" ]]; then hosts=(stardust laptop); else hosts=("$target"); fi
  for h in "${hosts[@]}"; do
    log "dispatch mode=$mode host=$h (TAO_SUDO_PASS= scp/nohup/poll)"
    out=$(rig_launch "$h" "$mode")
    [[ "$out" == /tmp/rig-smoke-* ]] || { log "error: rig_launch returned invalid path: $out"; continue; }
    log "poll host=$h out=$out"
    rig_poll "$h" "$out" "" "$mode" || true
    rig_fetch "$h" "$out" "${RIG_SCRATCH:-/tmp}"
  done
}

if [[ "${1:-}" == "--dry-run" ]]; then
  log "pattern: TAO_SUDO_PASS= | scp rig-smoke-remote.sh | ssh nohup ... & | poll /tmp/rig-smoke-*.out"
  log "modes: sync | json-smoke | screen-v012b"
  log "hosts: stardust=$(rig_host stardust) laptop=$(rig_host laptop)"
  bash -n "$REMOTE_SH" && log "remote script syntax OK"
  bash -n "$0" && log "dispatcher syntax OK"
  [[ -f "$ROOT/presets/cursiveos-presets-v0.12b-swappiness.sh" ]] && log "v0.12b preset present"
  exit 0
fi

MODE="${1:-}"
TARGET="${2:-}"
[[ -n "$MODE" && -n "$TARGET" ]] || { echo "Usage: $0 --dry-run | $0 <sync|json-smoke|screen-v012b> <stardust|laptop|all>"; exit 1; }
[[ -f "$KEY" ]] || { echo "Missing SSH key: $KEY"; exit 1; }

case "$MODE" in
  sync|json-smoke|screen-v012b) dispatch "$MODE" "$TARGET" ;;
  *) echo "Unknown mode: $MODE"; exit 1 ;;
esac