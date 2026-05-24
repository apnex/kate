# Honcho — Goal Mapping

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Probe date:** 2026-05-24

This document maps Honcho's substrate features against the kate memory-system goals (G1–G9). It is **descriptive of fit**, not comparative. "Strong" / "partial" / "absent" are characterisations of how the substrate addresses a goal, not rankings against other substrates.

> Goal definitions live in `kate/docs/memory/goals.md` (canonical). Summaries repeated below for readability only.

---

## G1 — Cross-session continuity

> *Memory persists and remains queryable across discrete conversational sessions.*

**Fit: strong.**

| Substrate feature | How it addresses G1 |
|---|---|
| `features/peer-representation.md` | Storage keyed by `(workspace, observer, observed)` peer-pair, independent of session. |
| `features/observer-observed.md` | Observation lifecycle decoupled from session lifecycle; observations survive session close. |
| `features/explicit-deductive.md` | Higher-order observations (deductive/inductive) reference premises across sessions via `source_ids`. |
| `features/peer-card.md` | Per-peer JSONB metadata persists in `Peer` row, queryable independently of session. |

## G2 — Auditable provenance

> *Every memory item can be traced to its sources.*

**Fit: strong (provenance-by-construction).**

| Substrate feature | How it addresses G2 |
|---|---|
| `features/explicit-deductive.md` | `source_ids` column links higher-order observations to premise observations. |
| `features/minimal-deriver.md` | Explicit observations carry `message_ids` metadata linking to source messages. |
| `features/dreamer.md` | DeductionSpecialist / InductionSpecialist populate `source_ids` when writing. |
| `features/dialectic-chat.md` (A22) | Query-time observation writes are attributable to the dialectic session that produced them. |

End-to-end chain: higher-order observation → `source_ids` → explicit observation → `message_ids` → source message. No gaps.

## G3 — Time-aware retrieval

> *Memory respects recency / staleness signals; queries can be biased by time.*

**Fit: partial.**

| Substrate feature | How it addresses G3 |
|---|---|
| `features/search-tools.md` | Search tools accept ordering preferences; recency is a first-class sort dimension. |
| `features/surprisal.md` (`SAMPLING_STRATEGY="recent"`) | Dream pre-filter can be biased to recent observations. |
| `features/summarizer.md` | Session summaries provide compressed historical context for older windows. |
| **Absent** | No TTL, no decay function, no automatic staleness scoring. (A9) |

The substrate gives operators primitives for time-aware retrieval but does not enforce time-decay. A staleness model would need to be added at the application layer.

## G4 — Bounded memory growth

> *Memory does not grow unbounded; some mechanism keeps the working set manageable.*

**Fit: partial — through deduplication and summarization, not forgetting.**

| Substrate feature | How it addresses G4 |
|---|---|
| `features/consolidation.md` | Hybrid cosine + token-set-difference dedup at write time; catches paraphrases. |
| `features/summarizer.md` | Compresses session history into smaller summary documents. |
| `features/token-batching.md` | Deriver batches at token threshold; limits prompt size for LLM-bounded contexts. |
| **Absent** | No TTL, no eviction, no observation-level forgetting. |

Honcho is **monotonic-growth-with-dedup-and-summarisation**. Operators who need hard bounds must impose them externally (e.g. periodic vector-store pruning, observation-level TTL via cron). The substrate provides the storage primitives but not the retention policy.

## G5 — Multi-perspective reasoning

> *Memory distinguishes "what A knows about B" from "what B knows about itself".*

**Fit: strong (architectural commitment).**

| Substrate feature | How it addresses G5 |
|---|---|
| `features/observer-observed.md` | `(observer, observed)` is the storage key, not just a query parameter (A14). |
| `features/peer-representation.md` | `RepresentationManager(observer, observed)` enforces perspectival scoping at the data-access layer. |
| `features/pluggable-vector-backend.md` (A26) | **Observation embeddings are perspectival** (`{prefix}.doc.{hash(workspace, observer, observed)}`); **message embeddings are workspace-global** (`{prefix}.msg.{hash(workspace)}`). Interpretations are pair-scoped, facts are global. |
| `features/dialectic-chat.md` | Dialectic queries are framed `target=observer, perspective=observed`; the answer reflects the observer's view. |

This is Honcho's load-bearing differentiator. The cost is N-observer write amplification (A13) for multi-peer sessions.

## G6 — Async / non-blocking memory updates

> *Memory writes don't block the user-facing path.*

**Fit: strong.**

| Substrate feature | How it addresses G6 |
|---|---|
| `features/worker-lease-model.md` | Postgres-backed queue (`QueueItem`) with worker leases; API process enqueues, deriver process drains. |
| `features/minimal-deriver.md` | Single LLM call per batch, async on the deriver worker process. |
| `features/dreamer.md` | Background reasoning runs on trigger cadence, not message cadence. |
| `features/reconciler.md` | Embedding generation decoupled from message creation; 3-hour vector-store outage headroom. |
| `features/dialectic-chat.md` (A24) | Dialectic agent runs without holding a DB connection during LLM calls. |

## G7 — Substrate-agnostic API shape

> *The memory API could be implemented against alternative storage backends.*

**Fit: partial — primitives portable, perspectival keying is a commitment.**

| Substrate feature | How it addresses G7 |
|---|---|
| `features/search-tools.md` | Semantic search + key-value writes — reproducible against any backend with these primitives. |
| `features/pluggable-vector-backend.md` | Three vector backends already proven (pgvector, LanceDB, Turbopuffer); abstraction is real. |
| **Architectural commitment** | `(observer, observed)` perspectival keying (G5) and read+write dialectic surface (A22) are not generic — a portable reproduction must match or explicitly diverge from these. |

A19's resolution: not trivially portable as a 1:1 API, but the *primitives* are recognisable. A reimplementation could match shape against any backend providing semantic search + KV writes.

## G8 — Observability of memory operations

> *Operators can see what the memory subsystem is doing and why.*

**Fit: strong.**

| Substrate feature | How it addresses G8 |
|---|---|
| `features/minimal-deriver.md` (A16) | `RepresentationCompletedEvent` emitted per batch with 19 fields (timing, tokens, cap snapshots). |
| `features/dreamer.md` | `DreamRunEvent` per dream cycle (specialists run, success flags, surprisal stats, iterations, duration, tokens). |
| `features/tool-loop.md` | `AgentIterationEvent` per LLM iteration including no-tool terminating iteration and synthesis call. |
| `features/dialectic-chat.md` | Reasoning traces emit per-step provenance for query-time decisions. |
| **Infrastructure** | CloudEvents sink + Prometheus exposition on port 9090 + Sentry transaction wrapping. |

War stories embedded in code (e.g. "provider tokenization drift" warning string in `deriver.py:266-284`) indicate production-grade observability culture.

## G9 — Operator-tunable cost / quality knobs

> *Operators can trade memory quality against compute cost.*

**Fit: strong (rich knob surface).**

| Knob | Mechanism | Source |
|---|---|---|
| Per-reasoning-level model selection | `DIALECTIC.LEVELS[level].MODEL_CONFIG` (min/low/medium/high/max maps to distinct models) | `features/dialectic-chat.md` (A25) |
| Per-specialist model selection | `DREAM.DEDUCTION_MODEL_CONFIG`, `INDUCTION_MODEL_CONFIG` | `features/hierarchical-config.md` |
| Surprisal pre-filter on/off + top-N% | `DREAM.SURPRISAL.ENABLED` + `TOP_PERCENT_SURPRISAL` | `features/surprisal.md` |
| Tree backend (cost/quality trade) | `DREAM.SURPRISAL.TREE_TYPE` (7 options) | `features/surprisal.md` (§C1) |
| Dream cadence (threshold + idle gate) | `DREAM.DOCUMENT_THRESHOLD`, `IDLE_TIMEOUT_MINUTES`, `MIN_HOURS_BETWEEN_DREAMS` | `features/dream-scheduler.md` |
| Deriver batching | `DERIVER.REPRESENTATION_BATCH_MAX_TOKENS`, `FLUSH_ENABLED` | `features/token-batching.md` |
| Dedup on/off | `DERIVER.DEDUPLICATE` | `features/consolidation.md` |
| Tool-loop iteration cap | `MAX_TOOL_ITERATIONS` per subsystem | `features/tool-loop.md` |

**Hierarchical config cascade** (`features/hierarchical-config.md`): init → env → .env → TOML → secrets → defaults. Workspace → peer → session resolution layered on top. Surface is wide; defaults are sensible; tuning is straightforward for operators who read the source.

---

## Summary

| Goal | Fit | Note |
|---|---|---|
| G1 Cross-session continuity | strong | peer-pair storage, session-independent |
| G2 Auditable provenance | strong | `source_ids` + `message_ids` chain |
| G3 Time-aware retrieval | partial | primitives present, no enforced decay |
| G4 Bounded growth | partial | dedup + summarisation, no forgetting |
| G5 Multi-perspective | strong | perspectival schema commitment |
| G6 Async writes | strong | queue + reconciler + DB-connection-free agent |
| G7 Substrate-agnostic API | partial | primitives portable, keying is a commitment |
| G8 Observability | strong | CloudEvents + Prometheus + Sentry + traces |
| G9 Operator knobs | strong | per-level models, surprisal trees, cadence gates |

Five strong, four partial, zero absent. **Honcho is a substantial fit for the kate memory-system goals**, with the two notable gaps being **time-aware retrieval** (G3) and **bounded growth** (G4) — both requiring an external retention/decay layer to fully address.
