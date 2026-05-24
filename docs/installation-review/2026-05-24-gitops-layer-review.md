# Kate GitOps Installation Review

**Date:** 2026-05-24
**Reviewer:** hermes-agent
**Scope:** GitOps layer of the Kate stack (assumes k8s + ArgoCD as prerequisites)
**Lens:** "New SRE joining the team" — every implicit step is a defect
**Repos audited:** `apnex/labops`, `apnex/honcho`, `apnex/hermes`, `apnex/kate`

## Verdict

🟢 **B+** — Strong foundation with clean separation of concerns. Several
portability and discoverability gaps prevent a "fork this and run" experience.
The bones are right; the documentation surface and teardown story are uneven.

## Repo layer-cake (as deployed)

```
┌─────────────────────────────────────────────────────────────────┐
│ apnex/labops          generic cluster infra + service registry  │
│   ├── argo/services.yaml        ← ApplicationSet input file     │
│   ├── argo/services.appset.yaml ← templating + git generator    │
│   ├── k3s/{install,up,remove}   ← (out of scope, prereq)        │
│   ├── hermes-vip/service.yaml   ← MetalLB Service for Hermes    │
│   └── (other apps: kubedoom, sockshop, etc.)                    │
│                                                                   │
│ apnex/honcho          memory server deployment                   │
│   ├── manifests/    (Kustomize: postgres + redis + api + deriver)│
│   └── docs/{runbook,secrets,teardown}.md                         │
│                                                                   │
│ apnex/hermes          agent deployment                           │
│   ├── manifests/    (Deployment, PVC, Service, ServiceAccount)   │
│   ├── set-secret    (helper for the LLM Secret)                  │
│   ├── setup-host-access.sh                                       │
│   └── hermes-tui    (exec into deployed pod for interactive use) │
│                                                                   │
│ apnex/kate            docs + decisions + this review (no deploy) │
│   └── docs/{memory,operations,decisions,installation-review}/    │
└─────────────────────────────────────────────────────────────────┘
```

Cross-coupling is minimal and correct: `labops/argo/services.yaml` references
the other two repos by URL only.

## What's working well 🟢

### Repo separation
Three apps + one docs repo. No cross-repo coupling beyond a single registry
entry per app. New apps onboard via a 7-line YAML entry. Excellent.

### ApplicationSet pattern
`labops/argo/services.appset.yaml` is a clean git-generator pattern:
- `goTemplate: true` + `templatePatch` cleanly routes git vs helm sources
- `selfHeal + prune + retry` baked into every generated Application
- One file (`services.yaml`) is the single source of truth for what's deployed

This is best-practice GitOps and would scale to dozens of apps without modification.

### Secrets discipline
The LLM key is **not** in any repo. The runbook (`honcho/docs/secrets.md`)
documents the hard-won lesson:

> ArgoCD's `selfHeal: true` will overwrite a managed Secret on every
> reconciliation, even with `compare-options: IgnoreExtraneous` annotation.
> The annotation suppresses *warnings* about unmanaged resources; it does
> not stop selfHeal on a managed one.

The fix is to keep the Secret entirely out of Git and document the
out-of-band `kubectl create secret` step. Correct posture, well-documented.

### Hermes README
Exemplary for a self-contained service repo:
- 4-step install (clone → secret → deploy → verify)
- Explicit "(a) Direct vs (b) Argo CD" deployment options
- Trust caveats called out (`/root` mount visibility, cluster-admin scope)
- Optional host-access feature gated by a separate Secret
- `hermes-tui` documented as the operator's interactive entry point

### Honcho runbook
`honcho/docs/runbook.md` covers the operational basics:
- Log inspection per workload
- Restart for config/secret changes (with the `rollout restart` correctness)
- LiteLLM key rotation
- Manual postgres backup + restore
- Forced Argo sync command

### Kate's organizational intent
Layout in `README.md` shows a sensible plan:
- `docs/memory/` numbered series (currently the only filled-in section)
- `docs/operations/` for runbooks (skeleton only)
- `docs/decisions/` for ADRs (skeleton only)

The "no code" disclaimer is clear: kate is the meta layer.

## Critical defects 🔴

### D1. No install order documented
**Severity:** High. New operator cannot bootstrap without prior knowledge.

The dependency chain `LiteLLM proxy → Honcho → Hermes` is **implicit**.
Nowhere does it say "install Hermes after Honcho" or "Honcho needs the
LiteLLM URL to exist first." Each repo's README presents itself as
self-contained, but the real bootstrap requires cross-repo coordination.

**Fix:** Add `kate/INSTALL.md` with a top-down install order:
```
1. Prereqs verified (k8s + Argo + LB + SC + LLM proxy reachable)
2. labops: argo/services.appset.yaml applied
3. Honcho: namespace + Secret + (Argo entry added to services.yaml)
4. Hermes: namespace + Secret + (Argo entry added to services.yaml)
5. Verify cross-stack (Hermes → Honcho → LiteLLM → models)
```

### D2. No teardown story for apps
**Severity:** High. PVCs orphan, secrets stick, VIPs leak.

`labops` has `k3s/remove` and `argo/remove` — good. But:
- `honcho` had **no removal docs** (✅ fixed in this commit batch — `docs/teardown.md` added)
- `hermes` has **no removal docs**

A new operator who wants to redeploy clean has to guess what to delete.
Postgres PVCs in particular need explicit guidance (preserve vs destroy).

**Fix:** Add `hermes/docs/teardown.md` symmetric to the new
`honcho/docs/teardown.md`.

### D3. Honcho README disagreed with manifests (✅ fixed)
**Severity:** Medium (was). Confusing to a forker.

Original README said "honcho API server + background deriver (one Deployment)"
but the manifests deploy two Deployments (`honcho` for the API,
`honcho-deriver` for the queue worker). Honcho v3.x split these processes;
the README hadn't caught up.

**Fix:** README updated in this commit batch to reflect the two-Deployment
reality and explain why (v3.x architecture change).

### D4. Image source ambiguity (✅ fixed)
**Severity:** Medium (was).

Original Honcho README referenced `ghcr.io/apnex/honcho:<version>` for image
distribution. The actual manifests use `localhost/honcho:v3.0.7` with
`imagePullPolicy: Never` — a single-node `docker save | ctr import` pattern.

**Fix:** README updated to describe the localhost-build flow as the
canonical path and mention the registry alternative for multi-node clusters.

### D5. No LiteLLM repo in the stack
**Severity:** High. **Largest portability gap.**

Hermes routes all LLM calls through a LiteLLM proxy. Honcho does too. The
proxy is foundational to both. But there is **no `apnex/litellm` repo** in
the four-repo stack. Where does the proxy live? Currently in `apnex/labops`
gcp/ directory (Terraform → GCP Cloud Run) — but it's undocumented, and
forking the stack to a different cloud means re-discovering the entire
proxy layer.

**Fix:** Either (a) carve out an `apnex/litellm` repo with the Terraform
and a clear "swap the cloud" note, or (b) move the proxy stack into
`labops/litellm/` and document it as a first-class component in
`kate/INSTALL.md`. **The forker has to know this exists, what it does,
and what alternatives are acceptable** (LiteLLM, LangFuse-routed, raw
OpenAI, OpenRouter, OpenWebUI proxy, etc.).

### D6. Kate skeleton vs reality mismatch
**Severity:** Medium.

`kate/README.md` describes a directory tree including `docs/operations/`,
`docs/decisions/`, etc. — but only `docs/memory/` and (now) this review
actually exist. A reader following the README will hit 404s.

**Fix:** Either backfill the empty sections or remove them from the README.
Recommend backfill with at least one file per section (e.g.,
`operations/litellm-routing.md`, `decisions/0001-honcho-as-memory.md`)
so the structure is self-bootstrapping.

## Portability blockers 🟡

### P1. ~~Hardcoded MetalLB VIP 192.168.1.250~~ (false alarm — fixed in docs)

**Initial finding:** Looked like the VIP was hardcoded.
**Investigation:** The *manifests* use `metallb.universe.tf/allow-shared-ip: host`
and **do not pin an IP** — MetalLB auto-assigns from the configured pool.
The "192.168.1.250" everywhere was the *resolved value* MetalLB happened to
choose, leaking into documentation as if it were canonical.

**Status:** Manifests are correct. README now uses `<your-vip>` placeholder
with a `kubectl get svc` command to discover the assigned IP.

### P2. Storage assumes a default StorageClass

Honcho's postgres StatefulSet requests a PVC with no explicit
`storageClassName`, relying on the cluster's default. k3s ships `local-path`;
EKS/GKE ship their own defaults. **Works on any flavor** as long as a
default is set, but undocumented.

**Fix:** Add a one-line note in Honcho README: "uses cluster default
StorageClass; set `storageClassName` in `manifests/postgres/statefulset.yaml`
to override."

### P3. `labops.sh` base URL coupling

`labops/argo/install` curls `https://labops.sh/argo/services.appset.yaml`
to bootstrap the ApplicationSet. This is convenient for apnex but ties any
forker to apnex's domain or requires them to mirror.

**Fix:** Optional. If portability matters, accept `LABOPS_BASE` env override
(the `k3s/up` script already does this — apply the same pattern to argo/install).

### P4. Single-node bias (acceptable)

The localhost-build + `imagePullPolicy: Never` pattern is single-node only.
Multi-node clusters need a registry push. Now documented in the updated
Honcho README, but could be more prominent.

### P5. Kustomize only, no Helm

Most teams prefer Helm charts for reuse. Kustomize is a defensible choice
(simpler, no values templating, easier to audit), but **call it out** in
each README's first paragraph so a chart-only team doesn't waste time
looking for a `chart/` directory.

## Discord integration — carve-out

**Current state:** Lives inside `hermes/README.md` as an "Optional: Discord
gateway" section (lines 90-137). Two env vars on the same Hermes Secret.

**Verdict:** Stays inside `hermes` repo (it IS a Hermes gateway feature),
but **move to its own docs page** so the main README stays focused on
"deploy Hermes." Apply the same pattern that `honcho/docs/runbook.md` uses.

**Gaps to address in the moved doc:**
1. Token rotation procedure (currently undocumented)
2. Allowlist management discipline (multi-user, multi-bot)
3. Voice-note transcription wiring (mentioned but unconfigured)
4. Bot permissions audit (currently a flat list; explain the *why* of each)

**Fix:** Create `hermes/docs/discord.md`. Replace the section in the main
README with a 3-line pointer.

## Top 7 actionable fixes (priority order)

| # | Action | Repo | Status |
|---|---|---|---|
| 1 | Write `INSTALL.md` covering full bootstrap order | kate | TODO |
| 2 | Write `TEARDOWN.md` per app | honcho ✅, hermes ⏳ | partial |
| 3 | Reconcile Honcho README ↔ manifests (single-deploy claim, image source) | honcho | ✅ done |
| 4 | Create `apnex/litellm` repo OR move proxy into `labops/litellm/` | labops/new | TODO |
| 5 | Move Discord to `hermes/docs/discord.md` | hermes | TODO |
| 6 | Add `kate/PORTABILITY.md` documenting every fork-time substitution | kate | TODO |
| 7 | Fill in the kate skeleton (operations/, decisions/) | kate | TODO |

## Recommendations beyond the 7

- **Add a single `Makefile` per repo** with `install`, `verify`, `teardown`
  targets. Currently the install paths are a mix of `./set-secret`,
  `./hermes-tui`, raw `kubectl apply -k`, and one-off scripts. A Makefile
  is the conventional "one entry point" answer.
- **Pin upstream image versions in a single config file.** Currently
  `localhost/honcho:v3.0.7` is in two manifest files. A Kustomize image
  transformer or a top-level `versions.yaml` would prevent drift.
- **Pre-flight script in `kate/scripts/preflight.sh`** that probes each
  prereq (LLM endpoint reachable, supports tool-calling, default SC
  exists, LB controller running, Argo ApplicationSet CRD present). This
  is the single biggest "easy install" win — catches portability issues
  before they become 30-minute debug sessions.

## Appendix: what this review committed

This review action also produced concrete changes:

**`apnex/honcho` @ `c45cc45`:**
- `README.md` reconciled with manifest reality (two Deployments, localhost image, portable VIP)
- `docs/teardown.md` added (symmetric to install, with data-preservation choices and Argo-prune semantics)

**`apnex/kate` @ this commit:**
- `docs/installation-review/2026-05-24-gitops-layer-review.md` (this file)
