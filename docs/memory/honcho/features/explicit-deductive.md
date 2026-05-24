# Feature: explicit-and-deductive-reasoning

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Derivation
**Triangulation:** ⚠ Significant claim/source mismatch — schema supports three reasoning levels (explicit, deductive, inductive); production deriver produces only explicit; deductive/inductive presumably populated by other code paths (see Behaviour notes)

## What it is (substrate's own terms)

Honcho's representation schema models **three reasoning levels** for observations:

- **Explicit** — atomic facts directly derivable from a message (e.g. "alice is 25 years old" from "I just turned 25").
- **Deductive** — conclusions reached by combining premises (each carries `source_ids` to premise documents + human-readable `premises` + a `conclusion`).
- **Inductive** — patterns, generalisations, personality insights derived across many observations (carries `source_ids` like deductive).

Per `reasoning.mdx`, Honcho claims to perform formal logical reasoning that extracts explicit premises, draws deductive conclusions from them, identifies inductive patterns, and infers abductive explanations.

## Requirement

The system SHALL maintain a schema capable of representing observations at three reasoning levels (`explicit`, `deductive`, `inductive`), with deductive and inductive observations carrying back-references (`source_ids`) to their premise/source observations enabling tree traversal. The system SHALL populate at least the explicit level through automatic background processing of messages; population of deductive and inductive levels is performed by background reasoning subsystems beyond the minimal deriver.

## Scenarios

### Scenario: explicit observation is produced by minimal deriver
- GIVEN a message *"I took my dog for a walk in NYC"* from `peer_alice`
- WHEN the minimal deriver processes the batch containing this message
- THEN at least one `ExplicitObservation` is produced with content semantically equivalent to *"alice has a dog"* and/or *"alice lives in NYC"*
- AND the observation is saved as a `Document` with `level='explicit'` and `premises=None`

### Scenario: deductive observation carries premise references
- GIVEN a `DeductiveObservation` produced by any subsystem
- WHEN it is saved via `_save_representation_internal`
- THEN the resulting `Document` has `level='deductive'`, `content=obs.conclusion`, and `metadata.premises=obs.premises` (human-readable)
- AND `obs.source_ids` references the Document IDs of the premise observations, enabling traversal queries

### Scenario: inductive observation has same shape as deductive
- GIVEN an `InductiveObservation` (pattern/generalisation/personality insight)
- WHEN persisted
- THEN it carries `source_ids` and a content payload, structurally parallel to deductive observations but semantically distinct (patterns vs. logical conclusions)

### Scenario: minimal deriver does NOT produce deductive observations
- GIVEN the production deriver prompt (`minimal_deriver_prompt`)
- WHEN it is invoked
- THEN the rendered prompt contains ONLY `[EXPLICIT]` extraction instructions
- AND `Representation.deductive` from a deriver call is empty in normal operation

### Scenario: abductive reasoning is claimed but not yet schema-visible
- GIVEN the reasoning docs claim abductive reasoning ("inferring the simplest explanations for observed behaviour")
- WHEN searching the codebase for an `AbductiveObservation` schema
- THEN no such class exists at SHA `7470866` — abduction is documented as a capability but not (yet) materialised as a distinct schema level

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` §Formal Logic Framework — "extracts what was explicitly stated, draws certain conclusions from those, identifies patterns across multiple conclusions, and infers the simplest explanations for behavior" |
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` example JSON — structure with `explicit[]` and `deductive[]` lists, deductive entries carrying `premises[]` + `conclusion` |
| Claim | `CLAUDE.md` §Memory Architecture — references the minimal deriver as "single LLM call per batch using structured output" |
| Source | `src/utils/representation.py:59-61` — `ExplicitObservationBase(content: str)` |
| Source | `src/utils/representation.py:64-74` — `DeductiveObservationBase(source_ids: list[str], premises: list[str], conclusion: str)` |
| Source | `src/utils/representation.py:77-95` — `InductiveObservationBase` (patterns, generalizations, personality insights) — third reasoning level not present in the docs' example JSON |
| Source | `src/crud/representation.py:165-181` — `_save_representation_internal` assigns `obs_level = "deductive"` for `DeductiveObservation`, `obs_level = "explicit"` otherwise; `premises` stored in document metadata for deductive only |
| Source | `src/deriver/prompts.py:55-81` — `minimal_deriver_prompt` — explicit-only instructions, no deductive scaffolding |
| Source | `src/deriver/deriver.py:233` — `total_observations = len(observations.explicit) + len(observations.deductive)` — code counts both, but in normal flow `deductive` is empty after the minimal-deriver call |
| Source | (negative) `grep -r "Abductive" src/` — no `AbductiveObservation` schema at this SHA |
| Source | (negative) `grep -r "Inductive" src/` — `InductiveObservationBase` defined but not produced by the minimal deriver path |

## Behaviour notes (Tier 3 — prober analysis)

- **Schema is richer than the production extraction path.** Three levels (explicit/deductive/inductive) are defined; the production deriver fills only one. This is a *design-for-extensibility* pattern — the storage and read paths support the richer model so that any background subsystem (the dreamer being the leading candidate) can backfill deductive/inductive observations later.
- **The dreamer is the missing reasoner.** The docs describe four reasoning modes (explicit / deductive / inductive / abductive). The deriver does only explicit. Where do the others happen? Hypothesis: the **dreamer specialists** (`src/dreamer/specialists.py`, 742 lines) implement the higher-order modes. The deriver feeds explicit facts to the database; the dreamer reads from the same database, runs specialist reasoning, and writes back deductive/inductive observations referencing the explicit ones via `source_ids`. **Tree traversal via `source_ids` is the architectural seam between deriver-output and dreamer-output.** To be verified in the dreamer feature spec.
- **Abductive is documented but not schematised.** Either:
  1. Abductive reasoning emerges from inductive-level outputs (loose categorisation), or
  2. Abductive is an unimplemented promise from the docs.
  Worth checking the dreamer specialist roster — if there's a "Detective" or "Hypothesiser" specialist, that's abductive in flight even without a named schema level.
- **`source_ids` is the killer feature for explainability.** Any deductive or inductive observation can be traced back through `source_ids` to its underlying explicit observations, and from those to source `message_ids`. **This is provenance-by-construction** — a property our G3 (auditable memory) goal explicitly wants. Major positive triangulation point for Honcho.
- **The docs' headline "formal logical reasoning" needs caveating for new users.** At the *deriver* level (the one most users will interact with first), reasoning is explicit fact extraction. The richer reasoning is a property of the *dreamer* — a background subsystem with different cadence, different costs, and (almost certainly) different latency to availability. If you query a peer representation immediately after a message, you get explicit observations only; deductive/inductive emerge over time as the dreamer runs.
