# Honcho — Probe Summary

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Probe date:** 2026-05-24
**Prober:** apnex + hermes
**Methodology:** `research/nanoprobe` (three-pass discovery, tier-separated, substrate-native vocabulary)
**Companion artefacts:** `02-architecture.md` (Tier 1+2 map), `04-assessment.md` (Tier 3 findings), `features/*.md` (18 specs), `03-mapping.md` (goals), `05-coverage.md` (scope reconciliation)

---

## Substrate in one paragraph

Honcho is an asynchronous memory substrate organised around perspectival peer-pairs `(observer, observed)`. A FastAPI server fronts a Postgres + Redis + pluggable-vector-store stack; a separate deriver worker process hosts three async schedulers (deriver-queue, reconciler, dreamer). Observations come in three levels — *explicit* (extracted by the minimal deriver), *deductive* and *inductive* (written by dreamer specialists with provenance via `source_ids`, and opportunistically by the dialectic agent at query time). Retrieval is via a tool-using dialectic agent that runs inline on the chat-request path without holding a DB connection. The substrate is configuration-heavy (hierarchical TOML/env/init precedence, per-reasoning-level model maps, per-specialist model configs) and observability-rich (CloudEvents per batch, Prometheus, Sentry, surprisal stats per dream run).

## Three writers, three cadences

| Writer | Cadence | Output level | Cost |
|---|---|---|---|
| Deriver | Message (batched by token threshold) | explicit | 1 LLM call / batch |
| Dreamer | Trigger (`check_and_schedule_dream` + idle timeout) | deductive, inductive | N specialist runs × tool loop |
| Dialectic | Query (when agent decides to write) | explicit, deductive, inductive, peer-card updates | Variable, agent-determined |

This split is the load-bearing architectural commitment. A benchmark that queries immediately after writes sees only explicit + query-time observations; dreamer output requires waiting for the trigger window.

## Pluggable surfaces

LLM backend, embedding backend, vector store (pgvector | LanceDB | Turbopuffer), auth, webhooks, telemetry. Each is a clean seam — providers slot in via config; the substrate doesn't hardcode commitments to specific vendors.

## Key capabilities discovered

- **Geometric surprisal as observation pre-filter** — seven tree backends behind a uniform `SurprisalTree` interface (`features/surprisal.md`). Optional; defaults off; failure mode degrades to unfiltered.
- **Perspectival storage at schema level** — `RepresentationManager(observer, observed)` and `Collection((workspace, observer, observed))` make "Bob's view of Alice" structural, not emergent (A14).
- **Provenance by construction** — higher-order observations carry `source_ids` referencing premise observations, which in turn carry `message_ids` referencing source messages. End-to-end auditability (G3).
- **Hybrid deduplication** — cosine-similarity ≥0.95 + token-set-difference scoring with information-preserving retention (`features/consolidation.md`). Catches paraphrases, no extra inference.
- **3-hour vector-store outage headroom** — reconciler retries with `MAX_SYNC_ATTEMPTS=20 × SYNC_BACKOFF=10min` before marking rows failed; primary writes never fail on vector outage.
- **DB-connection-free agent execution** — dialectic agent opens DB sessions only per tool call via `tracked_db`. Throughput bounded by LLM, not pool slots.
- **Worker leases are Postgres `INSERT … ON CONFLICT DO NOTHING`** — no application mutex; the unique index on `active_queue_sessions.work_unit_key` IS the mutex (`features/worker-lease-model.md`).

## Capabilities NOT present (negative findings)

- **No abductive specialist.** Docs claim four reasoning modes; schema has three observation levels; only two specialist classes exist (A11).
- **No TTL / decay / forgetting at any layer.** Only modulation is `DEDUPLICATE=True` at write time (A9). Honcho is monotonic-growth with retrieval ranking as the only filter.
- **No runtime config reload.** `config.toml` is loaded once at process start; operators must restart for changes (`features/hierarchical-config.md` §C2).
- **No standard (non-agentic) dialectic exposed.** `chat.py` exposes only the agent path. A faster `standard_dialectic` exists in code but is unrouted at this SHA (A23).

## Notable architectural smells

- **Summarizer at `src/utils/summarizer.py`** — 957 LOC subsystem classified as utility (A3, A31). The fifth subsystem in everything but directory placement.
- **Public-vs-code vocabulary dual** — API says "conclusion", code says "observation". Maintainers acknowledged but kept (A4).
- **`SECTION_MAP` is closed** — adding a new settings domain without updating it silently misses TOML overrides (`features/hierarchical-config.md` §C1).

## What this probe deliberately does NOT do

- **No cross-substrate comparison.** Per `research/nanoprobe` methodology, this artefact uses Honcho-native vocabulary only. Comparative work (e.g. Honcho vs. mem0 vs. Letta) is deferred to a separate crossprobe pass.
- **No infrastructure deep-dives.** Telemetry, cache, llm-providers, vector-store backends are listed as pluggable surfaces; full Tier-1/2/3 specs deferred (`05-coverage.md`).
- **No abductive-specialist forward-look.** Schema extensibility is noted but un-specced; the substrate doesn't implement it.

## Reading order

1. `02-architecture.md` — runtime topology, subsystems, primitives, config, storage, pluggable surfaces.
2. `features/*.md` — 18 specs grouped by layer (foundations, retrieval, async/cognition, infra). See `05-coverage.md` for the index.
3. `04-assessment.md` — Tier 3 analytical findings (A1–A31), evolution log via in-place strike-throughs.
4. `03-mapping.md` — substrate fitness against G1–G9 memory-system goals.
5. `05-coverage.md` — what was specced, what was deferred, what was promoted mid-probe.
