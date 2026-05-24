# OSS Deep-Research Methodology

**Status:** Active
**Date:** 2026-05-24
**Author:** apnex + hermes

## What this is

A multi-stage methodology for deep, code-grounded, evidence-triangulated
research on open-source projects. Used when survey-level information (stars,
README one-liner, marketing copy) is insufficient and we need to know what
the code actually does.

This document is the **human-readable index**. The methodology itself lives
as agent skills under the `research/` category. The skills are the source of
truth; this doc points to them.

## The two-pass shape

| Pass | What it does | Where it lives |
|---|---|---|
| **Per-repo audit** | Descriptive: characterise one repo on its own terms with triangulated evidence | skill: `nanoprobe` |
| **Cross-substrate analysis** | Comparative: reconcile feature taxonomies, build comparison matrices, identify capability gaps | skill: `crossprobe` (TBD) |

**The boundary is strict.** Describe in pass 1; compare only in pass 2. Mixing
the two contaminates the descriptive pass with comparative bias and forces
premature abstraction across substrates that may not actually align.

## Pass 1: nanoprobe

Per-repo, per-substrate deep audit. One nanoprobe = one repository = one
substrate's own feature list, characterised in its own vocabulary.

**Depth floor: L3 (code probe).** Every probe reads the actual source for
every feature. README and docs alone are never sufficient.

**Output shape** (under the domain folder, e.g. `kate/docs/memory/<substrate>/`):

```
<substrate>/
├── 00-summary.md       what is it, scope, findings, cull status
├── 02-code-trace.md    3-5 core code paths, narrative + file:line
├── 03-mapping.md       how it addresses our goals (cite features)
├── sources.md          every URL, SHA, file, retrieval date
└── features/           one file per feature
    ├── <feature>.md
    └── ...
```

**Each feature is triangulated** across:

- **Claim** — what the project says about itself (README, blog, paper)
- **Doc** — how it's documented (API ref, config schema, ARCHITECTURE.md)
- **Source** — what the code actually does (`file:line` @ SHA)

Mismatches between the three are *findings*, not failures.

**Feature spec format** (OpenSpec-inspired Requirement + Scenarios):

```
# Feature: <substrate-native-name>
**Triangulation:** ✓ Triangulated
## Requirement
The system SHALL <observable behaviour>.
## Scenarios
### Scenario: ...
- GIVEN ... WHEN ... THEN ...
## Evidence
| Type | Reference |
| Claim | <quote> — <url>, retrieved <date> |
| Doc | <section> — <url> |
| Source | <file:line> @ commit <sha> |
## Behaviour notes
- ...
```

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
  exists; nanoprobes pending.

Future domains may include inference engines, agent frameworks, MCP server
ecosystems, etc. Each gets its own goals doc, taxonomy, and substrate
folders.

## How to start a nanoprobe

Tell the agent:

> Run nanoprobe on `<substrate-name>`. Canonical repo: `<github-url>`. Pin to
> SHA / tag `<sha-or-tag>`. Output to `kate/docs/<domain>/<substrate>/`.
> Goals doc: `kate/docs/<domain>/00-goals.md`.

The agent will load the `nanoprobe` skill and follow the documented workflow.
Expect ~2 hours per substrate at L3 depth.

## Core principles (one-paragraph summary)

1. **One repo per probe.** Canonical upstream only. Satellite repos cited but
   not code-traced.
2. **Substrate-native vocabulary.** Name features what the project calls
   them. Renaming is crossprobe's job.
3. **No cross-substrate references in nanoprobe output.** Strict isolation.
4. **Triangulation required.** Every feature has claim, doc, source — or
   triangulation status flags the gap.
5. **L3 floor.** Code reading is non-negotiable.
6. **Reproducibility.** Every citation must be re-verifiable at the pinned
   SHA.

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

The corpus of nanoprobe outputs becomes a reusable evidence base for any
future architectural decision in the domain.
