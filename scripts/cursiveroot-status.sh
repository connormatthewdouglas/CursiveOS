#!/usr/bin/env bash
# cursiveroot-status.sh
# Pull and display decision-grade CursiveRoot run data.
# Usage: ./scripts/cursiveroot-status.sh [--limit N] [--latest N] [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$SCRIPT_DIR/tools/cursiveroot_analyze.py" "$@"
