# Honcho — Scope Coverage

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Probe date:** 2026-05-24
**Methodology:** `research/nanoprobe` "Option C" three-pass discovery

This document reconciles **planned scope** (the initial feature hypothesis) with **actual scope** (what got specced) and **deferred scope** (what was deliberately left out). It is the audit trail for the probe's coverage decisions.

---

## 1. Specs delivered (18)

### Foundations (5)
1. `features/observer-observed.md` — perspectival peer-pair as storage key
2. `features/peer-representation.md` — `RepresentationManager` data-access seam
3. `features/minimal-deriver.md` — single-LLM-call explicit extraction
4. `features/token-batching.md` — token-threshold batching at the deriver
5. `features/explicit-deductive.md` — three-level observation hierarchy + `source_ids`

### Retrieval (3)
6. `features/dialectic-chat.md` — inline agentic chat with write tools
7. `features/search-tools.md` — semantic + keyword search tool surface
8. `features/pluggable-vector-backend.md` — pgvector / LanceDB / Turbopuffer

### Async / cognition (5)
9. `features/dreamer.md` — async dream-cycle orchestrator + specialists
10. `features/reconciler.md` — async embedding sync + queue cleanup
11. `features/peer-card.md` — JSONB-on-`Peer` curated profile
12. `features/consolidation.md` — hybrid cosine + token-set dedup
13. `features/summarizer.md` — session-level summarisation

### Infrastructure (5) — batch 4
14. `features/hierarchical-config.md` — TOML/env/init precedence, nested settings, partial-override fix
15. `features/worker-lease-model.md` — Postgres `ON CONFLICT DO NOTHING` leases, stale reaper
16. `features/dream-scheduler.md` — singleton scheduler, two-layer anti-duplication, per-type fan-out
17. `features/tool-loop.md` — iterative agentic LLM loop, cap-hit synthesis, telemetry per iteration
18. `features/surprisal.md` — geometric surprisal sampling, 7 tree backends, 3 sampling strategies *(promoted mid-probe from sub-spec of dreamer)*

---

## 2. Planned-but-merged

These were initially planned as standalone specs but consolidated into broader specs during execution because they did not warrant Tier 1+2+3 separation:

| Originally planned | Merged into | Reason |
|---|---|---|
| `dream-trigger` | `dream-scheduler.md` | The trigger logic (`check_and_schedule_dream`) is operationally inseparable from the scheduler's state. |
| `representation-manager` | `peer-representation.md` | The manager IS the representation surface; splitting would duplicate sources. |
| `webhook-event-types` | (`02-architecture.md` §6 only) | Event list is enumerable; no algorithmic content warrants Tier-3 analysis. |
| `cloudevents-emitter` | (`02-architecture.md` §6 only) | Standard CloudEvents library usage; no novel substrate behaviour. |

---

## 3. Discovered mid-probe (promoted)

Features that were not on the original list but emerged as substantive during reading and were specced:

| Spec | When discovered | Promotion rule (research/nanoprobe §6.5) |
|---|---|---|
| `tool-loop.md` | Batch 4 | Shared infrastructure with non-trivial control flow (676 LOC, cap-hit synthesis, plan snapshotting) used by ≥2 subsystems. |
| `surprisal.md` | Batch 4 closing (this probe) | Own config namespace (`SurprisalSettings`), own source file (492 LOC), non-trivial algorithm (7 tree backends + 3 sampling strategies). User-flagged after batch-4 spec write. |

The surprisal promotion is the methodology's first live test of the "user-driven scope reconciliation" loop: user noticed surprisal was unspecced, agent verified scope gap, promotion criteria evaluated → promote.

---

## 4. Deferred (out-of-scope)

These were identified during reading but explicitly deferred — not because they're unimportant, but because they're either (a) generic infrastructure with no Honcho-specific surface, (b) operator concerns rather than substrate concerns, or (c) deserve their own probe pass.

| Area | Files | Why deferred |
|---|---|---|
| Telemetry pipeline | `src/telemetry/` (CloudEvents, Sentry, Prometheus, reasoning traces) | Generic observability infra; pattern is well-known. Mentioned in `02-architecture.md` §6 + G8 mapping. |
| Cache layer (`cashews` + SafeRedis) | `src/main.py:73-75` | Pure cache, no substrate-level memory semantics. Noted in A2. |
| LLM provider abstraction | `src/llm/backends/` + `src/llm/backend.py` + `src/llm/registry.py` | Generic provider routing; not Honcho-specific. Mentioned in `02-architecture.md` §6. |
| Auth / JWT key scoping | `src/security.py`, `src/routers/keys.py`, `AuthSettings` | Standard FastAPI auth; operator concern. |
| Webhook delivery | `src/webhooks/` + `src/routers/webhooks.py` | Event sink; standard HTTP delivery pattern. |
| Database migration history | `migrations/` directory | Maturity signal noted in A15; mechanism is Alembic, not novel. |
| Per-message metadata model | `src/models.py` Message column details | Schema reference; surface is small, no algorithmic content. |
| Dialectic loop-depth per reasoning level | (Open A20, A27) | Quick verification needed; not blocking probe close. Tracked as open assessment. |
| Abductive observations | Schema-extensible but unimplemented (A11) | No substrate behaviour to spec; absent feature. Noted in `00-summary.md`. |

---

## 5. Open assessments at probe close

From `04-assessment.md`:

- **A20** — What does `reasoning_level` control beyond model selection? (Partial: A25 confirmed model swap; loop depth / max tools / retrieval breadth per level still unverified.)
- **A21** — Does the worker-lease model serialise per `(observer, observed)` pair? *(Now resolvable from `features/worker-lease-model.md`: leases are per `work_unit_key` which encodes task_type + scope; for representation tasks the scope includes `(observer, observed)`. So yes — within a process. Cross-process: depends on `WORKERS` setting per replica.)*
- **A27** — `DIALECTIC_TOOLS` vs `DIALECTIC_TOOLS_MINIMAL` selection rule. Likely reasoning-level-keyed; quick verification still pending.

A21 can be promoted to resolved in a follow-up pass; A20 and A27 are deferred to a "dialectic-internals" mini-probe if needed.

---

## 6. Methodology notes (Option C confirmation)

This probe is the first to use the **three-pass discovery** model:

1. **Initial hypothesis pass** — list features expected from public docs + repo structure (yielded 13 candidates).
2. **Reading pass** — execute the spec writes, discover gaps, deferrals, and promotions. Identified 4 additional features in batch 4 (hierarchical-config, worker-lease-model, dream-scheduler, tool-loop) and 1 user-flagged promotion (surprisal). Identified 4 deferred infrastructure areas.
3. **Reconciliation pass** — this document. Reconciles planned vs. delivered vs. deferred, identifies promotion drivers, and surfaces remaining open assessments.

**Lesson for next probe**: the promotion criteria for §3 ("own config namespace + own source file >300 LOC + non-trivial algorithmic content") worked well. The user-driven scope check (surprisal) demonstrates the methodology is robust against agent-only blind spots; recommend baking a mid-probe "what did we miss?" prompt into `research/nanoprobe` as an explicit step.

---

## 7. Closing summary

- **18 features specced** (5 foundations + 3 retrieval + 5 async/cognition + 5 infrastructure).
- **4 features merged** into broader specs to avoid over-decomposition.
- **2 features promoted** mid-probe based on substrate evidence (tool-loop, surprisal).
- **8 areas deferred** as out-of-scope (generic infrastructure or operator concerns).
- **3 assessments remain open** (A20, A27, partial A21).
- **31 Tier-3 findings** logged in `04-assessment.md`, with in-place strike-through revisions tracking evolution.

The substrate is specced to a depth sufficient for the kate memory-system design work (per `03-mapping.md`). Cross-substrate comparative analysis is the next pass and explicitly out of scope for this probe.
