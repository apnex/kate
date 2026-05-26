# Backup Verification — 2026-05-26

**First-run verification of the Phase C / 3a backup procedures.**

## Honcho Postgres backup ✓

```
$ bash /host/kate/scripts/backup-honcho.sh
==> pg_dump | gzip
-rw-r--r--. 1 root root 53M /tmp/honcho-*.sql.gz
==> copy to NUC host
==> verify
-rw-------. 1 root root 53M /root/backups/honcho/honcho-*.sql.gz
```

- pg_dump used MVCC; transactionally consistent
- 53MB compressed
- No issues, works first try

## Hermes PVC backup ✓ (after 3 iterations)

```
$ bash /host/kate/scripts/backup-hermes.sh
==> upload backup-inside-pod script
  snapshot: kanban.db (102400 bytes)
  snapshot: response_store.db (20480 bytes)
  snapshot: state.db (88940544 bytes)
  tarring /opt/data (excluding live SQLite + cache/tmp)...
  note: tar reported file-changed during read (exit 1) — archive usable
  base tar size: 325044346 bytes
  appending SQLite snapshots...
  final bundle: 361862640 bytes
==> stream bundle from pod → NUC via kubectl exec cat
==> verify gzip integrity on NUC
gzip OK
==> verify
-rw-------. 1 root root 346M /root/backups/hermes/hermes-*.tar.gz
./kanban.db
./response_store.db
./state.db
```

**End-to-end byte verification:**
- Pod-side bundle: 361,862,640 bytes
- NUC-side file:   361,862,640 bytes (exact match)
- gzip integrity:  OK
- Archive contents: 13,063 files including 3 SQLite snapshots at root
- SQLite snapshot of state.db: SQLite 3.x file, 17 tables,
  **79 sessions + 7,711 messages** restored intact

## Three iterations of debugging that taught us things

### Iteration 1: naive `tar` while agent runs

```
tar: file changed as we read it
tar: File shrank by 363480851 bytes; padding with zeros
```

**Problem:** SQLite WAL/SHM files being actively written → tar reads
inconsistent state → fails. The hermes-data PVC has live SQLite under
write pressure (state.db with 17 tables, 79 sessions, 7711 messages
and growing).

**Lesson:** ANY tar of a live SQLite database is unsafe. Two solutions
exist: stop the agent, OR use SQLite's online-backup API.

### Iteration 2: `set -e` killed script on tar's exit-1 warning

GNU tar exits 1 for "some files differ as we read" (a warning that the
archive is still usable, per tar docs — only exit 2 is fatal). With
`set -e`, this killed the script before the SQLite-snapshot-append step.

**Fix:** explicitly `set +e` around tar, capture exit code, allow 0 or
1 to proceed, only abort on >= 2.

**Lesson:** `set -e` + tar = silent failures on workloads with active
writers. Always check tar's documented exit semantics when scripting it.

### Iteration 3: `kubectl cp` truncated the 361MB bundle

```
kubectl cp -c hermes "hermes/${POD}:/tmp/${BACKUP_NAME}" "/tmp/${BACKUP_NAME}"
# tar: /tmp/hermes-*.tar.gz: File shrank by 361323598 bytes; padding with zeros
```

**Problem:** `kubectl cp` is implemented as a tar-over-exec internally
and is known unreliable for large files — silently truncates.

**Fix:** replaced with `kubectl exec ... -- cat /tmp/bundle | nuc "cat
> dest"`. Plain stdout streaming via exec is reliable.

**Lesson:** for any file > ~50MB, NEVER trust `kubectl cp`. Use
`kubectl exec cat` streaming.

## Final scripts in repo

- `kate/scripts/backup-hermes.sh` — production-ready
- `kate/scripts/backup-honcho.sh` — production-ready

Both are documented inline; both have been run end-to-end against the
live cluster successfully on 2026-05-26.

## Disk usage on NUC

```
/root/backups/hermes/  ~346 MB per backup
/root/backups/honcho/  ~53 MB per backup
```

At daily cadence with the 14+8+6 retention policy that's been
discussed (but not yet implemented): roughly 28 generations of each,
so ~11 GB hermes + ~1.5 GB honcho = **~12.5 GB ceiling**. NUC has
1.5 TB free; not a concern.

## Restore procedures

See `02-backup-procedures.md` § Recovery sections for both Hermes and
Honcho restore commands. Restore procedures are documented but have
NOT been tested in this session. **Restore testing is open work** —
should be done before declaring Phase C complete-complete.
