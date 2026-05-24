# Tool loop

## §A Tier 1 — Claim

§A1 `execute_tool_loop` runs an iterative agentic LLM call: each iteration issues an LLM request with tools attached, runs the returned tool calls in parallel, appends results to the conversation, and continues until the model stops calling tools or the iteration cap is hit.

§A2 Iteration cap `max_tool_iterations` is bounded `[MIN_TOOL_ITERATIONS=1, MAX_TOOL_ITERATIONS=100]`; out-of-range values raise at entry.

§A3 After iteration 1, `tool_choice` is downgraded from `"required"`/`"any"` to `"auto"` so the model can terminate naturally on later turns.

§A4 If the model returns no tool calls before the cap, the loop exits early and that response is returned as-is (the terminating iteration still counts toward telemetry).

§A5 If the cap is reached with tool calls still pending, a **synthesis call** is issued with a fixed prompt ("You have reached the maximum number of tool calls… provide your final response now") and `tools=None`, `tool_choice=None`. This call is iteration N+1 in telemetry.

§A6 Cumulative bookkeeping (`total_input_tokens`, `total_output_tokens`, `cache_creation`, `cache_read`, `all_tool_calls`) is accumulated across iterations and merged onto the final response.

§A7 Per-iteration `max_input_tokens` enforcement: if `count_message_tokens(conversation_messages) > cap`, a `hit_input_token_cap` latch is set and `truncate_messages_to_fit` trims the conversation before the next call. The synthesis call re-checks because appending the synthesis prompt can push it back over.

§A8 Telemetry emits an `AgentIterationEvent` after every LLM response (including the no-tool terminating iteration and the synthesis call). Iteration number is 1-indexed.

§A9 ContextVars (`iteration`, `tool_call_seq`, provider id, last attempt plan) are scoped per call via `_with_iteration_scope` decorator so concurrent loops in the same asyncio Task cannot observe each other's state.

§A10 Provider plan is snapshotted via `get_attempt_plan()` after the loop settles; streaming retries pin to that exact client/model rather than re-running provider selection.

§A11 Optional `iteration_callback` fires after each iteration's tool execution with an `IterationData` payload; exceptions in the callback are caught and logged, never re-raised.

§A12 Empty-response handling: bounded retry counter (`empty_response_retries`) allows the loop to re-issue the same iteration if the provider returns an empty payload, without consuming a full iteration slot.

## §B Tier 2 — Source

§B1 `src/llm/tool_loop.py` lines 147-149: `MIN_TOOL_ITERATIONS=1`, `MAX_TOOL_ITERATIONS=100`.

§B2 Lines 54-69: `_with_iteration_scope` decorator (§A9).

§B3 Lines 71-93: `_telemetry_for_iteration` (per-iteration telemetry context copy).

§B4 Lines 95-145: `_emit_agent_iteration` (§A8).

§B5 Lines 191-269: `stream_final_response` (used by §A10 path).

§B6 Lines 272-?: `execute_tool_loop` body — entry validation (§A2), iteration scope, main while loop.

§B7 Lines 339-550: per-iteration block — LLM call, terminating-iteration return path (§A4), tool execution, append results, callback (§A11), tool_choice downgrade (§A3).

§B8 Lines 543-548: `"required"`/`"any"` → `"auto"` downgrade.

§B9 Lines 552-666: max-iteration path — synthesis prompt (§A5), token-cap re-check (§A7), streaming vs non-streaming finals, cumulative merge (§A6).

## §C Tier 3 — Analytical

§C1 **Cap-hit synthesis is a graceful degradation.** Rather than failing or returning mid-loop garbage, the loop forces a final non-tool answer. The model is told it's out of tool calls, which lets it summarise what it has rather than retry.

§C2 **Token-cap latch is sticky.** Once `hit_input_token_cap` is set in any iteration, it propagates onto the final response — downstream callers can detect that truncation occurred at some point in the loop even if the final iteration fit.

§C3 **Tool_choice downgrade prevents infinite tool-required loops.** With `"required"` held across all iterations the model can never produce a terminating no-tool turn; the iter-1 downgrade is the loop's primary off-ramp.

§C4 **Plan snapshotting decouples streaming retries from provider selection.** Mid-stream failures retry against the same provider+model rather than re-running fallback chains, preserving stable behavior under flaky providers.

§C5 **Synthesis call uses fixed prompt, not user-controllable.** Operators cannot customise the cap-hit recovery message; this trades flexibility for predictability across all agentic features (dialectic, dreamer specialists, tool-using deriver).

§C6 **Callback failures are swallowed.** Telemetry consumers attached via `iteration_callback` cannot break the loop; observability is best-effort by design.

§C7 **`MAX_TOOL_ITERATIONS=100` is generous.** Real configured caps (dialectic, dreamer) sit far below this hard ceiling; the bound is a runaway guard, not an expected operating point.
