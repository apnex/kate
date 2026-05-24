# Honcho — Architecture Map

**Substrate:** honcho
**Pinned SHA:** `7470866` (tag v3.0.7, 2026-05-21)
**Probe date:** 2026-05-24
**Scope:** `src/` of `plastic-labs/honcho` (canonical repo only — satellites listed in `sources.md`)

This document maps Honcho's structure as Honcho organises itself: subsystems, primitives, data flow, runtime topology, and pluggable surfaces. It is **descriptive only** — every claim is either cited to Honcho's own documentation (Tier 1) or to source at the pinned SHA (Tier 2). Probe analysis, trade-off interpretation, and gotchas live in `04-assessment.md`.

---

## 1. Runtime topology

Honcho is **two cooperating Python processes** sharing a Postgres database and a Redis cache. Each can run in multiple replicas.

```
┌──────────────────────┐     ┌────────────────────────┐
│   API server         │     │   Deriver worker       │
│   (FastAPI, uvicorn) │     │   (uvloop, asyncio)    │
│                      │     │                        │
│   • HTTP routes      │     │   Hosts THREE          │
│   • Dialectic agent  │     │   async schedulers:    │
│     (inline, sync)   │     │   • Deriver queue      │
│   • Webhook delivery │     │   • Reconciler         │
│                      │     │   • Dreamer            │
└──────┬───────────────┘     └──────┬─────────────────┘
       │                            │
       │       ┌────────────┐       │
       └──────►│ PostgreSQL │◄──────┘
               │            │
               │ • primitives (workspaces, peers,
               │   sessions, messages)
               │ • QueueItem (Postgres-backed queue)
               │ • collections / documents
               └────────────┘
               ┌────────────┐
               │   Redis    │  ← cache layer (cashews)
               │ (cashews)  │
               └────────────┘
               ┌────────────┐
               │  Vector    │  ← LanceDB OR Turbopuffer
               │  Store     │    (pluggable)
               └────────────┘
```

**Startup invariants** [code: `src/deriver/__main__.py:66`; `src/main.py` lifespan]:
- Both processes validate the embedding schema at startup; mismatch with config causes fail-fast in both.
- Deriver exposes Prometheus metrics on port 9090 when `settings.METRICS.ENABLED` [code: `src/deriver/__main__.py:18-21,81`].
- Deriver runs on `uvloop` event loop [code: `src/deriver/__main__.py:78`].

**Queue substrate** [code: `src/deriver/queue_manager.py:32` import; `src/models.py` `QueueItem`]:
The queue is a Postgres table (`QueueItem`), processed via row-level leases (`ActiveQueueSession`, tracked by `WorkerOwnership` named-tuple). Redis (via `cashews`) is used only as a cache; `cashews.backends.redis.client` errors are explicitly suppressed in logging because `SafeRedis` degrades gracefully [code: `src/main.py:73-75`].

---

## 2. Subsystems (the five named services)

All five run inside the **Deriver worker process** except Dialectic, which runs **inline within the API server** as a synchronous tool-loop on the chat-request path [claim: `CLAUDE.md` §Runtime Architecture; code: `src/main.py` imports `dialectic` router; `src/deriver/queue_manager.py:23-37` imports DreamScheduler + ReconcilerScheduler].

### 2.1 Deriver (`src/deriver/`)
Extracts conclusions from incoming messages, in batches, via a single LLM call with structured output.

| File | Lines | Role |
|---|---|---|
| `__main__.py` | 91 | Process entrypoint, uvloop setup, telemetry lifecycle |
| `queue_manager.py` | 1,007 | Postgres queue, worker leases, batch assembly, hosts Reconciler+Dreamer schedulers |
| `consumer.py` | 395 | `process_item`, `process_representation_batch` — per-batch entry |
| `deriver.py` | 317 | Deriver logic (LLM call, output handling) |
| `prompts.py` | 109 | `minimal_deriver_prompt` and related prompts |
| `enqueue.py` | 634 | Enqueue logic invoked from message creation paths |

[claim: `CLAUDE.md` §Deriver: *"the current architecture is 'minimal deriver' — a single LLM call per batch using structured output, not an agentic tool loop"*]

### 2.2 Dialectic (`src/dialectic/`)
Answers queries about a peer via inline tool-using agent loop on the synchronous request path.

| File | Lines | Role |
|---|---|---|
| `chat.py` | 140 | Chat-route handler entry |
| `core.py` | 544 | Tool loop orchestration |
| `prompts.py` | 237 | Dialectic agent prompts |

Tool definitions live in `src/utils/agent_tools.py` (2,566 lines); the tool loop infrastructure is `src/llm/tool_loop.py` (676 lines), shared with the deriver's LLM machinery.

### 2.3 Dreamer (`src/dreamer/`)
Background reasoning beyond the deriver's per-batch extraction. Runs reasoning "specialists" on accumulated state; triggered by surprisal computation rather than message arrival.

| File | Lines | Role |
|---|---|---|
| `dream_scheduler.py` | 406 | Scheduling logic |
| `orchestrator.py` | 411 | Coordinates specialist invocation |
| `specialists.py` | 742 | Individual reasoning specialists |
| `surprisal.py` | 492 | Surprisal (information-theoretic novelty) computation |
| `trees/` | — | Subdirectory (contents enumerated in feature spec) |

### 2.4 Reconciler (`src/reconciler/`)
Decouples embedding generation from message creation; periodically embeds messages with `sync_state='pending'` and cleans stale queue items.

| File | Lines | Role |
|---|---|---|
| `scheduler.py` | 268 | Periodic scheduler |
| `sync_vectors.py` | 629 | Embedding sync logic |
| `queue_cleanup.py` | — | Stale queue item cleanup |

[claim: `CLAUDE.md` §Runtime Architecture: *"embedding generation is decoupled from message creation by design"*]

### 2.5 Summarizer (`src/utils/summarizer.py`)
Produces session summaries. Lives in `utils/` rather than its own top-level directory. Invoked from the deriver queue with its own scheduling logic, separate from representation-task batching [claim: `docs/v3/documentation/core-concepts/reasoning.mdx` Note block: *"Summary and dream tasks have their own scheduling logic and are not subject to the token threshold"*].

---

## 3. Data primitives (the six entities)

| Primitive | Code symbol | API path | Role |
|---|---|---|---|
| Workspace | `Workspace` | `/v3/workspaces/...` | Top-level isolation boundary. Formerly "App". |
| Peer | `Peer` | `/v3/workspaces/{w}/peers/...` | Any participant — human or agent. Cross-session reasoning anchor. Formerly "User". |
| Session | `Session` | `/v3/workspaces/{w}/sessions/...` | Interaction thread; many-to-many with peers. |
| Message | `Message` | `/v3/workspaces/{w}/sessions/{s}/messages` | Fundamental unit; attributed to one peer, chronologically ordered. |
| Collection | `Collection` | (internal) | Vector storage container, keyed by `(observer, observed)` peer pairs. |
| Document | `Document` | (internal) | Individual vector-stored item; surfaced via the public `/conclusions` API. |

**Vocabulary dual** [claim: `CLAUDE.md` §Agent Architecture Terminology note: *"what users see as conclusions … is called observations in code symbols — create_observations, delete_observations, get_observation_context"*; code: `src/routers/conclusions.py`, `src/crud/representation.py`]:
The public API surface uses **"conclusion"**; code symbols use **"observation"**. They refer to the same entity.

**Pair-keyed collection model** [claim: `CLAUDE.md` §Key Primitives: *"Collections are keyed by (observer, observed) peer pairs"*]:
In single-peer sessions, observer and observed are the same peer (self-observation). In multi-peer sessions, each peer's collection-about-another-peer is distinct.

---

## 4. Configuration

Single canonical settings class `HonchoSettings(BaseSettings)` at `src/config.py:579`, Pydantic-based, sourced from `config.toml` + environment variables via custom `TomlConfigSettingsSource` [code: `src/config.py:520`].

Settings are split into named groups: `settings.DB`, `settings.AUTH`, `settings.EMBEDDING`, `settings.DERIVER`, `settings.DIALECTIC`, `settings.METRICS`. Each is its own `BaseModel`.

Per-call model overrides and fallback chains are first-class configuration:
- `ModelOverrideSettings` [code: `src/config.py:65`]
- `FallbackModelSettings` [code: `src/config.py:120`]
- `ConfiguredModelSettings` [code: `src/config.py:161`]
- `ResolvedFallbackConfig` [code: `src/config.py:205`]
- `ModelConfig` [code: `src/config.py:238`]
- `EmbeddingModelConfig` [code: `src/config.py:333`]

Configuration cascades **workspace → peer → session** [claim: `docs/v3/documentation/core-concepts/architecture.mdx` §Configuration & Extensibility; mechanism in `src/utils/config_helpers.py` — verified in `features/hierarchical-config.md`].

---

## 5. Storage tiers

### 5.1 PostgreSQL
- All six primitives as SQLAlchemy models in `src/models.py`
- Queue: `QueueItem` table, with `ActiveQueueSession` for worker leases
- Vectors: stored within Postgres when LanceDB is the backend

### 5.2 Redis (cache layer only)
- Wrapped via the `cashews` library
- Custom `SafeRedis` degrades `NoScriptError`/`ConnectionError` gracefully [code: `src/main.py:73-75`]
- Not used for queueing

### 5.3 Vector store (pluggable)
- `src/vector_store/lancedb.py`
- `src/vector_store/turbopuffer.py`
- Embedding generation performed by the Reconciler, async from message creation
- Embedding model configurable via `EmbeddingModelConfig` [code: `src/config.py:333`]

---

## 6. Pluggable surfaces

| Surface | Where | What's pluggable |
|---|---|---|
| **LLM backend** | `src/llm/backends/` + `src/llm/backend.py` + `src/llm/registry.py` | Multiple providers; shared backend-agnostic `tool_loop.py` |
| **Embedding backend** | `src/embedding_client.py`; `ConfiguredEmbeddingModelSettings` [code: `src/config.py:297`]; `EmbeddingModelConfig` [code: `src/config.py:333`] | Swappable provider/model; schema-validated at startup |
| **Vector store backend** | `src/vector_store/` | Two implementations (LanceDB, Turbopuffer) |
| **Auth** | `src/security.py`, `src/routers/keys.py`, `AuthSettings` [code: `src/config.py:626`] | Toggleable on/off; scoped JWT keys |
| **Webhooks** | `src/webhooks/`, `src/routers/webhooks.py` | Subscribe to events (e.g. `QueueEmptyEvent` [code: `src/deriver/queue_manager.py:42-45`]); HTTP delivery from API process |
| **Telemetry** | `src/telemetry/` (CloudEvents emitter, Prometheus, Sentry, reasoning traces) | Structured events; opt-in |

---

## 7. What this map does NOT cover

Deferred to per-feature specs in `features/*.md`:
- Specific configuration knobs (`DERIVER_WORKERS`, `MAX_INPUT_TOKENS`, batching thresholds, dialectic depth/reasoning level, dream scheduling cadence)
- The structured output schema of the minimal-deriver prompt
- The list and contracts of dialectic tools (`DIALECTIC_TOOLS` in `src/utils/agent_tools.py`)
- The dreamer's specialist roster
- Reconciler's scheduling cadence and sync triggers
- Webhook event types
- JWT key scoping rules
- Database migration history (vocabulary renames — App→Workspace, User→Peer)
- Hierarchical config cascade mechanism

Probe analysis, trade-off interpretation, and operator gotchas: see `04-assessment.md`.
Substrate fitness against memory-system goals (G1-G9): see `03-mapping.md`.
