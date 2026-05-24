# Worker lease model

## §A Tier 1 — Claim

§A1 Concurrency is gated at the granularity of a **work unit key** (string carrying task_type + scope, e.g. `representation:…` or `dream:…`).

§A2 A claim is acquired by inserting a row into the `active_queue_sessions` (AQS) table; the row's existence is the lease.

§A3 The claim is a single `INSERT … ON CONFLICT DO NOTHING RETURNING work_unit_key, id` over a candidate batch — Postgres adjudicates contention; losers silently drop out.

§A4 Each deriver process has an in-memory `worker_ownership: dict[worker_id, (work_unit_key, aqs_id)]` that mirrors what it believes it holds.

§A5 Per-poll claim budget: `limit = workers - len(worker_ownership)`; the poller never asks the DB for more work than the process can pick up.

§A6 Stale leases are reaped by `cleanup_stale_work_units` once `ActiveQueueSession.last_updated < now - DERIVER.STALE_SESSION_TIMEOUT_MINUTES` (default 5 minutes), using `SELECT … FOR UPDATE SKIP LOCKED` then `DELETE`.

§A7 During processing, every iteration re-checks `worker_ownership[worker_id] == work_unit_key`; mismatch causes the worker to abandon the unit without committing further changes.

§A8 Representation work units are additionally gated by accumulated token count: the candidate query filters to keys whose summed `Message.token_count` ≥ `DERIVER.REPRESENTATION_BATCH_MAX_TOKENS` (default 1024) — unless `DERIVER.FLUSH_ENABLED=true`, in which case the threshold is bypassed.

§A9 Lease release on shutdown: `worker_ownership` is drained, the corresponding AQS rows are deleted in one statement, and the in-memory dict cleared.

## §B Tier 2 — Source

§B1 `src/deriver/queue_manager.py` lines 122-175: `WorkerOwnership` dataclass + ownership tracker methods.

§B2 Lines 218-243: shutdown drain (`cleanup` releases AQS rows in bulk).

§B3 Lines 249-276: `cleanup_stale_work_units` (timestamp + `with_for_update(skip_locked=True)`).

§B4 Lines 278-353: `get_and_claim_work_units` (token-batch filter, AQS-exists exclusion, claim limit).

§B5 Lines 355-379: `claim_work_units` (`INSERT … ON CONFLICT DO NOTHING RETURNING`).

§B6 Lines 470-547: `process_work_unit` (re-checks ownership before each side-effect).

§B7 `src/config.py` lines 736-781: `DERIVER.WORKERS`, `POLLING_SLEEP_INTERVAL_SECONDS`, `STALE_SESSION_TIMEOUT_MINUTES`, `REPRESENTATION_BATCH_MAX_TOKENS`, `FLUSH_ENABLED`.

## §C Tier 3 — Analytical

§C1 **Lease atomicity is delegated to Postgres unique constraint.** No application-side mutex; the `ON CONFLICT DO NOTHING` clause is the entire mutual-exclusion mechanism. Correctness rides on the `work_unit_key` unique index existing on `active_queue_sessions`.

§C2 **No keepalive on `last_updated`.** A worker holding a unit for longer than `STALE_SESSION_TIMEOUT_MINUTES` without updating the timestamp is at risk of having its lease swept by another process. The 5-minute default sets an implicit upper bound on per-unit processing time.

§C3 **Ownership check is advisory, not transactional.** §A7's mismatch detection is best-effort: between the check and the next DB write, the lease could still be reaped. Idempotency of downstream writes is required for safety.

§C4 **Claim budget = workers, not threads.** With `DERIVER.WORKERS=1` (default), a process holds at most one unit at a time even if the queue is large; horizontal throughput requires either raising `WORKERS` or running more processes.

§C5 **Token-batch filter is a coalescing optimisation, not back-pressure.** Sub-threshold work units are not lost — they wait in `queue_items` until the next message bumps them over the threshold or `FLUSH_ENABLED` is toggled. With sparse traffic this can stall observation indefinitely; the dreamer's per-message scheduling does not depend on the deriver flushing.

§C6 **Stale reaper uses `SKIP LOCKED`.** Two concurrent reapers cannot collide; whichever locks a stale row first deletes it.
