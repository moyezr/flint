#!/bin/bash
set -euo pipefail

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is required." >&2
  exit 1
fi

if [[ -z "${FLINT_BACKUP_DIR:-}" ]]; then
  echo "FLINT_BACKUP_DIR must name the directory that will receive the backup." >&2
  exit 1
fi

for command in pg_dump pg_restore shasum; do
  if ! command -v "$command" >/dev/null; then
    echo "Required command is unavailable: $command" >&2
    exit 1
  fi
done

mkdir -p "$FLINT_BACKUP_DIR"
backup_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_path="$FLINT_BACKUP_DIR/flint-postgres-$backup_timestamp.dump"

pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$backup_path" \
  "$DATABASE_URL"

pg_restore --list "$backup_path" >/dev/null
shasum -a 256 "$backup_path" > "$backup_path.sha256"

echo "Created database backup: $backup_path"
echo "Created checksum: $backup_path.sha256"
