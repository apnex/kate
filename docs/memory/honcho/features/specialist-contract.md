# Specialist contract

## §A Tier 1 — Claim

§A1 Dreamer specialists are self-directed agentic LLM loops that share a common contract defined by `BaseSpecialist(ABC)`. Two concrete subclasses ship at this SHA: `DeductionSpecialist` and `InductionSpecialist`.

§A2 Each specialist owns: a `name`, a `peer_card_update_instruction`, a `can_update_peer_card` flag (default True; induction overrides to False), a `get_tools(*, peer_card_enabled)` method returning the JSON-schema tool list, a `get_model_config()` returning the `ConfiguredModelSettings` to use (typically reading `DREAM.{DEDUCTION|INDUCTION}_MODEL_CONFIG`), and `build_system_prompt(observed, *, peer_card_enabled)` + `build_user_prompt(hints, peer_card)` for the LLM conversation.

§A3 `BaseSpecialist.run(...)` is the shared 350+ LOC orchestration: peer preflight → peer-card preload → tool-executor construction → message build → LLM call via shared `tool_loop` infrastructure → telemetry rollup → `SpecialistResult` return. Subclasses only override the abstract methods; the loop is shared.

§A4 Per-specialist defaults: `get_max_tokens()=16384`, `get_max_iterations()=15`. Both are overridable; both are caps, not targets.

§A5 Per-level peer-card discipline: `can_update_peer_card=False` removes peer-card tools from the specialist's tool set AND skips the peer-card preload AND omits the peer-card section from the user prompt. InductionSpecialist exercises this override — induction explicitly cannot mutate identity markers.

§A6 DB-connection lifecycle: short-lived `tracked_db("dream.specialist.preflight")` session for peer lookup + peer-card preload, then **closed** before any LLM call. Tool executions open their own short-lived sessions per tool call via `tracked_db`. The LLM iteration loop never holds a DB connection.

§A7 Telemetry rollups accumulated across the loop: `created_observation_count`, `deleted_observation_count`, `peer_card_updated`, `search_tool_calls_count`, `created_counts_by_level: Counter[str]`, `deleted_counts_by_level: Counter[str]`. These flow into the parent `DreamRunEvent` emitted by the orchestrator (`features/dreamer.md`).

§A8 Failure semantics: telemetry state is initialized **before** the try block so the finally block always has consistent values even when preflight fails (peer lookup, peer-card preload, tool-executor construction, model-config resolution, prompt construction). A preflight failure produces a `SpecialistResult(success=False)` rather than orphaning the run from the downstream `DreamRunEvent`.

§A9 Hints input: `run(hints=...)` accepts an optional list of strings to bias exploration. When provided, hints are folded into the user prompt; when None, the specialist explores freely. Hints are an interface for surprisal-based pre-filtering (`features/surprisal.md`) — but the specialist is not bound by them (per `dreamer.md` orchestrator docstring: "specialists are free to follow the evidence wherever it leads").

§A10 Model-config resolution chain: `get_model_config()` reads `DREAM.{NAME}_MODEL_CONFIG` via `_require_specialist_model_config(name)`. Each specialist can route to a different model; operators tune cost/quality per-specialist independently.

## §B Tier 2 — Source

§B1 `src/dreamer/specialists.py:74` — `BaseSpecialist(ABC)` definition.

§B2 `src/dreamer/specialists.py:77-84` — name + `peer_card_update_instruction` + `can_update_peer_card` (§A2, §A5).

§B3 `src/dreamer/specialists.py:86-118` — abstract method signatures (`get_tools`, `get_model_config`, `build_system_prompt`, `build_user_prompt`).

§B4 `src/dreamer/specialists.py:96-102` — `get_max_tokens=16384`, `get_max_iterations=15` defaults (§A4).

§B5 `src/dreamer/specialists.py:120-133` — `_build_peer_card_context` (peer-card section of user prompt, §A5).

§B6 `src/dreamer/specialists.py:135-428` — `BaseSpecialist.run(...)` (the full shared orchestration, §A3, §A6, §A7, §A8).

§B7 `src/dreamer/specialists.py:166-188` — telemetry state initialized before try block (§A8).

§B8 `src/dreamer/specialists.py:192-217` — short-lived preflight DB session; explicit "DB session closed — LLM calls happen without holding a connection" comment (§A6).

§B9 `src/dreamer/specialists.py:233-247` — `create_tool_executor` invocation with telemetry context threading (`run_id`, `agent_type=self.name`, `parent_category="dream"`).

§B10 `src/dreamer/specialists.py:429-612` — `DeductionSpecialist(BaseSpecialist)`.

§B11 `src/dreamer/specialists.py:613-742` — `InductionSpecialist(BaseSpecialist)`.

§B12 `src/dreamer/specialists.py:29` — `SPECIALISTS` list exported (the registry the orchestrator iterates).

§B13 `src/dreamer/specialists.py:43-54` — `_require_specialist_model_config` (§A10).

§B14 `src/dreamer/specialists.py:56-72` — `SpecialistResult` dataclass shape (§A7 fields).

§B15 `src/config.py:1131-1212` — `DreamSettings` block including `DEDUCTION_MODEL_CONFIG`, `INDUCTION_MODEL_CONFIG`, `HISTORY_TOKEN_LIMIT`.

## §C Tier 3 — Analytical

§C1 **The base-class share-everything pattern is what makes adding a third specialist cheap.** An `AbductionSpecialist` would need: `name="abduction"`, four abstract method implementations, optionally `can_update_peer_card=False`, and an entry in `SPECIALISTS`. The 350-LOC orchestration is inherited. A11 (in `04-assessment.md`) notes abduction is schema-extensible; the cost of adding it is small precisely because of this contract.

§C2 **Per-specialist model routing (§A10) means cost/quality is a per-reasoning-mode knob.** Operators can run `DeductionSpecialist` on a cheap model and `InductionSpecialist` on a smart one (or vice versa) by setting different `MODEL_CONFIG` blocks. Reasoning-mode-aware budgeting is structural, not just a knob the prober wishes existed.

§C3 **`can_update_peer_card=False` for induction is a load-bearing policy decision.** Inductive observations are pattern-claims across multiple premises; allowing induction to write peer-card facts would let speculative patterns mutate the identity surface. Restricting peer-card writes to deduction (and the deriver-by-policy and dialectic-by-tool-choice) keeps the identity-of-the-peer layer tightly scoped to high-confidence updates.

§C4 **The 15-iteration max-tools cap (§A4) bounds runaway specialists.** With `tool_loop`'s cap-hit-synthesis behaviour (`features/tool-loop.md`), a specialist that hits 15 iterations gets one final no-tool synthesis call to commit whatever observations it has accumulated. Cost is bounded; output is never empty even when the specialist would have iterated longer.

§C5 **Pre-try telemetry initialization (§A8) is a recurring discipline in this codebase.** Same pattern in `consumer.py` for the deriver batch lifecycle. The substrate clearly treats "the failure path must still emit a coherent event" as a first-class observability invariant. Operators can rely on `DreamRunEvent` always firing even when individual specialists fail.

§C6 **DB-connection-free LLM execution (§A6) is the same scalability pattern as dialectic (A24).** Specialists do not consume connection pool slots during the expensive LLM-call window — only during preflight (microseconds) and tool calls (per-call, short-lived). This is what makes the dreamer process viable as a co-resident on the deriver worker rather than needing its own pool budget.

§C7 **The hints-as-non-binding-bias contract (§A9) is the design principle that keeps surprisal optional.** A specialist that's bound by hints would degrade to "execute the surprisal-decided plan" — the substrate explicitly avoids this. Surprisal informs; specialists decide. Removing surprisal entirely (`DREAM.SURPRISAL.ENABLED=False`) does not change the specialist contract.
