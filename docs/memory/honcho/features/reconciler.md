# Feature: reconciler-embedding-sync

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Background subsystem
**Triangulation:** ✓ Triangulated

## What it is

The reconciler is a periodic healing job that syncs Documents and Message embeddings to the external vector store on a rolling basis. It scans for `sync_state='pending'` rows past their backoff window, re-embeds if needed, and pushes to the vector store. After 20 failed attempts (with 10-minute backoff = ~3 hours of headroom) a row is marked permanently failed.

## Requirement

The system SHALL run a periodic reconciliation job that finds Documents and Messages with missing or stale vector-store representations, embeds and upserts them in batches of 50, applies a 10-minute backoff between sync attempts per row, and marks rows as failed after 20 consecutive attempts.

## Scenarios

### Scenario: pending documents are synced
- GIVEN Documents with `sync_state='pending'` whose `last_sync_at` is NULL or older than 10 minutes
- WHEN the reconciliation cycle runs
- THEN up to 50 documents are selected per cycle
- AND embeddings are computed if missing
- AND vector records are upserted into the external vector store
- AND `sync_state` is updated to `'synced'`, `last_sync_at=now()`, `sync_attempts=0` on success

### Scenario: failed sync increments attempts with backoff
- GIVEN a Document whose vector-store upsert fails
- WHEN the failure occurs
- THEN `sync_attempts` is incremented
- AND `last_sync_at` is set to now (engaging the 10-minute backoff)
- AND the row remains in `sync_state='pending'`

### Scenario: chronically-failed documents are marked failed
- GIVEN a Document whose `sync_attempts >= 20`
- WHEN the reconciliation cycle considers it
- THEN it is marked with `sync_state='failed'`
- AND it is no longer attempted on future cycles
- AND the reconciliation metric `documents_failed` is incremented

### Scenario: cycle respects a time budget
- GIVEN a reconciliation cycle has been running for ≥ `RECONCILIATION_TIME_BUDGET_SECONDS` (240s)
- WHEN the next batch would be processed
- THEN the cycle exits early to leave headroom for other maintenance work
- AND the next cycle resumes from where this one stopped

### Scenario: soft-deleted documents are cleaned up
- GIVEN Documents marked `deleted_at NOT NULL` (e.g. by deduplication rejection)
- WHEN reconciliation runs
- THEN their vectors are removed from the external vector store
- AND the document records are hard-deleted from Postgres

### Scenario: write-path crash leaves recoverable state
- GIVEN a deriver crash between Postgres commit and vector-store upsert
- THEN the Document exists in Postgres with `sync_state='pending'` and (possibly) NULL embedding
- AND the next reconciliation cycle re-embeds and upserts it

## Evidence

| Type | Reference |
|---|---|
| Claim | `CLAUDE.md` — references reconciler subsystem |
| Doc | `src/reconciler/sync_vectors.py:1-6` — "periodic reconciliation job that syncs documents and message embeddings to the vector store on a rolling basis, healing any missed writes" |
| Source | `src/reconciler/sync_vectors.py:32-37` — constants: `RECONCILIATION_BATCH_SIZE=50`, `RECONCILIATION_TIME_BUDGET_SECONDS=240`, `MAX_SYNC_ATTEMPTS=20`, `SYNC_BACKOFF=10min` |
| Source | `src/reconciler/sync_vectors.py:40-47` — `_backoff_eligible` predicate |
| Source | `src/reconciler/sync_vectors.py:50-70` — `ReconciliationMetrics` dataclass with synced/failed/cleaned counters |
| Source | `src/crud/document.py:518-522` — crash-recovery NOTE: "If the process crashes after this commit but before vector upsert completes, documents will be left in sync_state='pending' with NULL embeddings. The reconciliation job will automatically re-embed and sync these documents" |
| Source | `src/crud/document.py:502` — primary write path sets `sync_state='pending'` before vector upsert |
| Source | `src/reconciler/scheduler.py` (268 LOC) — periodic scheduler driving the reconciliation cycles |
| Source | `src/reconciler/queue_cleanup.py` (54 LOC) — companion job: cleanup of queue items |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Read-side queries** (how documents are retrieved by the agent layer) are promoted to `features/document-query-strategies.md`. This spec covers the reconciler's **vector-sync write-back path**; that spec covers the read paths the dialectic/dreamer use.
- **~3 hours of vector-store outage headroom before any data loss flag.** `MAX_SYNC_ATTEMPTS=20 × SYNC_BACKOFF=10min ≈ 200 minutes`. During an outage of less than this duration, all writes are recoverable. Operational implication: vector store downtime is non-fatal for short outages. See `04-assessment.md §A30`.
- **Vector-store-only worker — Postgres is the source of truth.**
- **"Heals missed writes" framing is precise.** The reconciler is not a generator or a refresher; it specifically targets the gap between Postgres durability and vector-store eventual consistency.
- **Soft-delete → vector cleanup → hard-delete sequence.** Deduplication rejects (soft-delete; see `features/consolidation.md`) flow through the reconciler for vector cleanup before the row is physically removed. Single subsystem owns vector-store hygiene.
- **Time budget (4 minutes per cycle) leaves operational headroom.** Designed to share its scheduler slot with the dreamer and deriver (all three are orchestrated by `queue_manager.py`). Not greedy.
- **No exponential backoff — flat 10-minute interval.** Design choice: predictable retry cadence over fast retry of transient errors. Trade-off: a transient blip causes a 10-minute delay before the next attempt.

## Configuration surface

| Knob | Default (hard-coded) | Source |
|---|---|---|
| `RECONCILIATION_BATCH_SIZE` | 50 | `src/reconciler/sync_vectors.py:32` |
| `RECONCILIATION_TIME_BUDGET_SECONDS` | 240 | `src/reconciler/sync_vectors.py:33` |
| `MAX_SYNC_ATTEMPTS` | 20 | `src/reconciler/sync_vectors.py:34` |
| `SYNC_BACKOFF` | 10 minutes | `src/reconciler/sync_vectors.py:37` |
| (Schedule cadence) | per `scheduler.py` | `src/reconciler/scheduler.py` |
