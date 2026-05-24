# Feature: peer-representation

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Storage
**Triangulation:** ✓ Triangulated (claim + doc + source agree on existence and shape; one mismatch on internal vocabulary, see Behaviour notes)

## What it is (substrate's own terms)

A **peer representation** is the accumulated state Honcho builds about one peer from one observer's perspective. Concretely, it is the set of `Document` rows in a `Collection` keyed `(observer, observed)`. Each document stores one **observation** (Honcho's internal term) / **conclusion** (Honcho's public-API term) extracted from messages — with content, embedding, level (`explicit` / `deductive` / `inductive`), source `message_ids`, optional `premises`, and `message_created_at` timestamp.

Representations are the persistent memory artefact that all of Honcho's reasoning produces, and the substrate that the Dialectic agent searches at query time.

## Requirement

The system SHALL maintain, for every `(observer, observed)` peer pair within a workspace, a vector-indexed collection of observations derived from messages authored by the observed peer. Each observation is attributable to one or more source messages, carries a content payload and embedding, and is tagged with its reasoning level.

## Scenarios

### Scenario: deriver writes observations after message extraction
- GIVEN one or more messages from `peer_alice` have been processed by the minimal deriver
- AND the resulting `Representation` contains at least one non-empty observation
- WHEN `RepresentationManager.save_representation` is invoked for each observer in `observers`
- THEN one `Collection` row exists (or is created) per `(observer, peer_alice)` pair
- AND one `Document` row is created per observation in that collection
- AND each document has `level=explicit` (or `level=deductive` if from a `DeductiveObservation`)
- AND each document records its source `message_ids`, `session_name`, `embedding`, and `message_created_at` in metadata

### Scenario: single LLM call writes to multiple observer collections
- GIVEN a multi-peer session with observers `[peer_bob, peer_charlie]` and observed `peer_alice`
- WHEN the deriver processes a batch of `peer_alice`'s messages
- THEN exactly one LLM call extracts observations
- AND `save_representation` is invoked once per observer, writing the same observations to both `(peer_bob, peer_alice)` and `(peer_charlie, peer_alice)` collections
- AND embedding generation is performed once per observation (batched via `embedding_client.simple_batch_embed`), but documents are written per-collection

### Scenario: deduplication is configurable
- GIVEN `settings.DERIVER.DEDUPLICATE` is enabled
- WHEN documents are created via `crud.create_documents`
- THEN duplicate-detection logic is applied at write time (algorithm characterised in feature `consolidation`)
- OTHERWISE all observations are written unconditionally as new documents

### Scenario: empty representation does not write
- GIVEN the deriver returned a `Representation` with no explicit and no deductive observations
- WHEN `save_representation` is called
- THEN no documents are created, the call returns `0`, and a warning is logged

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/core-concepts/architecture.mdx` §Key Primitives — "peer representations" as the central memory artefact |
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` §How It Works — "reasoning outputs… are stored as part of peer representations, indexed in vector collections" |
| Claim | `CLAUDE.md` §Key Primitives — Collections keyed by `(observer, observed)` peer pairs |
| Doc | `docs/v3/documentation/core-concepts/representation.mdx` (to be deeper-read in dreamer/dialectic specs) |
| Source | `src/utils/representation.py:50-95` — `ExplicitObservationBase`, `DeductiveObservationBase`, `InductiveObservationBase`, `ObservationMetadata` schemas |
| Source | `src/crud/representation.py:46-58` — `RepresentationManager(workspace, observer, observed)` constructor |
| Source | `src/crud/representation.py:60-138` — `save_representation` batch-embed → per-collection write |
| Source | `src/crud/representation.py:144-198` — `_save_representation_internal` — collection get-or-create, document `level` field assignment |
| Source | `src/deriver/deriver.py:185-222` — `Representation.from_prompt_representation` → loop over `observers` invoking `save_representation` |
| Source | `src/crud/representation.py:198` — `deduplicate=settings.DERIVER.DEDUPLICATE` toggle |

## Behaviour notes (Tier 3 — prober analysis)

- **Vocabulary dual** [see `04-assessment.md` §A4]: the persistent artefact is called "conclusion" in the public `/conclusions` API and "observation" everywhere in code. They are the same thing. Searching code for "conclusion" yields almost nothing.
- **One LLM call → N collection writes.** For multi-peer sessions, the cost model is: one LLM call (constant) + N embedding batches (linear in observers) + N collection writes (linear). The LLM-call cost is amortised across observers.
- **Three observation `level` values exist in code** (`explicit`, `deductive`, `inductive`), but the minimal deriver only produces `explicit` (see feature `minimal-deriver`). `deductive` and `inductive` levels exist as schema slots filled by other code paths (presumably the dreamer — to be verified in feature `dreamer`).
- **Schema migration scar** [code: `src/utils/representation.py:18-49` `flatten_message_ids`]: `message_ids` was previously `list[tuple[int, int]]` (ranges), now `list[int]` (individual IDs). Backward-compat shim is present. Architectural maturity signal — Honcho is past v1 and has migrated production schemas.
- **Dream triggering is coupled to representation save** [code: `src/crud/representation.py:15` imports `check_and_schedule_dream`]: after a representation is saved, a dream cycle may be scheduled. The dreamer is not invoked on a pure timer — it is reactively triggered by representation writes. This is the seam between deriver and dreamer.
