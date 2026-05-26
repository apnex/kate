# SESSION RESUME — read this first if picking up cold

**Project:** kate platform migration (kate / labops / hermes / honcho repos)
**Last active session:** 2026-05-26
**Status:** Phases D, C, B complete; Phase A cancelled; Phase E next. Halted between sessions.

---

## Where to start in 60 seconds

1. **Read `docs/research/platform-migration/05-open-questions.md`** —
   primary steering mechanism. Tells you what's actively in flight,
   what's been answered, what's still unknown. Per user convention,
   this is the canonical "what should I do next" file.

2. **Skim `docs/research/platform-migration/01-design-journal.md`** —
   append-only narrative. Latest entries (009, 008, 007, 006) cover
   the most recent session. Tells you what happened, what was decided
   and why.

3. **Reference `docs/architecture.md`** when implementing — the
   authoritative architecture and 4-phase plan, including the
   production cutover risks section.

That's it. Three files. You're caught up.

---

## Current state

| Repo | HEAD | Status |
|---|---|---|
| `apnex/kate` | `0e9d563` (main) | Phase B complete; structurally correct but NOT installable until Phase G cutover |
| `apnex/labops` | `d3494cb` (master) | stages/ removed; vip-hermes + argo.vip annotations migrated to metallb.io/* |
| `apnex/hermes` | unchanged | Has Deployment + ClusterIP; no vip.yaml yet (out of scope per Phase A finding) |
| `apnex/honcho` | `27ab82f` (main) | vip-honcho annotation migrated to metallb.io/* |

**Live cluster state — modified by previous sessions:**

- ✅ PV `pvc-a9187042-...` (hermes-data) and `pvc-d7844fdd-...` (honcho postgres) patched to `Retain` (Phase C — data-loss insurance during cutover)
- ✅ All three VIP Services (vip-hermes, vip-honcho, vip-argocd-server) migrated from `metallb.universe.tf/allow-shared-ip` to `metallb.io/allow-shared-ip` (Phase B). Shared IP `192.168.1.250` preserved across the swap.
- ✅ Backup scripts proven working: `scripts/backup-hermes.sh` (361MB bundle) and `scripts/backup-honcho.sh` (pg_dump) — backups land in `/root/backups/{hermes,honcho}/` on NUC.
- ❌ Kyverno NOT installed (Phase A cancelled — substrate already provides what it would have via MetalLB autoAssign).
- ⏸ Discord / Yuanbao / other live integrations untouched — Phase E will assess.

---

## Phase status

| Order | Phase | Status |
|---|---|---|
| 1 | D — Custom image audit | ✓ DONE (entry 006) |
| 2 | C — Backup discipline | ✓ DONE (entry 006, 007 for PV Retain durability) |
| 3 | A — Kyverno bootstrap | ✗ CANCELLED (entry 008 — premise wrong) |
| 4 | B — VIP verification + cleanup | ✓ DONE (entry 009) |
| 5 | **E — Integration continuity** | ← **NEXT** |
| 6 | F — Doc sweep | |
| 7 | G — Cutover | |

**Phase E scope:** verify Discord/Yuanbao/other live integrations
survive pod restart cleanly before cutover. Requires a planned
`kubectl rollout restart` at a low-traffic moment — user
coordination needed before executing.

---

## Critical context to remember

**The substrate/composition/component boundary is sharp:**

- **labops** = substrate (k3s, MetalLB, ArgoCD bootstrap). Shell-script
  bootstrapped, not ArgoCD-managed. The `kyverno/` directory exists
  but is NOT in the default `k3s/up` chain (kept as optional infra
  for future use cases; see `labops/kyverno/README.md`).
- **kate** = composition — which components compose the platform.
  Pure intent in `bundles/default/services.yaml`. ArgoCD-managed.
- **hermes / honcho** = components — workload manifests,
  substrate-agnostic. Each owns its full deployment surface including
  exposure (vip.yaml).

**Substrate-portability work is COMPLETE as of Phase B:**

- Component manifests are pool-agnostic (Phase A finding: MetalLB's
  `autoAssign: true` is the substrate-default mechanism; no pool
  annotation needed in source manifests)
- Annotation namespace is canonical `metallb.io/*` (Phase B work)
- vLLM still uses explicit `metallb.io/address-pool: vllm-pool` —
  correct, this is intentional pool selection

**Decisions that should NOT be re-litigated:**

- ApplicationSet+registry pattern (mirrors labops) ✓
- Kyverno NOT installed (cancelled; substrate already provides) ✓
- Components are pool-agnostic via MetalLB autoAssign defaulting ✓
- VIPs keep `vip-*` naming convention (Q-B2 resolved) ✓
- Pool name is `host-pool` (alphabetically-first autoAssign pool) ✓
- vLLM is out of scope (separate substrate concern, future bundle) ✓
- PV reclaim policy is `Retain` on hermes/honcho PVs (Phase C) ✓
- Cutover handoff uses `kubectl delete application --cascade=orphan`
  to transfer ownership without deleting children (entry 007) ✓
- Backups use `kubectl exec ... cat` streaming (not `kubectl cp`) and
  Python `sqlite3.backup()` API for live-DB consistency (entry 006) ✓

**Resumption etiquette:**

- Do NOT propose architectural changes without re-reading
  `architecture.md` first
- Do NOT propose promotion of methodology to mission-kit until cutover
  (Phase G) succeeds — that's the worked-example gate per user
  convention
- DO update this file's "Current state" table when commits land
- DO append journal entries in `01-design-journal.md` for decisions
- DO mark `05-open-questions.md` Q-X resolutions inline with date +
  journal pointer
- DO load any of the kate-platform-migration related context from
  session_search if you need depth beyond these three files

---

## Quick-reference file map

```
kate/
├── docs/
│   ├── SESSION-RESUME.md                          ← YOU ARE HERE
│   ├── architecture.md                            ← authoritative architecture + plan
│   └── research/
│       └── platform-migration/
│           ├── 00-charter.md                      ← frozen scope
│           ├── 01-design-journal.md               ← what happened (entries 1-9), append-only
│           ├── 02-backup-procedures.md            ← backup/restore operational guide
│           ├── 02-backup-verification-2026-05-26.md  ← Phase C verification log
│           ├── 03-phase-a-kyverno-investigation.md   ← why Phase A was cancelled
│           ├── 04-phase-b-vip-verification.md     ← Phase B annotation migration log
│           └── 05-open-questions.md               ← read first when resuming
├── scripts/
│   ├── backup-hermes.sh                           ← verified working: state.db SQLite snapshot + tar
│   └── backup-honcho.sh                           ← verified working: pg_dump snapshot
├── kate.yaml                                       ← install entry (not applied yet)
└── bundles/
    ├── README.md
    └── default/
        ├── services.appset.yaml                   ← ApplicationSet (mirrors labops)
        └── services.yaml                          ← 2-entry registry: hermes + honcho
```

**External repos:**

```
labops/                                            ← apnex/labops @ master d3494cb
├── kyverno/                                       ← OPTIONAL infra (NOT in k3s/up)
│   ├── README.md                                  ← explains why optional
│   ├── install, prepare, remove                   ← validated working
│   └── policy-default-metallb-pool.yaml           ← sample policy (Phase A artifact)
├── vip-hermes/service.yaml                        ← metallb.io/allow-shared-ip: host
├── argo/argo.vip.yaml                             ← metallb.io/allow-shared-ip: host
└── (stages/ REMOVED in Phase B cleanup)

honcho/                                            ← apnex/honcho @ main 27ab82f
└── manifests/honcho/vip.yaml                      ← metallb.io/allow-shared-ip: host
```

---

## Backup status

**Most recent verified backups (2026-05-26):**
- `/root/backups/hermes/hermes-backup-*.tar.gz` (361MB, 7,711 messages verified in state.db)
- `/root/backups/honcho/honcho-backup-*.sql.gz` (pg_dump verified)

**Recommended pre-cutover refresh:** Re-run both backup scripts on
the day of Phase G cutover before any destructive operations.
