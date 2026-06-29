#!/usr/bin/env bash
# One-command Linux parent-vs-candidate seed-organism mutation screen.

set -euo pipefail

REPO_URL="${CURSIVEOS_REPO_URL:-https://github.com/connormatthewdouglas/CursiveOS.git}"
TARGET_DIR="${CURSIVEOS_DIR:-$HOME/CursiveOS}"
BRANCH="${CURSIVEOS_BRANCH:-main}"
CYCLE_ID="${CURSIVEOS_CYCLE_ID:-4}"
PARENT_VARIANT="${CURSIVEOS_PARENT_VARIANT:-v0.12}"
CANDIDATE_VARIANT="${CURSIVEOS_CANDIDATE_VARIANT:-}"

say() { printf '\n[CursiveOS mutation screen] %s\n' "$*"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This mutation screen must run on Linux. This machine reports: $(uname -s)"
  exit 1
fi

missing=()
command -v git >/dev/null 2>&1 || missing+=("git")
command -v python3 >/dev/null 2>&1 || missing+=("python3")
if [[ ${#missing[@]} -gt 0 ]]; then
  say "Installing required basics: ${missing[*]}"
  sudo apt-get update
  sudo apt-get install -y "${missing[@]}"
fi

if [[ -d "$TARGET_DIR/.git" ]]; then
  say "Updating existing repo at $TARGET_DIR"
  git -C "$TARGET_DIR" fetch origin "$BRANCH"
  git -C "$TARGET_DIR" checkout "$BRANCH"
  git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH"
else
  say "Cloning CursiveOS into $TARGET_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
chmod +x cursiveos-full-test-v1.4.sh presets/*.sh tools/seed_organism.py
python3 tools/seed_organism.py init

if [[ -z "$CANDIDATE_VARIANT" ]]; then
  say "No active candidate is configured."
  say "Cycle 3's v0.11-zram-swappiness is already accepted/promoted to v0.12; v0.12b and v0.13 were rejected."
  say "For an explicit historical or new screen, set CURSIVEOS_CANDIDATE_VARIANT=<variant> and, if needed, CURSIVEOS_CYCLE_ID=<cycle>."
  exit 2
fi

case "$PARENT_VARIANT" in
  v0.8|genesis|genesis-linux)
    PARENT_FILE="references/seed-organism/variant.genesis-linux.json"
    PARENT_LABEL="v0.8/genesis"
    ;;
  *)
    PARENT_FILE="references/seed-organism/variant.${PARENT_VARIANT}.json"
    PARENT_LABEL="$PARENT_VARIANT"
    ;;
esac
CANDIDATE_FILE="references/seed-organism/variant.${CANDIDATE_VARIANT}.json"
[[ -f "$PARENT_FILE" ]] || { echo "Parent variant not found: $PARENT_FILE"; exit 1; }
[[ -f "$CANDIDATE_FILE" ]] || { echo "Candidate variant not found: $CANDIDATE_FILE"; exit 1; }

say "Screening parent $PARENT_LABEL against candidate $CANDIDATE_VARIANT."
say "This runs two full measurements. It is a screening observation, not an acceptance or payout event."
python3 tools/seed_organism.py screen-variant \
  --parent-variant "$PARENT_FILE" \
  --candidate-variant "$CANDIDATE_FILE" \
  --execute \
  --cycle-id "$CYCLE_ID"

say "Uploading local screen bundle to CursiveRoot."
python3 tools/seed_organism.py upload || say "Upload unavailable; the bundle remains saved locally under $TARGET_DIR/.cursiveos/seed/."
python3 tools/seed_organism.py status
say "Finished. Logs are under $TARGET_DIR/logs/."
