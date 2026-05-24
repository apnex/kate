# Feature: minimal-deriver

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Derivation
**Triangulation:** ⚠ Partially triangulated — claim of "explicit → deductive scaffolding" does NOT match source; the production deriver extracts explicit observations only

## What it is (substrate's own terms)

The minimal deriver is Honcho's per-batch observation-extraction subsystem. For each batch of messages from an observed peer, it makes **one LLM call** with a structured-output schema (`PromptRepresentation`), parses the response into `Representation` objects, and hands them to `RepresentationManager` for collection writes.

The file is explicit about its scope (`src/deriver/prompts.py` lines 1-6):
> *"Minimal prompts for the deriver module optimized for speed. … focused only on observation extraction. NO peer card instructions, NO working representation - just extract observations."*

## Requirement

The system SHALL, for each batch of messages enqueued for representation derivation, invoke a single configured LLM with a structured-output prompt requesting atomic factual observations about the observed peer, parse the structured response, and save the resulting observations to all relevant observer collections.

## Scenarios

### Scenario: batch produces observations via one LLM call
- GIVEN a batch of messages from `peer_alice` with `reasoning.enabled = true` in the resolved configuration
- WHEN `process_representation_tasks_batch` is invoked
- THEN `messages` are sorted by `id`, formatted via `format_new_turn_with_timestamp`
- AND `minimal_deriver_prompt(peer_id=alice, messages=…)` is constructed
- AND **exactly one** `honcho_llm_call` is made with `response_model=PromptRepresentation`, `json_mode=True`, `max_input_tokens=settings.DERIVER.MAX_INPUT_TOKENS`, `enable_retry=True`, `retry_attempts=3`
- AND the parsed response is converted to a `Representation` and saved to each observer collection

### Scenario: reasoning disabled short-circuits
- GIVEN the resolved configuration has `reasoning.enabled = false`
- WHEN `process_representation_tasks_batch` is invoked
- THEN the function returns immediately without any LLM call

### Scenario: deriver emits only EXPLICIT observations
- GIVEN any input messages
- WHEN `minimal_deriver_prompt` is rendered
- THEN the prompt contains ONLY `[EXPLICIT]` extraction instructions
- AND contains NO `[DEDUCTIVE]` premises-to-conclusion instructions
- AND contains NO peer-card instructions
- AND the resulting `Representation.deductive` list is consequently empty in the normal path

### Scenario: telemetry captures every batch
- GIVEN any batch processed (regardless of observation count)
- THEN a `RepresentationCompletedEvent` is emitted carrying: workspace, session, observed peer, queue items processed, message id range, message count, explicit conclusion count, context-prep ms, LLM-call ms, total ms, input/output tokens, batch-cap and input-cap snapshots, observer count
- AND Prometheus metrics record deriver tokens when `settings.METRICS.ENABLED`

### Scenario: token-breakdown invariants are validated
- GIVEN the LLM response reports `input_tokens` and the batcher computed `messages_tokens`
- WHEN `response.input_tokens < messages_tokens`
- THEN a warning is logged citing "provider tokenization drift or wrong messages_tokens computation"
- AND when `prompt_tokens <= 0`, a warning is logged citing "estimate_deriver_prompt_tokens may have failed silently"

## Evidence

| Type | Reference |
|---|---|
| Claim | `CLAUDE.md` §Deriver — "the current architecture is 'minimal deriver' — a single LLM call per batch using structured output, not an agentic tool loop" |
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` §Formal Logic Framework — "explicit reasoning model … outputs … explicitly stated [facts], which serve as premises to scaffold deductive conclusions" |
| Doc | `docs/v3/documentation/core-concepts/reasoning.mdx` — example JSON shows `explicit` AND `deductive` lists populated |
| Source | `src/deriver/prompts.py:1-6` — file docstring stating scope is observation extraction ONLY |
| Source | `src/deriver/prompts.py:55-81` — `minimal_deriver_prompt` — only `[EXPLICIT]` instructions present |
| Source | `src/deriver/deriver.py:36-46` — `@with_sentry_transaction("minimal_deriver_batch")`, `process_representation_tasks_batch` signature |
| Source | `src/deriver/deriver.py:86-87` — `reasoning.enabled` short-circuit |
| Source | `src/deriver/deriver.py:144-163` — single `honcho_llm_call` with `PromptRepresentation` response model |
| Source | `src/deriver/deriver.py:185-222` — Representation conversion + per-observer save loop |
| Source | `src/deriver/deriver.py:266-284` — token-breakdown invariant logging |
| Source | `src/deriver/deriver.py:287-317` — `RepresentationCompletedEvent` emission |

## Behaviour notes (Tier 3 — prober analysis)

- **MAJOR claim/source mismatch.** `reasoning.mdx` describes the deriver as producing both explicit premises AND deductive conclusions in a scaffolded structure. **The minimal deriver code produces ONLY explicit observations.** The `DeductiveObservation` schema exists, and `Representation.deductive` is read at line 233, but the *production prompt* never asks for deductive output. Two possibilities:
  1. The deductive path lives in the **dreamer**, not the deriver — i.e. dreamer specialists do deductive/inductive reasoning over already-extracted explicit observations. (Best hypothesis; to be verified in feature `dreamer`.)
  2. The docs are stale — the architecture was simplified to "minimal deriver" and the docs haven't caught up.
  Either way, **for a new user reading the docs**, the description of the deriver's reasoning depth is misleading at this SHA.
- **"Neuromancer XR" claim is configuration-time, not architectural.** The deriver code uses `settings.DERIVER.MODEL_CONFIG` (`deriver.py:32-33`), a generic per-call model setting. A Honcho deployment may or may not configure Neuromancer XR as the deriver model. The custom-model claim is real, but it's an *available choice*, not a wired-in dependency.
- **Single LLM call is genuinely single.** Source confirms no loop, no retry-with-different-prompt, no tool-augmented refinement. Three internal retry attempts on transient failure (`enable_retry=True, retry_attempts=3`), but logically one extraction call.
- **Sentry transaction wrapping** (`@with_sentry_transaction("minimal_deriver_batch", op="deriver")`) means every batch is traceable in Sentry with its full LLM-call timing. Strong observability posture.
- **Implications for our system:** if we use Honcho purely via the deriver, the reasoning quality is "explicit extraction only" — the rich deductive/inductive/abductive language in the docs presumably maps to the dreamer. Tuning `dialecticDepth` and `reasoningLevel` won't affect this — they affect query-time reasoning, not write-time extraction.
