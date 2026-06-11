#!/usr/bin/env bash
# CursiveOS Phase 0 one-paste test session.
#
# Run the whole Phase 0 measurement session on a Linux test rig with a single
# paste. The session is self-contained and uploads everything to CursiveRoot
# automatically — no further copy/paste needed from the operator.
#
# What it does, in order:
#   1. Installs basics (git, python3, curl) and clones/updates ~/CursiveOS.
#   2. RECOVERY: re-uploads any benchmark results and seed bundles still
#      saved locally from earlier installs (idempotent; safe after the
#      2026-06-10 CursiveRoot data loss).
#   3. GENESIS: records a v0.8 genesis baseline for this machine's hardware
#      fingerprint (skipped automatically if CursiveRoot already has one).
#   4. SCREEN: runs the v0.8 parent vs v0.9-network-efficient candidate
#      mutation screen (two full benchmark sessions, back to back).
#   5. Uploads all artifacts and prints the analyzer verdict.
#
# This takes a while (up to three full benchmark passes). Leave the terminal
# open; everything is logged under ~/CursiveOS/logs/.

set -uo pipefail

# This script is normally run via `curl ... | bash`, which makes stdin the
# script pipe instead of the keyboard. Rebind stdin to the real terminal so
# sudo and any prompts (here or in the benchmark harness) reach the operator.
# Without this, prompts hit EOF, default to "No", and the harness exits in
# seconds without benchmarking — the failure mode observed on 2026-06-10.
if [[ -e /dev/tty && -r /dev/tty ]]; then
  exec < /dev/tty
fi

REPO_URL="${CURSIVEOS_REPO_URL:-https://github.com/connormatthewdouglas/CursiveOS.git}"
TARGET_DIR="${CURSIVEOS_DIR:-$HOME/CursiveOS}"
BRANCH="${CURSIVEOS_BRANCH:-main}"
CYCLE_ID="${CURSIVEOS_CYCLE_ID:-1}"
SUPABASE_URL="${CURSIVEOS_SUPABASE_URL:-https://iovvktpuoinmjdgfxgvm.supabase.co}"
SUPABASE_KEY="${CURSIVEOS_SUPABASE_KEY:-sb_publishable_4WefsfMl0sNNo9O2c_lxnA_q2VQ01jn}"

PASS=0
FAIL=0
step() { printf '\n\033[1m[CursiveOS session] %s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This session must run on Linux. This machine reports: $(uname -s)"
  exit 1
fi

step "1/5 Preparing the machine"
# Ask for sudo ONCE, up front. The harness reuses TAO_SUDO_PASS for its long
# benchmark phases (sudo's 15-minute cache can expire mid-run), and skips its
# own password prompt when the variable is already exported.
if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
  if sudo -n true 2>/dev/null; then
    TAO_SUDO_PASS=""
    note "sudo already authorized (passwordless or cached)."
  else
    read -rsp "  [CursiveOS] sudo password (asked once, used by the benchmarks): " TAO_SUDO_PASS && echo
  fi
fi
export TAO_SUDO_PASS
echo "$TAO_SUDO_PASS" | sudo -S -v 2>/dev/null || sudo -v || { echo "sudo is required for benchmarks (tc/sysctl). Aborting."; exit 1; }

# Install everything the session AND the benchmark harness need, so no
# install prompt ever triggers mid-run (jq/bc/iperf3 are hard requirements
# of the harness; pciutils provides lspci for the hardware fingerprint).
missing=()
for dep in git python3 curl jq bc iperf3 lspci; do
  command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  pkgs=("${missing[@]/lspci/pciutils}")
  note "Installing required packages: ${pkgs[*]}"
  echo "$TAO_SUDO_PASS" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get update -qq
  echo "$TAO_SUDO_PASS" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
fi
for dep in git python3 curl jq bc iperf3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "Required dependency '$dep' could not be installed. Aborting."; exit 1; }
done

if ! command -v ollama >/dev/null 2>&1; then
  note "Ollama not found — installing it so inference benchmarks can run."
  note "(On Intel Arc, inference may run on CPU; the harness handles that.)"
  curl -fsSL https://ollama.com/install.sh | sh || note "Ollama install failed — inference metrics will be N/A, continuing."
fi

if [[ -d "$TARGET_DIR/.git" ]]; then
  note "Updating existing repo at $TARGET_DIR"
  git -C "$TARGET_DIR" fetch origin "$BRANCH" && \
  git -C "$TARGET_DIR" checkout "$BRANCH" && \
  git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH" || {
    note "Could not fast-forward (local changes?) — continuing with local version."
  }
else
  note "Cloning CursiveOS into $TARGET_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR" || { echo "clone failed"; exit 1; }
fi
cd "$TARGET_DIR"
chmod +x cursiveos-full-test-v1.4.sh tools/seed_organism.py presets/*.sh 2>/dev/null || true
python3 tools/seed_organism.py init

# Compute this machine's canonical fingerprint (same v2 recipe as the wrapper)
CPU_MODEL=$(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)
BOARD_VENDOR=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null | xargs || echo "unknown")
BOARD_NAME=$(cat /sys/class/dmi/id/board_name 2>/dev/null | xargs || echo "unknown")
GPU_PCI_IDS=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' | grep -oE '\[[0-9a-f]{4}:[0-9a-f]{4}\]' | sort | tr -d '\n' || true)
HW_ID_TUPLE="${CPU_MODEL:-unknown}|${BOARD_VENDOR:-unknown}|${BOARD_NAME:-unknown}|${GPU_PCI_IDS:-nogpu}"
if [[ "$HW_ID_TUPLE" == "unknown|unknown|unknown|nogpu" ]]; then
  HW_ID_TUPLE="machineid|$(cat /etc/machine-id 2>/dev/null || hostname)"
fi
FINGERPRINT=$(echo "$HW_ID_TUPLE" | sha256sum | cut -c1-16)
note "Machine fingerprint (v2): $FINGERPRINT"
note "Hardware: $CPU_MODEL / $BOARD_VENDOR $BOARD_NAME"

step "2/5 Recovering any locally saved results from earlier installs"
# Re-upload raw full-test results saved under logs/ (deduped server-side).
python3 - <<'PY' || note "Recovery scan failed — continuing; nothing is lost locally."
import glob, sys
from pathlib import Path
sys.path.insert(0, "tools")
import seed_organism as so

found = sorted(glob.glob("logs/cursiveos-full-test-*.json"))
if not found:
    print("  no saved full-test results found under logs/")
recovered = skipped = 0
for p in found:
    try:
        status = so.upload_full_test_result(so.read_json(Path(p)), result_path=Path(p))
        print(f"  {p}: {status}")
        recovered += 1
    except Exception as e:
        print(f"  {p}: skipped ({e})")
        skipped += 1
print(f"  recovery: {recovered} uploaded/confirmed, {skipped} skipped")
PY
# Re-upload any surviving local seed bundles + payout reports (idempotent).
python3 tools/seed_organism.py upload && note "Local seed artifacts synced to CursiveRoot." \
  || note "Seed artifact sync unavailable — artifacts remain saved locally."

step "3/5 Genesis baseline for this machine"
GENESIS_EXISTS=$(curl -s \
  -H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY" \
  "$SUPABASE_URL/rest/v1/seed_bundles?machine_id=eq.$FINGERPRINT&decision=eq.measured_baseline&select=bundle_hash&limit=1" 2>/dev/null || echo "")
if [[ "$GENESIS_EXISTS" == "["*"]" && "$GENESIS_EXISTS" != "[]" ]]; then
  note "CursiveRoot already has a genesis baseline for this fingerprint — skipping."
else
  note "Running the v0.8 genesis baseline (one full benchmark session)."
  note "This is baseline characterization: it is not a payout event."
  if python3 tools/seed_organism.py run-variant \
      --variant references/seed-organism/variant.genesis-linux.json \
      --execute \
      --cycle-id "$CYCLE_ID"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    note "Genesis run had a problem — see logs/. Continuing to the screen."
  fi
fi

step "4/5 Mutation screen: v0.8 parent vs v0.9-network-efficient candidate"
note "Two full benchmark sessions, back to back. Screening only — one screen"
note "cannot accept a mutation or create a payout."
if python3 tools/seed_organism.py screen-variant \
    --parent-variant references/seed-organism/variant.genesis-linux.json \
    --candidate-variant references/seed-organism/variant.v0.9-network-efficient.json \
    --execute \
    --cycle-id "$CYCLE_ID"; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
  note "Screen had a problem — see logs/. Artifacts are saved locally."
fi

step "5/5 Uploading artifacts and computing the verdict"
python3 tools/seed_organism.py upload || note "Upload unavailable — bundles remain saved under .cursiveos/seed/."
python3 tools/seed_organism.py status || true
python3 tools/cursiveroot_analyze.py 2>/dev/null || true

step "Session complete"
note "machine fingerprint : $FINGERPRINT"
note "phases with errors  : $FAIL"
note "All raw logs: $TARGET_DIR/logs/   Local audit bundles: $TARGET_DIR/.cursiveos/seed/"

# Hard verification against CursiveRoot — never let a silent failure look
# like success. Counts run rows uploaded for this machine today.
TODAY=$(date +%Y-%m-%d)
UPLOADED_TODAY=$(curl -s \
  -H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY" \
  "$SUPABASE_URL/rest/v1/runs?machine_id=eq.$FINGERPRINT&run_date=eq.$TODAY&select=id" 2>/dev/null \
  | grep -o '"id"' | wc -l || echo 0)
if [[ "${UPLOADED_TODAY:-0}" -gt 0 && "$FAIL" -eq 0 ]]; then
  printf '\n\033[1;32m  ✔ VERIFIED: %s benchmark run(s) from this machine reached CursiveRoot today.\033[0m\n' "$UPLOADED_TODAY"
  note "Nothing else to paste — the data is uploaded."
else
  printf '\n\033[1;31m  ✘ NOT VERIFIED: %s run(s) in CursiveRoot today, %s phase(s) had errors.\033[0m\n' "${UPLOADED_TODAY:-0}" "$FAIL"
  note "The session did NOT complete a full measured upload. Scroll up to the"
  note "first red/error line to see what failed, then re-paste the same"
  note "command — every step is safe to repeat."
fi
