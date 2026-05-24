# Memory System Design Decisions

Session: 2026-05-24
Status: Initial decision set captured. Subject to revision based on
operational outcomes over the next 2–3 weeks.

This document records the *why* behind concrete changes made to the
Hermes memory system. It pairs with `02-research-findings.md` (the
investigation that produced the option set) and `04-implementation-plan.md`
(deferred work queued from this session).

---

## DD-01 — Stay on Honcho

**Decision:** Continue using Honcho as the memory provider. Do not
evaluate alternatives further at this time.

**Why:**
- Of the eight in-tree memory providers shipped by Hermes, only Honcho,
  OpenViking, and Holographic are self-hostable. Holographic is
  primitive (single-machine SQLite + FTS5, no user-modeling).
  OpenViking is credible but has less mature user-modeling and is
  AGPL-3.0 licensed.
- The 5-layer architecture itself is provider-agnostic — the
  `MemoryProvider` ABC at `agent/memory_provider.py` is the
  portability seam. If we ever need to switch, it's a config swap +
  re-ingest, not a rewrite. G7 (portability) is structurally
  satisfied today.
- Honcho is the deepest AI-native option AND self-hostable AND already
  deployed and working. The cost of switching is real; the upside is
  not.

**Confidence:** High.

**Revisit when:** OpenViking matures its user-modeling layer, or
Honcho upstream stagnates for >6 months.

---

## DD-02 — Reuse existing skills; do NOT create `apnex-cluster`

**Decision:** All procedural content currently in MEMORY.md is
demoted to references in the existing `honcho-self-host-k3s` and
`hermes-agent` skills, not into a new `apnex-cluster` umbrella.

**Why:**
- Pre-execution recon revealed that `honcho-self-host-k3s` already
  covers ~95% of our Honcho-side procedural content, including the
  MetalLB shared-VIP convention, ConfigMap env-var schema, Argo
  selfHeal secret pitfall, and cold-start initContainer pattern.
- `hermes-agent/references/k3s-deployment.md` already covers the
  LiteLLM Cloud Run terraform.tfvars apply chain, the ADC gotcha, the
  linger/pulse-socket race, the ConfigMap-rendered Hermes config
  pattern, and the `memory_char_limit` tuning guide.
- Creating a new `apnex-cluster` umbrella would have duplicated
  content already curated by upstream Hermes. The skill curator's
  own guidance ("If multiple narrow skills cover overlapping ground,
  propose consolidation… don't create a new umbrella for one-session
  artifacts") explicitly warns against this.
- Result: zero new skill files, but MEMORY.md still drops to ~40%
  fullness because the existing skill content was authoritative.

**Confidence:** High. Verified by inspection of both skill files
before execution.

**Side note:** Future apnex-specific content that genuinely doesn't
fit existing umbrellas (e.g. apnex's personal workstation patterns,
home network conventions) may warrant a fresh skill. None such was
found in the current MEMORY.md.

---

## DD-03 — Pin the canonical decision tree as the single source of truth

**Decision:** Defer to `hermes-agent/references/memory-architecture.md`
as THE prescriptive reference for "what belongs where." No local
decision-tree document is written. Kate's role is to record
deployment-specific decisions, not to mirror upstream doctrine.

**Why:**
- The skill ref is exquisitely good and matches our exact failure
  mode line-for-line. Its worked example (LiteLLM TF detail at ~700
  chars in MEMORY.md as the canonical "do NOT put this here") is
  literally our deployment.
- Mirroring it into kate creates a drift surface (which copy is
  authoritative when the upstream skill updates?).
- The decision tree itself is short enough that loading the skill on
  demand has negligible cost.

**How it's enforced:** A pointer entry in MEMORY.md tells future
sessions to load the skill before writing to in-prompt memory.

**Confidence:** High.

---

## DD-04 — Cadence: 1 honcho_conclude per meaningful exchange

**Decision:** Adopt the documented "one distilled conclusion per
meaningful exchange" cadence. Initial batch of 11 conclusions filed
this session to bootstrap the profile from existing observation
chatter and USER.md content.

**Why:**
- Goal A3 sets the target at ≥10 active conclusions. Pre-session
  count was ~1, and the audit identified this as a top-three misuse.
- Conclusions cost zero per-turn tokens (retrieved on demand), so
  filing them aggressively is asymmetric upside.
- The conclude discipline is the most direct mechanism for offloading
  evergreen profile facts out of USER.md (which has a per-turn cost).

**What gets concluded vs. what stays in USER.md:**
- USER.md: per-turn behavioural rules the agent must always know
  (tone, format, action-first execution discipline).
- Honcho conclude: profile facts, distilled preferences, stable
  patterns retrievable when relevant (workflow norms, infra
  philosophy, tooling biases).

**Confidence:** High for the direction; MED for whether the agent
reliably keeps the cadence without nudging. Revisit in 2 weeks.

---

## DD-05 — Defer Honcho server-side cadence tuning

**Decision:** Do NOT change `honcho.json` cadence/contextTokens
settings this session. Queue as DEFERRED-01 in the implementation
plan.

**Why:**
- The audit found four cadence settings that deviate from skill-ref
  power-user recommendations (`sessionStrategy: per-session` vs.
  `per-repo`; `contextCadence: 5` vs. `1`; `dialecticCadence: 10`
  vs. `3`; `contextTokens: 2000` vs. `1200`). All four lean
  conservative (fewer LLM calls), not aggressive.
- Bumping `dialecticDepth` already happened (current: 2, recommended:
  2-3). That's the highest-leverage knob and it's already at the
  power-user floor.
- The remaining changes increase background LLM cost. Specifically:
  `dialecticCadence: 3` ≈ 3.3× more dialectic firings; `contextCadence: 1`
  ≈ 5× more context refreshes. Both deserve apnex's input on cost
  tolerance before applying.

**What's required to lift the deferral:** A short cost/latency
budgeting conversation, then a staged rollout (one knob at a time,
log before/after, roll back on regression).

**Confidence:** High that deferral is correct.

---

## DD-06 — Defer observation cleanup

**Decision:** Do NOT execute an observation purge this session. Queue
as DEFERRED-02.

**Why:**
- Goal A4 (signal-to-noise <3 noise entries in last 20) requires
  manual triage to define "noise" credibly.
- The Honcho REST API for raw observation deletion is the only path
  (the `honcho_conclude(delete_id=...)` tool only handles
  conclusions, per upstream issue #17968).
- Risk of deleting observations that retroactively turn out to
  have synthesis value if dialectic depth is later raised.

**Mitigation:** Track signal-to-noise informally over the next 2-3
sessions. If it stays >50% noise after dialectic depth tuning, then
do a manual triage pass.

**Confidence:** Medium. The deferral is conservative; risk is some
ongoing noise in dialectic outputs.

---

## DD-07 — Memory limits already at recommended values

**Decision:** No config change. Confirmed `memory_char_limit: 3000`
and `user_char_limit: 2000` are both at the documented power-user
recommended values.

**Why:**
- Audit recommendation #6 was to bump to these values. Pre-execution
  config inspection confirmed they were already set, likely during
  earlier sessions.
- The recommendation explicitly says: "DO NOT bump higher; the
  answer to 95%-full is skill-demotion." We're now at 40%/95%
  post-cleanup, well within healthy band.

**Confidence:** High.

---

## DD-08 — Document subagent isolation limitation; do NOT fight it

**Decision:** Subagent memory isolation (`skip_memory=True` hardcoded
at `tools/delegate_tool.py:1120`) is documented behaviour and aligns
with research-delegation use cases. For operational delegations,
restate critical context in the `context=...` field. No upstream PR
is pursued from this end.

**Why:**
- Issue #30269 tracks the upstream gap. The Hermes team has the same
  awareness; we don't need to push it.
- Our current delegations are research (Track B was a perfect example
  of why isolation is correct).
- Restating context is a 2-line discipline, not a structural problem.

**Confidence:** High.

---

## Cross-references

- `00-goals.md` — A1-A7 acceptance criteria these decisions address.
- `02-research-findings.md` — investigation that surfaced the options.
- `04-implementation-plan.md` — DEFERRED-01 (Honcho cadence) and
  DEFERRED-02 (observation cleanup) scaffolding.
- `hermes-agent/references/memory-architecture.md` — the canonical
  upstream reference (the source of truth this document defers to).
