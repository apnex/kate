# Honcho — Probe Assessment

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Probe date:** 2026-05-24
**Prober:** apnex + hermes
**Status:** open (will accumulate as feature specs are written)

> ⚠️ This document is **Tier 3 (analytical)**. Contents are the prober's interpretation of structural facts in `02-architecture.md` and `features/*.md` — not claims by the Honcho project, not verbatim source citations. Treat assessments as time-stamped opinion. Disagreeing with an assessment is not disagreeing with Honcho.

Format: structured single-line entries by default. Paragraph form reserved for entries that need structural argument (A2, A8, A14, A22).

---

## Resolved assessments

**A1 (2026-05-24) — Severity: factual correction.** License is AGPLv3, not Apache-2 [LICENSE@7470866]. Network-use copyleft. `substrate-landscape.md` row wrong — fix in separate commit post-probe.

**A2 (2026-05-24) — Severity: architectural — paragraph form.**
The queue is Postgres-backed (`QueueItem` SQLAlchemy model with `ActiveQueueSession` worker leases) [code: `src/deriver/queue_manager.py:32`, `:50-56`]. Redis via `cashews` is cache only [code: `src/main.py:73-75`]. The trade Honcho appears to have taken: **durability over throughput, single tech stack over operational surface**. Postgres ACID guarantees queue items survive any failure mode the database survives; a dropped Redis instance loses cache, not work. Cost: Postgres queue throughput caps below dedicated brokers. For a memory substrate where reasoning latency dominates, this is unlikely to be the bottleneck. Operator gotcha: Redis loss is recoverable (cache miss); the queue cannot be lost because it isn't there to lose.

**A3 (2026-05-24) — Severity: structural smell.** Summarizer lives at `src/utils/summarizer.py` while the other four named subsystems have top-level `src/` directories. Hypotheses: (1) genuinely smaller scope; (2) retro-fitted; (3) considered an internal utility despite docs framing. Expect Summarizer feature spec to be lighter. If non-trivial structure emerges, the architecture-style classification is misleading.

**A4 (2026-05-24) — Severity: vocabulary smell.** Public API uses "conclusion"; code symbols use "observation" [claim: `CLAUDE.md` §Agent Architecture Terminology; code: `src/routers/conclusions.py`, `src/crud/representation.py`]. Maintainers acknowledged the dual in CLAUDE.md but chose to live with it. Pattern matches prior public renames (App→Workspace, User→Peer) — conclusion/observation is unfinished business. Operator implication: search "observation" in code, "conclusion" in docs/API.

**A5 (2026-05-24) — Severity: speculative.** With Postgres queue + explicit lease rows, throughput ceiling at scale likely sits at row-level lock contention on `ActiveQueueSession` [code: `queue_manager.py:50-56`]. >10 concurrent deriver workers per peer-representation is the threshold to watch. Pre-emptive note; not a current problem. Verification deferred to `worker-lease-model` feature spec (A21).

**A6 (2026-05-24) — Severity: deployment trade.** Deriver process hosts three schedulers (Deriver queue + Reconciler + Dreamer) [code: `queue_manager.py:23-37`; `__main__.py`]. Trade: deployment simplification vs coupled failure modes and scheduling autonomy. For single-user deployments, simplification dominates. For managed-service-for-others futures, split into independent processes would be the natural evolution.

**A7 (2026-05-24) — Severity: factor-clarification.** `src/llm/tool_loop.py` is shared infrastructure used by both deriver (single-call mode) and dialectic (iterative mode) [code: `:289`, `:328`, `:344-348`, `:569-573`]. The "minimal deriver" descriptor applies to its agentic shape (no tool loop, no multi-step), not to the LLM machinery it shares. Don't read "minimal" as "lightweight."

**A8 (2026-05-24) — Severity: load-bearing finding — paragraph form.**
The deriver does NOT produce deductive observations. Its production prompt requests `[EXPLICIT]` atomic facts only [code: `src/deriver/prompts.py:1-6` docstring, `:55-81` prompt body]. `DeductiveObservation` and `InductiveObservation` schemas exist [code: `src/utils/representation.py:64-95`] and are written to the database when present, but the minimal deriver never produces them. This directly contradicts `reasoning.mdx`'s framing of the deriver as "[extracting] explicitly stated [facts], which serve as premises to scaffold deductive conclusions." **At this SHA, the deriver does extraction; the dreamer (hypothesised) and dialectic agent (confirmed in batch 2 — see A23) do reasoning.** Strong hypothesis: `src/dreamer/specialists.py` (742 lines) reads explicit observations and writes back higher-order ones with `source_ids` traceback. **Implication for Honcho-as-memory-quality assessment**: evaluate at dreamer-output level (and query-time dialectic mutations), not deriver-output level. Querying immediately after a message returns explicit observations only; richer reasoning has its own (slower) cadence. **Implication for docs**: reasoning.mdx is misleading for new users — file an issue post-probe (low priority).

**A9 (2026-05-24) — Severity: negative finding.** No TTL / decay / forgetting mechanism observed at deriver or storage layer across batch-1 reads. Only modulation is `DEDUPLICATE: bool = True` toggle at write time [code: `src/config.py:760`]. Open question: does reconciler/dreamer implement any decay? Consolidation in reasoning.mdx could be a soft form. Deferred to `consolidation` and `dreamer` specs. **Implication for G4**: if no forgetting exists anywhere, Honcho is monotonic-growth with retrieval ranking as the only filter — known design space, fitness depends on retrieval quality at large N.

**A10 (2026-05-24) — Severity: positive architectural property.** Three observation levels in schema (explicit/deductive/inductive); production deriver fills only explicit [code: `src/utils/representation.py:59-95`; `prompts.py:55-81`]. Architectural seam between deriver and dreamer is **`source_ids` tree traversal** — higher-order observations reference premise observations via document IDs. **Implication for G3 (auditable memory)**: provenance-by-construction. Higher-order observations trace back through `source_ids` to explicit observations, then via `message_ids` metadata to source messages. **Major positive for our goals.**

**A11 (2026-05-24) — Severity: claim/code mismatch (minor).** Reasoning docs claim four modes (explicit/deductive/inductive/abductive); schema implements three [negative search: no `AbductiveObservation` class at SHA]. Abduction is either approximated by inductive-level outputs or unimplemented. Schema is extensible — abduction could be added without breaking changes. Worth checking dreamer specialists for unnamed-abduction logic in batch 3.

**A12 (2026-05-24) — Severity: partial resolution.** `DEDUPLICATE: bool = True` default [code: `src/config.py:760`]; pipeline passes `deduplicate=settings.DERIVER.DEDUPLICATE` to `crud.create_documents` [code: `src/crud/representation.py:198`]. Algorithm itself (content hash / semantic / LLM-judged) not yet read. Resolves in `consolidation` feature spec (batch 3).

**A13 (2026-05-24) — Severity: operational.** N-observer write amplification: storage cost is linear in observer count [code: `src/deriver/deriver.py:200-222`]. One LLM call → N storage writes for N-peer session. Compute amortised (shared LLM + embedding); storage is not. For single-user-plus-assistant deployment: 2x worst case (tolerable). For multi-peer / agent-swarm futures: needs scoping configuration to avoid quadratic blowup.

**A14 (2026-05-24) — Severity: architectural — paragraph form.**
Perspectival peer pairs are the storage key, not just named entities [code: `src/crud/representation.py:46-58` `RepresentationManager(observer, observed)`; `:151-156` collection identity is `(workspace, observer, observed)`]. Honcho makes the perspectival pair structural rather than emergent at query time. Pays off when the system genuinely needs "what Alice knows about Bob, separately from what Bob knows about himself"; costs (per A13) when the perspectival distinction isn't used. Encodes one philosophical commitment — peers as observers of each other — at the schema level rather than the application level. *Comparative implications parked for crossprobe.*

**A15 (2026-05-24) — Severity: maturity signal.** Schema migration scar visible: `message_ids` was `list[tuple[int, int]]` (ranges), now `list[int]` [code: `src/utils/representation.py:18-49` `flatten_message_ids` with backward-compat docstring]. Combined with App→Workspace and User→Peer renames, indicates non-trivial schema migrations done in production with backward-compat. Positive signal for architectural maturity and upgrade-safety.

**A16 (2026-05-24) — Severity: positive observability.** Every deriver batch emits a `RepresentationCompletedEvent` (19 fields including timing breakdown, token accounting, batch-cap and input-cap snapshots) [code: `deriver.py:287-317`]. Sentry transaction wraps each batch [code: `:36`]. Token-breakdown invariant warnings logged when arithmetic doesn't add up [code: `:266-284` — note "provider tokenization drift" warning string, a war story embedded in code]. Production-grade observability. **Operator implication**: CloudEvents sink + Prometheus scraping (already in k3s) gives us excellent debugging.

**A22 (2026-05-24) — Severity: architectural — paragraph form.**
The dialectic agent has write tools. `DIALECTIC_TOOLS` includes `create_observations`, `create_observations_deductive`, `create_observations_inductive`, and `update_peer_card` [code: `src/utils/agent_tools.py:782`, `:1416-1604`]. **Query-time can mutate state.** Three consequences. (1) The dialectic agent is a **second writer** of deductive/inductive observations (alongside the hypothesised dreamer specialists) — A8's "deriver does extraction; dreamer does reasoning" needs amendment: deriver does extraction; dreamer AND dialectic do reasoning, on different cadences. (2) **Provenance gets a query-time dimension.** Higher-order observations may be written by a dialectic query about peer X for observer Y; those observations now live in Y's view of X. Auditability (G3) needs to track which subsystem wrote which observation when. (3) **Cost model is more complex than read-only retrieval suggests.** A query that triggers observation creation costs more than a query that doesn't, and the LLM decides which it is. Operator implication: dialectic latency and cost are not bounded purely by reasoning_level; they're also bounded by how often the agent decides to write.

**A23 (2026-05-24) — Severity: clarification.** The "agentic dialectic" entry point in `chat.py` is one of two variants. The agent docstring at `core.py:53-59` contrasts it with a "standard dialectic" that pre-gathers context for a single LLM call. The standard path is either internal-only, deprecated, or planned-future at this SHA — `chat.py` exposes only the agentic version. **Operator implication**: if we ever need a faster/cheaper non-agentic mode, the standard dialectic may exist as internal code that could be promoted.

**A24 (2026-05-24) — Severity: positive scalability property.** The dialectic agent runs without holding a DB connection [code: `src/dialectic/chat.py:42-66` preflight scope with comment "DB session closed — agent runs without holding a connection"]. Long agent runs do not consume DB pool slots; tools open short-lived sessions via `tracked_db` only when needed. **Implication for scaling**: dialectic throughput is bounded by LLM throughput and pool budgets at the *per-tool-call* granularity, not at the *per-query* granularity. Significant for high-concurrency scenarios.

**A25 (2026-05-24) — Severity: configuration surface.** `settings.DIALECTIC.LEVELS[reasoning_level].MODEL_CONFIG` [code: `src/dialectic/core.py:46-49`] means each reasoning level (min/low/medium/high/max) maps to its own model configuration. Tuning `reasoning_level` is therefore not just a parameter knob — it can select different models entirely. **Implication for our tuning**: when we raised dialecticReasoningLevel from low→medium (DEFERRED-01), we may have switched models, not just escalated within one. Check our LiteLLM proxy logs for the actual model used per level to confirm.

**A26 (2026-05-24) — Severity: architectural finding.** Document and message embeddings live in different namespace structures [code: `src/vector_store/__init__.py:76-107`]. **Document (observation) embeddings are perspectival**: `{prefix}.doc.{hash(workspace, observer, observed)}`. **Message embeddings are workspace-global**: `{prefix}.msg.{hash(workspace)}`. Two consequences. (1) Message-level semantic retrieval crosses peer boundaries within a workspace — `search_memory` against messages can return content from any peer's contributions to any session. (2) Observation-level retrieval respects the perspectival pair (A14). The combination is intentional: messages are factual events that all peers can reference; observations are interpretations bound to an observer. **Implication for theory-of-mind semantics**: the "Bob's view of Alice" boundary applies to *interpretations*, not to *facts*.

---

## Open assessments

**A17 (open) — Does the dreamer use `source_ids` tree-traversal to backfill deductive/inductive observations referencing explicit ones?** Key hypothesis from A8 and A10. Resolves in dreamer feature spec (batch 3).

**A18 (open) — What is the deduplication algorithm in `crud.create_documents`?** Content hash, semantic similarity, or LLM-judged? Materially affects evaluation of Honcho's consolidation. Resolves in `consolidation` spec (batch 3).

**A19 (resolved by batch 2) — How portable is Honcho's API conceptually (G7)?** The dialectic tool surface (`features/search-tools.md`) is reproducible in shape against any backend providing semantic search + key-value writes — but the `(observer, observed)` keying (A14) and the read+write dialectic surface (A22) are architectural commitments that a "portable" reproduction would need to either match or explicitly diverge from. **Conclusion: not trivially portable as API, but the primitives are recognisable.**

**A20 (partially resolved by batch 2) — What does `reasoning_level` actually control beyond model selection?** Confirmed (A25): each level can map to a different model. Not yet characterised: loop depth, max tool calls, retrieval breadth per level. Defer remainder to dialectic-loop-depth feature spec or as a follow-up reading pass.

**A21 (open) — Does the worker-lease model serialise per `(observer, observed)` pair?** Determines whether multiple workers can race on a collection or are statically partitioned. Affects A5. Resolves in `worker-lease-model` (batch 4).

**A27 (open) — How does the dialectic agent choose minimal vs full tool set?** `DIALECTIC_TOOLS` and `DIALECTIC_TOOLS_MINIMAL` both exist; selection rule not characterised. Likely keyed by reasoning_level or a separate config flag. Quick verification needed.

---

*Closing assessments will appear here once all feature specs are complete.*
