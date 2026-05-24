# Feature: pluggable-vector-backend

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Storage
**Triangulation:** ✓ Triangulated

## What it is

The vector store abstraction is a genuine plug point: an abstract base class (`VectorStore`) defines a contract (`upsert_many`, `query`, namespace helpers, etc.); two concrete implementations exist (`LanceDBVectorStore` ≈ 405 LOC, `TurbopufferVectorStore` ≈ 367 LOC) implementing the contract; namespace generation is centralised in the base class to enforce the strictest backend's constraints (Turbopuffer's `[A-Za-z0-9-_.]{1,128}`). The namespace strategy distinguishes **document embeddings** (perspectival: `{prefix}.doc.{hash(workspace, observer, observed)}`) from **message embeddings** (workspace-global: `{prefix}.msg.{hash(workspace)}`). Selection of which backend runs is configuration-driven via `settings.VECTOR_STORE`.

## Requirement

The system SHALL define a `VectorStore` abstract base class with namespace-scoped upsert and query operations, SHALL provide multiple concrete implementations selectable by configuration, and SHALL generate namespaces deterministically from workspace/peer identifiers via cryptographic hashing.

## Scenarios

### Scenario: document embeddings are scoped to observer-observed pair
- GIVEN an observation about observed `bob` from observer `alice` in workspace `w1`
- WHEN the embedding is persisted
- THEN the namespace `{prefix}.doc.{base64(sha256("w1.alice.bob"))}` is used
- AND a different `(observer, observed)` pair yields a different namespace

### Scenario: message embeddings are scoped per workspace only
- GIVEN a message in workspace `w1` from any peer
- WHEN the message embedding is persisted
- THEN the namespace `{prefix}.msg.{base64(sha256("w1"))}` is used
- AND all messages in `w1` share the same namespace regardless of peer

### Scenario: namespace constraints enforce the strictest backend
- GIVEN any combination of workspace/peer names
- WHEN the namespace is computed
- THEN the result matches `[A-Za-z0-9-_.]{1,128}` (Turbopuffer-compatible)
- AND the hash component is 43 characters (base64url-encoded SHA-256 without padding)

### Scenario: backend selection is configuration-driven
- GIVEN `settings.VECTOR_STORE` selects a specific backend (e.g. `"lancedb"` or `"turbopuffer"`)
- WHEN the vector store is instantiated
- THEN the corresponding concrete subclass is constructed
- AND its `upsert_many` and `query` implementations are used

### Scenario: contract operations are namespace-scoped
- GIVEN a populated namespace
- WHEN `query` is called with a different namespace
- THEN no results from the populated namespace are returned

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/reference/storage.mdx` — describes pluggable vector store |
| Doc | `src/vector_store/__init__.py:53-65` docstring — "Abstract base class for vector store implementations. All vector operations are namespace-scoped." |
| Source | `src/vector_store/__init__.py:16-30` — `_hash_namespace_components` SHA-256 + base64url namespace generator |
| Source | `src/vector_store/__init__.py:33-50` — `VectorRecord` and `VectorQueryResult` pydantic contracts |
| Source | `src/vector_store/__init__.py:53-126` — `VectorStore` ABC with `upsert_many` (abstract), `query` (abstract), `get_vector_namespace` (concrete) |
| Source | `src/vector_store/__init__.py:76-107` — namespace dispatch on `document` vs `message` type |
| Source | `src/vector_store/__init__.py:98-104` — document namespaces require `observer` and `observed` |
| Source | `src/vector_store/__init__.py:105-107` — message namespaces require only `workspace_name` |
| Source | `src/vector_store/lancedb.py` (405 LOC) — LanceDB implementation |
| Source | `src/vector_store/turbopuffer.py` (367 LOC) — Turbopuffer implementation |
| Source | `src/vector_store/__init__.py:20` — comment "Turbopuffer requires namespaces to match [A-Za-z0-9-_.]{1,128}" |

## Behaviour notes (Tier 3 — scoped to this feature)

- **The abstraction is shaped by the strictest backend.** Turbopuffer's namespace constraint (`[A-Za-z0-9-_.]{1,128}`) is enforced for both backends — even though LanceDB likely accepts arbitrary strings, the abstraction commits to the hashed namespace strategy uniformly. This is the right architectural call (no LanceDB-only namespace formats leak into application code) but it means the base class has knowledge of one specific backend's limits.
- **Document/message namespace asymmetry is significant.** Document (observation) embeddings are perspectival per `(observer, observed)`; message embeddings are workspace-global. **Message-level semantic retrieval crosses peer boundaries within a workspace**, while observation-level retrieval respects them. See `04-assessment.md §A22` for the cross-cutting implication for theory-of-mind semantics in retrieval.
- **Two implementations is enough to validate the abstraction is real, not theoretical.** Both backends have non-trivial line counts (LanceDB 405, Turbopuffer 367); the surface is broad enough that a half-baked abstraction would have shown its seams by now.
- **No in-process / Postgres-pgvector backend present at this SHA.** LanceDB (embedded) and Turbopuffer (managed cloud) are the only options. Adding a Postgres-pgvector backend would be the third implementation — well-defined by the existing ABC.

## Configuration surface

| Knob | Default | Source |
|---|---|---|
| `VECTOR_STORE.NAMESPACE` (prefix) | configurable | `src/config.py` |
| `VECTOR_STORE.PROVIDER` (backend selection) | configurable | `src/config.py` |
| `VECTOR_STORE.*` (provider-specific) | varies | `src/config.py` |
