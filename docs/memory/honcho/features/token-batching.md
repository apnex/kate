# Feature: token-batching

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Derivation
**Triangulation:** ✓ Triangulated (docs claim, source confirms exact number)

## What it is (substrate's own terms)

Rather than running the deriver on every individual message, Honcho accumulates messages in a per-`(observer, observed)` work-unit queue and processes them as a single batch once the cumulative token count crosses a configurable threshold (default **1024 tokens** — matches the docs' "roughly 1,000 tokens"). A flush-mode override (`FLUSH_ENABLED`) bypasses the threshold and processes every queued item immediately, useful for low-throughput or interactive scenarios.

## Requirement

The system SHALL, when assembling a deriver batch from queued items for a given work-unit, exclude items whose addition would not bring the cumulative token sum to at least `settings.DERIVER.REPRESENTATION_BATCH_MAX_TOKENS`, UNLESS `settings.DERIVER.FLUSH_ENABLED` is true (in which case the threshold is bypassed and items are processed as available). The threshold MUST NOT exceed `settings.DERIVER.MAX_INPUT_TOKENS`.

## Scenarios

### Scenario: batch waits below threshold (default mode)
- GIVEN `FLUSH_ENABLED=False` and `REPRESENTATION_BATCH_MAX_TOKENS=1024`
- AND a work-unit has 3 queued items totalling 600 tokens
- WHEN `get_queue_item_batch` is invoked
- THEN no batch is returned for processing (items remain queued)
- AND `hit_batch_token_cap=False`, `was_flush_enabled=False` are recorded in the (empty) `QueueBatchResult`

### Scenario: batch flushes when threshold reached
- GIVEN `FLUSH_ENABLED=False` and `REPRESENTATION_BATCH_MAX_TOKENS=1024`
- AND a work-unit has 5 queued items totalling 1200 tokens
- WHEN `get_queue_item_batch` is invoked
- THEN a batch containing items summing to ≥ 1024 tokens is returned
- AND the deriver receives this batch with `hit_batch_token_cap=True`, `was_flush_enabled=False`, `batch_max_tokens=1024`

### Scenario: flush mode bypasses threshold
- GIVEN `FLUSH_ENABLED=True`
- AND a work-unit has 1 queued item totalling 50 tokens
- WHEN `get_queue_item_batch` is invoked
- THEN the item is immediately included in a batch and returned
- AND `was_flush_enabled=True` is recorded for telemetry distinction from threshold-driven batches

### Scenario: configuration validation prevents inverted cap
- GIVEN a configuration sets `REPRESENTATION_BATCH_MAX_TOKENS=30000` and `MAX_INPUT_TOKENS=25000`
- WHEN settings are loaded
- THEN a validation error is raised: *"REPRESENTATION_BATCH_MAX_TOKENS (30000) cannot exceed max deriver input tokens (25000)"*

### Scenario: telemetry distinguishes batching modes
- GIVEN any batch processed by the deriver
- WHEN `RepresentationCompletedEvent` is emitted
- THEN it carries `batch_max_tokens` (the configured cap at fetch time), `hit_batch_token_cap` (whether the cap clamped this batch), `was_flush_enabled` (whether flush mode was active at fetch time)
- AND downstream analytics can distinguish "we waited for the batch to fill" from "we processed early because flush was on" from "we hit the cap and stopped batching"

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` §Token Batching — "Honcho accumulates messages in the queue and processes them as a batch once the total token count … crosses a threshold — roughly **1,000 tokens** at the current batch size" |
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` §Token Batching Note — "This batching only applies to **representation** tasks. Summary and dream tasks have their own scheduling logic and are not subject to the token threshold." |
| Source | `src/config.py:775-778` — `REPRESENTATION_BATCH_MAX_TOKENS: int = 1024` (range `[128, 16_384]`) |
| Source | `src/config.py:781` — `FLUSH_ENABLED: bool = False` |
| Source | `src/config.py:764` — `MAX_INPUT_TOKENS: int = 25000` (hard-capped, `le=25000`) |
| Source | `src/config.py:783-798` — validator: `REPRESENTATION_BATCH_MAX_TOKENS` cannot exceed `MAX_INPUT_TOKENS` |
| Source | `src/deriver/queue_manager.py:62-76` — `QueueBatchResult` dataclass fields (`hit_batch_token_cap`, `was_flush_enabled`, `batch_max_tokens`) |
| Source | `src/deriver/queue_manager.py:282-289` — batch-size logic preamble: "REPRESENTATION_BATCH_MAX_TOKENS (forced batching), unless FLUSH_ENABLED is True" |
| Source | `src/deriver/queue_manager.py:332-340` — `if not settings.DERIVER.FLUSH_ENABLED and batch_max_tokens > 0: ... >= batch_max_tokens` — the threshold gate |
| Source | `src/deriver/queue_manager.py:656-695` — `get_queue_item_batch` function returning `QueueBatchResult` |
| Source | `src/deriver/deriver.py:287-317` — `RepresentationCompletedEvent` emission carrying batch fields |

## Behaviour notes (Tier 3 — prober analysis)

- **Docs' "roughly 1,000 tokens" is exact: the default is 1024.** Slight over-precision in source vs round-numbering in docs is fine; the practical cost model the docs imply is accurate.
- **Batching applies only to representation tasks.** Summary tasks and dream tasks have their own schedulers (`src/utils/summarizer.py` and `src/dreamer/dream_scheduler.py`). Per-feature specs for those will document their independent cadence logic.
- **Flush mode is the right choice for interactive single-user scenarios.** With `FLUSH_ENABLED=True`, every message becomes a batch of 1 → the deriver runs per-message. This trades cost for latency; in our k3s single-user deployment, this is probably the better setting if reasoning latency matters more than cost.
- **The hard cap of 25000 on `MAX_INPUT_TOKENS`** is a defensive limit — even with `MAX_INPUT_TOKENS=25000` and `REPRESENTATION_BATCH_MAX_TOKENS=16384` (the configured maxes), the deriver will never see >25k tokens in one call. This is sensible for cost control but also limits the maximum useful batch.
- **`hit_batch_token_cap` vs `hit_input_token_cap` are two different things** [code: `deriver.py:313-314`]. The first means the BATCHER clamped the batch. The second means the LLM CALL truncated input. Both can fire independently. Operationally important for debugging "why didn't my message get fully reasoned over."
- **Empty queues drop `QueueEmptyEvent` webhooks** [code: `queue_manager.py:42-45` imports `QueueEmptyEvent`, `publish_webhook_event`]. Listeners can subscribe to know when reasoning catches up to message arrival. Useful for "wait for derivation complete" patterns.
