#!/bin/bash
# Manual hermes backup with SQLite consistency. Zero-downtime.
#
# Snapshots SQLite databases via Python sqlite3.backup() (MVCC-safe)
# before tarring the rest of /opt/data, then ships to /root/backups/ on
# the NUC host. Excludes cache/tmp as transient.
#
# See kate/docs/research/platform-migration/02-backup-procedures.md
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="hermes-${TIMESTAMP}.tar.gz"
HOST_TARGET="/root/backups/hermes/${BACKUP_NAME}"
POD=$(kubectl get pod -n hermes -l app=hermes -o jsonpath='{.items[0].metadata.name}')

echo "==> upload backup-inside-pod script"
# We use a single heredoc-rendered script and pipe it in; this avoids
# multi-layer shell quoting nightmares.
kubectl exec -i -n hermes "${POD}" -c hermes -- bash -s -- "${BACKUP_NAME}" <<'PODSCRIPT'
set -euo pipefail
BACKUP_NAME="$1"
STAGE=/tmp/hermes-backup-stage
rm -rf "$STAGE" "/tmp/${BACKUP_NAME}"
mkdir -p "$STAGE"

# 1. Online-backup each SQLite DB via Python sqlite3 API.
/opt/hermes/.venv/bin/python <<'PYEOF'
import sqlite3, os, glob
src_dir = '/opt/data'
stage = '/tmp/hermes-backup-stage'
for db_path in sorted(glob.glob(os.path.join(src_dir, '*.db'))):
    name = os.path.basename(db_path)
    dst_path = os.path.join(stage, name)
    src = sqlite3.connect(db_path)
    dst = sqlite3.connect(dst_path)
    with dst:
        src.backup(dst)
    src.close(); dst.close()
    print(f'  snapshot: {name} ({os.path.getsize(dst_path)} bytes)')
PYEOF

# 2. Tar everything except live SQLite + transient dirs.
# tar may exit 1 ("some files differ as we read") even with
# --warning=no-file-changed; that's a usable archive per tar docs.
# Only exit 2 is fatal. So we explicitly allow exit 1 here.
echo "  tarring /opt/data (excluding live SQLite + cache/tmp)..."
cd /opt/data
set +e
tar czf "/tmp/${BACKUP_NAME}" \
    --exclude='./*.db' --exclude='./*.db-wal' --exclude='./*.db-shm' \
    --exclude='./tmp' --exclude='./cache' \
    --warning=no-file-changed \
    .
TAR_RC=$?
set -e
if [ "$TAR_RC" -gt 1 ]; then
    echo "FATAL: tar returned $TAR_RC (expected 0 or 1)" >&2
    exit "$TAR_RC"
fi
if [ "$TAR_RC" -eq 1 ]; then
    echo "  note: tar reported file-changed during read (exit 1) — archive usable"
fi
echo "  base tar size: $(stat -c %s "/tmp/${BACKUP_NAME}") bytes"

# 3. Append SQLite snapshots into same tarball. tar -r needs uncompressed.
echo "  appending SQLite snapshots..."
gunzip "/tmp/${BACKUP_NAME}"
cd "$STAGE"
tar rf "/tmp/${BACKUP_NAME%.gz}" .
gzip "/tmp/${BACKUP_NAME%.gz}"

# 4. Cleanup
rm -rf "$STAGE"
echo "  final bundle: $(stat -c %s "/tmp/${BACKUP_NAME}") bytes"
PODSCRIPT

echo "==> stream bundle from pod → NUC via kubectl exec cat (kubectl cp is unreliable for large files)"
nuc "mkdir -p /root/backups/hermes" >/dev/null
kubectl exec -n hermes "${POD}" -c hermes -- cat "/tmp/${BACKUP_NAME}" \
  | nuc "cat > ${HOST_TARGET} && chmod 600 ${HOST_TARGET}"

echo "==> verify gzip integrity on NUC"
nuc "gzip -t ${HOST_TARGET} && echo 'gzip OK'"

echo "==> cleanup pod"
kubectl exec -n hermes "${POD}" -c hermes -- rm -f "/tmp/${BACKUP_NAME}"

echo "==> verify on NUC"
nuc "ls -lah ${HOST_TARGET}"
nuc "tar tzf ${HOST_TARGET} 2>/dev/null | grep -E '\\.db$' | head -5"
