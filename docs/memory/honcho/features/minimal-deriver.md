# Feature: minimal-deriver

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Derivation
**Triangulation:** ⚠ Mismatch — claim of "explicit → deductive scaffolding" contradicts source; deriver produces explicit observations only

## What it is

The minimal deriver is Honcho's per-batch observation-extraction subsystem. For each batch of messages from an observed peer, it makes one LLM call with a structured-output schema (`PromptRepresentation`), parses the response into `Representation` objects, and hands them to `RepresentationManager` for collection writes. Scope is explicit in the prompts module docstring: *"Minimal prompts for the deriver module optimized for speed … focused only on observation extraction. NO peer card instructions, NO working representation - just extract observations."*

## Requirement

The system SHALL, per enqueued batch of messages, invoke one configured LLM with a structured-output prompt and persist the resulting observations to all relevant observer collections, or short-circuit if reasoning is disabled.

## Scenarios

### Scenario: batch produces observations and persists them
- GIVEN a batch of messages from `peer_alice` with `reasoning.enabled = true`
- WHEN the batch processor is invoked
- THEN exactly one LLM call is made for this batch
- AND observations are persisted to each `(observer, alice)` collection for the session's peers
- AND a `RepresentationCompletedEvent` is emitted

### Scenario: reasoning disabled short-circuits
- GIVEN the resolved configuration has `reasoning.enabled = false`
- WHEN the batch processor is invoked
- THEN no LLM call is made
- AND no observations are persisted
- AND the function returns

### Scenario: deriver emits explicit observations only
- GIVEN any input messages
- WHEN the batch is processed
- THEN the persisted observations have `level='explicit'`
- AND no observations have `level='deductive'` or `level='inductive'`

### Scenario: token-breakdown invariants are validated
- GIVEN an LLM response with `input_tokens < messages_tokens` (impossible if tokenization is consistent)
- WHEN the batch is processed
- THEN a warning is logged citing "provider tokenization drift or wrong messages_tokens computation"

## Evidence

| Type | Reference |
|---|---|
| Claim | `CLAUDE.md` §Deriver — "the current architecture is 'minimal deriver' — a single LLM call per batch using structured output, not an agentic tool loop" |
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` §Formal Logic Framework — "explicit reasoning model … outputs … explicitly stated [facts], which serve as premises to scaffold deductive conclusions" (contradicted by source) |
| Doc | `docs/v3/documentation/core-concepts/reasoning.mdx` — example JSON shows `explicit` AND `deductive` populated (contradicted by source) |
| Source | `src/deriver/prompts.py:1-6` — file docstring declaring extraction-only scope |
| Source | `src/deriver/prompts.py:55-81` — `minimal_deriver_prompt` contains only `[EXPLICIT]` instructions |
| Source | `src/deriver/deriver.py:36-46` — `@with_sentry_transaction("minimal_deriver_batch")`, `process_representation_tasks_batch` |
| Source | `src/deriver/deriver.py:86-87` — `reasoning.enabled` short-circuit |
| Source | `src/deriver/deriver.py:144-163` — single `honcho_llm_call` with `PromptRepresentation` response model |
| Source | `src/deriver/deriver.py:185-222` — Representation conversion + per-observer save loop |
| Source | `src/deriver/deriver.py:266-284` — token-breakdown invariant warnings |
| Source | `src/deriver/deriver.py:287-317` — `RepresentationCompletedEvent` emission |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Claim/source mismatch.** Docs frame the deriver as producing both explicit and deductive observations. Source produces only explicit. The `DeductiveObservation` schema exists and is read at `deriver.py:233`, but the production prompt never asks for deductive output. See `04-assessment.md §A8` for the load-bearing finding and cross-cutting implications.
- **"Single LLM call" is genuinely single.** No loop, no retry-with-different-prompt, no tool-augmented refinement. Three internal retry attempts on transient failure (`enable_retry=True, retry_attempts=3`), but logically one extraction call.
- **Custom-model claim is configuration-time, not architectural.** The deriver uses `settings.DERIVER.MODEL_CONFIG`, a generic per-call model setting. Custom models (e.g. Neuromancer XR) are an available choice, not a wired-in dependency.
- **Sentry transaction wrapping** (`@with_sentry_transaction("minimal_deriver_batch", op="deriver")`) means every batch is traceable end-to-end. See `04-assessment.md §A16`.

## Configuration surface

| Knob | Default | Source |
|---|---|---|
| `DERIVER.MAX_INPUT_TOKENS` | `25000` (hard-capped) | `src/config.py:759` |
| `DERIVER.MODEL_CONFIG` | configurable | `src/config.py` (deriver section) |
| `DERIVER.LOG_OBSERVATIONS` | `False` | `src/config.py:761` |
