# Surprisal sampling

## §A Tier 1 — Claim

§A1 Surprisal sampling pre-filters observations for the dreamer by scoring each one against a tree built from the embedding set, then taking the top N% by score.

§A2 Pipeline (`sample_observations_with_surprisal`): fetch → extract embeddings → build tree → score → drop inf/nan → normalize min-max to [0,1] → rank desc → take top `TOP_PERCENT_SURPRISAL`.

§A3 Disabled by default (`DREAM.SURPRISAL.ENABLED=False`); when off, the dreamer runs specialists over the unfiltered observation set.

§A4 Seven tree backends behind a single `SurprisalTree` interface, selected by `TREE_TYPE`: `kdtree`, `balltree`, `rptree`, `covertree`, `lsh`, `graph`, `prototype`. Factory `create_tree(tree_type, **kwargs)` dispatches.

§A5 `kdtree` and `balltree` wrap scikit-learn via `SklearnTreeWrapper`; `rptree`, `covertree`, `lsh`, `graph`, `prototype` are first-party implementations under `src/dreamer/trees/`.

§A6 Three sampling strategies for selecting the candidate observation pool (`SAMPLING_STRATEGY`): `recent` (default — `created_at DESC`), `random` (Postgres `ORDER BY random()`), `all` (cap-bounded `created_at DESC`). Unknown values fall back to `recent` with a warning.

§A7 Per-observation surprisal is computed by `tree.surprisal(embedding)` — interpretation is "geometric novelty of the point given the existing tree structure". The exact metric is tree-specific.

§A8 Level filter (`INCLUDE_LEVELS`, default `["explicit", "deductive"]`) restricts the candidate pool. Inductive observations are excluded by default to prevent self-reinforcement.

§A9 Minimum-observations gate: if `len(observations) < TREE_K * 2`, the function returns `[]` without computing — the tree has insufficient data for meaningful scoring.

§A10 Invalid scores (`inf`/`nan`) are filtered between scoring and normalization with a WARNING log; partial results are kept.

§A11 Identical-score degenerate case (max == min after scoring): all scores are set to 0.5 rather than dividing by zero.

§A12 Filter floor: `_filter_by_percent` always returns at least one observation (`max(1, int(len(scores) * top_percent))`) — surprisal sampling never returns empty when input is non-empty and passes the gates.

§A13 Top-level error handler catches any exception and returns `[]`, logging full trace. Dream continues without surprisal-informed observations.

§A14 Hybrid-mode hint: `MIN_HIGH_SURPRISAL_FOR_REPLACE` (default 10) governs downstream dreamer behaviour — whether high-surprisal observations replace standard questions in specialist prompts.

## §B Tier 2 — Source

§B1 `src/dreamer/surprisal.py:1-7` — module docstring (geometric surprisal, tree-based, targeted deductive reasoning on anomalous observations).

§B2 `src/dreamer/surprisal.py:27-43` — `ObservationData`, `SurprisalScore` dataclasses.

§B3 `src/dreamer/surprisal.py:46-172` — `sample_observations_with_surprisal` (full pipeline including §A2, §A9-A13).

§B4 `src/dreamer/surprisal.py:175-233` — `_fetch_observations` strategy dispatch (§A6).

§B5 `src/dreamer/surprisal.py:236-269` — `_fetch_recent_observations`.

§B6 `src/dreamer/surprisal.py:272-309` — `_fetch_random_observations` (`func.random()`).

§B7 `src/dreamer/surprisal.py:312-351` — `_fetch_all_observations`.

§B8 `src/dreamer/surprisal.py:354-370` — `_extract_embeddings`.

§B9 `src/dreamer/surprisal.py:373-394` — `_build_tree`.

§B10 `src/dreamer/surprisal.py:397-426` — `_compute_surprisal_scores`.

§B11 `src/dreamer/surprisal.py:429-470` — `_normalize_scores` (min-max, identical-score fallback §A11).

§B12 `src/dreamer/surprisal.py:473-492` — `_filter_by_percent` (top-N% with floor §A12).

§B13 `src/dreamer/trees/__init__.py:17-47` — `create_tree` factory (§A4).

§B14 `src/dreamer/trees/base.py` — `SurprisalTree` abstract base, node types.

§B15 `src/dreamer/trees/sklearn_wrapper.py` — `kdtree` / `balltree` wrapping scikit-learn.

§B16 `src/dreamer/trees/{rptree,covertree,lsh,graph,prototype}.py` — first-party tree implementations (157/114/84/128/97 LOC respectively).

§B17 `src/config.py:1105-1128` — `SurprisalSettings`: `ENABLED`, `TREE_TYPE`, `TREE_K`, `SAMPLING_STRATEGY`, `SAMPLE_SIZE`, `TOP_PERCENT_SURPRISAL`, `MIN_HIGH_SURPRISAL_FOR_REPLACE`, `INCLUDE_LEVELS`.

## §C Tier 3 — Analytical

§C1 **Tree-type choice is unconstrained at the spec level.** Seven backends are exposed via a string enum in config; the spec does not prescribe a default for production use beyond `kdtree`. Each tree has different cost/quality trade-offs (LSH approximate, cover tree exact-metric, RP randomized) — operators tune blind unless they read the source.

§C2 **Scoring metric is delegated to each tree implementation.** `tree.surprisal(embedding)` is a polymorphic contract, not a uniform formula. "Geometric surprisal" is therefore a substrate-level claim, not an algorithmic one — what counts as surprising varies by `TREE_TYPE`.

§C3 **DB connection scope is short by design.** Comments on line 71 highlight that `tracked_db` closes before the compute phase begins; the embedding-to-score pipeline runs without holding a DB connection. This matters for connection-pool pressure during long surprisal runs.

§C4 **Sampling strategy biases the tree.** `recent` builds a tree over the latest N observations and thus reports novelty relative to recent history; `random` reports novelty relative to a uniform sample of all-time observations; `all` (cap-bounded) approximates `recent` once the population exceeds the cap. Switching strategy changes what "surprising" means without changing any other knob.

§C5 **Excluding inductive observations is a feedback-loop guard.** Same shape as `check_and_schedule_dream` counting only explicit documents (see `features/dream-scheduler.md` §A4): dreamer output should not seed dreamer input.

§C6 **Failures fail open.** §A13's blanket-catch ensures a broken tree backend or bad embedding does not block dreaming — it merely degrades dreaming to unfiltered mode. Operators relying on surprisal-driven prioritisation get silent fallback rather than visible failure.

§C7 **Min-observations gate is `TREE_K * 2`.** With default `TREE_K=5`, surprisal needs ≥10 candidate observations to activate. Fresh peers will run dreams without surprisal regardless of `ENABLED`.

§C8 **Top-N% with `max(1, …)` floor.** With `TOP_PERCENT_SURPRISAL=0.10` and 5 observations, `int(5*0.10)=0` → floor returns 1. Surprisal therefore always contributes ≥1 observation once the min-observations gate clears.

§C9 **Normalisation is purely cosmetic for ranking.** Sorting by raw vs normalized surprisal produces identical ordering; min-max normalization to [0,1] exists for prompt-side legibility (specialist prompts show normalized scores to the LLM), not for filtering correctness.
