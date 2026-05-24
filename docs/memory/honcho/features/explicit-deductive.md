# Feature: explicit-and-deductive-reasoning

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Derivation
**Triangulation:** ⚠ Mismatch — schema supports three observation levels (explicit / deductive / inductive); production deriver writes only explicit; docs describe a richer scaffolding than source delivers at this SHA

## What it is

The Honcho data model defines three levels of observation about an observed peer: **Explicit** (atomic facts stated directly in messages), **Deductive** (necessarily-true conclusions derived from explicit facts plus logical inference), and **Inductive** (probabilistic generalisations from patterns across multiple explicit observations). Each level has its own Pydantic schema with provenance fields (`source_ids`) for tracing higher-order observations back to their premise observations.

At this SHA, only the explicit level is produced by the production deriver. Deductive and inductive observations exist as schemas, are accepted by the storage layer, and are read by retrieval, but the path that *writes* them is not the minimal deriver — it lives elsewhere (hypothesised: dreamer specialists; to verify in batch 3).

## Requirement

The system SHALL define and persist observations at three logical levels — explicit, deductive, inductive — each with provenance back-references (`source_ids`) supporting tree traversal from higher-order observations to their premise observations.

## Scenarios

### Scenario: explicit observations carry message-level provenance
- GIVEN messages processed by the deriver
- THEN persisted explicit observations have `level='explicit'`
- AND each observation's `message_ids` references the source message(s) it was extracted from

### Scenario: schema accepts deductive observations with observation-level provenance
- GIVEN a deductive observation written by any subsystem
- THEN the persisted observation has `level='deductive'`
- AND its `source_ids` field references the explicit observations it was derived from

### Scenario: source_ids tree traversal supports provenance queries
- GIVEN a deductive or inductive observation with non-empty `source_ids`
- WHEN traversing source_ids
- THEN the referenced observations exist in the same Collection
- AND from those, `message_ids` references trace back to source messages

### Scenario: production deriver writes explicit-only
- GIVEN any batch processed by the minimal deriver
- THEN persisted observations have `level='explicit'`
- AND no observations have `level='deductive'` or `level='inductive'`

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` §Formal Logic Framework — describes explicit→deductive→inductive→abductive reasoning modes |
| Doc | `docs/v3/documentation/core-concepts/reasoning.mdx` — example JSON output structure shows `explicit` and `deductive` lists populated by the deriver |
| Source | `src/utils/representation.py:59-95` — `ExplicitObservationBase`, `DeductiveObservationBase`, `InductiveObservationBase` schemas |
| Source | `src/utils/representation.py:64-95` — `source_ids` field on Deductive/Inductive bases for provenance tree |
| Source | `src/deriver/prompts.py:55-81` — `minimal_deriver_prompt` requests only `[EXPLICIT]` extraction |
| Source | `src/deriver/deriver.py:233` — `len(observations.explicit) + len(observations.deductive)` reads both, deductive list is empty in normal path |
| Source | negative search at SHA `7470866`: no `AbductiveObservation` class found |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Claim/source mismatch.** Docs claim four reasoning modes; schema implements three (no abductive); production deriver produces only one (explicit). See `04-assessment.md §A8` and `§A11`.
- **`source_ids` tree traversal is the seam between deriver and dreamer.** Deductive/inductive observations reference their premise explicit observations via document IDs — this is provenance-by-construction. See `04-assessment.md §A10` for the cross-cutting positive implication for auditable memory.
- **Where the deductive/inductive writes actually happen** is not in the deriver code path. Strong hypothesis: dreamer specialists (`src/dreamer/specialists.py` — 742 lines) read explicit observations and write back higher-order ones. To verify in batch 3 (see `04-assessment.md §A17`).
- **Schema-vs-prompt asymmetry is design-for-extensibility.** Storage and read paths support all three levels so background subsystems can backfill higher-order observations without schema changes. The seam exists; the writer-on-the-other-side is what needs to be characterised.
