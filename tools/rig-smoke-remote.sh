#!/usr/bin/env bash
# On-rig worker for rig-smoke.sh (sync, json-smoke, screen-v012b).
set -euo pipefail

MODE="${1:-}"
OUT="${2:-/tmp/rig-smoke-remote.out}"
ROOT="${CURSIVEOS_ROOT:-$HOME/CursiveOS}"
export TAO_SUDO_PASS="${TAO_SUDO_PASS:-}"

: >"$OUT"
log() { echo "$*" | tee -a "$OUT"; }

normalize_scripts() {
  local f
  for f in "$ROOT/cursiveos-full-test-v1.4.sh" "$ROOT/tools/rig-smoke-remote.sh"; do
    [[ -f "$f" ]] || continue
    sed -i 's/\r$//' "$f" 2>/dev/null || true
    python3 - "$f" <<'PY' 2>/dev/null || true
import pathlib, sys
p = pathlib.Path(sys.argv[1])
b = p.read_bytes()
if b.startswith(b"\xef\xbb\xbf"):
    p.write_bytes(b[3:])
PY
  done
}

sync_repo() {
  cd "$ROOT"
  normalize_scripts
  git stash push -m "rig-smoke-$(date +%Y%m%d)" -- cursiveos-full-test-v1.4.sh 2>/dev/null || true
  git fetch origin main 2>&1 | tee -a "$OUT"
  git reset --hard origin/main 2>&1 | tee -a "$OUT"
  normalize_scripts
  log "SYNC_HEAD=$(git rev-parse --short HEAD)"
  bash -n "$ROOT/cursiveos-full-test-v1.4.sh" && log "SYNTAX_OK full-test"
}

json_smoke() {
  cd "$ROOT"
  normalize_scripts
  export TAO_SUDO_PASS=
  PRESET="presets/cursiveos-presets-v0.12.sh"
  log "JSON_SMOKE_START $(date -Iseconds) preset=$PRESET"
  set +e
  bash ./cursiveos-full-test-v1.4.sh "$PRESET" >>"$OUT" 2>&1
  rc=$?
  set -e
  json_new=$(ls -t logs/cursiveos-full-test-*.json 2>/dev/null | head -1 || true)
  log "JSON_SMOKE_RC=$rc json=$json_new"
  if [[ -n "$json_new" ]]; then
    python3 - "$json_new" <<'PY' | tee -a "$OUT"
import json, sys
d = json.load(open(sys.argv[1]))
keys = ["schema_version", "wrapper_version", "baseline", "telemetry"]
ok = all(k in d for k in keys)
idle = d.get("baseline", {}).get("idle_watts")
print(f"JSON_VALID={'true' if ok else 'false'} schema={d.get('schema_version')} idle_w={idle}")
sys.exit(0 if ok and idle is not None else 1)
PY
  else
    log "JSON_VALID=false reason=no_json"
    return 1
  fi
}

metric_json() {
  grep '^METRIC_JSON ' | tail -1 | sed 's/^METRIC_JSON //'
}

run_arm() {
  local label="$1" preset="$2"
  log "=== ARM $label preset=$preset ==="
  bash "$ROOT/$preset" --undo 2>/dev/null || true
  bash "$ROOT/$preset" --apply-temp 2>&1 | tee -a "$OUT" | tail -3
  mem_out=$(bash "$ROOT/benchmarks/benchmark-memory-pressure-v0.2.sh" 1024 384 3 5 2>&1) || true
  echo "$mem_out" | tee -a "$OUT"
  mem_json=$(echo "$mem_out" | metric_json)
  lp_out=$(bash "$ROOT/benchmarks/benchmark-inference-load-power-v0.1.sh" 4 mistral 2>&1) || true
  echo "$lp_out" | tee -a "$OUT"
  lp_json=$(echo "$lp_out" | metric_json)
  bash "$ROOT/$preset" --undo 2>&1 | tee -a "$OUT" | tail -2
  python3 - "$label" "$mem_json" "$lp_json" <<'PY' | tee -a "$OUT"
import json, sys
label, mem_s, lp_s = sys.argv[1:4]
def parse(s):
    try: return json.loads(s) if s else {}
    except: return {}
mem, lp = parse(mem_s), parse(lp_s)
print(f"ARM_SUMMARY {label} mem_refault_s={mem.get('refault_time_s_median')} "
      f"load_total_w={lp.get('total_w_median')} load_j_per_tok={lp.get('joules_per_token')} "
      f"load_tok_s={lp.get('aggregate_tok_s')}")
PY
}

screen_v012b() {
  cd "$ROOT"
  normalize_scripts
  export TAO_SUDO_PASS=
  log "SCREEN_V012B_START $(date -Iseconds) HOST=$(hostname)"
  run_arm "v0.12-parent" "presets/cursiveos-presets-v0.12.sh"
  run_arm "v0.12b-candidate" "presets/cursiveos-presets-v0.12b-swappiness.sh"
  python3 - "$OUT" <<'PY' | tee -a "$OUT"
import re, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
arms = {}
for m in re.finditer(r"ARM_SUMMARY (\S+) mem_refault_s=([0-9.]+|None) load_total_w=([0-9.]+|None) load_j_per_tok=([0-9.]+|None) load_tok_s=([0-9.]+|None)", text):
    arms[m.group(1)] = {"mem": float(m.group(2)) if m.group(2) != "None" else None,
                        "w": float(m.group(3)) if m.group(3) != "None" else None,
                        "jpt": float(m.group(4)) if m.group(4) != "None" else None,
                        "tok": float(m.group(5)) if m.group(5) != "None" else None}
p, c = arms.get("v0.12-parent", {}), arms.get("v0.12b-candidate", {})
mem_delta = ((c.get("mem") or 0) - (p.get("mem") or 0)) / (p.get("mem") or 1) * 100 if p.get("mem") else None
jpt_delta = ((c.get("jpt") or 0) - (p.get("jpt") or 0)) / (p.get("jpt") or 1) * 100 if p.get("jpt") else None
accept = False
reason = "insufficient_data"
if p.get("mem") and c.get("mem") and p.get("jpt") and c.get("jpt"):
    mem_better = c["mem"] < p["mem"] * 0.95
    load_ok = c["jpt"] <= p["jpt"] * 1.05
    accept = mem_better and load_ok
    reason = f"mem_better={mem_better} load_ok={load_ok} mem_delta_pct={mem_delta:.1f} jpt_delta_pct={jpt_delta:.1f}"
print(f"V012B_VERDICT accept={accept} reason={reason}")
print(f"V012B_PARENT mem={p.get('mem')} jpt={p.get('jpt')} w={p.get('w')}")
print(f"V012B_CAND mem={c.get('mem')} jpt={c.get('jpt')} w={c.get('w')}")
PY
  log "SCREEN_V012B_DONE"
}

case "$MODE" in
  sync) sync_repo ;;
  json-smoke) json_smoke ;;
  screen-v012b) screen_v012b ;;
  *)
    echo "Unknown mode: $MODE" >&2; exit 1 ;;
esac