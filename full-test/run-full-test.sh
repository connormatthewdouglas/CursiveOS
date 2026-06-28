#!/usr/bin/env bash
# Launch full-test in background on a rig; CRLF-safe.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export TAO_SUDO_PASS="${TAO_SUDO_PASS:-}"
if [[ -f cursiveos-full-test-v1.4.sh ]]; then
  sed -i 's/\r$//' cursiveos-full-test-v1.4.sh 2>/dev/null || true
  python3 - cursiveos-full-test-v1.4.sh <<'PY' 2>/dev/null || true
import pathlib, sys
p = pathlib.Path(sys.argv[1])
b = p.read_bytes()
if b.startswith(b"\xef\xbb\xbf"):
    p.write_bytes(b[3:])
PY
fi
PRESET="${1:-presets/cursiveos-presets-v0.12.sh}"
LOGFILE="logs/cursiveos-full-test-$(date +%Y%m%d-%H%M%S).log"
echo "LOG=$LOGFILE"
bash cursiveos-full-test-v1.4.sh "$PRESET" > "$LOGFILE" 2>&1 &
echo "PID=$!"
echo "$! $LOGFILE" > /tmp/tao-fulltest-run.txt