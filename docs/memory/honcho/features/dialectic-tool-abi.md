# Dialectic tool ABI

## §A Tier 1 — Claim

§A1 The dialectic agent (and dreamer specialists, via shared infrastructure) invokes capabilities through a **tool ABI** defined in `src/utils/agent_tools.py`. The ABI provides ~20 distinct tool handlers behind a uniform dispatch contract — JSON-schema input validation, async execution, structured-result return, telemetry-wrapped lifecycle.

§A2 Tool handlers are paired: each tool has a `*_TOOL_DEFINITION` JSON schema (declares name + parameters + description) and a `_handle_*` async function (executes the call). Dispatch maps tool name → handler at call time.

§A3 All handlers receive a shared `ToolContext` dataclass — workspace/observer/observed identity, current message context, history token limits, resolved configuration, telemetry correlation fields (`run_id`, `agent_type`, `parent_category`), and a shared `db_lock` for serializing writes to the same `(workspace, observer, observed)` triple.

§A4 Three classes of tool: **read** (`get_recent_history`, `search_memory`, `get_observation_context`, `search_messages`, `grep_messages`, `get_messages_by_date_range`, `search_messages_temporal`, `get_recent_observations`, `get_most_derived_observations`, `get_session_summary`, `get_peer_card`, `extract_preferences`); **write** (`create_observations`, `create_observations_deductive`, `create_observations_inductive`, `delete_observations`, `update_peer_card`); **control** (`finish_consolidation`).

§A5 Observation locking: writes to a `(workspace, observer, observed)` triple serialize via a module-level `asyncio.Lock` registry, accessed via `get_observation_lock(...)`. Concurrent tool executors sharing the same triple share the same lock; locks are garbage-collected when all referencing executors finish.

§A6 Output truncation: every tool result passes through `_truncate_tool_output` (default cap `LLM.MAX_TOOL_OUTPUT_CHARS`). When truncated, the result is wrapped in `ToolResult` with `metadata={"was_truncated": True, "result_chars_before_truncation": N}` so the `AgentToolCallCompletedEvent` emitter can report it. Untruncated results return as bare `str` to keep the handler contract unchanged.

§A7 Per-message truncation: `_truncate_message_content` clamps individual message bodies to `LLM.MAX_MESSAGE_CONTENT_CHARS` before they're folded into a tool result. For grep/exact-search tools, `_extract_pattern_snippet` returns context around the match rather than the message head.

§A8 Validation failures are non-fatal at batch granularity: `create_observations` validates each observation individually and returns an `ObservationsCreatedResult` listing `created_count` + `failed: list[ObservationFailure]`. Partial success is the norm, not the exception.

§A9 Level-policy enforcement at the ABI: when `ctx.current_messages` is set (deriver context), only `level="explicit"` observations may be created — other levels are rejected at validation time. When `ctx.current_messages` is None (dreamer/dialectic context), the default level is `"deductive"`. Forced-level callers (`_handle_create_observations_deductive`, `_handle_create_observations_inductive`) override the validation gate.

§A10 The `create_tool_executor` factory binds a `ToolContext` and returns a callable `(tool_name, tool_input) → result` that dispatches through the handler map. Specialists, dialectic, and any other tool-using subsystem use this same factory.

## §B Tier 2 — Source

§B1 `src/utils/agent_tools.py:1271-1290` — `ToolContext` dataclass.

§B2 `src/utils/agent_tools.py:299-327` — `get_observation_lock` (§A5).

§B3 `src/utils/agent_tools.py:347-388` — `_truncate_tool_output`, `_maybe_truncated_result` (§A6).

§B4 `src/utils/agent_tools.py:390-396` — `_truncate_message_content` (§A7).

§B5 `src/utils/agent_tools.py:399-426` — `_extract_pattern_snippet` (§A7).

§B6 `src/utils/agent_tools.py:330-345` — `ObservationFailure`, `ObservationsCreatedResult` dataclasses (§A8).

§B7 `src/utils/agent_tools.py:1293-1414` — `_handle_create_observations_impl` (§A8, §A9).

§B8 `src/utils/agent_tools.py:1416-1442` — `_handle_create_observations`, `_handle_create_observations_deductive`, `_handle_create_observations_inductive` (forced-level dispatchers, §A9).

§B9 `src/utils/agent_tools.py:1442-1604` — `_handle_update_peer_card`.

§B10 `src/utils/agent_tools.py:849-1270` — public-API tool implementations (`create_observations`, `get_recent_history`, `search_memory`, `get_observation_context`, `extract_preferences`).

§B11 `src/utils/agent_tools.py:1605-2138` — `_handle_*` dispatchers (§A4 read/write/control classes).

§B12 `src/utils/agent_tools.py` — `create_tool_executor` factory (§A10); referenced from `src/dreamer/specialists.py:236` and `src/dialectic/core.py`.

§B13 `src/dreamer/specialists.py:233-247` — specialist invocation of `create_tool_executor` showing the `parent_category`, `run_id`, `agent_type` telemetry threading (§A3).

§B14 `src/config.py` — `LLM.MAX_TOOL_OUTPUT_CHARS`, `LLM.MAX_MESSAGE_CONTENT_CHARS` (the truncation knobs §A6, §A7).

## §C Tier 3 — Analytical

§C1 **The ABI is the substrate's load-bearing reuse seam.** Three subsystems (dialectic, dreamer/specialists, deriver via `_handle_create_observations` with `current_messages` set) all go through this same tool layer for observation writes. Changing observation-write semantics in one place changes them everywhere. Strong invariant by construction.

§C2 **Per-triple write serialization is at the ABI, not the storage layer.** `get_observation_lock` is an in-process `asyncio.Lock` keyed by `(workspace, observer, observed)` — it serializes concurrent tool calls inside one deriver/dialectic process, NOT across replicas. Cross-replica serialization relies on the worker-lease model (`features/worker-lease-model.md`). Operator implication: scaling the API server horizontally without considering tool-write contention is safe (the lock only matters within a single inflight request's tool loop); scaling the deriver beyond one replica per workspace can produce duplicate writes that the dedup layer (`features/consolidation.md`) is the only catch for.

§C3 **Output truncation is a token-budget guard, not a result-fidelity policy.** The truncated suffix `[OUTPUT TRUNCATED - showing X of Y characters]` is parsed by the LLM in subsequent iterations. Operators tuning for smaller models must understand: shrinking `MAX_TOOL_OUTPUT_CHARS` makes tool calls cheaper but also makes the agent more likely to ask for the same data with narrower filters in the next iteration — pushing cost from the result to additional iterations.

§C4 **Level-policy enforcement at the ABI is the structural guarantee for `features/explicit-deductive.md`'s three-level model.** The rule "deriver can only write explicit" is enforced in `_handle_create_observations_impl:1328-1334` — a callsite cannot bypass it by setting `level="deductive"` in `tool_input`. The provenance discipline is structural, not just conventional.

§C5 **Partial-success result shape (§A8) is what makes batch observation writes safe.** A single bad observation in a batch of 20 does not poison the other 19; the agent gets back `created_count=19, failed=[ObservationFailure(...)]` and can decide whether to retry the failure. Without this shape, batch writes would degrade to one-at-a-time to preserve fault isolation.

§C6 **The ABI is the dialectic agent's "write side", not its retrieval side.** Read tools (§A4 first column) are how the agent gathers context; write tools are how the agent mutates state in response to a query. A22 in `04-assessment.md` notes that this write authority makes dialectic a second writer of higher-order observations. The ABI is where that authority is gated — there is no "read-only mode" toggle for the dialectic agent at this SHA; whether writes happen is decided by `DIALECTIC_TOOLS` vs `DIALECTIC_TOOLS_MINIMAL` selection (A27, still open).

§C7 **Telemetry threading via `parent_category` (§A3) is how cross-subsystem observability stays coherent.** A tool call from a dreamer specialist tags `parent_category="dream"`; the same handler called from dialectic tags `parent_category="dialectic"`. `AgentToolCallCompletedEvent` consumers can fan out by caller without parsing the run_id correlation graph.
