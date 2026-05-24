# 02 — Memory Research Findings

**Status:** Subagent investigation complete
**Date:** 2026-05-24
**Author:** Hermes Research Subagent (Track B)
**Inputs:** `01-research-brief.md`, `00-goals.md`
**Scope:** Read-only investigation; no code/config changes proposed for action by this report — only recommendations.

---

## Executive summary

1. **The 4+1-layer mental model is canonical.** The Hermes team's own
   `hermes-agent` skill ships a dedicated reference,
   `references/memory-architecture.md`, that names exactly the same five
   layers we already use (MEMORY.md, USER.md, Honcho observations, Honcho
   conclusions, skills) and the same discipline (procedural →
   skills, profile → conclusions, evergreen rules → in-prompt). **Our
   mental model is correct; our content placement is the broken part.**
2. **The "fill, then bump char limit" reaction is the documented
   anti-pattern.** Both the skill reference and merged PR #22781 explicitly
   warn against treating bigger MEMORY.md as a power-user signal —
   the canonical fix is **demote procedural detail to a skill**, not
   raise the ceiling. Issue #5320 is the *only* upstream voice asking
   for auto-scaling, and it's still open with no merge in sight.
3. **Honcho is the canonical "long tail" layer and we are dramatically
   under-tuning it.** We're sitting at near-defaults (`dialecticDepth: 1`,
   probably default cadences, `recallMode` unknown) while the docs treat
   `dialecticDepth`, `dialecticCadence`, `contextCadence`,
   `dialecticReasoningLevel`, and `sessionStrategy` as three orthogonal
   knobs power-users are expected to set deliberately. Default cold-start
   prewarm at depth 1 is documented as "often thin output."
4. **Honcho conclusion underuse is the dominant content-discipline
   failure** (G4/A3 in goals doc). The team's reference calls out exactly
   our symptom: "1-2 conclusions after weeks → `honcho_conclude` is
   being underused; useful facts are falling through the cracks." The
   prescribed cadence is **one conclusion per meaningful exchange**, not
   per session.
5. **Subagent memory isolation is a known, hardcoded, open-bug behaviour
   (#30269).** `tools/delegate_tool.py:1120` hardcodes `skip_memory=True`
   with no opt-out. For our use case (research subagents) this is *correct
   behaviour* — but for delegations that need user preferences, the only
   fix today is `context=` forwarding. Cron has the same hardcoding
   (#9763) and the same workaround.

The TL;DR: our **architecture is right, our knobs are wrong, and our
content discipline is the actual fix.** A handful of config changes
plus a documented "what goes where" decision tree will land all of A1–A7.

---

## Canonical architecture (as documented)

### Source-of-truth files

| Source | Path | Authority |
|---|---|---|
| Hermes team skill ref | `~/.hermes/skills/.../hermes-agent/references/memory-architecture.md` | Highest — published by Hermes team, designed for exactly this question |
| Built-in memory doc | `/opt/hermes/website/docs/user-guide/features/memory.md` | High — official public docs |
| Memory providers doc | `/opt/hermes/website/docs/user-guide/features/memory-providers.md` | High |
| Honcho feature doc | `/opt/hermes/website/docs/user-guide/features/honcho.md` | High |
| Honcho plugin README | `/opt/hermes/plugins/memory/honcho/README.md` | High — config reference of record |
| Context engine ref | `hermes-agent/references/context-engine-and-external-brain.md` | Medium — design-pattern, not prescriptive |
| Plugin dev guide | `/opt/hermes/website/docs/developer-guide/memory-provider-plugin.md` | Medium — only relevant for portability test |

### The five layers (verbatim from the skill reference)

```
LAYER              WHERE                  WHAT                        SIZE
1. MEMORY.md       ~/.hermes/             agent's notes about         3,000 chars
   (in-prompt)                            environment
2. USER.md         ~/.hermes/             agent's notes about         2,000 chars
   (in-prompt)                            user
3. Honcho obs.     Postgres               raw event log               unbounded
4. Honcho concl.   Postgres               synthesized profile facts   unbounded
5. Skills          ~/.hermes/skills/      procedural knowledge,       unbounded,
                                          load-on-demand              ZERO per-turn cost
```

The decision tree (paraphrased from the skill ref):

```
USER preference?
  per-turn behavioural rule? → USER.md
  profile fact / pattern?    → honcho_conclude

ENVIRONMENT fact?
  needed every turn?         → MEMORY.md
  procedural ("to do X...")? → Skill reference

CLASS of task / runbook?     → Skill (umbrella or reference)

TRANSIENT (PRs, today's work)? → NOWHERE (session_search recovers)
```

### Discipline rules the docs codify

- **"Frozen snapshot pattern"** — built-in memory is read once at session
  start to preserve prefix cache; new writes don't appear until next
  session (`features/memory.md` line 47).
- **Honcho injects into the user message, not the system prompt**, also
  for cache preservation (`honcho/README.md` line 29). Mode header in
  system prompt is the only static bit.
- **`honcho_conclude` discipline:** file ONE distilled fact per
  meaningful exchange, not chatter (memory-architecture.md, "The Honcho
  Conclude Discipline" section).
- **Cron and delegated subagents both ship with `skip_memory=True`
  hardcoded** — this is a deliberate choice for context isolation, but
  it's a footgun if you didn't know (delegate_tool.py:1120,
  cron/scheduler.py L748, issue #9763, #30269).

---

## What we're doing right

| Goal | Status | Evidence |
|---|---|---|
| Using the canonical 5-layer model | ✅ Match | Our layers map 1:1 to the documented architecture |
| Self-hosted Honcho in k3s | ✅ Aligned with "sovereign infra" constraint | `context-engine-and-external-brain.md` explicitly documents self-host as the production path |
| Profile (single-tenant) setup | ✅ Match | `sessionStrategy: per-directory` is the documented default for single-user |
| Skills layer in active use | ✅ Match | We have `hermes-agent` loaded, planning `apnex-cluster` — exactly the demotion target the team prescribes |
| Workspace + AI peer per profile | ✅ Honcho-canonical | `honcho.md` line 31 "multi-agent profiles" describes our pattern |
| Honcho as provider, NOT as toolset | ✅ Correct | The k3s-deployment skill ref calls out `memory.provider: honcho` is the right place, NOT a toolset entry |

**Don't change any of the above.**

---

## What we're doing wrong

### Misuse 1 — Procedural detail in in-prompt memory

Symptom: MEMORY.md at 98%, USER.md at 95% (just bumped from 1,375).

Evidence: This is the *exact failure mode* `memory-architecture.md`
addresses by name, line-by-line. The skill ref's "Worked example" cites
LiteLLM proxy detail (TF repo location, ADC path, fallback chain) as
"~700 chars of procedural detail that all belongs in a skill ref, not
MEMORY.md." That worked example is almost certainly ours.

Anti-pattern we're trending toward: bumping the char ceiling.
Documented reaction: PR #22781 ("tighten MEMORY_GUIDANCE against
ephemeral PR/issue/SHA notes") tightens upstream guidance in the
opposite direction. Issue #5320 (raise defaults) has been open since
April with no merge.

### Misuse 2 — `honcho_conclude` dramatically underused

Symptom: 1 conclusion after weeks of meaningful exchange.

Evidence: `memory-architecture.md` literally enumerates this symptom
in the "Signs You're Misusing the Layers" table:

> "Honcho conclusions has 1-2 entries after weeks of conversation →
> `honcho_conclude` is being underused — useful facts are falling
> through the cracks"

Target per A3 in goals: ≥10 active conclusions. Documented cadence:
one per meaningful exchange. We're under by ~10x.

### Misuse 3 — Observation noise tolerated, never pruned

Symptom: ~60 observations, ~50% noise.

Evidence: `memory-architecture.md` "Signs" table again:

> "Honcho observation log has 50+ trivial entries → Observer is filing
> transcript-of-the-obvious noise. Either ignore and trust dialectic to
> synthesize signal, OR selectively delete via
> `honcho_conclude(delete_id=...)` in a cleanup pass"

We've done neither. There's no maintenance cadence and the noise is
shaping dialectic synthesis quality downward. **Caveat:** Issue #17968
notes that `honcho_conclude` historically lacked delete; the upstream
SDK supports `ConclusionScope.delete(conclusion_id)` and recent docs
(`memory-providers.md` line 54) show `honcho_conclude(delete_id=...)`
is now exposed — but only for **conclusions**, not raw observations.
Observation deletion is currently via the Honcho REST API directly.

### Misuse 4 — Honcho dialectic almost certainly under-tuned

Symptom: Conclusions sparse, dialectic responses likely shallow,
re-asking questions across sessions.

Evidence (config defaults vs. likely-active in our deployment):

```
KNOB                         DEFAULT   POWER-USER     OUR VALUE
                                       RECOMMENDATION (unverified)
─────────────────────────────────────────────────────────────────
dialecticDepth               1         2-3            likely 1
dialecticCadence             2         2-3            likely default
contextCadence               1         1              likely default
dialecticReasoningLevel      low       medium/high    likely default low
dialecticDynamic             true      true           likely default
recallMode                   hybrid    hybrid         likely default ✓
sessionStrategy              per-dir   per-dir or
                                       per-repo       likely default ✓
contextTokens                null      cap to ~1200   likely uncapped
dialecticMaxChars            600       1000-1500      likely default
writeFrequency               async     async ✓        likely default ✓
```

Source: `honcho.md` line 99 explicitly states "A single-pass prewarm
on a cold peer often returns thin output — multi-pass depth runs the
audit/reconcile cycle before the user ever speaks." For a power-user
single-tenant deployment this is unambiguously the wrong default.

### Misuse 5 — Subagent isolation behaviour unverified (it's the bug-for-bug expected behaviour)

Symptom: "Subagent memory isolation unverified."

Verified: `tools/delegate_tool.py:1120` hardcodes `skip_memory=True`
on subagent spawn. Open issue #30269 confirms there is no opt-out.

For research subagents this is **correct** — exactly what the skill ref
calls "a feature, not a bug" for fresh-eyes research. For operational
delegation it's a footgun. We're using it correctly here (research),
so no action needed unless we start delegating operational tasks.

### Misuse 6 — Honcho `honcho_search` + `honcho_context` may be returning broader-than-asked context

Issue #29402 (open, P3): "Honcho memory tools ignore focused query and
token budget controls." `honcho_context(query=...)` doesn't pass
the query through; `honcho_search(max_tokens=N)` doesn't bind output.
This means even with good discipline, the tools we *do* invoke return
noisier-than-spec responses. Not actionable on our end (upstream bug)
but worth knowing why dialectic feels diffuse.

---

## Tunable knobs not used (the punchlist)

```
HONCHO (single biggest leverage)
  dialecticDepth: 2  or 3            # power-user default per docs
  dialecticReasoningLevel: medium    # base ceiling; dynamic still adapts
  dialecticCadence: 2-3              # don't fire every turn at depth >1
  contextTokens: 1200                # cap injection size (currently uncapped)
  dialecticMaxChars: 1000            # more substance per dialectic block
  sessionStrategy: per-repo          # if our work is repo-scoped (apnex/kate, labops, ...)
                                     # otherwise leave per-directory
  observationMode: directional       # default ✓; confirm not overridden

BUILT-IN MEMORY
  memory_char_limit: 3000  (currently likely 2200 default — bump moderately)
  user_char_limit:   2000  (currently likely 1375 default — already bumped, ok)
  → these are the documented power-user values from
    memory-architecture.md "Recommended Default Topology"
  → DO NOT bump higher; the answer to 95%-full is skill-demotion

SKILLS
  Per goal G3 / A5: a planned `apnex-cluster` skill umbrella that
  absorbs the procedural content currently in MEMORY.md.
  Topics observed in current memory pressure:
    - LiteLLM proxy chain
    - MetalLB rules
    - k3s boot hardening
    - ConfigMap rendering pattern
  Each is a `references/<topic>.md` under the umbrella, plus one-line
  pointers from MEMORY.md.

UPSTREAM (won't help us today, worth tracking)
  Issue #5320 — auto-scale memory limits to context length
  Issue #25309 — dreaming / background memory consolidation
  Issue #28279 — per-chat memory scoping
  Issue #29402 — honcho_context query plumbing fix
  Issue #30269 — subagent memory inheritance opt-in
  Issue #9763  — cron skip_memory opt-in
```

---

## Alternative providers (honest tradeoffs vs. Honcho)

Hermes ships **8 in-tree memory providers** (`plugins/memory/`). The
team has officially closed `plugins/memory/` to new in-tree additions
(merged PR #25302) — future providers must ship as standalone
`~/.hermes/plugins/` repos using the same `MemoryProvider` ABC. This
matters for our G7 (provider portability) — the ABC IS the portability
surface.

```
PROVIDER       SELF-HOST?   AI-NATIVE?   STORAGE          FIT FOR US
─────────────────────────────────────────────────────────────────────
honcho         ✓ (k8s)      ✓ (deepest)  Postgres+pgvec   ← INCUMBENT, KEEP
openviking     ✓ (server)   ~ (extract)  self-hosted      Possible alt; AGPL-3.0
holographic    ✓ (SQLite)   ✗ (algebraic) local SQLite    Too primitive for our needs
hindsight      cloud OR local PG ✓ (graph) PG embedded    Interesting (graph + reflect)
mem0           ✗ cloud only ✓ (extract)  mem0 cloud       Violates sovereign constraint
supermemory    ✗ cloud only ✓ (semantic) supermemory      Violates sovereign constraint
retaindb       ✗ cloud only ✓            retaindb         $20/mo + cloud — fails constraints
byterover      local CLI    ~ (fuzzy)    local            Node-CLI dep; non-Python ✓ but lighter than Honcho
```

**Verdict:** Stay on Honcho. Of the self-hostable options:

- **Holographic** is too primitive (single-machine SQLite + FTS5 + HRR;
  no continuous user-modeling, no dialectic).
- **OpenViking** is the only credible alternative — filesystem-style
  hierarchy with tiered retrieval, self-hosted, structured browsing.
  Tradeoff: less mature user-modeling than Honcho, no equivalent to
  dialectic, but more "browseable" knowledge graph. **AGPL-3.0** —
  acceptable for personal infra, worth flagging.
- **Hindsight (local mode)** has a unique `hindsight_reflect`
  cross-memory synthesis tool that no other provider offers, but it's
  cloud-first; the local mode runs embedded Postgres, adding ops surface
  comparable to Honcho without the user-modeling depth.

**G7 portability:** The 5-layer architecture itself is provider-agnostic.
"Conclusions, observations, queryable profile" are universal concepts
the `MemoryProvider` ABC enforces (`memory_provider.py` — see plugin
dev guide). Swapping providers would be a config swap + content
re-ingest, not a rewrite. **G7 is structurally satisfied today.**

---

## Concrete recommendations

Numbered, with confidence levels. Each maps to ≥1 acceptance criterion.

### 1. Adopt the documented decision tree as the only file-the-fact rule (G1, A1, A2)
- **Change:** Pin `memory-architecture.md`'s decision tree (the
  USER/ENVIRONMENT/CLASS/TRANSIENT branch) at the top of
  `kate/docs/memory/`. Reference it from MEMORY.md as the "before you
  write here, check this" pointer.
- **Rationale:** This single discipline change resolves Misuse 1
  without any code or config changes.
- **Evidence:** `memory-architecture.md` "The 'What Belongs Where'
  Decision Tree" section.
- **Confidence:** **HIGH** — directly cited from the Hermes team's
  authoritative reference.

### 2. Plan + execute the `apnex-cluster` skill umbrella demotion (G3, A1, A5)
- **Change:** Create `apnex-cluster` skill with `references/` files for
  LiteLLM, MetalLB, k3s boot, ConfigMap pattern. Replace MEMORY.md
  procedural blocks with one-line pointers. Target: MEMORY.md drops to
  50-60% (≈1,700 chars from 2,940).
- **Rationale:** Documented "Skill Reference Demotion Pattern" —
  exactly the prescribed fix for our exact symptom.
- **Evidence:** `memory-architecture.md` "Skill Reference Demotion
  Pattern" section, steps 1-6.
- **Confidence:** **HIGH**.

### 3. Tune Honcho for power-user depth (G4, G6, A3, A6)
- **Change** (in `honcho.json` under the `hermes` host block):
  ```json
  "dialecticDepth": 2,
  "dialecticReasoningLevel": "medium",
  "dialecticCadence": 3,
  "contextCadence": 1,
  "contextTokens": 1200,
  "dialecticMaxChars": 1000,
  "sessionStrategy": "per-repo"
  ```
- **Rationale:** Defaults are sized for casual users; we're a
  multi-week, multi-repo single-tenant deployment where context
  continuity is the headline goal (G6).
- **Evidence:** `honcho.md` lines 73-99 — three orthogonal knobs;
  prewarm-at-depth-1 explicitly noted as "often thin output."
- **Confidence:** **MED-HIGH.** The direction is right; the exact
  numbers should be tuned over 2-3 sessions and rolled back if cost or
  latency spikes are visible. Recommend logging dialectic latency before
  + after.

### 4. Adopt "one `honcho_conclude` per meaningful exchange" as agent habit (G4, A3)
- **Change:** Encode in USER.md (≤1 short line) and in the kate
  decisions doc: "After any exchange where the user expresses a
  preference, pattern, or correction → file ONE distilled
  `honcho_conclude`. Not the chatter, the distillation."
- **Rationale:** Most direct path to A3 (≥10 conclusions). The skill
  ref gives ~5 example concl./not-concl. mappings to internalize the
  pattern.
- **Evidence:** `memory-architecture.md` "The Honcho Conclude
  Discipline" section.
- **Confidence:** **HIGH** for the *direction*; **MED** for whether
  the agent will reliably do it without continued nudging — this is a
  behaviour change, not a config change. Worth revisiting in 2 weeks
  to measure.

### 5. Schedule an observation cleanup pass (G5, A4)
- **Change:** One-off action: list current observations, identify
  the ~30 noise entries, delete via direct Honcho REST API call
  (`DELETE` to `/v3/workspaces/{ws}/peers/{peer}/observations/{id}`).
  Future: trust dialectic to synthesize from raw — only intervene if
  signal-to-noise stays under 70%.
- **Rationale:** Cleaner observation pool = better synthesis. Goal A4
  requires <3 noise in last 20.
- **Evidence:** `memory-architecture.md` "Signs" table cleanup
  recommendation; `honcho_conclude(delete_id=...)` available for
  conclusions only — observation delete still requires REST.
- **Confidence:** **MED.** Risk: deleting "noise" we later regret. Do
  a dry-run review first (10-min manual triage).

### 6. Bump in-prompt memory char limits, but only after recommendations 1+2 land (G2, A1, A2)
- **Change:** After demotion, set `memory.memory_char_limit: 3000`
  and `memory.user_char_limit: 2000` if not already.
- **Rationale:** These are the *documented* "Recommended Default
  Topology" values from `memory-architecture.md`. Do NOT bump higher.
- **Evidence:** `memory-architecture.md` "Recommended Default
  Topology" section.
- **Confidence:** **HIGH.** **CAUTION:** never frame this as "the fix"
  — the fix is recommendations 1+2; the limit bump is just sizing.

### 7. Subagent memory: document the limitation, don't fight it (G8)
- **Change:** Add to `kate/docs/memory/` a one-liner:
  "Subagents (`delegate_task`) and cron jobs do NOT inherit
  MEMORY/USER/Honcho context — `delegate_tool.py:1120` and
  `cron/scheduler.py:L748` hardcode `skip_memory=True`. For operational
  delegations, restate critical preferences in `context=...`. For
  research delegations (like this one), keep the isolation."
- **Rationale:** Matches G8 exactly. Operationally correct, well-cited.
- **Evidence:** Issue #30269 (subagents), #9763 (cron),
  `delegate_tool.py:1120`, `memory-architecture.md` "Subagent Memory"
  section.
- **Confidence:** **HIGH.**

### 8. Validate G7 (portability) with a thought-experiment, not an action (A7)
- **Change:** None — just record in `kate/docs/memory/decisions/` that
  swapping to OpenViking (the only credible self-host alternative)
  would be a config swap (`memory.provider: openviking`) + content
  re-ingest, no architectural rewrite. The `MemoryProvider` ABC IS
  the portability surface.
- **Rationale:** A7 explicitly says "thought experiment."
- **Confidence:** **HIGH.**

---

## Open questions (need human input)

1. **What is our current `honcho.json`?** I could not introspect the
   actual file from this subagent context. All Honcho tuning
   recommendations assume near-defaults; if `dialecticDepth` is
   already 2-3, recommendation 3 needs revision.
2. **Is the kate repo the right home for the demoted procedural
   content, or should `apnex-cluster` be a hub-published skill?** The
   recently-merged PR #25302 closes in-tree memory plugins to new PRs
   but says nothing about skills — `hermes skills publish` is
   available if we want it discoverable beyond personal use.
3. **Do we want session-strategy `per-repo` or `per-directory`?** The
   subagent doesn't know how apnex's day-to-day work clusters
   (single repo with subdirs vs. many sibling repos). `per-repo` is
   recommended when work is repo-bounded; `per-directory` when it
   isn't.
4. **Acceptable Honcho deriver LLM cost increase from depth 1 → 2-3?**
   `context-engine-and-external-brain.md` flags "background LLM cost
   nobody talks about" — depth 2 roughly 2x's the LiteLLM calls per
   dialectic firing.
5. **Are we hitting issue #29402 in practice?** If `honcho_context`
   feels too broad regardless of query, that's the upstream bug, not
   us. Worth a one-time `honcho_context(query="foo")` test to confirm.
6. **Observation cleanup approval threshold:** how aggressive should
   recommendation 5 be? "Delete anything below this signal bar" is a
   judgement call we can't make without seeing the entries.

---

## Sources

### Hermes source / docs (local)
- `/opt/hermes/plugins/memory/` — 8 provider directories; ABC at
  `/opt/hermes/agent/memory_provider.py` (referenced from plugin docs)
- `/opt/hermes/plugins/memory/honcho/README.md` — full Honcho config
  reference of record
- `/opt/hermes/plugins/memory/honcho/plugin.yaml` — minimal, just declares
  `on_session_end` hook
- `/opt/hermes/tools/delegate_tool.py:1120` — `skip_memory=True`
  hardcoded
- `/opt/hermes/website/docs/user-guide/features/memory.md` —
  built-in memory reference
- `/opt/hermes/website/docs/user-guide/features/memory-providers.md` —
  all 8 providers comparison + tools
- `/opt/hermes/website/docs/user-guide/features/honcho.md` — Honcho
  architecture (two-layer injection, cold/warm, three knobs)
- `/opt/hermes/website/docs/developer-guide/memory-provider-plugin.md`
  — `MemoryProvider` ABC contract (portability surface)

### Hermes-team authoritative skill reference
- `~/.hermes/skills/.../hermes-agent/references/memory-architecture.md`
  — THE prescriptive document; 5-layer model, decision tree, demotion
  pattern, conclude discipline, subagent gotcha
- `.../references/context-engine-and-external-brain.md` — design pattern
  for external-brain architectures, Honcho upstream context
- `.../references/k3s-deployment.md` — k3s-specific config gotchas (our
  exact deployment shape)

### GitHub issues (NousResearch/hermes-agent)
- #30269 — Subagents don't inherit MEMORY.md (open, P3) — confirms the
  hardcoded `skip_memory=True`
- #9763 — Cron jobs hardcode `skip_memory=True` (open, P3) — same issue
  for scheduler
- #5320 — feat(memory): raise/auto-scale `memory_char_limit` (open) —
  upstream proposal we should NOT wait for
- #17968 — `honcho_conclude` no delete/update (open) — partially
  addressed in current `honcho_conclude(delete_id=...)` for conclusions
- #29402 — Honcho tools ignore focused query/token budget (open, P3)
- #28279 — per-chat memory scoping (open) — N/A single-user, but
  watch
- #25309 — Dreaming / auto-consolidation (open) — interesting future
  feature

### GitHub merged PRs (direction-of-travel)
- #25302 — "close in-tree memory plugins to new PRs and codify skill
  standards" — confirms `MemoryProvider` ABC is the long-term
  portability seam
- #22781 — "tighten MEMORY_GUIDANCE against ephemeral PR/issue/SHA
  notes" — upstream is tightening, not loosening, in-prompt memory
- #28583 — "label recalled memory as informational, not authoritative"
  — recent provider-context labelling change worth knowing about
- #10619 — Honcho 5-tool surface + cost safety overhaul — the
  feature set we use today
- #15381, #12419, #4751 — Honcho stability/bug-fix consolidation —
  the upstream is mature and actively maintained

### Goals document
- `/root/kate/docs/memory/00-goals.md` — A1-A7 acceptance criteria

### What I couldn't determine
- Exact contents of our current `honcho.json` (no host filesystem read
  from this subagent toolset for that path; visible only via SSH which
  I didn't burn time on since the recommendation surface doesn't
  require it)
- Live observation/conclusion counts (would require a Honcho API call
  the subagent isn't tooled for)
- Whether we're hitting #29402 in practice (requires interactive test)
