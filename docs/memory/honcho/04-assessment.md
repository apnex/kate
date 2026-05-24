# Honcho — Probe Assessment

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Probe date:** 2026-05-24
**Prober:** apnex + hermes
**Status:** open (will accumulate as feature specs are written)

> ⚠️ This document is **Tier 3 (analytical)**. Its contents are the prober's interpretation of structural facts found in `02-architecture.md` and `features/*.md` — they are *not* claims by the Honcho project and *not* verbatim source citations. Treat assessments as time-stamped opinion, useful for reasoning but distinct from descriptive facts. If you disagree with an assessment, you are not disagreeing with Honcho.

This file captures probe analysis, trade-off interpretation, surprising findings, and operator gotchas that don't fit the descriptive shape of `02-architecture.md` or the goal-mapping shape of `03-mapping.md`. Each entry is dated.

---

## A1 — License is AGPLv3 (correction to prior survey)
**Date:** 2026-05-24
**Tier:** factual correction (Tier 2) with analytical implication (Tier 3)

**Fact:** `LICENSE` file at SHA `7470866` is AGPLv3 (GNU Affero General Public License v3, 19 November 2007). The earlier `kate/docs/memory/substrate-landscape.md` row asserted Apache-2 — that's incorrect.

**Implication for G7 (provider portability):** AGPLv3 has network-use copyleft. Self-hosting Honcho privately is unaffected, but exposing a *modified* Honcho server as a network service to third parties triggers source-disclosure obligations. For a single-user sovereign deployment this is moot. For any future "Honcho as a managed service for others" scenario, it's material.

**Action:** correct the row in `substrate-landscape.md` in a separate commit after this nanoprobe lands.

---

## A2 — Queue is Postgres-backed, not Redis-backed
**Date:** 2026-05-24
**Tier:** Tier 3 interpretation of Tier 2 facts

**Facts** [code: `src/deriver/queue_manager.py:32` (imports `from src.models import QueueItem`); `src/main.py:73-75` (Redis silenced because `SafeRedis` degrades gracefully)]: The queue uses a `QueueItem` SQLAlchemy model with worker leases (`ActiveQueueSession`, `WorkerOwnership`). Redis via `cashews` is the cache layer only.

**Assessment:** This is unusual for a substrate of this scale. Most async-worker architectures of similar complexity use Redis, RabbitMQ, or SQS as the broker. The trade-off Honcho appears to have chosen:
- **Durability over throughput.** Postgres ACID guarantees queue items survive any failure mode the database survives. A dropped Redis instance does not lose queue items because the queue isn't in Redis.
- **Single tech stack for primitives + queue + (when LanceDB) vectors.** Reduces operational surface area — one persistent store to backup, monitor, scale.
- **Bound on horizontal throughput.** Postgres queue throughput tops out below what a dedicated broker would deliver. For a memory substrate where reasoning latency dominates, this is unlikely to be the bottleneck — but worth knowing.

**Operator gotcha:** Redis can be lost without losing queue state, but it cannot be lost without losing cache state. Cache miss behaviour should be graceful (and is, per `SafeRedis`).

---

## A3 — Summarizer-in-utils asymmetry
**Date:** 2026-05-24
**Tier:** Tier 3 interpretation

**Fact:** Four of the five named subsystems live in their own top-level directories under `src/`: `deriver/`, `dialectic/`, `dreamer/`, `reconciler/`. The fifth — Summarizer — lives at `src/utils/summarizer.py`.

**Assessment:** The asymmetry suggests one of:
1. Summarizer is genuinely smaller in scope (a single file, one function — no orchestrator, no scheduler of its own).
2. Summarizer was retro-fitted into the system after the other four were established as first-class subsystems.
3. Summarizer is considered an *internal utility* invoked by the deriver rather than a peer-level subsystem, even though `CLAUDE.md` and `reasoning.mdx` describe it as one of the named agents.

Either way, **expect the Summarizer feature spec to be lighter-weight than the other four subsystems'**. If it turns out to have non-trivial internal structure, that's a finding (the architecture-style classification is misleading).

---

## A4 — Vocabulary dual: Conclusion (API) vs Observation (code)
**Date:** 2026-05-24
**Tier:** Tier 2 fact with Tier 3 interpretation

**Fact** [claim: `CLAUDE.md` §Agent Architecture Terminology; code: `src/routers/conclusions.py`, `src/crud/representation.py` (functions `create_observations`, etc.)]: The same entity has two names — "conclusion" everywhere in the public API and docs; "observation" everywhere in code symbols.

**Assessment:** This is a smell. The cost is:
- Reading the code, you don't see "conclusion" anywhere — searching for it returns mostly router/handler boilerplate.
- Reading the docs, you don't see "observation" anywhere — except `CLAUDE.md`'s explicit note that they're the same thing.
- New contributors must learn the dual to be productive.

The maintainers acknowledged it explicitly enough to write a terminology note in CLAUDE.md, which means they know. But choosing to live with it (vs renaming one side) suggests the public API is frozen for backward compatibility while the code was renamed (or vice versa). Migration shows the same pattern: `Workspace` was `App`, `Peer` was `User` — Honcho has done public renames before. The conclusion/observation split is unfinished business.

**Operator implication:** when reading source for a feature, search for "observation" not "conclusion". When reading the API, search for "conclusion" not "observation". `git log --all -S 'observation'` and `git log --all -S 'conclusion'` would clarify the history — out of scope for this probe, noted for future archaeology.

---

## A5 — Postgres queue + worker leases imply lease contention is the throughput cap
**Date:** 2026-05-24
**Tier:** Tier 3 speculative

**Facts** [code: `src/deriver/queue_manager.py:50-56` (`WorkerOwnership` named-tuple), `:60-74` (`QueueBatchResult` with `hit_batch_token_cap`, `was_flush_enabled`, `batch_max_tokens`)]: Workers acquire lease rows in `ActiveQueueSession` to claim work units. Batch assembly tracks whether the token cap clamped the batch.

**Speculative assessment:** With Postgres-backed queueing and explicit lease rows, the throughput ceiling at scale is likely **row-level lock contention on `ActiveQueueSession`** when many workers compete for the same work unit. If a deployment ever needs >10 concurrent deriver workers per peer-representation, lease churn on that table is the place to look first. Not a current problem; pre-emptive note.

**Verification needed:** Read `src/deriver/queue_manager.py` work-unit acquisition logic in the feature spec for `worker-lease-model`. This assessment may turn out to be wrong.

---

## A6 — Single deriver process hosting three schedulers ties their lifecycles
**Date:** 2026-05-24
**Tier:** Tier 3 interpretation

**Fact** [code: `src/deriver/queue_manager.py:23-37` (imports `DreamScheduler`, `ReconcilerScheduler`); `src/deriver/__main__.py` (single `main()` entry)]: The Deriver worker process is the runtime host for the Deriver queue consumer, the Reconciler scheduler, and the Dreamer scheduler. The three are not independent services.

**Assessment:**
- **Deployment simplification.** One process to run, one set of replicas to scale. Operationally simpler than three services with three separate config/secret/health-check stories.
- **Coupled failure modes.** A crash in the Dreamer or Reconciler scheduler can take down the Deriver queue consumer (unless they are exception-isolated in code — verify in feature spec). Conversely, scaling the Deriver also scales the other two — useful or wasteful depending on their relative workloads.
- **Constraint on scheduling autonomy.** All three share the same event loop, the same database connection pool, the same telemetry initialisation. This is fine for a unified async system; less fine if (e.g.) the Dreamer ever needs significantly different resource characteristics than the Deriver.

**Sovereignty note:** for a single-user deployment, the simplification dominates. For a managed-service-for-others future, splitting these into independently scalable processes would be a natural evolution.

---

## A7 — `src/llm/tool_loop.py` is shared infrastructure used by both deriver and dialectic
**Date:** 2026-05-24
**Tier:** Tier 2 fact, Tier 3 interpretation

**Fact** [code: `src/llm/tool_loop.py:289` (`max_input_tokens` parameter), `:328` (truncation latch), `:344-348`, `:569-573` (truncation logic)]: The tool loop infrastructure handles token budgeting and conversation truncation generically.

**Assessment:** Despite `CLAUDE.md` describing the deriver as "single LLM call, not agentic tool loop", the deriver still relies on `src/llm/` for its LLM call — just without iterating. The tool loop file specifically is used by Dialectic (and by Dreamer specialists — to be verified). This is well-factored infrastructure, not a code smell.

**Implication for assessment of "minimal deriver" claim:** the deriver being "minimal" applies to its agentic shape (no tool loop, no multi-step reasoning), not to the LLM machinery it shares. Don't read "minimal" as "lightweight."

---

## Open assessments (placeholders — fill as feature specs surface evidence)

- **A8 — Does the dreamer's "surprisal" actually use information theory, or is it a metaphor?** Reading `src/dreamer/surprisal.py` (492 lines) during the dreamer feature spec will resolve this. If actual entropy/surprise computation, that's a significant differentiator. If metaphor only, that's a finding worth noting (and a marketing-vs-code mismatch).

- **A9 — Does Honcho have any forgetting / TTL / decay mechanism?** Apparent answer from the structure is "no, only consolidation/dedup at write time" — but feature specs may reveal a lifecycle subsystem I haven't yet found. Open.

- **A10 — How portable is Honcho's API conceptually (G7)?** The primitives (workspace/peer/session/message/conclusion) are universal-ish, but `(observer, observed)` collection keying is structurally unusual. Will the dialectic agent's tool surface (`search_memory`, `get_observation_context`) be reproducible against another substrate, or Honcho-shaped? Resolves in the dialectic feature spec.

- **A11 — What's the dialectic agent's actual quality vs depth trade?** We tune `dialecticDepth=3, reasoningLevel=medium`. The source will reveal what these knobs actually change. If `depth=3` means "3 reasoning passes" the cost model is clear; if it means something deeper (multi-hop graph traversal, recursive reconciliation), the cost model is murkier.

- **A12 — Does the deriver actually consolidate, or does it append-and-rely-on-retrieval-ranking?** Major behavioural distinction. The `consolidation` claim in `reasoning.mdx` needs source verification — the actual algorithm might be "extract, embed, store" with no consolidation step at all, and "consolidation" might happen only at dialectic-query time via the tools.

---

## Closing assessments will appear here once all feature specs are complete.
