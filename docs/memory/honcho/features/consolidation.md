# Feature: consolidation

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Storage
**Triangulation:** ✓ Triangulated

## What it is

When `DERIVER.DEDUPLICATE=true` (default), every new observation passes through `is_rejected_duplicate` before persistence. The function uses two-stage logic: (1) find the nearest existing observation by cosine similarity within the same `(observer, observed)` collection, gated at distance ≤ 0.05 (similarity ≥ 0.95); (2) if a near-duplicate exists, choose the winner by token-set-difference score weighted toward unique information, with ties broken in favour of the new document. The loser is soft-deleted (`deleted_at` set); the reconciler later removes its vectors and hard-deletes the row.

## Requirement

The system SHALL, when deduplication is enabled, compare every incoming observation against existing observations in the same `(observer, observed)` collection by cosine similarity, retain whichever document carries more unique information, soft-delete the loser, and let the reconciler complete physical cleanup.

## Scenarios

### Scenario: deduplication disabled bypasses the check
- GIVEN `DERIVER.DEDUPLICATE = false`
- WHEN a new observation is persisted
- THEN `is_rejected_duplicate` is not called
- AND the observation is unconditionally inserted

### Scenario: no near-duplicate exists, new observation is accepted
- GIVEN deduplication is enabled
- AND no existing observation has cosine distance ≤ 0.05 to the new content
- WHEN the new observation is persisted
- THEN the observation is inserted
- AND no existing observation is modified

### Scenario: new observation has more information, existing is soft-deleted
- GIVEN an existing near-duplicate observation `D_old`
- WHEN a new observation `D_new` with `score_new >= score_existing` arrives
- THEN `D_old.deleted_at` is set to now
- AND `D_new` is inserted
- AND a warning is logged: `[DUPLICATE DETECTION] Deleting existing in favor of new`

### Scenario: existing observation has more information, new is rejected
- GIVEN an existing near-duplicate observation `D_old`
- WHEN a new observation `D_new` with `score_new < score_existing` arrives
- THEN `D_new` is NOT inserted (function returns True from `is_rejected_duplicate`)
- AND `D_old` is unchanged
- AND a warning is logged: `[DUPLICATE DETECTION] Rejecting new in favor of existing`

### Scenario: tie goes to the new observation
- GIVEN `score_new == score_existing`
- THEN `D_old` is soft-deleted
- AND `D_new` is inserted

### Scenario: soft-deleted observations are cleaned up by reconciler
- GIVEN observations with `deleted_at != NULL`
- WHEN the reconciler's cleanup cycle runs
- THEN their vectors are removed from the external vector store
- AND the rows are hard-deleted from Postgres

## Evidence

| Type | Reference |
|---|---|
| Doc | `src/crud/document.py:963-984` — `is_rejected_duplicate` docstring: "Uses: 1) Cosine similarity (>=0.95), 2) Token diff for retention" |
| Source | `src/crud/document.py:457-462` — dedup gate inside `create_documents` |
| Source | `src/crud/document.py:986-995` — Step 1: cosine similarity search via `query_documents` with `max_distance=0.05, top_k=1` |
| Source | `src/crud/document.py:1003-1010` — Step 2: token-set-difference scoring (`score = total_tokens + unique_tokens * 10`) |
| Source | `src/crud/document.py:1013-1020` — new-wins path: soft-delete existing, return False (accept new) |
| Source | `src/crud/document.py:1022-1026` — existing-wins path: return True (reject new) |
| Source | `src/crud/document.py:1018` — `existing_doc.deleted_at = datetime.now(UTC)` soft-delete |
| Source | `src/crud/document.py:1029+` — `cleanup_soft_deleted_documents` reconciliation hook |
| Source | `src/config.py:760` — `DEDUPLICATE: bool = True` default |
| Source | `src/crud/representation.py:200` — `deduplicate=settings.DERIVER.DEDUPLICATE` toggle plumbed through |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Document query strategies** (semantic, recent, most-derived, filter-only) are promoted to `features/document-query-strategies.md`. This spec covers consolidation's **write-side dedup**; that spec covers the read paths.
- **The algorithm is hybrid, not pure.** Cosine similarity finds candidates; token-set-diff scoring picks the winner. This is more sophisticated than hash-based dedup (catches paraphrases) and cheaper than LLM-judged dedup (no extra inference call). Resolves `04-assessment.md §A18`.
- **Latest-wins on cosine-near match.**
- **Information-preserving bias.** The `unique_tokens * 10 + total_tokens` weighting heavily favours observations with novel information. A short observation that adds new tokens beats a longer observation that merely restates existing ones.
- **Tie-breaking favours recency (new beats equal old).** Subtle but matters: if extracted observations are oscillating between two equivalent phrasings, the most recent always wins. Avoids stale-content lock-in.
- **Soft-delete prevents data loss during partial failures.** Hard-delete happens only after vector cleanup; if the reconciler crashes mid-cleanup, the row is still queryable until the next cycle.
- **Per-`(observer, observed)` scope.** Dedup is scoped to the same observer-observed collection. Identical content held by different observers about the same observed peer is NOT deduplicated — consistent with the perspectival storage model (A14, A26).
- **Cosine threshold of 0.95 is conservative.** Catches obvious paraphrases and exact restatements; near-misses (e.g., a more specific fact and a more general one) are not deduped. This is the right default — false positives in dedup would destroy real information.
- **No consolidation at higher levels (deductive/inductive) characterised here.** Whether dreamer specialists trigger their own dedup against existing deductive/inductive observations is not in this code path — they presumably use the same `crud.create_documents` interface, inheriting the same dedup behaviour. Verification not in scope of this spec.

## Configuration surface

| Knob | Default | Source |
|---|---|---|
| `DERIVER.DEDUPLICATE` | `True` | `src/config.py:760` |
| Cosine distance threshold | 0.05 (hard-coded) | `src/crud/document.py:992` |
| Token-uniqueness weight | 10 (hard-coded) | `src/crud/document.py:1009-1010` |
