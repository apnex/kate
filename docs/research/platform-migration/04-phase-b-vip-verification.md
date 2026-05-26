# Phase B — Component VIP Verification + Annotation Migration (2026-05-26)

**Outcome:** Phase B completed. All three apnex VIP Services successfully
migrated from the legacy `metallb.universe.tf/*` annotation namespace to
the current canonical `metallb.io/*` namespace, with zero service
disruption and IP continuity preserved. As a side cleanup, the
abandoned `apnex/labops/stages/` directory was removed.

## Background

Phase B was originally scoped as "author component vip.yaml manifests"
in the platform migration plan. After Phase A's discovery that
component manifests are already substrate-agnostic (the
`metallb.io/ip-allocated-from-pool` annotation is MetalLB-written
status, not user-set), Phase B was descoped to **verification + minor
cleanup**.

While verifying, two real issues surfaced:

1. **Annotation namespace drift.** All VIP manifests use the legacy
   `metallb.universe.tf/allow-shared-ip: host` annotation. The current
   canonical form in MetalLB v0.16.0 (the deployed version) is
   `metallb.io/allow-shared-ip`. Both forms work for backward
   compatibility, but the canonical form should be used going forward.

2. **Abandoned `labops/stages/` directory.** User-confirmed early
   abandoned experiment. Zero incoming references from any repo. Safe
   to remove.

## What was changed

### Repo: apnex/labops @ master (commits e30bf86, d3494cb)

1. **e30bf86 — cleanup: remove abandoned stages/ directory**
   - Removed `stages/stage4/` entirely (9 files, ~580KB including a
     1MB orphan `boot.iso`)
   - Was an early multi-stage bootstrap experiment (stage1/2/3 never
     materialized); the canonical bootstrap path is direct module
     composition via `k3s/up`, `argo/install`, etc.
   - Public `https://labops.sh/stages/stage4/*` URLs now 404 but
     nothing uses them

2. **d3494cb — vip: migrate metallb.universe.tf -> metallb.io**
   - `vip-hermes/service.yaml`: annotation key migrated
   - `argo/argo.vip.yaml`: annotation key migrated
   - Value `host` unchanged

### Repo: apnex/honcho @ main (commit 27ab82f)

3. **27ab82f — vip: migrate metallb.universe.tf -> metallb.io**
   - `manifests/honcho/vip.yaml`: annotation key migrated
   - Value `host` unchanged

### Live cluster (zero-downtime swap)

Applied in order argocd → hermes → honcho:

| Service | Application mechanism | Result |
|---|---|---|
| vip-argocd-server | `bash argo/set-service` (curls labops.sh) | IP 192.168.1.250 preserved, annotation swapped |
| vip-hermes | ArgoCD sync of `vip-hermes` Application | IP 192.168.1.250 preserved, annotation swapped |
| vip-honcho | ArgoCD sync of `honcho` Application | IP 192.168.1.250 preserved, annotation swapped |

**Smoke tests passed after final swap:**
- hermes dashboard (9119): 200 ✓
- honcho /docs (8000): 200 ✓
- argocd UI (8472): 200 ✓
- All pods Running, no restarts
- All Service endpoints correctly bound

## Why this matters

### Annotation migration

MetalLB has been transitioning its annotation namespace from
`metallb.universe.tf/*` to `metallb.io/*` for several releases. The
CRD group is already `metallb.io` (IPAddressPool, L2Advertisement,
etc.), and v0.16.0 documents the new annotation namespace as
canonical. Continuing to use the legacy form is:

- Fine functionally — both still work in v0.16.0
- Eventually deprecation-fragile — future MetalLB versions may remove
  legacy support
- Inconsistent with the rest of the substrate (CRDs are `metallb.io`)

Migrating now eliminates a deferred-maintenance item before the
migration cutover, and validates that the swap mechanism is safe (it
is — the swap is a single atomic PATCH; MetalLB's watcher never sees
an intermediate state with neither annotation).

### Stages cleanup

The `stages/` directory was a maintenance debt: 580KB of
git-tracked files (1MB binary in git history forever), with no
documented purpose and confirmed-abandoned by the original author. It
also held a stale duplicate of `argo.vip.yaml` that would have been
yet-another-file to keep in sync during the annotation migration.
Removing it simplified the migration to a single canonical file per
VIP.

If a "layered/staged" workflow is wanted later, it should be designed
fresh against the current substrate architecture, not resurrected
from this stale snapshot.

## What this does NOT do

- ❌ Does NOT remove the `metallb.io/ip-allocated-from-pool: host-pool`
  annotation — that's MetalLB-written status, not in source manifests
- ❌ Does NOT change which pool each VIP gets allocated from — still
  `host-pool` via MetalLB autoAssign defaulting
- ❌ Does NOT change the shared IP — still 192.168.1.250 for all three
- ❌ Does NOT change ports, selectors, or any spec field
- ❌ Does NOT touch vip-vllm — already uses the canonical
  `metallb.io/address-pool: vllm-pool` annotation

## Live cluster final state

```
argocd/vip-argocd-server:  IP=192.168.1.250  metallb.io/allow-shared-ip=host
hermes/vip-hermes:         IP=192.168.1.250  metallb.io/allow-shared-ip=host
honcho/vip-honcho:         IP=192.168.1.250  metallb.io/allow-shared-ip=host
```

All three Services share `192.168.1.250` across the following ports:
- 8000 (honcho HTTP)
- 8472 (argocd-server HTTPS)
- 8642 (hermes API)
- 9119 (hermes dashboard)

## Lessons captured

1. **The substrate's annotation namespace matters.** When the
   substrate (MetalLB CRDs, controllers, docs) has moved to a new
   namespace, downstream manifests should follow even if the legacy
   form still works. Treating "both work" as "no action needed" is
   how deprecation cliffs ambush you.

2. **The `last-applied-configuration` annotation is your friend for
   safe swaps.** `kubectl apply` (and ArgoCD's three-way merge)
   handles annotation key renames atomically: the old key disappears
   from `last-applied`, the new key appears, and the diff against
   the live object produces a single PATCH that removes old + adds
   new in one ResourceVersion bump. Substrate watchers (MetalLB)
   only ever see the post-swap state.

3. **Abandoned-but-served orphans are real risk.** `stages/`
   contained scripts publicly served at `labops.sh/stages/*` that
   nothing referenced anymore. Anyone reading old docs or following
   a stale URL would have hit them. Periodic dependency audits
   matter, especially for repos that serve content publicly via
   httpfs/CDN.

## Consequences for migration sequence

| Order | Phase | Status |
|---|---|---|
| 1 | D — Custom image audit | ✓ DONE |
| 2 | C — Backup discipline | ✓ DONE |
| 3 | A — Kyverno bootstrap | ✗ CANCELLED (premise wrong) |
| 4 | B — Component vip.yaml + cleanup | ✓ DONE |
| 5 | E — Integration continuity | NEXT |
| 6 | F — Doc sweep | |
| 7 | G — Cutover | |

Phase E (integration continuity) is next: verify Discord and other
live integrations survive pod restart cleanly before cutover.
