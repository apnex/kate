# Feature: dreamer

**Substrate:** honcho v3.0.7 (SHA `7470866`)
**Category:** Derivation
**Triangulation:** ✓ Triangulated

## What it is

The dreamer is Honcho's asynchronous higher-order reasoning subsystem. Where the deriver does cheap, fast explicit extraction (`features/minimal-deriver.md`), the dreamer runs slower, optionally surprisal-informed reasoning passes that produce **deductive** and **inductive** observations referencing their explicit-observation premises via `source_ids`. A dream cycle is orchestrated by `run_dream`, which runs two specialists sequentially: `DeductionSpecialist` then `InductionSpecialist`. Specialists are self-directed agents — given the observation space (optionally hint-filtered by geometric surprisal), they explore freely and write back higher-order observations.

## Requirement

The system SHALL provide an asynchronous dream-cycle orchestrator that, per `(workspace, observer, observed, session?)` scope, optionally pre-filters observations by geometric surprisal and then runs deduction and induction specialists to produce higher-order observations linked back to their premise observations via `source_ids`.

## Scenarios

### Scenario: full dream cycle runs both specialists
- GIVEN `settings.DREAM.ENABLED = true` AND `configuration.dream.enabled = true`
- WHEN `run_dream` is invoked
- THEN the deduction specialist runs first
- AND the induction specialist runs second
- AND a `DreamRunEvent` is emitted with `specialists_run`, success flags, surprisal stats, total iterations, duration, token counts

### Scenario: dream skipped when disabled at workspace or session level
- GIVEN `settings.DREAM.ENABLED = false`
- WHEN `run_dream` is invoked
- THEN no specialists run
- AND `None` is returned (no DreamResult)

### Scenario: dream skipped when configuration disables it per-session
- GIVEN global `DREAM.ENABLED = true` but resolved session `configuration.dream.enabled = false`
- WHEN `run_dream` is invoked
- THEN no specialists run
- AND a log message records "Dreams disabled for {workspace}/{session}"

### Scenario: surprisal sampling pre-filters observations when enabled
- GIVEN dream config with surprisal sampling enabled
- WHEN `run_dream` runs
- THEN `sample_observations_with_surprisal` is called BEFORE specialists
- AND observations are scored by geometric surprisal using tree-based embeddings
- AND high-surprisal observations are passed to specialists as hints
- AND the surprisal count and enabled flag appear on the DreamResult

### Scenario: deduction specialist writes deductive observations with provenance
- GIVEN the deduction specialist runs
- THEN any persisted observations have `level='deductive'`
- AND each observation's `source_ids` field references explicit observations it was derived from

### Scenario: induction specialist writes inductive observations with provenance
- GIVEN the induction specialist runs
- THEN any persisted observations have `level='inductive'`
- AND each observation's `source_ids` field references the explicit observations the pattern was inferred from

### Scenario: dream cycle does not hold a DB connection
- GIVEN a running dream cycle
- WHEN specialists are calling the LLM
- THEN no DB session is held open during the LLM call
- AND DB sessions open per-operation via `tracked_db`

## Evidence

| Type | Reference |
|---|---|
| Claim | `docs/v3/documentation/core-concepts/reasoning.mdx` — references higher-order reasoning |
| Claim | `CLAUDE.md` §Dreamer — describes background reasoning |
| Doc | `src/dreamer/orchestrator.py:1-12` — file docstring describing the cycle: "0. [Optional] Surprisal sampling … 1. Run deduction specialist … 2. Run induction specialist" |
| Doc | `src/dreamer/orchestrator.py:79-94` — `run_dream` docstring with cycle steps |
| Source | `src/dreamer/orchestrator.py:67-77` — `run_dream` signature |
| Source | `src/dreamer/orchestrator.py:95-96` — early return on `DREAM.ENABLED=false` |
| Source | `src/dreamer/orchestrator.py:117-120` — per-session config short-circuit |
| Source | `src/dreamer/orchestrator.py:106-116` — short-lived DB session for config resolution |
| Source | `src/dreamer/orchestrator.py:44-64` — `DreamResult` dataclass (run_id, specialists_run, success flags, surprisal stats, iterations, duration, tokens) |
| Source | `src/dreamer/specialists.py:74` — `BaseSpecialist(ABC)` |
| Source | `src/dreamer/specialists.py:429` — `class DeductionSpecialist(BaseSpecialist)` |
| Source | `src/dreamer/specialists.py:613` — `class InductionSpecialist(BaseSpecialist)` |
| Source | `src/dreamer/specialists.py:29` — `SPECIALISTS` list exported |
| Spec | `features/surprisal.md` — full pipeline, seven tree backends, sampling strategies, config surface |

## Behaviour notes (Tier 3 — scoped to this feature)

- **Surprisal is a separable mechanism.** Promoted to its own spec at `features/surprisal.md`. The dreamer-level claim is only that surprisal can pre-filter observations before specialists run; the algorithm, tree backends, sampling strategies, and config block live in the surprisal spec.
- **Two specialists, not three or four.** No abductive specialist class exists at this SHA. Schema-extensible (the InductiveObservation/DeductiveObservation hierarchy could accommodate an AbductiveObservation; a third specialist class would follow the BaseSpecialist contract). Confirms A11.
- **Specialists are "self-directed agents"**, not single LLM calls. They iterate over the observation space, can fetch context, and write multiple observations per run (`total_iterations` field on DreamResult). Cost model is materially different from the minimal deriver.
- **Surprisal hints don't constrain specialists.** Per orchestrator docstring line 11: "specialists are free to follow the evidence wherever it leads." Surprisal informs but doesn't dictate. Tunable bias toward novelty, not hard filter.
- **The deriver/dreamer separation is the load-bearing reasoning architecture.** Deriver = cheap explicit extraction at message cadence. Dreamer = expensive informed reasoning at trigger cadence (driven by `check_and_schedule_dream` and surprisal). See `04-assessment.md §A8` (now fully resolved) and `§A29` for the cadence-and-cost split.
- **DB-connection-free execution mirrors dialectic** (A24) — supports high-concurrency scenarios.

## Configuration surface

| Knob | Default | Source |
|---|---|---|
| `DREAM.ENABLED` | configurable | `src/config.py` |
| `DREAM.SURPRISAL.*` (threshold, top_n, min_obs) | configurable | `src/config.py` |
| `DREAM.SPECIALIST_MODEL_CONFIG` (per-specialist) | configurable | `src/config.py` (per `_require_specialist_model_config:43`) |
| Per-session `configuration.dream.enabled` | true if workspace enabled | `src/utils/config_helpers.py` |
