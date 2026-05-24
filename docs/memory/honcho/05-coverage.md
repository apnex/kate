# Honcho — Scope Coverage

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Probe date:** 2026-05-24 (initial probe) → 2026-05-24 (retro-audit pass D.1-D.4)
**Methodology:** `research/nanoprobe` five-pass meta-process (formalised post-probe in D.4)

This document reconciles **planned scope** (the initial feature hypothesis) with **actual scope** (what got specced) and **deferred scope** (what was deliberately left out). It is the audit trail for the probe's coverage decisions.

---

## 1. Specs delivered (21)

### Foundations (5)
1. `features/observer-observed.md` — perspectival peer-pair as storage key
2. `features/peer-representation.md` — `RepresentationManager` data-access seam
3. `features/minimal-deriver.md` — single-LLM-call explicit extraction
4. `features/token-batching.md` — token-threshold batching at the deriver
5. `features/explicit-deductive.md` — three-level observation hierarchy + `source_ids`

### Retrieval (4)
6. `features/dialectic-chat.md` — inline agentic chat with write tools
7. `features/search-tools.md` — semantic + keyword search tool catalogue
8. `features/pluggable-vector-backend.md` — pgvector / LanceDB / Turbopuffer
9. `features/document-query-strategies.md` — four retrieval shapes (semantic, recent, most-derived, filter-only) **(promoted in retro-audit D.1)**

### Async / cognition (6)
10. `features/dreamer.md` — async dream-cycle orchestrator
11. `features/reconciler.md` — async embedding sync + queue cleanup
12. `features/peer-card.md` — JSONB-on-`Peer` curated profile
13. `features/consolidation.md` — hybrid cosine + token-set dedup
14. `features/summarizer.md` — session-level summarisation
15. `features/specialist-contract.md` — `BaseSpecialist` ABC + the dreamer's three-write-tool ABI **(promoted in retro-audit D.1)**

### Infrastructure (6) — batches 4 + retro-audit
16. `features/hierarchical-config.md` — TOML/env/init precedence, nested settings, partial-override fix
17. `features/worker-lease-model.md` — Postgres `ON CONFLICT DO NOTHING` leases, stale reaper
18. `features/dream-scheduler.md` — singleton scheduler, two-layer anti-duplication, per-type fan-out
19. `features/tool-loop.md` — iterative agentic LLM loop, cap-hit synthesis, telemetry per iteration
20. `features/surprisal.md` — geometric surprisal sampling, 7 tree backends, 3 sampling strategies *(promoted mid-probe from sub-spec of dreamer)*
21. `features/dialectic-tool-abi.md` — dispatch contract, `ToolContext` injection, observation locking, partial-success result shape **(promoted in retro-audit D.1)**

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
| `surprisal.md` | Batch 4 closing | Own config namespace (`SurprisalSettings`), own source file (492 LOC), non-trivial algorithm (7 tree backends + 3 sampling strategies). User-flagged after batch-4 spec write. |
| `dialectic-tool-abi.md` | Retro-audit D.1 | Cited as Source row in `dialectic-chat.md`, `search-tools.md`, and `specialist-contract.md` but never had its own spec. Promotion-heuristic re-evaluation applied to existing citations (per skill pitfall #22) surfaced it. Meets 3 criteria: own dispatch surface, >300 LOC dedicated to ABI, non-trivial algorithm (level-policy enforcement, partial-success shape, parent_category telemetry threading). |
| `document-query-strategies.md` | Retro-audit D.1 | Cited as Source row in `consolidation.md` and `reconciler.md`. Four semantically-distinct retrieval shapes (semantic, recent, most-derived, filter-only) with their own perspectival keying invariant. Meets 2 criteria: own algorithmic complexity, >300 LOC dedicated. |
| `specialist-contract.md` | Retro-audit D.1 | Cited as Source row in `dreamer.md` Evidence table. `BaseSpecialist` ABC + three-tool ABI is reused by every dreamer specialist; spans deduction, induction (+ extensibility for abduction). Meets 3 criteria: own contract class, distinct from dreamer's orchestration logic, non-trivial (hints-as-non-binding-bias, per-specialist model routing, 15-iteration cap). |

The first two promotions (tool-loop, surprisal) were caught by the in-pass scan and user-flagging. The latter three were missed by the in-pass scan but caught by the retro-audit applying the promotion heuristic to **existing Source citations**, not just to gaps. This validated skill pitfall #22 (the most dangerous gaps are the ones you've already mentioned in passing — they pass the "did I notice this?" filter but fail the "did I characterise it adequately?" filter).

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

## 6. Methodology notes (five-pass meta-process)

This probe was originally executed in three passes (initial-hypothesis, reading, reconciliation). The retro-audit pass (D.1-D.4) revealed that the three-pass model under-counted the work — the actual discipline that produced this probe is **five passes**, now codified in `research/nanoprobe` §"Multi-pass meta-process":

1. **Sweep** — descriptive coverage in batches (the original 4 batches)
2. **Triangulation** — evidence-table audit per spec (folded into batch writes)
3. **Promotion audit** — apply 4-criterion heuristic to every Source citation (D.1 — caught dialectic-tool-abi, document-query-strategies, specialist-contract)
4. **Synthesis** — apply cross-feature lenses to thin Tier 3 sections (D.3 — added cross-feature bullets to token-batching, peer-representation, minimal-deriver)
5. **Reconciliation** — `05-coverage.md` + `00-summary.md` + `03-mapping.md` (this file)

The original three-pass framing collapsed passes 2-4 implicitly into pass 1, which under-counts the work and misses the discipline that distinguishes a publishable probe from a draft. The five-pass model makes each frame explicit and runnable in isolation; switching frames mid-spec produces shallow output in both.

Also formalised in D.4: five new lenses (lens 7-11 in `references/substrate-analysis-lenses.md`) covering locus-of-enforcement, operator-impact, failure-mode, structural-criticality, cross-feature-invariant. These were the patterns the B4 specs used but weren't codified anywhere reusable.

**Lessons:**
- Promotion criteria of "2+ of {own config namespace, own file >300 LOC, non-trivial algorithm, independently configurable}" worked well.
- **Apply promotion criteria to existing Source citations**, not just to gaps. The D.1 retro-audit caught three promotions that the in-batch scan missed because they were already cited in parent specs.
- **User-driven scope checks** (surprisal) are robust against agent-only blind spots; the retro-audit pattern catches the same class of miss without requiring user prompting, by forcing a re-read of the spec set against fixed criteria after writing.
- **Tier-3-leak pass** (D.2) compressed 7 specs' "What it is" sections by removing analytical framing that belonged in Behaviour notes. This was a stability-bias failure mode: specs as written looked fine until subjected to a fresh discipline pass.

---

## 7. Closing summary

- **21 features specced** (5 foundations + 4 retrieval + 6 async/cognition + 6 infrastructure).
- **4 features merged** into broader specs to avoid over-decomposition.
- **5 features promoted** based on substrate evidence (tool-loop, surprisal, dialectic-tool-abi, document-query-strategies, specialist-contract — last three from D.1 retro-audit).
- **8 areas deferred** as out-of-scope (generic infrastructure or operator concerns).
- **3 assessments remain open** (A20, A27, partial A21).
- **31 Tier-3 findings** logged in `04-assessment.md`, with in-place strike-through revisions tracking evolution.
- **Methodology evolved mid-probe**: three-pass → five-pass model formalised in `research/nanoprobe` skill (D.4); 5 new cross-feature lenses (7-11) codified.

The substrate is specced to a depth sufficient for the kate memory-system design work (per `03-mapping.md`). Cross-substrate comparative analysis is the next pass and explicitly out of scope for this probe.
