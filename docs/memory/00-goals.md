# 00 — Memory System Goals

**Status:** Draft, pre-research
**Date:** 2026-05-24
**Author:** apnex + hermes

## Purpose

Define what "effective and efficient memory" means for this Hermes deployment
*before* we research solutions or commit to an architecture. Acceptance
criteria, not implementation choices.

## Context

apnex runs a single-user power-deployment of Hermes on a k3s NUC. Sessions
span days or weeks, often resuming infrastructure work across reboots and
context windows. The memory system today is a 4-layer stack:

1. Local `MEMORY.md` — in-prompt agent notes about the environment
2. Local `USER.md` — in-prompt agent notes about the user
3. Honcho server observations — raw event log
4. Honcho server conclusions — synthesized profile facts

Plus a 5th layer used inconsistently:

5. Hermes skills (`hermes-agent`, etc.) — load-on-demand procedural knowledge

## Symptoms of dysfunction (current)

- `MEMORY.md` reached 98% in one working session
- `USER.md` reached 95% after being bumped from a state where writes were
  silently dropped
- Honcho observations contain ~50% transcript-of-the-obvious noise
- Only 1 active Honcho conclusion despite weeks of meaningful exchange
- Procedural knowledge (LiteLLM TF location, MetalLB rules, boot hardening)
  crammed into in-prompt memory instead of skill references

These symptoms suggest **content is being filed at the wrong layer**, not
that the layers themselves are wrong.

## Goals — what good looks like

### G1 — Right content at the right layer

Every memory item has an obvious correct home. Test: pick a random fact
from any layer; can a fresh operator explain why it lives there and not
elsewhere?

### G2 — In-prompt memory stays under 70% headroom

`MEMORY.md` ≤ 2,100 / 3,000 chars in normal use.
`USER.md` ≤ 1,400 / 2,000 chars in normal use.

The remaining 30% is room for genuinely new evergreen facts to land
without immediate overflow pressure.

### G3 — Procedural knowledge lives in skills

Anything matching "if you need to do X, here's how" belongs in a skill
reference. Test: any runbook >300 chars in `MEMORY.md` is a smell.

### G4 — Honcho carries the long tail

Profile facts (preferences, environment, conventions, history) accumulate
in Honcho conclusions. Test: a fresh session should be able to recover
the user's working context purely via Honcho retrieval — `MEMORY.md` should
contain rules, not history.

### G5 — Observation discipline

Honcho observations should be high-signal. Test: random sample of 10
recent observations; ≥7 should be facts a future-me would benefit from
knowing.

### G6 — Cross-session continuity

Resuming work after a 1-week gap should require zero re-stating of:
- environment topology
- workflow preferences
- past architectural decisions
- in-progress projects (via Honcho recall, not local memory)

### G7 — Provider portability

Memory architecture should not be Honcho-shaped to the point that swapping
to another provider would require a rewrite. Conclusions, observations, and
queryable profile are universal concepts; how we organise them should be too.

### G8 — Subagent memory isolation

Subagents should not pollute Honcho with research-process noise. Briefings
flow IN, summaries flow OUT, intermediate chatter stays in the subagent.

### G9 — Operator legibility

Future-apnex (or another operator) can read `kate/docs/memory/` and
understand the why, not just the what. No tribal knowledge.

## Non-goals

- Multi-tenant memory (single user, single Hermes instance)
- Real-time memory replication across nodes (one NUC, no HA)
- Memory encryption beyond what Honcho/Postgres already provide
- Cross-provider memory federation (we pick one provider and own it)

## Acceptance criteria (measurable)

| # | Criterion | Test |
|---|---|---|
| A1 | MEMORY.md ≤ 2100 chars sustained over 5 sessions | manual char count |
| A2 | USER.md ≤ 1400 chars sustained over 5 sessions | manual char count |
| A3 | ≥10 active Honcho conclusions | `honcho_profile` returns ≥10 facts |
| A4 | <3 transcript-noise observations in last 20 | manual sample review |
| A5 | All cluster runbooks accessible via skill | `skills_list` shows them |
| A6 | New session recovers context in ≤3 exchanges | timed observation |
| A7 | Provider swap would be doc-update + config-swap | thought experiment |

## Open questions for research

These drive the Track B research brief:

- Q1: What memory layers does Hermes canonically expose? Have we missed any?
- Q2: What memory providers does Hermes ship besides Honcho? Tradeoffs?
- Q3: Are there documented best-practice patterns from the Hermes team?
- Q4: How do subagents interact with memory by design?
- Q5: What Honcho features are we underusing (cadences, strategies, peer cards)?
- Q6: How do other power-user Hermes deployments handle this?
- Q7: What's the recommended discipline for observation vs. conclusion?
- Q8: Is the 4-layer mental model the canonical one, or is there a better frame?

## Definition of done (for this whole effort)

This goals doc is "done" when:
- Track B research is complete and findings are documented
- Design decisions are recorded in `docs/decisions/`
- Implementation plan is executed
- All A1–A7 criteria are met for at least 2 consecutive sessions
- Changelog has at least one post-implementation tuning entry
