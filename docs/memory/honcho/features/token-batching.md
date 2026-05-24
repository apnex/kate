# Feature: token-batching

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Derivation
**Triangulation:** ✓ Triangulated

## What it is

Token-batching is the deriver queue's mechanism for accumulating multiple enqueued messages for the same `(observer, observed)` work unit into one LLM call. The batcher draws items from `QueueItem` rows, sums their estimated tokens against `REPRESENTATION_BATCH_MAX_TOKENS`, and flushes the batch when the cap is reached (or when `FLUSH_ENABLED` triggers a timeout-driven flush). The result is one deriver LLM call per batch instead of one per message.

## Requirement

The system SHALL accumulate enqueued messages into batches bounded by a token cap, and SHALL flush partial batches when the timeout-driven flush is enabled.

## Scenarios

### Scenario: messages accumulate until token cap
- GIVEN multiple messages enqueued for the same `(observer, observed)` work unit, none individually exceeding the batch token cap
- WHEN the queue is polled
- THEN messages are accumulated into one batch until adding the next message would exceed `REPRESENTATION_BATCH_MAX_TOKENS` (default 1024)
- AND the batch is flushed with `hit_batch_token_cap=true` on the resulting `QueueBatchResult`

### Scenario: single oversized message is flushed alone
- GIVEN a single message whose estimated tokens exceed `REPRESENTATION_BATCH_MAX_TOKENS`
- WHEN the queue is polled
- THEN that one message constitutes its own batch
- AND no other messages are bundled with it

### Scenario: flush bypass for non-representation tasks
- GIVEN a queued summary or dream task
- WHEN the queue is polled
- THEN the token-batching cap does NOT apply
- AND the task is processed as a single unit

### Scenario: flush-enabled timeout drains partial batch
- GIVEN `FLUSH_ENABLED=true` and a partial batch sitting in the queue past the flush threshold
- WHEN the flush-enabled path triggers
- THEN the partial batch is processed
- AND `was_flush_enabled=true` is recorded on the resulting `QueueBatchResult`

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` §Token-Batched Reasoning — "messages are bundled into batches of approximately 1000 tokens before LLM processing" |
| Doc | `docs/v3/documentation/core-concepts/reasoning.mdx` Note block — "Summary and dream tasks have their own scheduling logic and are not subject to the token threshold" |
| Source | `src/deriver/queue_manager.py:60-74` — `QueueBatchResult` named-tuple with `hit_batch_token_cap`, `was_flush_enabled`, `batch_max_tokens` |
| Source | `src/config.py:758` — `REPRESENTATION_BATCH_MAX_TOKENS: int = 1024` (range 128–16384) |
| Source | `src/config.py:759` — `MAX_INPUT_TOKENS: int = 25000` (hard cap on any single LLM call) |
| Source | `src/config.py:761` — `FLUSH_ENABLED: bool = False` (timeout-driven flush off by default) |
| Source | `src/deriver/queue_manager.py` — batch assembly logic referencing `REPRESENTATION_BATCH_MAX_TOKENS` |

## Behaviour notes (Tier 3 — scoped to this feature)

- The docs' "approximately 1000 tokens" figure is the `REPRESENTATION_BATCH_MAX_TOKENS = 1024` default. Configurable from 128 to 16384.
- `FLUSH_ENABLED=false` by default means partial batches sit until the cap is reached. A low-traffic peer can wait indefinitely for a flush. Operators with sparse traffic should enable flush or accept high derive latency.
- `MAX_INPUT_TOKENS=25000` is a separate, larger cap on the actual LLM input — it includes prompt overhead beyond message content. Batch cap (1024) bounds *content tokens*; input cap (25000) bounds *total LLM input*.
- `QueueBatchResult` carries `hit_batch_token_cap` and `was_flush_enabled` as observable signals for telemetry and post-hoc analysis of batching behaviour.
