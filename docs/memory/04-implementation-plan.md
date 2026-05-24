# Implementation Plan — Deferred Memory Work

Session: 2026-05-24
Status: Scaffolding only. Two work units (DEFERRED-01, DEFERRED-02)
captured for future sessions where the user can be in the loop on
cost/triage calibrations.

This document is intentionally light. The audit and design-decision
documents (02, 03) hold the *why*; this file holds the *when*
and *what unblocks each item*.

---

## Completed this session (2026-05-24)

```
ID     DESCRIPTION                                STATUS
─────────────────────────────────────────────────────────
EXEC-1 Slim MEMORY.md from 99% → 40% (2,941     ✓ DONE
       → 1,209 chars) by demoting procedural
       content to existing skill references
EXEC-2 File 11 Honcho conclusions to bootstrap   ✓ DONE
       profile (goal A3 ≥10 conclusions)
EXEC-3 Verify memory_char_limit/user_char_limit  ✓ DONE
       at recommended 3000/2000
EXEC-4 Verify Honcho dialecticDepth=2 (already   ✓ DONE
       at power-user floor)
EXEC-5 Document decisions in 03-design-          ✓ DONE
       decisions.md (DD-01 through DD-08)
```

---

## DEFERRED-01 — Honcho server-side cadence tuning

**Goal addressed:** A6 (dialectic produces ≥2 substantive multi-fact
syntheses in 10 mixed-topic sessions).

**What's queued:** Four cadence/budget settings in `honcho.json` to
align with skill-ref power-user recommendations:

```
KNOB                  CURRENT  RECOMMENDED  COST IMPLICATION
────────────────────────────────────────────────────────────────
sessionStrategy       per-      per-repo    nil — pure scoping
                      session                strategy change
contextCadence        5         1           ~5× more context
                                              refreshes per session
dialecticCadence      10        3           ~3.3× more dialectic
                                              firings per session
contextTokens         2000      1200        nil — reduces injection,
                                              not cost
(add) dialecticMaxChars  unset  1000        nil — output budget per
                                              dialectic block
```

**What unblocks this:** A short cost/latency budgeting decision:
- "How much extra LiteLLM spend per Hermes session is OK for richer
  recall?"
- "Is `per-repo` or `per-session` the right scoping unit for apnex's
  workflow?" (apnex works across multiple repos, sometimes in the same
  session — both are defensible.)

**Suggested rollout sequence (one knob per session):**

```
SESSION  CHANGE                              LOG/MEASURE
──────────────────────────────────────────────────────────────────
1        contextTokens 2000 → 1200            injection size,
                                                synthesis quality
2        dialecticMaxChars  → 1000            output substance
3        sessionStrategy → per-repo           recall coherence
4        dialecticCadence  10 → 3             firing rate, latency,
                                                cost delta
5        contextCadence    5 → 1              context freshness vs.
                                                cost
```

**Rollback criterion (any session):** P95 user-facing latency
increases >25%, OR LiteLLM daily cost increases >2×, OR dialectic
synthesis quality measurably degrades. Revert the most recent change.

---

## DEFERRED-02 — Observation cleanup pass

**Goal addressed:** A4 (signal-to-noise ratio in observation log:
<3 noise entries in last 20).

**What's queued:** Manual triage + selective deletion of observation
entries via Honcho REST API.

**Why deferred:**
- Defining "noise" requires apnex's input — what looks like noise to
  the agent might be triangulation data for dialectic synthesis.
- `honcho_conclude(delete_id=...)` only handles conclusions; raw
  observation deletion requires direct REST API calls.
- Risk of regret if deleted observations would have contributed to
  later synthesis once cadence is tuned (DEFERRED-01).

**What unblocks this:**
1. DEFERRED-01 lands first (so we know dialectic is using
   observations well).
2. Two weeks of post-DEFERRED-01 operation to establish a noise
   baseline.
3. Then a one-off manual triage: list observations, sort by
   semantic value, apnex approves a delete batch.

**Implementation sketch (when ready):**

```bash
# List observations for the apnex peer
curl -sS http://192.168.1.250:8000/v3/workspaces/hermes/peers/apnex/observations | \
  jq '.[] | {id, content, created_at}' | less

# Delete one (selective)
curl -sS -X DELETE \
  http://192.168.1.250:8000/v3/workspaces/hermes/peers/apnex/observations/$ID
```

(API path verified against Honcho v3 source; double-check on the day
of execution.)

---

## DEFERRED-03 — Habit verification: are we keeping the conclude cadence?

**Goal addressed:** A3 (≥10 active conclusions, growing over time).

**What's queued:** After 2-3 weeks of operation, check the conclusion
count. If it hasn't grown beyond the initial 11, the per-exchange
cadence isn't being kept and we need a mechanism (USER.md rule,
agent-side reminder, or post-session ritual).

**What unblocks this:** Just time. Self-checking task.

---

## Out-of-scope (explicitly not planned)

- **Switching memory providers.** DD-01 settled this; revisit only if
  the OpenViking user-modeling layer materially matures.
- **Creating `apnex-cluster` skill.** DD-02 settled this; existing
  skills cover the surface.
- **Upstreaming subagent memory opt-in.** DD-08 settled this; the
  Hermes team is already tracking it.
- **Bumping `memory_char_limit` above 3000.** Skill ref is explicit
  this is misuse; we have 60% headroom now.
