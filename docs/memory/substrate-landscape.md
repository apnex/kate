# 05 — Memory Substrate Landscape

**Status:** Initial survey (snapshot)
**Date:** 2026-05-24
**Author:** apnex + hermes (delegated research subagent)
**Scope:** Survey of AI-agent memory / context-engineering substrates available
as of May 2026. Sibling to `02-research-findings.md` (which focused on tuning
the *current* Honcho deployment); this document looks **outward** at what else
exists, so future architecture decisions are informed by the landscape rather
than re-derived ad-hoc.

---

## Why this document exists

The Hermes deployment standardised on **Honcho v3.0.7** (Plastic Labs) for one
specific reason: it does *derived* memory — a background "Dialectic API" that
reasons over raw observations to form persistent conclusions about the user
(theory-of-mind style), rather than just storing and retrieving text.

That choice was made in May 2026 after a short comparison against Letta/MemGPT,
mem0, Zep, and Cognee. Since then the space has moved fast: MemOS, A-MEM,
LightRAG, HippoRAG 2, and the "sleep-time compute" pattern have all emerged
or matured. This doc captures the wider field so that:

1. We can re-evaluate Honcho periodically against credible alternatives
   without redoing the survey from scratch.
2. A future "substrate swap" or "substrate alongside Honcho" decision has a
   shared reference point.
3. Newcomers worth tracking are written down before they're forgotten.

This is a **snapshot**, not a living comparison matrix. Re-survey quarterly
or when a substrate change is actively being considered.

---

## The axis that matters: *derived* vs *stored* memory

Most "agent memory" projects are storage and retrieval — better-flavoured
vector DBs with a chat-history shape. They help with recall but do not form
*new* facts about the user or world over time.

A smaller subset performs **derived memory**: a background loop that reads
observations and emits persistent, deduplicated, sometimes-reconciled
conclusions. This is the property Honcho was chosen for, and it is the axis
on which any replacement must be evaluated first.

Other axes (memory model, license, surface area, maturity) matter for
ops fit but only after the derivation question is answered.

---

## Landscape snapshot (May 2026)

Honcho baseline for reference:

- Memory model: dialectic / theory-of-mind, derived from observations
- Storage: Postgres + pgvector
- Surface: REST + Python/TS SDK + MCP
- License: AGPL-ish, self-hostable
- Maturity: ~4.1k stars, very active (last push May 22, 2026)
- Differentiator: background dialectic reasoning forms persistent conclusions
- Limitation: no temporal-graph reasoning; conclusion quality depends heavily
  on `dialecticDepth` / `dialecticReasoningLevel` tuning (see `02-research-findings.md`)

```
┌─────────────────────┬──────────────┬────────────────┬────────────┬─────────────────────────┐
│ Substrate           │ Model        │ Self-host / Lic│ Derived?   │ Diff vs Honcho          │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ Letta (ex-MemGPT)   │ Tiered       │ Y / Apache-2   │ Self-edit  │ Full agent runtime;     │
│ 22.9k stars         │ (core/arch)  │                │ on writes  │ heavier, opinionated    │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ mem0                │ Vector       │ Y / Apache-2   │ Yes (LLM   │ Biggest ecosystem;      │
│ 56.5k stars         │ (+graph)     │ + SaaS tier    │ extract)   │ shallow fact-list flavor│
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ Zep / Graphiti      │ Temporal KG  │ Graphiti=OSS;  │ Yes (KG    │ Best temporal reasoning │
│ 26.4k / 4.6k stars  │              │ Zep Cloud=SaaS │ build)     │ (valid-time edges)      │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ Cognee              │ Graph+vector │ Y / Apache-2   │ Ontology   │ ETL framework vibe,     │
│ 17.5k stars         │              │                │ inference  │ ontology-first          │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ MemoryOS (BAI-Lab)  │ STM/MTM/LTM  │ Y / MIT        │ Persona    │ EMNLP'25 academic; tiny │
│ 1.4k stars          │ tiered       │                │ drift,heat │ ops story               │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ MemOS (MemTensor)   │ Hybrid       │ Y / Apache-2   │ Skill      │ Most credible "next-gen"│
│ 9.4k stars (fast)   │ (vec+gr+KV)  │                │ consolid.  │ sovereign substrate     │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ A-MEM               │ Atomic notes │ Y / MIT        │ Notes      │ Memories rewrite their  │
│ 1.0k stars          │ + links      │                │ self-evolve│ own links — novel       │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ txtai (memory)      │ Vec (+graph) │ Y / Apache-2   │ No         │ Single-binary feel; no  │
│ 12.6k stars         │              │                │            │ derivation layer        │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ Redis LangCache /   │ Vec KV +     │ Self-host Redis│ No (cache  │ Ops-mature, not derived │
│ RedisVL             │ session log  │ LangCache=SaaS │ + summary) │ memory at all           │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ Pinecone Assistants │ Vec + hist   │ N — SaaS only  │ Summary    │ Fails sovereignty test  │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ LangMem (LangChain) │ Vec + prof/  │ Y / MIT lib    │ Background │ Best inside LangGraph,  │
│ 1.5k stars          │ episodic     │                │ reflect    │ awkward standalone      │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ LlamaIndex memory   │ Memory       │ Y / MIT        │ Fact-      │ Composable blocks; lib  │
│ 49.6k (framework)   │ blocks       │                │ extract    │ not a service           │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ Composio memory     │ Vec + KV per │ Hybrid (OSS+   │ No (tool   │ 1000 tools + auth bundled│
│ 28.4k stars         │ user/agent   │ control plane) │ scratchpad)│ memory layer is thin    │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ HippoRAG 2 (OSU)    │ Graph + PPR  │ Y / MIT        │ Continual  │ Neurobio-inspired       │
│ 3.5k stars          │              │                │ KG merge   │ continual integration   │
├─────────────────────┼──────────────┼────────────────┼────────────┼─────────────────────────┤
│ LightRAG (HKUDS)    │ Graph+vector │ Y / MIT        │ Incremental│ Becoming default "graph │
│ 35.6k (huge mo.)    │ dual-level   │                │ graph upd. │ memory" engine          │
└─────────────────────┴──────────────┴────────────────┴────────────┴─────────────────────────┘
```

### Mergers / renames worth knowing

- **MemGPT → Letta.** The Berkeley team rebranded; `cpacker/MemGPT` redirects.
  The "OS" framing (core / archival / recall tiers + paging) lives on inside
  Letta. If you read older blog posts mentioning MemGPT, mentally substitute
  Letta.
- **Sema4** pivoted away from memory toward agent actions. The closest live
  "memory + tools" substrate in that lineage today is **Composio**.

---

## Newcomers worth tracking

Architecturally interesting but not yet mature enough to be table-row peers:

- **MemOS (MemTensor)** — 9.4k stars in under 12 months. "Memory cube"
  abstraction unifying KV-cache + vector + graph memory with a scheduler.
  Closest in *spirit* to Honcho's "memory as a first-class substrate"
  framing, but skill-reuse flavoured rather than dialectic. Worth a
  serious POC on k3s if/when we re-evaluate.
- **A-MEM** — tiny (~1k stars) but the *mechanic* is the most novel
  derived-memory idea in OSS: each new observation can rewrite the links
  between existing memories, Zettelkasten-style. The idea is liftable into
  a Honcho-style service even if you don't adopt the whole project.
- **LightRAG** — not user-memory per se, but the incremental dual-level
  graph index is becoming the de facto "graph memory" engine that other
  substrates plug underneath (mem0's graph mode, several MemoryOS forks).
- **"Sleep-time compute" pattern** — Q1 2026 HN/arxiv cluster around
  nightly memory-rewrite loops (merge / reweight / drop / re-embed).
  Not a product, a pattern. Honcho-likes are converging on it. Track the
  arxiv `2503.xxxxx` "sleep-time compute" cluster.
- **"Context engineering substrate"** as a term — popularised late 2025 by
  Karpathy and HN threads. Honcho, Letta, and MemOS are the three projects
  most often cited under this banner in early-2026 discussion.

---

## Sovereign-deploy shortlist (given current k3s + LiteLLM topology)

In order of how plausibly each could land in our actual cluster today:

1. **Stay on Honcho** if dialectic theory-of-mind is the core value we want.
   This is the current default. Re-confirm by checking whether conclusion
   quality (see `02-research-findings.md`) justifies continued use.
2. **Add Graphiti *alongside* Honcho** (Apache-2, runs on Neo4j we could
   helm-chart) if we want temporal-KG reasoning Honcho doesn't do. Hybrid
   deployment, not replacement.
3. **POC MemOS (MemTensor)** as the most credible "next-gen" sovereign
   substrate. Treat as a parallel substrate, not a Honcho swap, until its
   derivation quality is benchmarked against ours.
4. **Cognee** if our corpus shifts toward document/ontology rather than
   conversation. Not relevant today; flagged for future drift.
5. **Skip:** Pinecone Assistants, Zep Cloud, LangCache SaaS — all fail the
   sovereignty test for this deployment.

---

## How this fits with the rest of `docs/memory/`

- `00-goals.md` — what "good memory" means for this deployment (criteria).
- `01-research-brief.md` — frozen scope handed to the Honcho-tuning subagent.
- `02-research-findings.md` — findings on tuning the *current* Honcho stack.
- `03-design-decisions.md` — decisions taken off the back of (02).
- `04-implementation-plan.md` — execution plan for (03).
- **`05-substrate-landscape.md` (this doc)** — outward view of alternatives,
  so (03) and future re-evaluations have a shared frame of reference.

This is the first "look outward" entry. Future siblings might be:

- `06-substrate-benchmark.md` — once we actually POC MemOS or Graphiti.
- `07-substrate-swap-decision.md` — only if we ever seriously consider moving
  off Honcho.

---

## Re-survey triggers

Refresh this snapshot when any of:

- Honcho hits a wall we can't tune around (conclusion quality, latency,
  multi-user fan-out).
- A newcomer in the "track" list crosses ~5k stars *and* ships a v1.0 or
  equivalent stability signal.
- A paradigm shift in the space (e.g. "sleep-time compute" lands as a
  productised substrate, or temporal KGs become standard).
- Quarterly anyway, to avoid silent staleness.

Otherwise, treat this as reference material, not a TODO list.
