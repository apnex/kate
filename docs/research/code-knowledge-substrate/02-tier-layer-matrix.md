# Tier × Layer Matrix — Living Doc

Status: LIVING (updated as research progresses; supersedes Entry 001 §3 once changes accrete)
First seeded: 2026-05-25 from design journal Entry 001
Owner: this folder

This document holds the authoritative current state of the tier × layer
matrix. The design journal records *why* it changed; this document records
*what it currently is*.

## Current matrix (v0.1)

|         | §A Behaviour | §B Mechanism | §C Configuration |
|---------|--------------|--------------|------------------|
| **L1 (node-local)** | Class 1: Gherkin / EARS | Class 1: typed prose + invariants | Class 1: keyed schema |
| **L2 (relational)** | Class 2: sequence / state diagrams | Class 2: dataflow / module graph | Class 2: config-dependency graph |
| **L3 (consumer view)** | Question-answering on contracts | Question-answering on "how" | Question-answering on tuning |

## Open cells (not yet resolved)

- **L1 §B Mechanism (Class 1 choice):** "typed prose + invariants" is a
  placeholder. Needs survey: is there an existing notation that does this
  well? Z schemas? Hoare triples? Plain structured English with a
  controlled vocabulary? Tracked in Q1.
- **L1 §C Configuration (Class 1 choice):** "keyed schema" likely resolves
  to JSON Schema fragments or TOML-style typed bullets. Needs Track A
  decision.
- **L2 §A Behaviour (Class 2 choice):** sequence vs state diagram is
  per-feature, not a global pick. Need a rule for "when to use which."

## Class-2 fit table (L1 embedding rules)

| Class-2 form | Strong fit at L1? | Pushes to L2 when... |
|--------------|-------------------|----------------------|
| Mermaid `stateDiagram` | YES (state machines local to one feature) | The state space spans multiple features |
| Mermaid `sequenceDiagram` | YES if ≤6 participants | Participants exceed 6 or cross module boundaries |
| Mermaid `flowchart` | MAYBE — only for single-function dispatch | Anything spanning files |
| DOT call graph | NO — almost always L2 | Always |
| PlantUML class diagram | NO — L2 only | Always (cross-class by nature) |
| YAML edge-list | YES for "this feature's dependencies" stub | Full dependency graph |

## Change log

- 2026-05-25 — seeded from Entry 001
