# Feature: dialectic-chat

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Retrieval
**Triangulation:** ✓ Triangulated

## What it is

Dialectic chat is Honcho's query-time retrieval surface. Given a query about an observed peer from an observer peer's perspective, the system synthesises an answer by spinning up a `DialecticAgent` that iteratively gathers context via tools and produces a response. The agent runs as an LLM-driven tool loop with read and write tools, then synthesises a final answer.

## Requirement

The system SHALL accept a query bound to `(workspace, session?, observer, observed, reasoning_level)`, gather context via an iterative tool-driven LLM agent, and return a synthesised answer either as a complete string or as a streamed chunk iterator.

## Scenarios

### Scenario: synchronous answer for a global query
- GIVEN observer `alice` querying about observed `bob` with no session
- WHEN `agentic_chat` is invoked
- THEN a `DialecticAgent` is constructed with `session_name=None`
- AND a synthesised answer string is returned
- AND a `DialecticCompletedEvent` is emitted with timing and token metrics

### Scenario: streamed answer for a session-scoped query
- GIVEN observer `alice` querying about observed `bob` within `session_name='s1'`
- WHEN `agentic_chat_stream` is invoked
- THEN an async iterator of response chunks is returned
- AND the agent has access to recent-history tools scoped to `s1`

### Scenario: peer cards injected upfront, not retrieved
- GIVEN `configuration.peer_card.use = true`
- WHEN the agent is constructed
- THEN observer and (if different) observed peer cards are fetched from the database during preflight
- AND passed to the `DialecticAgent` constructor
- AND included in the system prompt

### Scenario: agent runs without a DB connection held
- GIVEN any dialectic invocation
- WHEN the agent's tool loop is executing
- THEN no database session is held open by the agent itself
- AND DB sessions are opened per-tool only when a tool requires database access

### Scenario: reasoning level selects the model configuration
- GIVEN `reasoning_level='medium'`
- WHEN the agent calls the LLM
- THEN `settings.DIALECTIC.LEVELS['medium'].MODEL_CONFIG` is used
- AND a different model may be used than at `reasoning_level='low'`

### Scenario: tool set varies by configuration
- GIVEN the configuration selects the minimal tool set
- WHEN the agent is constructed
- THEN it is bound to `DIALECTIC_TOOLS_MINIMAL` (a strict subset of `DIALECTIC_TOOLS`)

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/api-reference/chat.mdx` — dialectic API surface |
| Claim | `CLAUDE.md` §Dialectic — describes agent-driven query answering |
| Doc | `src/dialectic/core.py:53-59` docstring — "Unlike the standard dialectic which pre-gathers all context before a single LLM call, this agent uses tools to strategically gather only the context needed" |
| Source | `src/dialectic/chat.py:20-78` — `agentic_chat` entry point with short-lived DB preflight |
| Source | `src/dialectic/chat.py:81-140` — `agentic_chat_stream` mirror with streaming iterator |
| Source | `src/dialectic/chat.py:42-66` — preflight: peer validation, session lookup, configuration load, peer card fetch |
| Source | `src/dialectic/chat.py:66` — comment "DB session closed — agent runs without holding a connection" |
| Source | `src/dialectic/core.py:46-49` — `_get_dialectic_level_model_config` reads `settings.DIALECTIC.LEVELS[reasoning_level].MODEL_CONFIG` |
| Source | `src/dialectic/core.py:34-39` — imports both `DIALECTIC_TOOLS` and `DIALECTIC_TOOLS_MINIMAL` |
| Source | `src/dialectic/core.py:94-101` — system prompt construction with observer/observed peer cards |
| Source | `src/llm/tool_loop.py` — shared tool-loop infrastructure used by the agent |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Two dialectic variants exist; only one is exposed.** The docstring at `core.py:53-59` references a "standard dialectic" that pre-gathers context for a single LLM call, contrasting it with the agentic variant. `chat.py` exposes only the agentic path. The standard path is either internal-only, deprecated, or planned-future at this SHA.
- **Per-reasoning-level model configs are a configuration surface, not just a parameter.** `min/low/medium/high/max` can each map to a different model (potentially small/cheap for low, large/reasoning-tuned for high). Operationally this means tuning `reasoning_level` isn't just a knob on the same model — it's a model-selection signal.
- **DB-connection-free agent execution is a scalability property.** Long agent runs don't consume DB pool slots. Each tool that needs DB opens its own short-lived session via `tracked_db`.
- **Peer cards always loaded upfront when enabled.** Agent does not have a tool to fetch its own peer card — it receives them at construction time. Operational implication: peer card freshness at query time is fixed; the agent cannot refresh it mid-loop.
- **What `reasoning_level` actually controls beyond model selection** (loop depth, max tool calls, retrieval breadth) is not characterised by this spec — see `04-assessment.md §A20`.
- **The tool surface includes write tools.** Dialectic can mutate state during a query — see `features/search-tools.md` for the full surface and `04-assessment.md §A22` for the cross-cutting implication.

## Configuration surface

| Knob | Default | Source |
|---|---|---|
| `DIALECTIC.LEVELS[level].MODEL_CONFIG` | per-level | `src/config.py` |
| `peer_card.use` | true (when card exists) | `src/config.py` configuration helpers |
| Reasoning level (per call) | `"low"` | `src/dialectic/chat.py:26` default |
