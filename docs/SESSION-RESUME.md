# SESSION RESUME — read this first if picking up cold

**Project:** kate platform migration (kate/labops/hermes/honcho repos)
**Last active session:** 2026-05-26
**Status:** Phase 1 complete; Phases 2-4 + 3a/3b/3c pending; halted
between sessions.

---

## Where to start in 60 seconds

1. **Read `docs/research/platform-migration/05-open-questions.md`** —
   primary steering mechanism. Tells you what's actively in flight,
   what's been answered, what's still unknown. Per user convention,
   this is the canonical "what should I do next" file.

2. **Skim `docs/research/platform-migration/01-design-journal.md`** —
   append-only narrative. Tells you what happened, what was decided
   and why.

3. **Reference `docs/architecture.md`** when implementing — the
   authoritative architecture and 4-phase plan, including the
   production cutover risks section.

That's it. Three files. You're caught up.

---

## Current state

| Repo | HEAD | Status |
|---|---|---|
| `apnex/kate` | `10670fc` (or latest) | Phase 1 complete; structurally correct but NOT installable until Phase 4 |
| `apnex/labops` | unchanged | Still owns hermes/honcho/vip-hermes via ArgoCD ApplicationSet |
| `apnex/hermes` | unchanged | Has Deployment + ClusterIP; no vip.yaml yet |
| `apnex/honcho` | unchanged | Has Deployment + ClusterIP; no vip.yaml yet |

**Live cluster:** untouched by kate work. Still in pre-migration state.

---

## Next planned work

**Phase D / 3b — Custom container image audit.**

Why first: biggest unknown, biggest risk. If audit reveals "nobody
remembers why these patches exist," cutover blocks until resolved.
See `docs/architecture.md` § Production cutover risks § Risk 3 for
the audit checklist, and `05-open-questions.md` § Phase D for the
specific questions to answer.

**Approved sequence after D:** C (backups), A (Kyverno), B (vip.yaml),
E (integration verification), F (doc sweep), G (cutover).

D, C, A, B, E can each run in their own session.

---

## Critical context to remember

**The substrate/composition/component boundary is sharp:**

- **labops** = substrate (k3s, MetalLB, ArgoCD, Kyverno bootstrap) — knows
  about this specific cluster's quirks. Shell-script bootstrapped.
- **kate** = composition — which components compose the platform. Pure
  intent in `bundles/default/services.yaml`. ArgoCD-managed.
- **hermes / honcho** = components — workload manifests, substrate-agnostic.
  Each owns its full deployment surface including exposure.

**Decisions that should NOT be re-litigated:**

- ApplicationSet+registry pattern (mirrors labops) ✓
- Kyverno installs as shell-script bootstrap (NOT ArgoCD) ✓
- Components ship substrate-agnostic LoadBalancers; Kyverno injects
  pool annotations at admission ✓
- Pool name is `host-pool` (already exists in live cluster) ✓
- `vip-*` Service ownership moves from labops to component repos ✓
- vLLM is out of scope (separate substrate concern, future bundle) ✓

**Resumption etiquette:**

- Do NOT propose architectural changes without re-reading `architecture.md`
  first
- Do NOT propose promotion of methodology to mission-kit until cutover
  (Phase G/4) succeeds — that's the worked-example gate per user convention
- DO update this file's "Current state" table when commits land
- DO append journal entries in `01-design-journal.md` for decisions
- DO mark `05-open-questions.md` Q-X resolutions inline with date + journal pointer
- DO load any of the kate-platform-migration related context from session_search
  if you need depth beyond these three files

---

## Quick-reference file map

```
kate/
├── docs/
│   ├── SESSION-RESUME.md          ← YOU ARE HERE
│   ├── architecture.md            ← authoritative architecture + plan
│   └── research/
│       └── platform-migration/
│           ├── 00-charter.md      ← frozen scope
│           ├── 01-design-journal.md  ← what happened, append-only
│           └── 05-open-questions.md  ← read first when resuming
├── kate.yaml                      ← install entry (not applied yet)
└── bundles/
    ├── README.md
    └── default/
        ├── services.appset.yaml   ← ApplicationSet (mirrors labops)
        └── services.yaml          ← 2-entry registry: hermes + honcho
```
