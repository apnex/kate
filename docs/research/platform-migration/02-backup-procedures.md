# Backup Procedures — Phase C / 3a

**Status:** Established 2026-05-26. Manual-only (no scheduled jobs
yet, per user direction — to be added once the system is finalised).
**Target:** NUC host `/root/backups/` (in-cluster trust boundary).
**Off-host roadmap:** see `backup-offsite-roadmap.md` for the planned
upgrade path.

---

## What's backed up

| Component | Source | Method | Target |
|---|---|---|---|
| Hermes session state | PVC `hermes-data` (mounted at `/opt/data`) | `tar czf` via `kubectl exec` | `/root/backups/hermes/hermes-YYYYMMDD-HHMMSS.tar.gz` |
| Honcho memory database | Postgres in `honcho` namespace, db `honcho` | `pg_dump` via `kubectl exec` | `/root/backups/honcho/honcho-YYYYMMDD-HHMMSS.sql.gz` |

**Not backed up (by design):**
- Honcho Redis state — transient worker queue, recoverable
- Honcho/Hermes Deployments — stateless, defined in manifests
- Kubernetes Secrets — managed out-of-band via `set-secret` scripts in
  each component repo (apnex/hermes and apnex/honcho); credentials live
  in the user's password store, not in backups
- ConfigMaps — GitOps-managed, recoverable from Git

---

## Cutover insurance: PV ReclaimPolicy patched to Retain

**Done 2026-05-26.** Both PVs in scope have been patched from `Delete`
(local-path-provisioner default) to `Retain`:

```bash
kubectl patch pv pvc-a9187042-3c89-475b-8bb3-92c006f6f610 \
  -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

kubectl patch pv pvc-d7844fdd-1276-4195-b384-e3bf39c27625 \
  -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

This means: even if ArgoCD mistakenly prunes the PVC during cutover,
the underlying PV (and the data on it at
`/var/lib/rancher/k3s/storage/`) survives and can be manually re-bound.

**Future PVCs** created by either component will revert to `Delete`
because that's the StorageClass default. Long-term fix (a custom
StorageClass with `Retain` default) is tracked in
`backup-offsite-roadmap.md` § "Substrate-level PV protection".

---

## Hermes backup procedure (manual)

**IMPORTANT — SQLite consistency:** Hermes maintains live SQLite
databases (`state.db`, `response_store.db`, `kanban.db`) under
`/opt/data/`. A naive `tar` while the agent is running captures
**inconsistent** snapshots (tar reports `file changed as we read it`
+ `File shrank by N bytes`). To get transactionally safe backups
without stopping the agent, snapshot the SQLite files first using
Python's `sqlite3.backup()` API (online-backup, MVCC-safe), then tar
everything from the staging dir.

The `sqlite3` CLI is not present in the image. Python is — and the
venv at `/opt/hermes/.venv/bin/python` has the sqlite3 stdlib module.

```bash
#!/bin/bash
# Manual hermes backup with SQLite consistency. Zero-downtime.
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="hermes-${TIMESTAMP}.tar.gz"
HOST_TARGET="/root/backups/hermes/${BACKUP_NAME}"

echo "==> stage SQLite snapshots + tar inside pod"
kubectl exec -n hermes deploy/hermes -c hermes -- bash -c "
set -euo pipefail
STAGE=/tmp/hermes-backup-stage
rm -rf \"\$STAGE\"
mkdir -p \"\$STAGE\"

# 1. Online-backup each SQLite DB via Python sqlite3 API.
#    Auto-discovers any .db files at /opt/data root (state.db,
#    response_store.db, kanban.db today; resilient to future additions).
/opt/hermes/.venv/bin/python <<'PYEOF'
import sqlite3, os, glob, pathlib
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

# 2. Tar everything from /opt/data EXCEPT the live SQLite files + their
#    WAL/SHM sidecars (those would be inconsistent). Then merge in the
#    consistent snapshots.
cd /opt/data
tar czf \"/tmp/${BACKUP_NAME}\" \\
    --exclude='*.db' --exclude='*.db-wal' --exclude='*.db-shm' \\
    --exclude='./tmp' --exclude='./cache' \\
    .

# 3. Append the SQLite snapshots into the tar as if they were /opt/data/*.db
cd \"\$STAGE\"
tar rzf \"/tmp/${BACKUP_NAME}\" -C \"\$STAGE\" . 2>/dev/null || \\
  (gunzip \"/tmp/${BACKUP_NAME}\"; tar rf \"/tmp/${BACKUP_NAME%.gz}\" -C \"\$STAGE\" .; gzip \"/tmp/${BACKUP_NAME%.gz}\")

# 4. Cleanup stage
rm -rf \"\$STAGE\"

echo \"  bundle: \$(ls -lah /tmp/${BACKUP_NAME} | awk '{print \$5}')\"
"

echo "==> copy to NUC host"
POD=\$(kubectl get pod -n hermes -l app=hermes -o jsonpath='{.items[0].metadata.name}')
kubectl cp -c hermes "hermes/\${POD}:/tmp/${BACKUP_NAME}" "/tmp/${BACKUP_NAME}"
nuc "mkdir -p /root/backups/hermes" >/dev/null
cat "/tmp/${BACKUP_NAME}" | nuc "cat > ${HOST_TARGET} && chmod 600 ${HOST_TARGET}"
rm -f "/tmp/${BACKUP_NAME}"
kubectl exec -n hermes deploy/hermes -c hermes -- rm -f "/tmp/${BACKUP_NAME}"

echo "==> verify"
nuc "ls -lah ${HOST_TARGET}"
```

**Why this works:**
- `sqlite3.backup()` is the SQLite online-backup API — takes a
  transactionally consistent snapshot while the source DB stays
  fully writable
- WAL/SHM sidecars are excluded from the main tar (excluding them
  prevents tar-time inconsistency warnings)
- Snapshots are added to the same tarball so restore is one operation
- `cache/` and `tmp/` excluded as recoverable transient data

**Estimated size:** ~280-350MB compressed.

**Recovery:** untar into the PVC at `/opt/data/`. The SQLite snapshots
restore as ordinary `*.db` files — they take effect when the agent
next opens them (which means restore should be done with the agent
scaled to zero):
```bash
kubectl scale deploy -n hermes hermes --replicas=0
kubectl wait --for=delete pod -n hermes -l app=hermes --timeout=60s
# Approach 1: restore via temporary helper pod that mounts the PVC
kubectl run -n hermes restore-helper --rm -it \
  --image=busybox --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"hermes-data"}}],"containers":[{"name":"restore","image":"busybox","stdin":true,"tty":true,"command":["sh"],"volumeMounts":[{"name":"data","mountPath":"/opt/data"}]}]}}'
# Inside the helper: cd /opt/data && tar xzf /tmp/restore.tar.gz
kubectl scale deploy -n hermes hermes --replicas=1
```

---

## Honcho backup procedure (manual)

```bash
#!/bin/bash
# Manual Honcho Postgres backup. Run from any machine with kubectl access.
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="honcho-${TIMESTAMP}.sql.gz"
HOST_TARGET="/root/backups/honcho/${BACKUP_NAME}"

echo "==> running pg_dump inside postgres-0"
kubectl exec -n honcho postgres-0 -- bash -c '
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists
' | gzip > "/tmp/${BACKUP_NAME}"

echo "==> copying to host via nuc"
nuc "mkdir -p /root/backups/honcho" >/dev/null
cat "/tmp/${BACKUP_NAME}" | nuc "cat > ${HOST_TARGET} && chmod 600 ${HOST_TARGET}"
rm -f "/tmp/${BACKUP_NAME}"

echo "==> verify"
nuc "ls -lah ${HOST_TARGET}"
```

**Notes:**
- `--clean --if-exists` makes the dump self-contained: restore can be
  applied to a fresh or existing DB without manual cleanup
- `--no-owner` strips ownership grants — restoring to a different
  Postgres role works without errors
- Credentials sourced from envFrom on the pod (`POSTGRES_USER`,
  `POSTGRES_DB` from `postgres-credentials` Secret)
- The dump captures schema + data + pgvector extension state
- Host file mode `600` — DB dump contains all peer/memory data

**Estimated size:** small (Postgres dumps of vector data compress well;
typical few MB at current scale).

**Recovery (full restore):**
```bash
# 1. Ensure postgres pod is running
# 2. Optionally drop existing DB contents if doing a clean restore:
#    kubectl exec -n honcho postgres-0 -- psql -U honcho -d postgres -c 'DROP DATABASE honcho;'
#    kubectl exec -n honcho postgres-0 -- psql -U honcho -d postgres -c 'CREATE DATABASE honcho;'
# 3. Stream the dump back in
zcat /root/backups/honcho/honcho-YYYYMMDD-HHMMSS.sql.gz | \
  kubectl exec -n honcho -i postgres-0 -- \
    psql -U honcho -d honcho
```

**WARNING:** restoring to a live Honcho should be done with the API
deployments (`honcho`, `honcho-deriver`) scaled to zero first, to
prevent races during the restore:
```bash
kubectl scale deploy -n honcho honcho honcho-deriver --replicas=0
# ... restore ...
kubectl scale deploy -n honcho honcho honcho-deriver --replicas=1
```

---

## Verification log (first runs)

See `backup-verification-2026-05-26.md` (sibling doc) for the
first-run verification results from this session.

---

## Future work

- **Scheduling:** Add CronJobs or hermes cron tasks once system is
  finalised. Tentative cadence: daily + weekly rotation.
- **Off-host:** See `backup-offsite-roadmap.md` for the planned upgrade
  path to true disaster-proof backups.
- **Substrate-level PV protection:** Custom StorageClass with Retain
  default to make future PVCs automatically safe.
