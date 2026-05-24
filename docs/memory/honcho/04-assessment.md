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

## A8 — The deriver does NOT do deductive reasoning; only the dreamer does
**Date:** 2026-05-24 (updates earlier open A8 placeholder)
**Tier:** Tier 2 fact with major Tier 3 implication for our system

**Fact** [code: `src/deriver/prompts.py:1-6` file docstring; `src/deriver/prompts.py:55-81` `minimal_deriver_prompt`; `src/deriver/deriver.py:185-200`]: The minimal deriver's production prompt requests ONLY `[EXPLICIT]` atomic facts. It does NOT request `[DEDUCTIVE]` premises-and-conclusions. The `DeductiveObservation` and `InductiveObservation` schemas exist (`src/utils/representation.py:64-95`) and are written to the database at `level='deductive'`/`level='inductive'`, but the minimal deriver never produces them.

**Assessment:** This directly contradicts `docs/v3/documentation/core-concepts/reasoning.mdx` which describes the deriver as "[extracting] explicitly stated [facts], which serve as premises to scaffold deductive conclusions." At this SHA, that's not what the deriver does. Strong hypothesis based on architecture: the dreamer (specifically `src/dreamer/specialists.py`, 742 lines) is where deductive/inductive/abductive reasoning happens, reading explicit observations from the database and writing back higher-order observations with `source_ids` traceback.

**Implication for our system:** for any quality assessment of Honcho's reasoning depth, we need to evaluate at the dreamer-output level, not the deriver-output level. Querying a peer-representation immediately after a message gives explicit observations only; deeper reasoning has its own (slower) cadence.

**Implication for the docs:** the reasoning.mdx page is misleading for new users. The Honcho project should be made aware (low priority — file an issue post-probe).

---

## A9 — No forgetting / TTL / decay mechanism observed
**Date:** 2026-05-24 (updates earlier open A9 placeholder, partial answer)
**Tier:** Tier 2 fact (negative finding) with Tier 3 implication

**Fact:** Across the batch-1 feature spec reads (deriver, representation save, collection storage), no time-based decay, TTL, or forgetting mechanism is invoked. Observations are written, optionally deduplicated, and persist indefinitely. The only modulation is the `DEDUPLICATE: bool = True` toggle at write time.

**Assessment:** Confirmed at the deriver/storage layer. Open question for batches 2-4: does the reconciler, dreamer, or any subsystem implement TTL/decay/forgetting? The dreamer's "consolidation" capability mentioned in reasoning.mdx could be a softer form of forgetting (consolidating multiple observations into one, deleting sources). To-verify in `consolidation` feature spec.

**Implication for G4 (memory-system-as-evolving-state):** if no forgetting exists anywhere, Honcho is monotonic-growth — observations accumulate forever, with retrieval ranking as the only filter. This is a known design space (vs. Letta's archival memory which has explicit move-to-archive lifecycle). Whether monotonic-growth is right for our use case depends on retrieval quality at large N. To-evaluate alongside dialectic-chat spec.

---

## A10 — Three observation levels in schema (explicit/deductive/inductive); production deriver fills only explicit
**Date:** 2026-05-24
**Tier:** Tier 2 fact, Tier 3 interpretation

**Fact** [code: `src/utils/representation.py:59-95`]: Three observation-level schemas exist. The minimal-deriver path fills only `explicit`. Storage and read paths support all three.

**Assessment:** This is design-for-extensibility — the storage and read paths support the richer model so background subsystems can backfill higher-order observations later. The architectural seam between deriver-output and dreamer-output is **`source_ids` tree traversal**: deductive/inductive observations reference their source explicit observations, enabling provenance queries.

**Implication for G3 (auditable memory):** Honcho gives us provenance-by-construction. Any higher-order observation can be traced back through `source_ids` to source explicit observations, and from those via `message_ids` metadata to source messages. **This is a major positive for our goals.**

---

## A11 — Abductive reasoning is documented but not schematised
**Date:** 2026-05-24
**Tier:** Tier 2 fact (negative finding) with Tier 3 implication

**Fact** [negative search: `grep -r "Abductive" src/` returns no `AbductiveObservation` class at this SHA]: The reasoning docs claim four modes (explicit, deductive, inductive, abductive). The schema implements three. Abductive is not a distinct schema level.

**Assessment:** Either abduction is approximated by the inductive-level outputs (loose categorisation by the dreamer), or it is an unimplemented promise from the docs. Worth checking the dreamer's specialist roster (`src/dreamer/specialists.py`) for any "Hypothesiser" / "Detective" / "Explainer" specialist that performs abduction without being named so in the schema.

**Implication:** Marketing-vs-code mismatch is mild — the schema is extensible, abduction *could* be added as a fourth level without breaking changes. Not a sovereignty/correctness issue, but worth noting for accurate expectation-setting.

---

## A12 — `DEDUPLICATE` defaults to True; algorithm characterised in feature `consolidation`
**Date:** 2026-05-24 (updates earlier open A12 placeholder, partial answer)
**Tier:** Tier 2 fact with Tier 3 implication

**Fact** [code: `src/config.py:760` `DEDUPLICATE: bool = True`; `src/crud/representation.py:198` passes `deduplicate=settings.DERIVER.DEDUPLICATE` to `crud.create_documents`]: Deduplication is on by default. The actual algorithm lives in `src/crud` and has not yet been read.

**Assessment:** At least one form of consolidation (write-time dedup) is real and on by default. Whether this is content-hash dedup, semantic-similarity dedup, or LLM-judged dedup matters significantly for evaluating Honcho's consolidation capability. To-resolve in the `consolidation` feature spec (batch 3).

---

## A13 — N-observer write amplification: storage cost is linear in observer count
**Date:** 2026-05-24
**Tier:** Tier 3 operational implication

**Fact** [code: `src/deriver/deriver.py:200-222` per-observer save loop]: One deriver call (single LLM call, single embedding batch) writes the same observations to N collections — one per observer in the session.

**Assessment:** For multi-peer sessions (group chats, multi-agent simulations), storage cost scales linearly with peer count for the same conversation content. A 10-peer session stores observations 10x in 10 separate `(observer, observed)` collections. Computational cost is amortised (LLM call + embedding batch are shared); storage cost is not.

**Operator implication:** Session size matters for deployment sizing. For our single-user-plus-assistant deployment this is 2x at worst (alice-about-alice + assistant-about-alice). Tolerable. For any future "agent swarm" use case, would need session/observer scoping configuration to avoid quadratic blowup.

---

## A14 — Theory-of-mind at the storage layer is structurally unusual and architecturally significant
**Date:** 2026-05-24
**Tier:** Tier 3 interpretation (cross-substrate-comparison-adjacent — kept abstract here, will inform crossprobe)

**Fact** [code: `src/crud/representation.py:46-58` `RepresentationManager(observer, observed)`; `:151-156` collection identity is `(workspace, observer, observed)`]: Perspectival pairs of peers are the storage key, not just named entities.

**Assessment:** Most memory substrates we surveyed in the substrate-landscape doc treat per-agent memory as a single namespace, with multi-agent reasoning emerging at query time. Honcho makes the perspectival pair structural. This is a load-bearing design decision that:
- Pays off when the system genuinely needs "what Alice knows about Bob, separately from what Bob knows about himself"
- Costs (storage amplification per A13) when the perspectival distinction isn't used
- Encodes one philosophical commitment (peers as observers of each other) at the schema level

**Cross-substrate note (for crossprobe, NOT for this probe):** the alternative — single peer-memory namespaces — should be characterised in other substrate audits. Don't add comparison here per the no-cross-substrate-refs rule.

---

## A15 — Schema migration scar: `message_ids` was `list[tuple]`, now `list[int]`
**Date:** 2026-05-24
**Tier:** Tier 2 fact, Tier 3 architectural-maturity signal

**Fact** [code: `src/utils/representation.py:18-49` `flatten_message_ids` with backward-compat docstring]: The schema for observation-source-message references was `list[tuple[int, int]]` (representing message ranges) and is now `list[int]` (individual IDs). Backward-compat shim handles old data.

**Assessment:** Honcho has done at least one non-trivial schema migration in production and kept backward-compat. Combined with the App→Workspace and User→Peer renames, this indicates a substrate that has iterated on its model in response to learning. Positive signal for architectural maturity; minor positive signal for upgrade-safety (migrations are real, not optional).

---

## A16 — Strong telemetry posture: every deriver batch is fully traced
**Date:** 2026-05-24
**Tier:** Tier 3 interpretation

**Fact** [code: `src/deriver/deriver.py:287-317` `RepresentationCompletedEvent` emission carrying 19 fields; `:36` `@with_sentry_transaction("minimal_deriver_batch", op="deriver")`; `:266-284` token-breakdown invariant warnings]: Each deriver batch emits a CloudEvent with full timing breakdown (context-prep ms, LLM-call ms, total ms), token accounting (input/output/messages/prompt/extra-context), batch-cap and input-cap snapshots, and observer count. Sentry transaction wrapping every batch. Invariant warnings logged when token-breakdown maths don't add up.

**Assessment:** This is production-grade observability. The team building Honcho clearly runs it at scale and has been bitten by silent-drift failures (note the "provider tokenization drift" warning string at line 272 — that's the war story embedded in the code). Strongly positive signal for operational viability.

**For our deployment:** the Prometheus + CloudEvents + Sentry surface gives us excellent debugging if anything goes wrong. We just need a CloudEvents sink (and Prometheus scraping, which we already have via k3s).

---

## Open assessments (placeholders — fill as feature specs surface evidence)

- **A8/A9/A12 — partially resolved above; remaining questions deferred to batch 2/3 specs.**

- **A17 (NEW) — Does the dreamer actually use the source_ids tree-traversal pattern to backfill deductive/inductive observations referencing explicit ones?** This is the key architectural hypothesis from A8 and A10. Resolves in the dreamer feature spec (batch 3).

- **A18 (NEW) — What's the actual deduplication algorithm in `crud.create_documents`?** Content hash, semantic similarity, or LLM-judged? Resolves in the `consolidation` feature spec (batch 3).

- **A19 — How portable is Honcho's API conceptually (G7)?** The primitives are universal-ish, but `(observer, observed)` collection keying is structurally unusual. Will the dialectic agent's tool surface be reproducible against another substrate, or Honcho-shaped? Resolves in the `dialectic-chat` feature spec (batch 2).

- **A20 — What does `dialecticDepth` actually mean?** If `depth=3` means "3 reasoning passes" the cost model is clear; if it means something deeper (multi-hop graph traversal, recursive reconciliation), the cost model is murkier. Resolves in `dialectic-chat`.

- **A21 (NEW) — Does the worker-lease model serialise per `(observer, observed)` pair?** Determines whether multiple workers can race on the same collection (rare collision) or are statically partitioned (no race possible). Affects assessment of A5. Resolves in `worker-lease-model` (batch 4).

---

## Closing assessments will appear here once all feature specs are complete.
