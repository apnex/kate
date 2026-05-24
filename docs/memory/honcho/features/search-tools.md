# Feature: search-tools

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Retrieval
**Triangulation:** ✓ Triangulated

## What it is

Search tools is the catalogue of LLM-callable tools exposed to the `DialecticAgent` during query answering. The catalogue ships as two declared tool sets — `DIALECTIC_TOOLS` (full surface) and `DIALECTIC_TOOLS_MINIMAL` (strict subset) — defined as JSON-schema tool descriptors and bound to handler functions via a dispatch table. The surface mixes **read tools** (semantic search, recent history, observation context, preference extraction) with **write tools** (create observations at three reasoning levels, update peer card). The agent can therefore mutate memory state during a query — not just retrieve from it.

## Requirement

The system SHALL expose to the dialectic agent a catalogue of tools for retrieving memory context (semantic search, recent history, observation context, preference extraction) and for mutating memory state (creating observations at explicit/deductive/inductive levels, updating peer cards), with each tool having a JSON-schema descriptor and an async handler.

## Scenarios

### Scenario: agent retrieves semantically-similar observations
- GIVEN an agent answering a query about observed `bob`
- WHEN the agent invokes the `search_memory` tool with a search string
- THEN observations from collection `(workspace, observer, bob)` are queried by vector similarity
- AND the matching observation contents are returned to the agent as tool output

### Scenario: agent fetches recent conversation history
- GIVEN an agent with `session_name='s1'`
- WHEN the agent invokes `get_recent_history` with a message count
- THEN the requested number of most-recent messages from `s1` are returned
- AND messages are formatted for LLM consumption

### Scenario: agent creates an explicit observation during query
- GIVEN an agent processing a query that surfaces a new fact about the observed peer
- WHEN the agent invokes the `create_observations` write tool with the new fact
- THEN one or more new explicit observations are persisted to the appropriate collection
- AND subsequent `search_memory` calls in the same loop can retrieve them

### Scenario: agent updates the observed peer's card
- GIVEN an agent processing a query that reveals biographical information
- WHEN the agent invokes `update_peer_card` with new lines
- THEN the observed peer's card is updated in storage
- AND validation is applied per `_validate_peer_card_entry`

### Scenario: minimal tool set is a strict subset
- GIVEN the agent is bound to `DIALECTIC_TOOLS_MINIMAL`
- WHEN it attempts to call a tool present in `DIALECTIC_TOOLS` but absent from the minimal set
- THEN the LLM provider does not expose that tool name to the agent
- AND the tool cannot be invoked

### Scenario: tool output is truncated when oversized
- GIVEN a tool returns a result exceeding the configured truncation threshold
- WHEN the result is returned to the agent
- THEN the result is truncated by `_truncate_tool_output` / `_maybe_truncated_result`
- AND the agent receives the truncated form with a truncation marker

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/api-reference/chat.mdx` — dialectic-chat tool surface |
| Doc | `CLAUDE.md` §Dialectic — agent uses tools to gather context |
| Source | `src/utils/agent_tools.py:782` — `DIALECTIC_TOOLS: list[dict[str, Any]] = [...]` |
| Source | `src/utils/agent_tools.py:795` — `DIALECTIC_TOOLS_MINIMAL: list[dict[str, Any]] = [...]` |
| Source | `src/utils/agent_tools.py:849-1062` — read tools: `create_observations` (defined here, used as both read context and write), `get_recent_history`, `search_memory` |
| Source | `src/utils/agent_tools.py:1109-1190` — `get_observation_context`, `extract_preferences` |
| Source | `src/utils/agent_tools.py:1271-1291` — `ToolContext` carrying workspace/session/observer/observed scope to handlers |
| Source | `src/utils/agent_tools.py:1293-1722` — `_handle_*` dispatch implementations for each tool name |
| Source | `src/utils/agent_tools.py:1442-1604` — `_handle_update_peer_card` write path with validation |
| Source | `src/utils/agent_tools.py:347-388` — `_truncate_tool_output` and `_maybe_truncated_result` truncation guards |
| Source | `src/utils/agent_tools.py:299-329` — `get_observation_lock` for write contention control |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Read+write tool surface is the key architectural shape.** The dialectic agent can mutate observations and peer cards during query answering. This blurs the read/write split that other architectures keep clean — see `04-assessment.md §A22` for the cross-cutting implication.
- **Write tools are split by observation level.** Three separate handlers (`_handle_create_observations`, `_handle_create_observations_deductive`, `_handle_create_observations_inductive`) match the three observation-level schemas. The dialectic agent is therefore *the second writer of deductive/inductive observations* (alongside the hypothesised dreamer specialists — see `features/explicit-deductive.md`).
- **`ToolContext` is the scope-injection mechanism.** Handlers don't take workspace/observer/observed as arguments from the LLM — those are bound at agent construction time via `ToolContext` and injected at dispatch. This prevents the LLM from forging cross-peer or cross-workspace accesses via tool arguments.
- **`get_observation_lock` exists** — write contention control for observation creation. Implies concurrent dialectic loops could race on the same collection.
- **Tool output truncation is observable to the LLM.** The agent sees a truncation marker when a tool result is cut, allowing it to decide whether to narrow the query or accept partial context.
- **Minimal vs full tool set selection rule** (which configuration chooses minimal vs full) is not characterised by this spec — likely keyed by `reasoning_level` or a separate `tools.minimal` config flag.

## Tool catalogue (descriptive)

| Tool name | Read/Write | Handler | Purpose |
|---|---|---|---|
| `search_memory` | Read | `_handle_search_memory` (1632) | Vector search across `(observer, observed)` collection |
| `get_recent_history` | Read | `_handle_get_recent_history` (1605) | Recent N messages from session |
| `get_observation_context` | Read | `_handle_get_observation_context` (1722) | Load full observation by id with related |
| `extract_preferences` | Read | (in `extract_preferences:1190`) | Extract preference-shaped observations |
| `create_observations` | Write | `_handle_create_observations` (1416) | Persist new explicit observations |
| `create_observations_deductive` | Write | `_handle_create_observations_deductive` (1422) | Persist new deductive observations |
| `create_observations_inductive` | Write | `_handle_create_observations_inductive` (1432) | Persist new inductive observations |
| `update_peer_card` | Write | `_handle_update_peer_card` (1442) | Modify observed peer's card lines |
