#!/usr/bin/env bash
# cursiveroot-status.sh
# Pull and display decision-grade CursiveRoot run data.
# Usage: ./scripts/cursiveroot-status.sh [--limit N] [--latest N] [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_python() {
  local candidate
  for candidate in "${PYTHON:-}" python3 python; do
    [[ -n "$candidate" ]] || continue
    command -v "$candidate" >/dev/null 2>&1 || continue
    # On Windows/MSYS, python3 may be the Microsoft Store stub. Prove the
    # interpreter can actually execute Python before selecting it.
    if "$candidate" - <<'PY' >/dev/null 2>&1
import sys
sys.exit(0)
PY
    then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

PYTHON_BIN="$(find_python)" || {
  echo "cursiveroot-status: could not find a working Python interpreter (tried PYTHON, python3, python)" >&2
  exit 127
}
exec "$PYTHON_BIN" "$SCRIPT_DIR/tools/cursiveroot_analyze.py" "$@"
