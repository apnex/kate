# Honcho — Sources

**Substrate:** honcho
**Pinned SHA:** `7470866d12845ed4b56bf3449d058e65df96b1c1` (short `7470866`)
**Pinned tag:** v3.0.7
**Probe date:** 2026-05-24
**License:** AGPLv3 (verified from `LICENSE` file at SHA)
**Status:** in-progress — feature specs will append additional citations

Complete index of every URL, repo, file, and citation used in this nanoprobe. All file:line citations are pinned to the SHA above. To reproduce any claim, clone at `git checkout 7470866` and consult the cited line.

---

## Canonical repository

- **plastic-labs/honcho** — https://github.com/plastic-labs/honcho
- **Pinned tag:** v3.0.7 (https://github.com/plastic-labs/honcho/releases/tag/v3.0.7)
- **Pinned commit:** 7470866d12845ed4b56bf3449d058e65df96b1c1 (2026-05-21)
- **Retrieved:** 2026-05-24 via `git clone --depth 1 --branch v3.0.7`
- **Local clone:** `/tmp/honcho-probe` (transient — re-clone for verification)

---

## Documentation cited (Tier 1 — claim-tier)

All under `docs/` at the pinned SHA unless otherwise marked.

| Path | Section / Note | Used for |
|---|---|---|
| `CLAUDE.md` | §Runtime Architecture | Two-process topology; deriver hosts schedulers |
| `CLAUDE.md` | §Deriver | "Minimal deriver — single LLM call per batch" claim |
| `CLAUDE.md` | §Key Primitives | `(observer, observed)` collection keying |
| `CLAUDE.md` | §Agent Architecture Terminology | Conclusion ↔ Observation vocabulary dual |
| `README.md` | Header — "Pareto Frontier of Agent Memory" | Marketing claim (not source-cited in architecture; noted in assessment) |
| `docs/v3/documentation/core-concepts/architecture.mdx` | Whole doc | Substrate self-description; six design principles; hierarchical config cascade |
| `docs/v3/documentation/core-concepts/reasoning.mdx` | §Why Reasoning; §Formal Logic Framework; §How It Works | Custom-model claim (Neuromancer XR); explicit→deductive structure; ~1000-token batching; representation vs summary vs dream task types |
| `docs/v3/documentation/core-concepts/representation.mdx` | TBD — to read during representation feature spec | Peer-representation concept |
| `docs/v3/documentation/core-concepts/design-patterns.mdx` | TBD | Patterns documented by Honcho |
| `docs/v3/documentation/features/chat.mdx` | TBD — dialectic feature spec | Dialectic chat surface |
| `docs/v3/documentation/features/get-context.mdx` | TBD — retrieval feature spec | Retrieval surface |
| `docs/v3/documentation/features/storing-data.mdx` | TBD | Storage primitives |
| `docs/v3/documentation/reference/configuration.mdx` (681 lines) | TBD — config feature spec | Knob enumeration |
| `docs/v3/documentation/reference/platform.mdx` | TBD | Platform/deployment surface |
| `docs/v3/documentation/reference/storage.mdx` | TBD | Vector/Postgres details |
| `docs/v3/documentation/reference/sdk.mdx` | TBD | SDK surface (cite-only, not code-traced) |

---

## Source files cited (Tier 2)

All under `src/` at the pinned SHA. Line numbers verified during scaffolding pass and will be augmented by per-feature specs.

### Process entrypoints
- `src/main.py` — API server entrypoint (FastAPI, Sentry, Prometheus middleware, cashews/Redis cache init, router registration)
  - `:73-75` — cashews Redis error suppression (`MetricsAccessFilter`, `SafeRedis`)
  - lifespan — embedding schema validation
- `src/deriver/__main__.py` — Deriver worker entrypoint (91 lines total)
  - `:18-21` — Prometheus metrics HTTP server start
  - `:24-54` — `setup_logging`
  - `:57-70` — `run_deriver` (telemetry lifecycle wrapper)
  - `:66` — `validate_embedding_schema` call
  - `:78` — `uvloop.EventLoopPolicy`
  - `:81-82` — `settings.METRICS.ENABLED` gate
  - `:85` — `asyncio.run(run_deriver())`

### Configuration
- `src/config.py` (1,339 lines) — all settings
  - `:65` — `ModelOverrideSettings`
  - `:120` — `FallbackModelSettings`
  - `:161` — `ConfiguredModelSettings`
  - `:205` — `ResolvedFallbackConfig`
  - `:238` — `ModelConfig`
  - `:297` — `ConfiguredEmbeddingModelSettings`
  - `:333` — `EmbeddingModelConfig`
  - `:520` — `TomlConfigSettingsSource`
  - `:579` — `HonchoSettings(BaseSettings)` (canonical)
  - `:604` — `DBSettings`
  - `:626` — `AuthSettings`

### Deriver subsystem
- `src/deriver/queue_manager.py` (1,007 lines)
  - `:23-37` — imports `DreamScheduler`, `ReconcilerScheduler` (subsystem co-hosting evidence)
  - `:32` — imports `QueueItem` (queue-is-Postgres evidence)
  - `:42-45` — webhook event imports (`QueueEmptyEvent`)
  - `:50-56` — `WorkerOwnership` named-tuple
  - `:60-74` — `QueueBatchResult` dataclass (`hit_batch_token_cap`, `was_flush_enabled`, `batch_max_tokens`)
- `src/deriver/consumer.py` (395 lines) — `process_item`, `process_representation_batch`
- `src/deriver/deriver.py` (317 lines) — TBD per feature spec
- `src/deriver/prompts.py` (109 lines) — `minimal_deriver_prompt`
- `src/deriver/enqueue.py` (634 lines) — enqueue paths

### Dialectic subsystem
- `src/dialectic/chat.py` (140 lines) — chat-route handler
- `src/dialectic/core.py` (544 lines) — tool loop orchestration
- `src/dialectic/prompts.py` (237 lines) — dialectic prompts

### Dreamer subsystem
- `src/dreamer/dream_scheduler.py` (406 lines)
- `src/dreamer/orchestrator.py` (411 lines)
- `src/dreamer/specialists.py` (742 lines)
- `src/dreamer/surprisal.py` (492 lines)
- `src/dreamer/trees/` (subdirectory; contents TBD)

### Reconciler subsystem
- `src/reconciler/scheduler.py` (268 lines)
- `src/reconciler/sync_vectors.py` (629 lines)
- `src/reconciler/queue_cleanup.py` (TBD lines)

### Summarizer
- `src/utils/summarizer.py` (TBD lines) — note the `utils/` location asymmetry

### LLM abstraction (shared)
- `src/llm/tool_loop.py` (676 lines)
  - `:289` — `max_input_tokens` parameter
  - `:328` — truncation latch
  - `:344-348` — truncation logic (first occurrence)
  - `:569-573` — truncation logic (second occurrence)
- `src/llm/backend.py` (TBD)
- `src/llm/backends/` (subdirectory — provider implementations)
- `src/llm/registry.py` (TBD)
- `src/llm/executor.py` (TBD)
- `src/llm/types.py`
  - `:106` — `max_input_tokens` documentation in type docstring

### Vector store
- `src/vector_store/lancedb.py` (TBD lines)
- `src/vector_store/turbopuffer.py` (TBD lines)

### CRUD / data layer
- `src/crud/peer_card.py` — peer card primitive
- `src/crud/representation.py` — `create_observations`, `delete_observations`, `get_observation_context` (code-side of conclusion/observation dual)
- `src/crud/message.py` — message creation
- `src/crud/document.py` — vector document CRUD
- `src/crud/collection.py` — collection CRUD
- `src/models.py` — `Workspace`, `Peer`, `Session`, `Message`, `Collection`, `Document`, `QueueItem`, `ActiveQueueSession`

### Routers (HTTP surface)
- `src/routers/conclusions.py` — public `/conclusions` endpoints (vocabulary-dual evidence)
- `src/routers/messages.py`
- `src/routers/peers.py` — includes the chat route (dialectic entry)
- `src/routers/sessions.py`
- `src/routers/workspaces.py`
- `src/routers/keys.py`
- `src/routers/webhooks.py`

### Telemetry
- `src/telemetry/events/representation.py`
  - `:109-110` — `max_input_tokens` event field
  - `:123` — truncation event flag
- `src/telemetry/events/dialectic.py`
  - `:75` — `settings.DIALECTIC.MAX_INPUT_TOKENS` reference

### Utilities
- `src/utils/agent_tools.py` (2,566 lines) — `DIALECTIC_TOOLS` definitions
  - `:1651` — embedding token cap error message (cites `settings.EMBEDDING.MAX_INPUT_TOKENS`)
- `src/utils/search.py`
  - `:393` — query token cap error message
- `src/utils/config_helpers.py` (TBD) — config cascade mechanism
- `src/utils/summarizer.py` — see Summarizer above

### Security & startup
- `src/security.py` (TBD)
- `src/startup.py` (TBD) — `validate_embedding_schema`

---

## Non-cited support files (read but not directly cited)

- `pyproject.toml` — dependency manifest (verified: cashews, uvloop, fastapi, sqlalchemy, sentry-sdk, prometheus_client, nanoid present)
- `migrations/` — Alembic migrations (App→Workspace, User→Peer rename history; not yet traced for this probe)
- `tests/` — present, read selectively for behaviour assertions in feature specs

---

## Satellite repos (cited as availability/portability evidence; NOT code-traced)

Per nanoprobe rule, satellite repos are noted here but never traced. Per-feature specs may cite their *existence* as evidence of portability (G7) but never their internal implementation.

- `sdks/python/` — Python SDK (in monorepo)
- `sdks/typescript/` — TypeScript SDK (in monorepo)
- `mcp/` — MCP server wrapper (in monorepo)
- `honcho-cli/` — CLI (in monorepo)
- `examples/crewai/`, `examples/gmail/`, `examples/granola/`, `examples/langgraph/`, `examples/n8n/`, `examples/zo/` — integration examples
- `docker/` — container definitions

External satellite repos to check during the probe (if they exist as separate repos rather than in-monorepo):
- TBD — verify via README links during 00-summary writing

---

## External sources (Tier 1, off-repo)

- **Plastic Labs blog** — referenced from docs
  - https://blog.plasticlabs.ai/blog/Memory-as-Reasoning — philosophy of "memory as reasoning"
  - https://blog.plasticlabs.ai/research/Introducing-Neuromancer-XR — named custom model
  - https://blog.plasticlabs.ai/blog/Introducing-Honcho-Chat — honcho.chat demo
- **Plastic Labs Discord** — https://discord.gg/honcho (community channel; cited only as support contact)
- **Honcho Chat (demo)** — https://honcho.chat
- **Honcho Platform** — https://app.honcho.dev (managed offering; not in scope for sovereignty audit)

---

## Reproduction protocol

To verify any claim in this nanoprobe:

```bash
git clone https://github.com/plastic-labs/honcho.git honcho-probe
cd honcho-probe
git checkout 7470866d12845ed4b56bf3449d058e65df96b1c1
# Then consult the cited file:line
```

Doc references (`docs/v3/...`) are stable within the SHA. External URLs (blog posts, marketing pages) may drift — they're cited with retrieval date 2026-05-24.

---

## Citation completion status

- ✅ Architecture map (`02-architecture.md`) — all claims cited
- ✅ Assessment (`04-assessment.md`) — all factual claims cited; assessments labelled Tier 3
- ⏳ Per-feature specs — citations append as each spec is written
- ⏳ Goal mapping (`03-mapping.md`) — pending feature specs
- ⏳ Summary (`00-summary.md`) — written last
