# Design Journal — Code Knowledge Substrate

Append-only. Strike-through corrections, never delete. Each entry dated and
numbered. New entries at the bottom.

---

## Entry 001 — 2026-05-25 — Founding sharpening

Context: arrived here from the Honcho audit work after recognizing that the
feature-spec format debate (A vs B) was a symptom of a missing layer model
and a missing notation taxonomy. This entry captures the architectural
decisions made in the session that birthed this folder.

### 1. The 4-layer model (codified)

| Layer | Name | Content | Authored by |
|-------|------|---------|-------------|
| L0 | Source / Evidence | Raw repo: code, issues, PRs, ADRs, commit history, design docs *as authored by the substrate maintainers* | Humans (upstream) |
| L1 | Nanoprobe / Feature Corpus | Feature nodes — one per discrete capability — with §A/§B/§C-style tiered slots | Nanoprobe pass (agent + human) |
| L2 | Derivations / Relational | Graphs, cross-cuts, dependency maps, behavioural traces. Consumes L1, produces relational artefacts | Derivation pass (agent) |
| L3 | Consumer Agents | Architect, Reviewer, Onboarding-explainer, etc. Read L1+L2, never need to descend to L0 for normal work | Downstream agents |

**Layer 0 broadening (decided 2026-05-25):** L0 is not just source code. It
includes any substrate-authored evidence: issues, PRs, ADRs, RFCs, commit
messages, design docs. The discriminator is "authored by the substrate
maintainers as a primary artefact" — distinguishing it from L1+ which are
derived representations.

**Layer separation rule:** A consumer at layer N may freely read layers
0..N-1, but the schema only *requires* it to read layer N-1. The Architect
(L3) is required to be functional from L1+L2 alone; reading L0 is
permitted-but-not-required. This is what makes the substrate useful.

### 2. Notation classes (codified)

- **Class 1 — Slot-format notations.** Structured-text micro-syntaxes that
  fill a single slot in a feature node. Examples: Gherkin (Given/When/Then),
  EARS (Easy Approach to Requirements Syntax), Z schemas, plain typed
  bullets. *One notation per slot type*, not per feature.

- **Class 2 — Relational notations.** Textual, LLM-readable graph/diagram
  syntaxes. Examples: Mermaid, DOT/Graphviz, PlantUML, structured YAML
  edge-lists. **Decided 2026-05-25:** the source notation must be textual
  because the Architect consumes the syntax, not the rendered image.

- **Class 3 — Change/delta notations.** How a feature node evolves across
  versions. Unified diff is the obvious candidate; richer alternatives
  (semantic deltas, ADR-as-delta) deferred to later research.

### 3. Tier × Layer matrix (new sharpening — Entry 001's primary contribution)

The §A/§B/§C tiers from Format B map onto layers but are *not the same as*
layers. A feature node lives at L1, but its slots span tier-of-concern:

|         | §A Behaviour | §B Mechanism | §C Configuration |
|---------|--------------|--------------|------------------|
| **L1 (node-local)** | Class 1: Gherkin / EARS | Class 1: typed prose + invariants | Class 1: keyed schema |
| **L2 (relational)** | Class 2: sequence / state diagrams | Class 2: dataflow / module graph | Class 2: config-dependency graph |
| **L3 (consumer view)** | Question-answering on contracts | Question-answering on "how" | Question-answering on tuning |

**Implication:** each cell is governed by a different notation rule. The
feature-node schema doesn't pick *one* notation — it picks one *per cell*.

### 4. Class-2 dual citizenship (strong/weak fit)

Class-2 notations live at L2 *primarily*, but L1 nodes may embed Class-2
*fragments* when a single feature's mechanism is irreducibly relational
(e.g., a state machine that only makes sense as a diagram). The rule:

- **Strong fit for L1 embedding:** state machines (Mermaid `stateDiagram`),
  small sequence diagrams (≤6 participants), tight call graphs of a single
  function's dispatch.
- **Weak fit for L1 embedding (push to L2):** cross-module dependency
  graphs, full system architecture diagrams, anything requiring more than
  one feature node's worth of context to interpret.
- **Rendering responsibility:** L1 nodes *embed source notation*; they do
  not own rendering. Rendering (to SVG/PNG for human consumption) is a
  publishing concern, not a substrate concern.

### 5. Schema-validates-which-notation-per-slot-type

Direct consequence of (3) + (4): the feature-node schema is not a flat
"these slots exist" definition. It is a *typed* schema where each slot
declares (a) which Class it accepts, (b) which specific notations within
that class are admissible, and (c) whether the slot is mandatory at L1 or
deferred to L2.

This is the primary research deliverable.

### 6. Research priority (revised)

Previous priority (pre-sharpening): Class 1 survey → Class 2 catalogue →
schema draft → Honcho backfill.

**Revised priority:** Class 1 survey and Class 2 catalogue proceed in
parallel as Tracks A and B, *because the schema cannot be drafted until
both are mapped*. Schema draft is gated on both tracks delivering at least
a "good enough to pick from" shortlist. Honcho backfill is the
proof-of-methodology, not a parallel workstream.

### 7. AST-symbol-corpus split

The AST extraction work is its own research mission with its own folder
(`../ast-symbol-corpus/`). It is a *contributor* to L0→L1 automation but is
not a prerequisite for this substrate's design. The two missions cross-pollinate
but do not block each other.

### 8. Codification target

This 4-layer + 3-class model is currently codified *only here*. It is not
yet in any skill or mission-kit document. **Promotion gate:** the model
moves to mission-kit only after the Honcho backfill worked example proves
it survives contact with real specs.

— end Entry 001 —
