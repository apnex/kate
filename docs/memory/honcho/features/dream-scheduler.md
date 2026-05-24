# Dream scheduler

## §A Tier 1 — Claim

§A1 `DreamScheduler` is a process-singleton holding `pending_dreams: dict[work_unit_key, asyncio.Task]`; one delayed task per `(workspace, observer, observed, dream_type)`.

§A2 Scheduling a dream creates an `asyncio.Task` that sleeps `DREAM.IDLE_TIMEOUT_MINUTES` then enqueues a queue item. Scheduling the same key twice cancels the prior task first.

§A3 Eligibility check `check_and_schedule_dream(collection)` is invoked per-collection and fires only when all gates pass: dreams enabled; `Δexplicit_documents ≥ DREAM.DOCUMENT_THRESHOLD`; hours since last dream ≥ `DREAM.MIN_HOURS_BETWEEN_DREAMS`; no pending dream queue item for the same key; no scheduled in-memory task.

§A4 Document count compared against threshold counts only `Document.level == "explicit"` rows — dreamer output (`deductive` / `inductive` / `contradiction`) is excluded to prevent self-reinforcing feedback.

§A5 Baseline (`last_dream_document_count`) and timestamp (`last_dream_at`) live in `Collection.internal_metadata["dream"]` and advance only when a dream actually consolidates.

§A6 In-flight detection uses two layers: (a) the in-memory `pending_dreams` dict, (b) a `queue_items WHERE task_type='dream' AND processed=False AND work_unit_key IN (…)` existence check that mirrors the DB-level partial-unique index `uq_queue_dream_pending_work_unit_key`.

§A7 Each enabled dream type in `DREAM.ENABLED_TYPES` gets its own work unit key, so multiple dream types can be scheduled concurrently for one collection.

§A8 Telemetry captures both `trigger_reason` ("document_threshold") and `delay_reason` ("idle_timeout" or "immediate") at schedule time; the kwargs are threaded through the queue payload to `DreamRunEvent`.

§A9 Cancellation: `cancel_dream(key)` removes from `pending_dreams` and awaits task termination; `cancel_dreams_for_observed(workspace, observed)` cancels all dreams targeting a given observed peer (used when the peer is deleted).

§A10 Process shutdown cancels every entry in `pending_dreams` and gathers them with `return_exceptions=True`.

## §B Tier 2 — Source

§B1 `src/dreamer/dream_scheduler.py` lines 33-52: singleton + `pending_dreams` state.

§B2 Lines 54-95: `schedule_dream` (cancel-then-create-task pattern).

§B3 Lines 97-106: `cancel_dream` (with `contextlib.suppress(CancelledError)`).

§B4 Lines 108-?: `cancel_dreams_for_observed`.

§B5 Lines 240-245: shutdown drain.

§B6 Lines 248-406: `check_and_schedule_dream` (gates §A3, baseline read §A5, in-flight check §A6, fan-out per type §A7).

§B7 Lines 280-288: explicit-only document count.

§B8 Lines 305-313: `trigger_reason` / `delay_reason` split.

§B9 Lines 337-360: queue-level pending check using `construct_work_unit_key` and the partial-unique index mirror.

§B10 `src/config.py` `DreamSettings` (lines 1131+): `ENABLED`, `DOCUMENT_THRESHOLD`, `MIN_HOURS_BETWEEN_DREAMS`, `IDLE_TIMEOUT_MINUTES`, `ENABLED_TYPES`, surprisal thresholds.

## §C Tier 3 — Analytical

§C1 **Two writers, one queue, two anti-duplication layers.** The in-memory `pending_dreams` dict guards within a single process; the partial-unique index `uq_queue_dream_pending_work_unit_key` guards across processes. Either alone is insufficient — restart drops the in-memory layer; the DB layer doesn't see scheduled-but-not-yet-enqueued tasks.

§C2 **Idle-timeout debouncing.** `IDLE_TIMEOUT_MINUTES > 0` gives a window to coalesce bursty messages into a single dream. `=0` makes dreams fire immediately on threshold, at the cost of more dream-runs per unit time.

§C3 **Min-hours gate is post-trigger.** The threshold check fires first; the min-hours guard then suppresses the schedule. Telemetry records only dreams that actually fire — gated-off attempts are invisible to dashboards but logged at INFO level.

§C4 **Baseline advance coupled to consolidation success.** If the dream task crashes or the consolidator rejects, `last_dream_document_count` does not advance and the next message retries — at most the gate windows back off, never the substrate.

§C5 **No persistence of scheduled (vs enqueued) timers.** A process kill during the IDLE window loses the pending `asyncio.Task`; the next message that triggers a re-check restarts the timer (in-memory layer empty + DB layer empty → re-schedule).

§C6 **Per-type fan-out is intentional.** Each dream type is an independent specialist; running them concurrently amortises the idle wait and lets a single trigger feed deductive + inductive + contradiction passes in parallel.
