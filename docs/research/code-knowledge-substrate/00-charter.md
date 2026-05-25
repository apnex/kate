# Code Knowledge Substrate — Research Charter

Status: DRAFT (Entry 001 of design journal)
Started: 2026-05-25
Owner: apnex + hermes (collaborative)
Location discipline: this folder lives in `/root/kate/docs/research/code-knowledge-substrate/`.
Promotion target: `apnex/mission-kit` (only after worked-example proof).

## Why this exists

The Honcho audit (`/root/kate/docs/memory/honcho/`) exposed a gap: we have feature
specs in two formats (A = Gherkin/scenario, B = §A/§B/§C tiers) but no
codified theory of what a feature *node* is, what notations are admissible
inside it, and how those nodes compose into something an Architect-class
agent can reason over without re-reading the source repo.

This research mission codifies that theory. The output is a substrate —
a structured, multi-layer, agent-consumable representation of a codebase's
knowledge — not a documentation system for humans.

## Scope (in)

- Layer model (L0 source → L1 nanoprobe → L2 derivations → L3 consumer agents)
- Notation classes (Class 1 slot-format, Class 2 relational, Class 3 delta)
- Feature node schema (mandatory vs optional slots, per slot-type)
- Format selection rules (which Class-1 notation per slot type, which
  Class-2 notation per relational concern)
- Promotion / triangulation discipline (carried over from nanoprobe audit)

## Scope (out — handled elsewhere)

- AST extraction mechanics → `ast-symbol-corpus/` sibling research mission
- Honcho-specific feature backfill → `kate/docs/memory/honcho/` (consumer of this work)
- Mission-kit skill authoring → only after methodology proves out

## Success criteria

A worked example: the Honcho audit re-rendered under the codified schema,
producing feature nodes consumable by a downstream Architect agent that
has never seen the Honcho source repo and can still answer non-trivial
"how does X work?" questions from the nodes alone.

## Anti-goals

- Not a documentation generator for humans
- Not a replacement for the source repo (L0 remains authoritative)
- Not a single-format dogma — the schema mandates *which class*, the slot
  picks *which notation within that class*
