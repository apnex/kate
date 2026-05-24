# Feature: observer-observed-collections

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Storage
**Triangulation:** ✓ Triangulated

## What it is

Honcho's storage model represents memory not as per-peer namespaces but as per-perspectival-pair collections. Each Collection is keyed by the triple `(workspace, observer, observed)` — encoding "what `observer` knows/believes about `observed`". In single-peer sessions, observer == observed (self-observation). In multi-peer sessions, each observer has a distinct collection for each peer they observe, including themselves. This is theory-of-mind at the storage layer rather than at the application layer.

## Requirement

The system SHALL identify Collections by the triple `(workspace, observer_peer, observed_peer)`, SHALL support arbitrary observer/observed pairs including self-observation, and SHALL ensure observations written via one LLM call are persisted to every relevant observer collection.

## Scenarios

### Scenario: self-observation for a single-peer session
- GIVEN a session with one peer `alice`
- WHEN messages from `alice` are processed by the deriver
- THEN a Collection identified by `(workspace, alice, alice)` is created/updated
- AND no other observer-observed pair collections are created

### Scenario: theory-of-mind collections for a two-peer session
- GIVEN a session with peers `alice` and `bob`
- WHEN messages from `alice` are processed by the deriver
- THEN one LLM call extracts observations about `alice`
- AND those observations are written to BOTH `(workspace, alice, alice)` AND `(workspace, bob, alice)`

### Scenario: collection separation across observers
- GIVEN populated collections `(workspace, alice, charlie)` and `(workspace, bob, charlie)`
- WHEN a caller queries `RepresentationManager(observer=alice, observed=charlie).get_representation()`
- THEN only documents from `(workspace, alice, charlie)` are returned
- AND documents from `(workspace, bob, charlie)` are not mixed in

### Scenario: workspace isolation
- GIVEN two workspaces `w1` and `w2` each with a peer `alice`
- WHEN observations are written for alice in `w1`
- THEN the Collection `(w1, alice, alice)` is populated
- AND the Collection `(w2, alice, alice)` is unaffected

## Evidence

| Type | Reference |
|---|---|
| Claim | `CLAUDE.md` §Key Primitives — "Collections are keyed by (observer, observed) peer pairs" |
| Claim | `CLAUDE.md` §Agent Architecture — describes theory-of-mind reasoning as supported via the perspectival-pair model |
| Doc | `docs/v3/documentation/core-concepts/architecture.mdx` §Memory & Representations |
| Source | `src/crud/representation.py:46-58` — `RepresentationManager(observer: Peer, observed: Peer)` constructor |
| Source | `src/crud/representation.py:120-156` — `save_representation` writes to collection identified by `(workspace, observer, observed)` |
| Source | `src/deriver/deriver.py:200-222` — per-observer save loop iterating session peers as observers, with shared `observed` peer |
| Source | `src/models.py` — Collection model with workspace/observer/observed identification fields |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Compute is amortised; storage is not.** One LLM call produces one set of observations; those observations are written to N collections (one per observer). Embedding cost is also amortised (shared batch). Vector-store size scales with observer count per session.
- **Self-observation is the default case** (single-peer sessions). Theory-of-mind only activates when sessions have multiple peers — many deployments will never exercise the multi-observer path.
- **Theory-of-mind is structural rather than emergent.** Other approaches handle perspectival reasoning at query time over a single namespace; Honcho commits to it at the schema level. See `04-assessment.md §A14` for the cross-cutting architectural argument.
- **Operational implication of write amplification** for multi-peer / agent-swarm use cases — see `04-assessment.md §A13`.
