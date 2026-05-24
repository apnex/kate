# Feature: peer-card

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Storage
**Triangulation:** ✓ Triangulated

## What it is

A peer card is a small, structured list of biographical strings describing an observed peer from an observer's perspective. Storage is **not** a dedicated table but a JSONB key inside the *observer* Peer row's `internal_metadata` column. The key is `"peer_card"` for self-observation (observer == observed) or `"{observed}_peer_card"` for cross-observation. Peer cards are loaded upfront by the dialectic agent (when `configuration.peer_card.use=true`) and injected into the system prompt; they can be updated mid-query by the dialectic agent's `update_peer_card` tool (`features/search-tools.md`).

## Requirement

The system SHALL persist, per `(observer, observed)` peer pair, a list of biographical strings as a JSONB key inside the observer Peer row's `internal_metadata`, SHALL provide read and write functions keyed by the perspectival pair, and SHALL invalidate the relevant cache key on every write.

## Scenarios

### Scenario: self-peer-card storage uses unprefixed key
- GIVEN observer == observed == `alice`
- WHEN `set_peer_card` is called with a peer card list
- THEN the value is stored at key `"peer_card"` inside `alice`'s Peer `internal_metadata`

### Scenario: cross-peer-card storage uses observed-prefixed key
- GIVEN observer = `alice`, observed = `bob`
- WHEN `set_peer_card` is called
- THEN the value is stored at key `"bob_peer_card"` inside `alice`'s Peer `internal_metadata`
- AND `bob`'s Peer row is not modified

### Scenario: read returns None when no card exists
- GIVEN no peer card has been set for `(alice, bob)`
- WHEN `get_peer_card(observer=alice, observed=bob)` is invoked
- THEN `None` is returned

### Scenario: read returns the stored list
- GIVEN a peer card has been set for `(alice, bob)`
- WHEN `get_peer_card(observer=alice, observed=bob)` is invoked
- THEN the stored list of strings is returned

### Scenario: missing observer peer raises ResourceNotFoundException
- GIVEN observer `nonexistent` does not exist in the workspace
- WHEN `set_peer_card` is invoked targeting that observer
- THEN `ResourceNotFoundException` is raised

### Scenario: cache invalidation on write
- GIVEN the observer's Peer row is cached
- WHEN `set_peer_card` succeeds
- THEN the peer cache key is deleted via `safe_cache_delete`

### Scenario: peer-card upsert via JSONB concat operator
- GIVEN an existing `internal_metadata` JSONB blob on the observer Peer row
- WHEN `set_peer_card` writes a new card
- THEN the existing metadata is preserved and only the relevant key is updated
- AND the SQL uses the Postgres `||` (JSONB concatenation) operator

## Evidence

| Type | Reference |
|---|---|
| Claim | `CLAUDE.md` §Peer Cards — biographical summaries per peer |
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` — peer cards as agent-readable context |
| Doc | `src/crud/peer_card.py:24-39` — `get_peer_card` docstring |
| Doc | `src/crud/peer_card.py:58-69` — `set_peer_card` docstring |
| Source | `src/crud/peer_card.py:17-47` — `get_peer_card` implementation, reads from `peer.internal_metadata` |
| Source | `src/crud/peer_card.py:50-100` — `set_peer_card` implementation with JSONB `||` upsert |
| Source | `src/crud/peer_card.py:103-106` — `construct_peer_card_label` keying rule (`"peer_card"` vs `"{observed}_peer_card"`) |
| Source | `src/crud/peer_card.py:91-94` — `ResourceNotFoundException` raised when observer Peer row not updated |
| Source | `src/crud/peer_card.py:98-100` — cache invalidation via `safe_cache_delete(peer_cache_key(...))` |
| Source | `src/dialectic/chat.py:56-65` — peer cards loaded upfront during dialectic preflight |
| Source | `src/utils/agent_tools.py:1442-1604` — `_handle_update_peer_card` write path |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Peer cards live on the observer, not the observed.** A peer card about Bob held by Alice lives in Alice's row (`alice.internal_metadata.bob_peer_card`). Implication: deleting Bob does not delete what Alice knew about Bob. Implication: querying "all peer cards about Bob" requires scanning every observer's metadata.
- **JSONB concatenation preserves unrelated metadata.** Uses Postgres `||` operator (line 81-87) so existing `internal_metadata` keys are untouched. Safe to evolve metadata schema.
- **No separate peer_cards table is a simplicity decision.** Operational consequence: peer card lookups don't add a join; updates touch only one row. Limitation: no native indexing of peer card content (must scan JSONB).
- **Dialectic loads peer cards at preflight, not via tool.** The agent receives observer + observed peer cards at construction time (`chat.py:56-65`); it cannot fetch fresh cards mid-loop. The `update_peer_card` tool writes but does not refresh the agent's in-memory view.
- **Cache invalidation only deletes the observer cache key.** If multiple observers have cards about the same observed peer, updating one observer's card does not invalidate other observers' caches (correct — they don't reference this card).
- **The keying scheme is asymmetric** (`"peer_card"` vs `"{observed}_peer_card"`). Slightly unusual but pragmatic — the self-case avoids the prefix.

## Configuration surface

| Knob | Default | Source |
|---|---|---|
| `peer_card.use` | true when card exists | `src/utils/config_helpers.py` |
