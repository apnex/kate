# Feature: peer-representation

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Storage
**Triangulation:** ✓ Triangulated

## What it is

A peer-representation is the persistent memory artefact about an observed peer, scoped to one observer's view. Identified by the pair `(observer_peer, observed_peer)`. Realised in storage as a Vector Collection keyed by `(workspace, observer, observed)` containing a stream of Document objects. Each Document carries an `Observation` payload (explicit / deductive / inductive) plus metadata. Same primitive supports self-observation (observer == observed) and theory-of-mind (observer != observed) by varying the pair.

## Requirement

The system SHALL persist, per `(observer, observed)` peer pair, a Collection of Document objects whose content is observations about the observed peer, derived from messages, and SHALL return that Collection on demand for downstream retrieval.

## Scenarios

### Scenario: writing self-observations for a single-peer session
- GIVEN a session with one peer `alice` and a new message authored by `alice`
- WHEN the deriver processes that message
- THEN one Collection identified by `(workspace, alice, alice)` exists
- AND it contains documents whose `metadata` references the source message

### Scenario: writing theory-of-mind observations for a multi-peer session
- GIVEN a session with peers `alice` and `bob`, and a message from `alice`
- WHEN the deriver processes that message
- THEN a Collection `(workspace, alice, alice)` is populated with self-observations
- AND a Collection `(workspace, bob, alice)` is populated with bob's-view-of-alice observations
- AND the LLM call that produced both is a single shared call

### Scenario: reading a representation
- GIVEN any `(observer, observed)` pair with existing observations
- WHEN a caller invokes `RepresentationManager.get_representation` or `RepresentationManager.get_working_representation`
- THEN a `Representation` object is returned containing the observations
- AND the working representation is capped at `WORKING_REPRESENTATION_MAX_OBSERVATIONS` (default 100)

### Scenario: schema migration backward-compat for message references
- GIVEN observations persisted under the old `message_ids: list[tuple[int, int]]` shape
- WHEN read at this SHA
- THEN `flatten_message_ids` transparently returns `list[int]` regardless of stored shape

## Evidence

| Type | Reference |
|---|---|
| Claim | `CLAUDE.md` §Key Primitives — "Collections are keyed by (observer, observed) peer pairs and contain Documents" |
| Doc | `docs/v3/documentation/core-concepts/architecture.mdx` §Memory & Representations |
| Source | `src/utils/representation.py:18-49` `flatten_message_ids` with backward-compat for old `list[tuple]` shape |
| Source | `src/utils/representation.py:59-128` observation-class hierarchy (Explicit/Deductive/Inductive bases + concrete variants) |
| Source | `src/crud/representation.py:46-58` `RepresentationManager(observer, observed)` constructor |
| Source | `src/crud/representation.py:120-156` `save_representation` — writes to collection identified by `(workspace, observer, observed)` |
| Source | `src/crud/representation.py:198` `deduplicate=settings.DERIVER.DEDUPLICATE` flag passed to `crud.create_documents` |
| Source | `src/config.py:760` `DEDUPLICATE: bool = True` (default on) |
| Source | `src/config.py` `WORKING_REPRESENTATION_MAX_OBSERVATIONS: 100` (default) |

## Behaviour notes (Tier 3 — scoped to this feature)

- **The `(observer, observed)` triple is the substrate's perspectival keying invariant — enforced at storage, retrieval, AND write paths.** Every read API (`features/document-query-strategies.md`), every write API (`features/dialectic-tool-abi.md`), every reconcile API (`features/reconciler.md`), and every collection lookup go through this same key shape. There is no "look across observers" surface anywhere in the substrate — that constraint is structural, not conventional.
- Collection identity is the triple `(workspace, observer, observed)` — observer first, observed second. In code, `observer` is the entity *holding* the representation; `observed` is the entity *being represented*.
- Three observation schemas exist (explicit / deductive / inductive). At this SHA, only explicit observations are produced by the production deriver — see `features/minimal-deriver.md` Behaviour notes.
- The working representation has a hard cap (default 100 observations); retrieval beyond that requires the full representation API path.
- Deduplication is on by default at write time; the algorithm is specced in `features/consolidation.md`.
- Schema-migration backward-compat present for `message_ids` shape — indicates non-trivial production migrations have occurred (see `04-assessment.md §A15`).
- Storage cost is linear in observer count per session; see `04-assessment.md §A13` for the cross-cutting implication.

## Configuration surface

| Knob | Default | Source |
|---|---|---|
| `DERIVER.DEDUPLICATE` | `True` | `src/config.py:760` |
| `DERIVER.WORKING_REPRESENTATION_MAX_OBSERVATIONS` | `100` | `src/config.py` |
