# OSS Deep-Research Methodology

**Status:** Active
**Date:** 2026-05-24 (revised)
**Author:** apnex + hermes

## What this is

A multi-stage methodology for deep, code-grounded, evidence-triangulated
research on open-source projects. Used when survey-level information (stars,
README one-liner, marketing copy) is insufficient and we need to know what
the code actually does.

This document is the **human-readable index**. The methodology itself lives
as agent skills under the `research/` category. The skills are the source of
truth; this doc points to them.

## Skill stack

| Layer | Skill | What it provides |
|---|---|---|
| Generic discipline | `research-artefacts` | Four rules every research artefact follows: tier separation, signal density, scaffolding before execution, two-pass discipline |
| Per-repo audit | `nanoprobe` | OSS-audit-specific shape on top: code-as-source-tier, triangulation taxonomy, feature-spec format, architectural-seams path selection |
| Cross-substrate analysis | `crossprobe` (TBD) | Comparative pass that consumes N nanoprobe outputs |

`research-artefacts` is the foundational layer — load it first when working on
any persistent research artefact, not just OSS audits.

## The two-pass shape

| Pass | What it does | Where it lives |
|---|---|---|
| **Per-repo audit** | Descriptive: characterise one repo on its own terms with triangulated evidence | skill: `nanoprobe` |
| **Cross-substrate analysis** | Comparative: reconcile feature taxonomies, build comparison matrices, identify capability gaps | skill: `crossprobe` (TBD) |

**The boundary is strict.** Describe in pass 1; compare only in pass 2. Mixing
the two contaminates the descriptive pass with comparative bias and forces
premature abstraction across substrates that may not actually align. This is
Rule 4 of `research-artefacts` — two-pass discipline.

## Pass 1: nanoprobe

Per-repo, per-substrate deep audit. One nanoprobe = one repository = one
substrate's own feature list, characterised in its own vocabulary.

**Depth floor: L3 (code probe).** Every probe reads the actual source for
every feature. README and docs alone are never sufficient.

**Output shape** (under the domain folder, e.g. `kate/docs/memory/<substrate>/`):

```
<substrate>/
├── 00-summary.md       Tier 3 abstract — distilled findings, written LAST
├── 02-architecture.md  Tier 1+2 — substrate-shaped descriptive map
├── 03-mapping.md       Tier 3 — how it addresses domain goals
├── 04-assessment.md    Tier 3 — probe analysis: trade-offs, gotchas, gaps
├── sources.md          reproducibility — every URL, SHA, file, retrieval date
└── features/           Tier 1+2 — one file per feature
    ├── <feature>.md
    └── ...
```

### Three-tier knowledge discipline (Rule 1 of research-artefacts)

| Tier | What | Where it lives |
|---|---|---|
| **Tier 1 — Claim** | Substrate's self-description (README, docs) | Architecture map + feature specs (cited inline) |
| **Tier 2 — Source** | Verifiable file:line facts at pinned SHA | Architecture map + feature specs (cited inline) |
| **Tier 3 — Analytical** | Prober's interpretation, dated/signed | Assessment (open-ended), mapping (goal-bounded), summary (final synthesis) |

Tier 1+2 artefacts contain no analytical language. Tier 3 artefacts open with
an explicit Tier 3 banner. When Tier 3 appears inside a Tier 1+2 artefact
(e.g. "Behaviour notes" in a feature spec), it is explicitly labelled.

### Triangulation

Each feature spec triangulates across:

- **Claim** — what the project says about itself (README, blog, paper)
- **Doc** — how it's documented (API ref, config schema, ARCHITECTURE.md)
- **Source** — what the code actually does (`file:line` @ SHA)

Triangulation status (fixed taxonomy — do not invent new statuses):

- ✓ Triangulated — all three present and consistent
- ⚠ Partial — at least two of three present, no documented inconsistency
- ⚠ Mismatch — all three present, but docs/claim actively contradict source (must surface in Behaviour notes AND assessment)
- ✗ Single-source — only one of claim/doc/source present

### Feature spec format

```
# Feature: <substrate-native-name>
**Triangulation:** ✓ Triangulated
## What it is
One paragraph in the substrate's own vocabulary.
## Requirement
The system SHALL <observable behaviour>.
## Scenarios
### Scenario: ...
- GIVEN ... WHEN ... THEN <observable outcome>
## Evidence
| Type | Reference |
| Claim | <quote> — <url>, retrieved <date> |
| Doc | <section> — <url> |
| Source | <file:line> @ commit <sha> |
## Behaviour notes (Tier 3 — scoped to THIS feature only)
- Edge cases, defaults, surprises, claim/source mismatches
```

Scenarios describe **observable behaviour** (telemetry events, side effects,
return values, persisted state changes) — not implementation steps. Behaviour
notes are scoped strictly to behaviour of THIS feature; cross-cutting analysis
goes to `04-assessment.md` with a back-reference.

See `skill_view(name="nanoprobe")` for the full methodology.

## Pass 2: crossprobe (TBD)

Consumes N nanoprobe outputs as input. Produces:

- Feature taxonomy reconciliation across substrates
- Cross-substrate comparison matrices
- Capability gap analysis
- Abstract-concept-to-goal mapping across the full substrate set

Not yet built. Will be created after enough nanoprobe outputs exist to ground
the methodology empirically (planned: post-Honcho nanoprobe + at least 2 more).

## Where outputs live

Per-domain, in this repo (`apnex/kate`):

```
kate/docs/<domain>/
├── 00-goals.md                  domain-specific goals
├── substrate-landscape.md       L1 survey row-per-substrate
├── <substrate-1>/               nanoprobe output
├── <substrate-2>/               nanoprobe output
└── analysis/                    crossprobe output (when it exists)
```

Current domains:

- **memory** — `kate/docs/memory/` — AI agent memory / context engineering
  substrates. Honcho is the current production substrate. Landscape doc
  exists; Honcho nanoprobe in progress (2026-05-24).

Future domains may include inference engines, agent frameworks, MCP server
ecosystems, etc. Each gets its own goals doc, taxonomy, and substrate
folders.

## How to start a nanoprobe

Tell the agent:

> Run nanoprobe on `<substrate-name>`. Canonical repo: `<github-url>`. Pin to
> SHA / tag `<sha-or-tag>`. Output to `kate/docs/<domain>/<substrate>/`.
> Goals doc: `kate/docs/<domain>/00-goals.md`.

The agent will load the `research-artefacts` and `nanoprobe` skills and follow
the documented workflow. Expect ~2-4 hours per substrate at L3 depth for a
medium-sized substrate (~10k LOC, ~5 subsystems).

## Core principles

1. **One repo per probe.** Canonical upstream only. Satellite repos cited but
   not code-traced.
2. **Substrate-native vocabulary.** Name features what the project calls
   them. Renaming is crossprobe's job.
3. **No cross-substrate references in nanoprobe output.** Strict isolation —
   applies uniformly to Tier 1+2 AND Tier 3.
4. **Triangulation required.** Every feature has claim, doc, source — or
   triangulation status flags the gap.
5. **L3 floor.** Code reading is non-negotiable.
6. **Reproducibility.** Every citation must be re-verifiable at the pinned
   SHA.
7. **Tier separation.** Descriptive artefacts carry no analytical language;
   analytical artefacts open with explicit Tier 3 banner.
8. **Signal density.** Default to terse structured entries; paragraph prose
   is the exception.
9. **Scaffolding before execution.** Probe plan exists before any code-trace.

## Why this exists (rationale)

The first memory-substrate survey (`substrate-landscape.md`) was an L1 sweep:
stars, README descriptions, one-line differentiators. Useful for triage, but
insufficient for actual decisions — we don't *know* if a substrate's claimed
"derived memory" is real derivation or just `LLM.extract_facts(text)` in a
loop. The only way to know is to read the code.

This methodology defends against:

- **Marketing-driven evaluation** — claims systematically overstate.
- **Doc-driven evaluation** — docs systematically lag reality.
- **Vibes-based comparison** — "feels similar" is not evidence.
- **One-off research that can't be re-verified** — without pinned SHAs and
  inline citations, every re-evaluation starts from zero.
- **Contaminated descriptions** — research that mixes "what is" with "what
  it means" produces artefacts readers can't trust.

The corpus of nanoprobe outputs becomes a reusable evidence base for any
future architectural decision in the domain.

## Revision history

- 2026-05-24 (initial) — methodology defined; nanoprobe skill created
- 2026-05-24 (revised) — `research-artefacts` skill added as foundational
  layer; output structure updated (`02-architecture.md` replaces
  `02-code-trace.md`; `04-assessment.md` added); tier discipline documented;
  triangulation taxonomy fixed at four statuses
