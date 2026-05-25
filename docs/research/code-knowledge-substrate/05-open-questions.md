# Open Questions — Code Knowledge Substrate

Primary steering mechanism. Each question is numbered, dated, and either
OPEN, RESOLVED (with pointer to journal entry), or DEFERRED (with reason).

---

## Q1 — How do we reliably codify code/logic behaviour without reproducing the code itself?

Status: OPEN
Raised: 2026-05-25 (pre-folder, in design discussion)
Carried as the central research question.

The §B Mechanism tier risks degenerating into "paste the function here."
We need a discipline that captures *what the mechanism does and why* at a
level of abstraction where a consumer agent can reason about it without
the source. Candidate approaches to evaluate: typed prose with named
invariants; pseudo-code at a fixed abstraction level; state-transition
descriptions; pre/post conditions; algebraic data-flow specifications;
property lists with worked examples.

Tracked against Track A (Class 1 survey).

---

## Q2 — What is the mandatoriness pattern for feature-node slots?

Status: OPEN
Raised: 2026-05-25

Per Entry 001 §5, the schema declares per-slot: (a) admissible class,
(b) admissible notations within that class, (c) whether mandatory at L1
or deferred to L2. We need a *pattern* for (c): is mandatoriness
per-feature-type (e.g., "all features must have §A; only stateful features
must have a state diagram")? Per-domain? Per-consumer (Architect needs X,
Reviewer needs Y)?

Resolution depends on Track A + Track B outputs and on at least one
worked example.

---

## Q3 — Which Class-1 notation per slot type?

Status: OPEN — Track A research mission
Raised: 2026-05-25

For each slot in the matrix (currently 3 at L1: §A, §B, §C), survey
existing notations and pick one (or a small set with explicit rules for
when to use which). Known candidates:
- §A Behaviour: Gherkin, EARS, plain Given/When/Then prose, scenario tables
- §B Mechanism: typed prose, Z, Hoare triples, pseudo-code at fixed level
- §C Configuration: JSON Schema, TOML-typed bullets, keyed YAML

Deliverable: a written shortlist per slot with selection rationale.

---

## Q4 — Class-2 catalogue and per-cell selection rules

Status: OPEN — Track B research mission
Raised: 2026-05-25

Enumerate textual relational notations admissible at L2. For each, declare
its fit across the §A/§B/§C tiers. Bootstrap list:
- Mermaid (stateDiagram, sequenceDiagram, flowchart, classDiagram, erDiagram)
- DOT / Graphviz
- PlantUML
- Structured YAML edge-lists
- Cypher-style relational triples

Deliverable: a catalogue table extending the v0.1 fit table in
`02-tier-layer-matrix.md`.

---

## Q5 — Class-3 (delta) notation — full specification deferred?

Status: DEFERRED
Reason: Class-3 only becomes pressing once we have at least one stable L1
corpus that has gone through a version change. Pre-corpus, picking a delta
notation is premature optimization. Revisit after Honcho backfill v1 exists.

---

## Q6 — How does this substrate interact with the AST symbol corpus?

Status: OPEN
Raised: 2026-05-25

Sibling research mission (`../ast-symbol-corpus/`) will produce a symbol
inventory and call-graph extraction. Question: does the symbol corpus
become an L0.5 layer (machine-extracted evidence sitting between raw L0
and human-curated L1), or does it become an L1 *contributor* (producing
node stubs that humans then enrich)? Or both? Likely "both" with a clear
contract, but the contract needs writing.

Depends on first AST mission output.

---

## Q7 — Promotion criteria from kate to mission-kit

Status: OPEN
Raised: 2026-05-25

Working assumption (carried from research protocol): methodology must be
proven via worked example before any of this moves to mission-kit. Worked
example = Honcho backfill under the new schema. But: what counts as
"proven"? Does the Architect agent need to pass a Q&A test? Does a second
human need to onboard via the substrate? Need acceptance criteria.

---

## Conventions for this file

- Add new questions at the bottom, numbered sequentially.
- Never renumber. If a question is split, the new ones get fresh numbers and
  the original is marked RESOLVED with pointers.
- Status transitions: OPEN → RESOLVED (pointer to journal) | DEFERRED (reason)
  | SUPERSEDED (pointer to replacement Q).
- Resolved questions stay in this file as record; do not move them out.
