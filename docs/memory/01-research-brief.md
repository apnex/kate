# 01 — Memory Research Brief

**Status:** Brief (subagent investigation pending)
**Date:** 2026-05-24
**Author:** apnex + hermes
**Target output:** `docs/memory/02-research-findings.md`

## Investigation goal

Determine the canonical / idiomatic / best-practice memory architecture for a
power-user Hermes deployment, given the constraints below. Return a structured
recommendation backed by source citations.

## Hard context (the subagent knows nothing — this is the briefing)

### Current deployment

- Single user (apnex), single Hermes instance, k3s on a Fedora NUC
- LLM backend: self-hosted LiteLLM proxy on Cloud Run
- Memory provider: Honcho (self-hosted in cluster, AUTH_USE_AUTH=false)
- Hermes config templated via ConfigMap, rendered to `/opt/data/config.yaml`
- Sessions span days/weeks via Discord transport
- User is infra-fluent (k8s, GitOps, GCP, Terraform)

### Current memory layers in use

1. Local `MEMORY.md` — in-prompt, 3,000 char ceiling (currently 98%)
2. Local `USER.md` — in-prompt, 2,000 char ceiling (currently 95%, just bumped from 1,375)
3. Honcho observations — server-side, ~60 entries (~50% noise)
4. Honcho conclusions — server-side, 1 entry (severely underused)
5. Skills (`hermes-agent`, `apnex-cluster` planned) — load-on-demand procedural

### Symptoms

- Local memory layers fill rapidly with procedural and historical content
  that should live elsewhere
- Honcho conclusions almost never used despite tool availability
- Honcho observations dominated by transcript-of-the-obvious noise
- Subagent memory isolation behaviour unverified
- No idea if there are layers we're missing entirely

### Constraints

- Sovereign infra preferred (self-host over SaaS where possible)
- GitOps strict (Git → Argo, never raw kubectl)
- Non-Python backends preferred where viable
- Provider portability matters (don't lock into Honcho)
- Single-tenant — no multi-user concerns
- Operator legibility — future-me must understand the why

## Investigation tasks

### Task 1 — Inspect the hermes-agent skill (authoritative source)

Load via `skill_view(name='hermes-agent')`. This is the Hermes team's own
documented architecture. Pay particular attention to any references about:
- memory providers (what ships, what's recommended)
- the role of skills vs. in-prompt memory vs. provider memory
- subagent memory wiring
- recommended discipline / patterns

Cite any specific references files within the skill that touch memory.

### Task 2 — Inspect the Hermes codebase locally

Hermes is at `/opt/hermes` in the pod's filesystem. Investigate:

- `plugins/memory/` — what providers ship? What hooks exist?
- The context engine — what assembles the prompt? How is memory injected?
- Subagent code path — how do subagents interact with the parent's memory?
- Tool registration for `honcho_*` and any `memory_*` tools
- Config schema for the `memory:` and `honcho:` blocks

Cite specific file paths + line numbers.

### Task 3 — Hermes documentation deep-dive

Walk `/opt/hermes/website/docs/` looking for:

- Any "architecture" or "design" pages touching memory
- Plugin documentation (memory-provider plugins specifically)
- User-guide pages for honcho.md, skills, subagents, context
- Any "best practice" / "patterns" / "recommended" sections

Cite page paths.

### Task 4 — GitHub repo investigation (use gh CLI on host)

The NUC at 192.168.1.250 has `gh` v2.92 authenticated as apnex. SSH via
`/etc/hermes-host-ssh/id_ed25519` then invoke `gh` directly. Read-only
operations only — no comments, no PR creation, no issue creation.

For the Hermes repo (find via `gh repo view nousresearch/hermes-agent` or
similar — confirm the actual org/repo name from `/opt/hermes/website` or
`pyproject.toml`):

- `gh issue list -L 100 --search "memory"` — open + closed issues
- `gh issue list -L 100 --search "honcho"`
- `gh issue list -L 100 --search "context"`
- `gh pr list -L 50 --state merged --search "memory"` — recent direction
- `gh pr list -L 50 --state open --search "memory OR context"`
- For ≥3 most-relevant issues/PRs, fetch full body + comments
- `gh search code "memory_provider" --owner <hermes-org>` for code patterns

Goal: surface pitfalls users hit, recent architectural changes, the team's
unwritten conventions visible in PR review comments.

### Task 5 — Honcho repo investigation (also via gh)

- Find the canonical Honcho org/repo (likely `plastic-labs/honcho` or similar
  — verify from `/opt/hermes/website/docs/user-guide/features/honcho.md`)
- Look for under-utilised features: peer cards, workflows, cadences,
  sessionStrategy, observerModel, dialecticReasoningLevel tuning
- Recent PRs / issues touching these
- Recommended configuration patterns

### Task 6 — Alternative providers survey

Check if Hermes ships or documents support for:
- mem0
- letta (formerly memgpt)
- zep
- any built-in / local provider
- any "no provider" pattern

For each, briefly note: shape of integration, tradeoffs vs. Honcho, fit
with sovereign/k8s/non-Python constraints.

### Task 7 — Community / external patterns

Search GitHub broadly (not just Hermes org):
- `gh search repos --topic hermes-agent`
- `gh search code "memory_provider: honcho" --language yaml`
- Look for blog posts, example configs, postmortems

Lower priority — only invest time if Tasks 1–6 leave open questions.

## Deliverable: write to `docs/memory/02-research-findings.md`

Structure the report as:

```
# 02 — Memory Research Findings

## Executive summary
3-5 bullet points: the headline findings.

## Canonical architecture (as documented)
What Hermes officially says memory should look like.

## What we're doing right
Honest call-out — no need to fix what works.

## What we're doing wrong
Specific gaps vs. canonical, with evidence.

## Tunable knobs not used
Specific config / API features available that we're not leveraging.

## Alternative providers (if relevant)
Honest tradeoffs vs. sticking with Honcho.

## Concrete recommendations
Numbered list. Each: change, rationale, evidence, confidence (high/med/low).

## Open questions
Things the research couldn't answer; need human input.

## Sources
File paths, GitHub URLs, issue numbers, line refs.
```

## Constraints on the subagent

- **Read-only.** No code changes, no commits, no GitHub writes, no honcho
  writes. Investigation only.
- **Cite sources.** Every claim needs a file path or URL.
- **Be honest about uncertainty.** "Couldn't find authoritative guidance" is
  better than guessing.
- **Don't propose change for change's sake.** If our setup is mostly correct,
  say so.
- **Time-box.** Aim to return within 20-30 minutes of work. If running long,
  return a best-effort summary plus "didn't get to X".
- **Subagent has no Honcho.** Self-contained context — everything needed is
  in this brief.

## Toolsets to grant

- `file` — reading Hermes code and docs
- `terminal` — running `gh` via SSH bridge, grep, find
- `web` — fallback for things not on the NUC
- `skills` — loading `hermes-agent` skill

NOT granted: `delegation` (no nested subagents — one focused researcher).

## Brief is frozen

This brief is captured BEFORE the subagent runs. Don't edit it after.
The subagent's findings document is the working layer.
