# Document query strategies

## §A Tier 1 — Claim

§A1 `src/crud/document.py` provides four distinct document-query strategies, each tuned for a different retrieval pattern: `query_documents` (semantic), `query_documents_recent` (chronological), `query_documents_most_derived` (provenance-weighted), and `get_documents_with_filters` (key-only).

§A2 `query_documents(query, observer, observed, ...)` performs semantic-similarity retrieval. Dispatches by backend: when `_uses_pgvector()` is True, runs `_query_documents_pgvector` (pure DB); otherwise queries the external vector store for document IDs and fetches the row data from Postgres separately.

§A3 Embedding-input optimisation: `query_documents` accepts an optional pre-computed `embedding` parameter. When provided, skips the `embedding_client.embed(query)` call. Reduces cost when the caller already has an embedding (e.g., reusing one from the same dialectic iteration).

§A4 Token-limit failure mode: `embedding_client.embed(query)` raises `ValueError` when the query exceeds `EMBEDDING.MAX_INPUT_TOKENS`; the strategy re-raises as `ValidationException` with a user-facing message. Failure is loud, not silent.

§A5 Two-phase external-vector retrieval (§A2 second path): (1) `query_external_vector_document_ids(...)` returns ranked IDs from the external store; (2) `fetch_documents_by_ids(...)` materializes the rows from Postgres. The split exists so the **external call holds no DB connection** and the **DB call holds no vector-store connection**.

§A6 DB-session lifecycle: every strategy accepts `db: AsyncSession | None`. When `db is None`, the function opens a short-lived `tracked_db(...)` session for the duration of its own DB work and closes it before returning. Caller-owned sessions are honoured when provided.

§A7 Session expunging: caller-owned-session results are returned attached; function-managed-session results are `expunge`d before the session closes (`for doc in docs: managed_db.expunge(doc)`) so the SQLAlchemy objects remain usable after the session is gone.

§A8 `query_documents_recent(workspace, observer, observed, top_k, filters)` returns the most-recent N documents (matching the perspectival pair + filters) ordered by `created_at DESC`. No semantic ranking. Used by dreamer specialists for "what did I see lately" context.

§A9 `query_documents_most_derived(workspace, observer, observed, top_k, filters)` returns documents ranked by the count of higher-order observations referencing them via `source_ids` — the documents that have produced the most derivation. Used to surface load-bearing premises to specialists. Provenance-weighted retrieval.

§A10 `get_documents_with_filters(...)` and `get_all_documents(...)` are key-only retrieval paths for administrative / debugging / migration use — no semantic ranking, no provenance weighting. Returns matching rows in DB order.

§A11 `query_documents` accepts `max_distance: float | None` (cosine distance cutoff) and `top_k: int = 5` defaults. `filters: dict[str, Any] | None` supports `level` and `session_name` at the vector-store level (push-down).

## §B Tier 2 — Source

§B1 `src/crud/document.py:316-422` — `query_documents` (the dispatcher, §A2-§A7).

§B2 `src/crud/document.py:282-315` — `_query_documents_pgvector` (pgvector path).

§B3 `src/crud/document.py:204-253` — `query_external_vector_document_ids` (external-store phase 1, §A5).

§B4 `src/crud/document.py:254-281` — `fetch_documents_by_ids` (external-store phase 2, §A5).

§B5 `src/crud/document.py:121-159` — `query_documents_recent` (§A8).

§B6 `src/crud/document.py:160-196` — `query_documents_most_derived` (§A9).

§B7 `src/crud/document.py:35-82` — `get_all_documents` (§A10).

§B8 `src/crud/document.py:83-120` — `get_documents_with_filters` (§A10).

§B9 `src/crud/document.py:197-203` — `_uses_pgvector` (backend dispatch, §A2).

§B10 `src/crud/document.py:349-357` — embedding-or-embed branch (§A3, §A4).

§B11 `src/crud/document.py:383-385,419-421` — session expunge pattern (§A7).

§B12 `src/crud/document.py:1117-1143` — `get_documents_by_ids` (companion path used by tool ABI).

§B13 `src/crud/document.py:1144-1180` — `get_child_observations` (provenance traversal companion to §A9).

§B14 `src/config.py:1213-1257` — `VectorStoreSettings` (backend selection that drives §A2 dispatch).

## §C Tier 3 — Analytical

§C1 **Three semantically-distinct retrieval shapes, one perspectival keying invariant.** Every strategy takes `observer + observed` as required positional arguments — there is no "query across all peers" surface at this layer. The perspectival commitment (`features/observer-observed.md` A14) is enforced at the retrieval API, not just at write time.

§C2 **Two-phase external-vector retrieval (§A5) is a deliberate connection-pool decoupling.** The pattern "vector call without DB; DB call without vector" appears across the substrate (dreamer specialists §A6, dialectic A24) — query_documents is the same pattern at the CRUD layer. Combined: a single semantic query consumes 1 vector-store request + 1 short DB query, with neither holding the other's resource.

§C3 **pgvector vs external-store paths produce different latency profiles for the same caller.** pgvector path: one DB query with `ORDER BY embedding <=> %s LIMIT k` (single round trip). External-store path: one vector-store query + one DB `WHERE id IN (...)` fetch (two round trips, one external). Operators tuning latency must understand: switching `VECTOR_STORE.TYPE` from `lancedb`/`turbopuffer` to `pgvector` reduces round-trip count and removes the external dependency but couples vector-search performance to Postgres tuning.

§C4 **`query_documents_most_derived` (§A9) is a substrate-native answer to "what observations matter".** Most semantic-retrieval systems answer "what's most similar"; this strategy answers "what's most-built-upon". The provenance graph (`source_ids` chain from `features/explicit-deductive.md`) is the input. Operationally this is what lets a specialist ask "what are the load-bearing premises for this peer" rather than "what's similar to this string" — a structurally different question.

§C5 **The `db: AsyncSession | None` convention (§A6) makes every strategy callable both inside and outside a transaction.** Callers that need to atomically combine query + create can pass their own session; callers that just want a one-shot read can pass None and let the function manage. The cost is per-function defensive lifecycle code; the benefit is no caller is forced to think about transaction scope unless it matters.

§C6 **Embedding-input optimisation (§A3) is a small but consequential lever.** A dialectic agent that calls `search_memory("foo", ...)` then immediately `query_documents("foo", ...)` would otherwise generate the same embedding twice. Threading the embedding through cuts the embedding cost in half for these patterns. Not all callers exploit this; tool-abi layer (`features/dialectic-tool-abi.md`) does not currently pass embeddings through but could.

§C7 **`get_documents_with_filters` and `get_all_documents` (§A10) are admin-shape surfaces, not agent-shape.** They have no perspectival argument requirement at the same strictness level (filters supply the scope). An operator running migrations or audits uses these; the agent layer would not. Mixing them at the agent layer would bypass the perspectival invariant of §C1.
