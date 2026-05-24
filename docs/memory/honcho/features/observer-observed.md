# Feature: observer-observed-collections

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Storage
**Triangulation:** ✓ Triangulated (claim + source agree on the keying model and its multi-peer semantics)

## What it is (substrate's own terms)

All observations are stored in `Collection` rows keyed by a **pair of peer identities** within a workspace: `(observer, observed)`. A collection represents *"what `observer` knows/believes about `observed`"*. In single-peer sessions, observer and observed are the same peer (self-observation). In multi-peer sessions, each peer's view of another peer is a distinct collection — encoding theory-of-mind at the storage layer rather than as a query-time abstraction.

## Requirement

The system SHALL store derived observations in collections uniquely identified by `(workspace, observer, observed)`. When the deriver processes messages from an observed peer in a session with N observers, it SHALL write the same observations to N separate collections — one per `(observer_i, observed)` pair. Collection creation SHALL be idempotent (get-or-create), and concurrent creation SHALL be safe (`IntegrityError` retry).

## Scenarios

### Scenario: single-peer session creates a self-observation collection
- GIVEN a session containing only `peer_alice`
- WHEN `peer_alice` sends a message that the deriver processes
- THEN a collection keyed `(observer=peer_alice, observed=peer_alice)` is created (or fetched if existing)
- AND observations about alice from alice's own messages are written to this collection
- AND no other collections are created from this batch

### Scenario: multi-peer session creates one collection per observer
- GIVEN a session containing `peer_alice`, `peer_bob`, and `peer_charlie`
- WHEN `peer_alice` sends a message
- THEN the deriver enqueues with `observers=[peer_alice, peer_bob, peer_charlie]` and `observed=peer_alice` (and may also enqueue for additional observer/observed permutations per session config)
- AND when processed: three collections exist — `(alice, alice)`, `(bob, alice)`, `(charlie, alice)` — each containing the same observation set from this batch
- AND embeddings are computed ONCE (one batch call) and written N times (one per collection)

### Scenario: concurrent collection creation is safe
- GIVEN two concurrent derivers processing batches for the same `(observer, observed)` pair
- AND neither finds an existing collection on first read
- WHEN both attempt to create the collection
- THEN one succeeds, the other catches the `IntegrityError`, retries the read, and proceeds with the now-existing collection

### Scenario: collections are workspace-scoped
- GIVEN `peer_alice` exists in `workspace_X` AND `workspace_Y`
- WHEN observations are derived in each workspace
- THEN `(workspace=X, observer=alice, observed=alice)` and `(workspace=Y, observer=alice, observed=alice)` are independent collections
- AND no data crosses the workspace boundary

## Evidence

| Type | Reference |
|---|---|
| Claim | `CLAUDE.md` §Key Primitives — "Collections are keyed by `(observer, observed)` peer pairs" |
| Claim | `CLAUDE.md` §Memory Architecture — "Collections / Documents — vector storage; collections keyed by `(observer, observed)` for theory-of-mind" |
| Doc | `docs/v3/documentation/core-concepts/architecture.mdx` §Core Concepts — peer-centric design making peers the durable reasoning anchor |
| Source | `src/crud/representation.py:46-58` — `RepresentationManager(workspace_name, *, observer: str, observed: str)` — the type signature itself encodes the pair-key |
| Source | `src/crud/representation.py:151-156` — `crud.get_or_create_collection(db, workspace_name, observer=self.observer, observed=self.observed)` — collection identity is the triple `(workspace, observer, observed)` |
| Source | `src/crud/representation.py:152` (comment) — "`get_or_create_collection` already handles `IntegrityError` with rollback and a retry" |
| Source | `src/deriver/deriver.py:200-222` — per-observer save loop: ONE derived `Representation` is saved to EACH observer's collection |
| Source | `src/deriver/deriver.py:41-42` — `process_representation_tasks_batch(..., observers: list[str], observed: str, ...)` — signature carries the list of observers explicitly |
| Source | `src/models.py` — `Collection` SQLAlchemy model (to verify constraint declaration in dedicated read) |

## Behaviour notes (Tier 3 — prober analysis)

- **Theory-of-mind at the storage layer is structurally unusual.** Most agent-memory systems we've surveyed (per the earlier substrate-landscape doc) keep one memory store per agent/user, with multi-peer reasoning bolted on at query time. Honcho makes the perspectival pair the storage primitive itself. **Implication:** if our system uses Honcho and ever needs to represent "what does Alice know about Bob, separately from what Bob knows about himself", the substrate gives this for free. Conversely, if we never need this distinction, we pay storage overhead for an unused dimension.
- **N-observer write amplification is real but bounded.** One LLM call → one embedding batch → N document-write batches. For a 3-peer session, that's 3x storage for the same observations. For a 10-peer session, 10x. Storage cost scales linearly with observer count for the same conversation. **Operational implication:** sessions with many peers (e.g. group chats, multi-agent simulations) inflate storage; consider session size in deployment sizing.
- **Get-or-create handles a real race.** The `IntegrityError`-retry comment indicates this isn't theoretical — concurrent derivers DO race for collection creation. The pattern is correct, but it implies multiple workers can be active on the same observed peer simultaneously (consistent with the worker-lease model in queue_manager). To-verify: does the lease model serialise per `(observer, observed)` pair, or only per work-unit? Affects whether the race is common or rare.
- **Workspace scoping is the multi-tenancy boundary.** Combined with workspace-scoped JWT keys (feature `scoped-jwt-keys` — TBD), `(workspace, observer, observed)` is the unit of access control. No tenant can read another tenant's `(observer, observed)` collection.
- **Self-observation collections may dominate single-user data.** For an agent system with one human user + one assistant peer, both peers observe both peers in many sessions → 4 collections per session-peer-set. Realistic deployments may want to disable per-peer-pair enqueueing for unused permutations (e.g. assistant-about-assistant) via session/peer config.
- **This is the structural feature that justifies "peer-centric".** When the docs say peer-centric design, this is what they mean operationally: not just that peers are named entities, but that perspectival pairs of peers are the storage key.
