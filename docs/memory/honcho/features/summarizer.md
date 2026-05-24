# Feature: summarizer

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Background subsystem
**Triangulation:** ✓ Triangulated

## What it is

The summarizer produces and serves message summaries for session context APIs. Summaries are stored in session metadata as typed objects (`Summary` TypedDict with `content`, `message_id`, `summary_type`, `created_at`, `token_count`, `message_public_id`). Two summary types exist (`short` and `long`, exposed via the `SummaryType` enum). The summarizer is invoked when callers request session context via `get_session_context` or related public functions.

## Requirement

The system SHALL produce and serve short and long summaries of session message history, persist them in session metadata as typed `Summary` objects, and expose them via public functions for session-context APIs.

## Scenarios

### Scenario: caller requests session context
- GIVEN a session with N messages
- WHEN `get_session_context` is invoked
- THEN summaries (if available and current) are loaded from session metadata
- AND messages newer than the latest summary's `message_id` are returned alongside

### Scenario: summary covers messages up to a specific message_id
- GIVEN a summary with `message_id=42` was produced
- WHEN later messages 43-100 are added
- THEN the summary remains valid for messages 1-42
- AND messages 43-100 are not covered until the next summarization run

### Scenario: short and long summaries are independent
- GIVEN a session
- WHEN both summary types are retrieved
- THEN `get_both_summaries` returns both `short` and `long` `Summary` objects independently
- AND each tracks its own `message_id` coverage

### Scenario: summary creation emits telemetry
- GIVEN a new summary is created (typically by the deriver pipeline)
- WHEN the summary is persisted
- THEN an `AgentToolSummaryCreatedEvent` is emitted

### Scenario: token count is tracked per summary
- GIVEN any summary
- WHEN it is persisted
- THEN its `token_count` field reflects estimated tokens in the summary content
- AND the count contributes to deriver input-token tracking via `track_deriver_input_tokens`

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` — summarization as part of the memory subsystem |
| Claim | `CLAUDE.md` — summarizer as a deriver task |
| Source | `src/utils/summarizer.py:39-56` — `Summary` TypedDict with all fields |
| Source | `src/utils/summarizer.py:59-67` — `to_schema_summary` converter |
| Source | `src/utils/summarizer.py:71-80` — `__all__` exposing `get_summary`, `get_both_summaries`, `get_summarized_history`, `get_session_context`, `get_session_context_formatted`, `SummaryType`, `Summary`, `to_schema_summary` |
| Source | `src/utils/summarizer.py:22` — `AgentToolSummaryCreatedEvent` import |
| Source | `src/utils/summarizer.py:31` — `track_deriver_input_tokens` import |
| Source | `src/utils/summarizer.py:13-14` — `cache_client` import (read-through pattern for session) |
| Source | `src/utils/summarizer.py:15` — `session_cache_key` import |
| Source | (file 957 LOC, full enumeration of implementation details deferred — public surface fully described above) |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Largest single utility file in the codebase (957 LOC).** Despite living under `src/utils/`, the line count exceeds most subsystem directories. The `src/utils/` placement is the classification smell flagged in `04-assessment.md §A3` — operationally it behaves like a subsystem (caching, telemetry events, token tracking, two distinct summary types), but it's not architecturally classified as one.
- **Two summary types is a design commitment, not a configuration accident.** `short` and `long` SummaryType enum members + `get_both_summaries` function suggest distinct use cases (likely: quick context vs. detailed handover).
- **Coverage tracked by message_id rather than time** — robust to clock skew and message reordering. Implies summaries are append-mode: each summary covers `[start, message_id]`; new summaries cover `[message_id+1, new_message_id]`.
- **Read-through caching pattern.** `cache_client` and `session_cache_key` imports indicate summaries are cached at the session level, invalidated on session writes.
- **Telemetry distinct from observation creation.** `AgentToolSummaryCreatedEvent` (not a generic event) suggests summarizer-specific dashboards/alerts.
- **Public surface deliberately narrow** — only 8 names exported via `__all__`. Internal complexity (957 LOC) hidden behind a small API.
- **Full functional characterisation of summary triggering and content generation deferred.** This spec characterises the public-API surface and storage model; the LLM prompts, triggering conditions, and prompt-tuning details are not enumerated. Adequate for the substrate map; a deeper dive would be warranted if we operate Honcho at scale and need to tune summary quality.

## Configuration surface

| Knob | Default | Source |
|---|---|---|
| `SUMMARIZER.*` (prompt model, token thresholds) | configurable | `src/config.py` |
| Session cache TTL | per `cache_client` config | `src/cache/` |
