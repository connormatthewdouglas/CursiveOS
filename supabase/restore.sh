#!/usr/bin/env bash
#
# Restore a CursiveRoot encrypted backup into a Postgres database.
#
# Usage:
#   BACKUP_PASSPHRASE='...' SUPABASE_DB_URL='postgresql://...' \
#     ./supabase/restore.sh supabase/backups/cursiveroot-YYYYMMDD-HHMMSS.dump.gpg
#
# If no file is given, the newest backup in supabase/backups/ is used.
#
# Requirements: gpg, pg_restore (PostgreSQL 17 client).
#
# SAFETY: This restores into whatever SUPABASE_DB_URL points at. Point it at a
# scratch/branch database first and verify before ever aiming it at production.
# --clean drops public-schema objects before recreating them.

set -euo pipefail

: "${BACKUP_PASSPHRASE:?Set BACKUP_PASSPHRASE (same passphrase used to encrypt the backup)}"
: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL (target connection string, e.g. session pooler)}"

backups_dir="$(cd "$(dirname "$0")" && pwd)/backups"
enc="${1:-$(ls -1t "$backups_dir"/cursiveroot-*.dump.gpg 2>/dev/null | head -n1)}"

if [[ -z "${enc:-}" || ! -f "$enc" ]]; then
  echo "No backup file found. Pass one explicitly or populate $backups_dir." >&2
  exit 1
fi

echo "Restoring from: $enc"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

plain="$tmp/restore.dump"
gpg --batch --yes --pinentry-mode loopback \
  --passphrase "$BACKUP_PASSPHRASE" \
  --decrypt --output "$plain" "$enc"

# --clean --if-exists makes the restore idempotent against an existing public schema.
pg_restore \
  --no-owner --no-privileges \
  --clean --if-exists \
  --schema=public \
  --dbname "$SUPABASE_DB_URL" \
  "$plain"

echo "Restore complete."
