#!/bin/bash
# Manual Honcho Postgres backup.
#
# pg_dump uses Postgres MVCC for transactionally consistent snapshots —
# no live-write race even while honcho-deriver is busy. Ships to
# /root/backups/honcho/ on the NUC host.
#
# See kate/docs/research/platform-migration/02-backup-procedures.md
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="honcho-${TIMESTAMP}.sql.gz"
HOST_TARGET="/root/backups/honcho/${BACKUP_NAME}"

echo "==> pg_dump | gzip"
kubectl exec -n honcho postgres-0 -- bash -c '
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    --no-owner --clean --if-exists
' | gzip > "/tmp/${BACKUP_NAME}"

ls -lah "/tmp/${BACKUP_NAME}"

echo "==> copy to NUC host"
nuc "mkdir -p /root/backups/honcho" >/dev/null
cat "/tmp/${BACKUP_NAME}" | nuc "cat > ${HOST_TARGET} && chmod 600 ${HOST_TARGET}"
rm -f "/tmp/${BACKUP_NAME}"

echo "==> verify"
nuc "ls -lah ${HOST_TARGET}"
