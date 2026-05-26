# Platform Migration — Design Journal

**Append-only.** New entries at the bottom. Use strike-through for
corrections; do not delete or edit prior entries.

Entry format:
- Date + number
- Topic
- What happened / decided
- Why
- Consequences / next actions

---

## Entry 001 — 2026-05-26 — Kate architecture stabilised (Phase 1 complete)

**What:** After a multi-iteration design conversation, kate's architecture
landed in `apnex/kate` at commit `10670fc` (atop `a1239b2`).

**Why:** Multiple refinements of the substrate/composition/component
boundary during the conversation:

1. Started with hand-rolled ArgoCD Application files per workload
2. Discovered labops's existing ApplicationSet+registry pattern in
   `labops/argo/services.appset.yaml` + `services.yaml`
3. Adopted the same pattern in kate (mirror, not invent)
4. Refined boundary: components own full deployment surface including
   exposure (vip.yaml moves into hermes/honcho repos)
5. Sharper refinement: substrate-awareness lives only in substrate;
   components ship substrate-agnostic manifests; substrate decorates
   via cluster-wide Kyverno policies at admission

Final commits to kate:
- `a1239b2` — `refactor(bundles): adopt ApplicationSet+registry pattern`
- `10670fc` — `docs: capture multi-phase platform architecture + migration plan`

**Consequences:** Kate is structurally correct but NOT yet installable.
Labops's registry still owns hermes/honcho. Cutover (Phase 4) requires
coordinated multi-repo changes plus risk mitigation work.

---

## Entry 002 — 2026-05-26 — Production cutover risks identified

**What:** During the "ready to execute?" reality check, four risks
surfaced that span beyond the architectural cutover:

1. **Hermes session state** — transcripts, skills, memory, configuration
2. **Honcho state** — Postgres database with months of memory
3. **Custom container image** — modifications to plugins + audio of
   unclear provenance; current pod runs a custom-built image
4. **Live integrations** — Discord connectivity, channel mappings,
   reconnection behaviour

**Why this matters:** The kate cutover was originally drafted as a
self-contained architectural operation. These risks are not unique to
cutover — they're standing operational concerns of running Hermes/Honcho
on k8s — but cutover forces them into focus. None is intrinsically
hard; all need explicit handling before Phase 4.

**Decisions:**

- Insert pre-cutover due diligence phases: 3a (backup discipline),
  3b (custom image audit), 3c (live integration verification)
- These can run in parallel; all gate Phase 4
- Sequence approved by user, ranked by importance: D/3b first (biggest
  unknown), C/3a second (should exist anyway), A/2 third, B/3 fourth,
  E/3c fifth, F sixth, G/4 last

**Consequences:** Phase 4 timeline extends; safety improves
significantly. The forced operational hygiene is positive even
independent of cutover success.

---

## Entry 003 — 2026-05-26 — Kyverno install path: shell-script bootstrap (NOT ArgoCD)

**What:** During Phase 2 design, originally proposed Kyverno as an
ArgoCD-managed Application via the labops registry. User pushed back:
MetalLB is the precedent — it MUST be shell-bootstrapped because
ArgoCD itself requires MetalLB. Kyverno should follow the same model
for consistency.

**Why:** Substrate layer is shell-imperative; kate layer is
ArgoCD-declarative. Sharper boundary.

**Decision:** Kyverno installs via `labops/kyverno/install` +
`labops/kyverno/prepare` shell scripts, integrated into `k3s/up` chain:
`k3s/install → metallb/install → metallb/prepare → kyverno/install →
kyverno/prepare → argo/install`.

**Consequences:**

- labops's `argo/services.yaml` registry may be **empty or near-empty**
  after Phase 4 cutover. The ArgoCD registry mechanism lives in labops,
  but every entry in it belongs to kate. This is the correct boundary.
- Phase 2 plan in `architecture.md` updated to reflect this.

---

## Entry 009 — 2026-05-26 — Phase B COMPLETE: annotation namespace migrated, stages/ cleanup

**What:** Phase B completed. Three subsequent changes (one cleanup, two
annotation migrations) landed across two repos with zero service
disruption. Full details in `04-phase-b-vip-verification.md`.

**Discoveries during verification:**

1. **Annotation namespace drift.** All three VIP Services
   (vip-hermes, vip-honcho, vip-argocd-server) were using the legacy
   `metallb.universe.tf/allow-shared-ip` annotation. MetalLB v0.16.0
   has migrated to `metallb.io/allow-shared-ip` as the canonical
   form. Both work for backward compatibility but the canonical form
   is the future-proof choice.

2. **`labops/stages/` directory abandoned.** Single half-built
   `stage4` experiment from early labops history, with a 1MB orphan
   `boot.iso` and self-contained script duplicates of canonical
   `argo/*` modules that had since drifted. Zero incoming references
   from anywhere. Safe to delete.

3. **Multiple sources for the three VIPs:**
   - `vip-hermes` → `apnex/labops/vip-hermes/service.yaml` (ArgoCD-owned)
   - `vip-honcho` → `apnex/honcho/manifests/honcho/vip.yaml` (child of honcho App)
   - `vip-argocd-server` → `apnex/labops/argo/argo.vip.yaml` (no ArgoCD ownership,
     applied via `argo/set-service` curling labops.sh)

**Changes committed:**

- `apnex/labops@e30bf86` — cleanup: remove abandoned stages/
- `apnex/labops@d3494cb` — vip: migrate metallb annotations
- `apnex/honcho@27ab82f` — vip: migrate metallb annotations

**Live application sequence (zero-downtime):**

1. `vip-argocd-server` via `bash argo/set-service` — IP preserved
2. `vip-hermes` via ArgoCD sync — IP preserved
3. `vip-honcho` via ArgoCD sync — IP preserved

**Mechanism validated:** `kubectl apply`'s three-way merge handles
annotation-key renames as a single atomic PATCH. MetalLB's watcher
never sees an intermediate state with neither annotation; the swap
preserves the shared IP across all sharing Services.

**Smoke tests post-swap:**
- hermes dashboard :9119 → 200 ✓
- honcho /docs :8000 → 200 ✓
- argocd :8472 → 200 ✓
- All pods Running, zero restarts triggered by the sync
- All Service endpoints correctly bound

**Architectural consequence:** The substrate-portability work is now
complete. Component manifests are pool-agnostic (per Phase A) AND on
the canonical annotation namespace (per this entry). When the kate
platform reorganization happens at cutover (Phase G), VIPs will move
cleanly between ApplicationSets without manifest changes.

**Side benefit from stages/ removal:** Eliminated 580KB of git
history weight, the `argo.vip.yaml` duplicate that would have needed
sync, and a public `labops.sh/stages/*` zombie endpoint surface.

**Sequence:**

| Order | Phase | Status |
|---|---|---|
| 1 | D — Custom image audit | ✓ DONE |
| 2 | C — Backup discipline | ✓ DONE |
| 3 | A — Kyverno bootstrap | ✗ CANCELLED |
| 4 | B — Component vip.yaml + cleanup | ✓ DONE |
| 5 | E — Integration continuity | NEXT |
| 6 | F — Doc sweep | |
| 7 | G — Cutover | |

---

## Entry 008 — 2026-05-26 — Phase A CANCELLED: substrate already provides what Kyverno would have

**What:** Phase A (labops Kyverno bootstrap) cancelled after live
empirical validation revealed the design premise was wrong. The
mechanism was meant to inject `metallb.io/ip-allocated-from-pool:
host-pool` onto pool-agnostic component Services at admission time.
Reality: that annotation is a MetalLB-written STATUS field, not a
user-set request field. The actual substrate-default mechanism is
MetalLB's `autoAssign: true` which picks the first matching pool when
no annotation is set.

**Live validation that produced the finding:**
1. Wrote 4 production scripts (`kyverno/install|prepare|remove` +
   `policy-default-metallb-pool.yaml`) + modified `k3s/up`
2. Ran install — Kyverno installed cleanly, 4 deployments, 20 CRDs
3. Ran prepare — ClusterPolicy applied, status READY, admission
   webhook active
4. Test: created LoadBalancer Service with no annotation → Kyverno
   logs confirmed mutation rule fired → BUT final stored object had
   no `metallb.io/ip-allocated-from-pool` annotation
5. Investigated `vip-hermes` source manifest → it has NO pool
   annotation either, only `metallb.universe.tf/allow-shared-ip:
   host`. The live annotation is MetalLB-written status.
6. Confirmed: `vip-vllm` uses `metallb.io/address-pool: vllm-pool`
   (the actual REQUEST annotation), which is a different field
   entirely.

**Architectural consequences:**

- Phase A drops out of the migration entirely
- Phase B becomes a verification step ("confirm component manifests
  are pool-agnostic" — they already are)
- Total cutover work decreased
- Substrate boundary is slightly less opinionated (relies on MetalLB
  autoAssign rather than explicit policy) but substrate-portability
  is achieved either way

**What was kept:**

- `apnex/labops/kyverno/` as OPTIONAL infrastructure for future use
  cases (multi-substrate pool defaulting, validation policies,
  sidecar injection, etc.)
- `kyverno/README.md` documents the optional status and the Phase A
  finding so future users know why it's not in `k3s/up`

**What was removed:**

- Kyverno from the cluster (via `kyverno/remove` — clean removal:
  namespace, CRDs, all RBAC, all controllers, no residue)
- The `kyverno/install kyverno/prepare` modules from `k3s/up`
  MODULES array (reverted to original)

**Side findings worth keeping:**

1. labops scripts run on the NUC HOST, not from inside the hermes
   pod (`jq` missing in hermes container). This is by design — labops
   is substrate-tier; the agent talking to the substrate runs the
   scripts via SSH (`nuc 'bash labops/...'`).

2. `vip-vllm` is the canonical example of how to explicitly request a
   pool: `metallb.io/address-pool: vllm-pool`. Other Services using
   the default (vip-hermes, vip-honcho, vip-argocd-server) have NO
   pool annotation in source manifests — MetalLB's autoAssign picks
   `host-pool` because it's the first matching pool with `autoAssign:
   true`.

3. Two MetalLB IPAddressPools currently in cluster, both
   `autoAssign: true`: `host-pool` (192.168.1.250/32) and `vllm-pool`
   (192.168.1.251/32). If both are autoAssign and a Service doesn't
   request either, the alphabetical first wins (`host-pool`). This is
   stable but worth noting if a third pool is ever added.

**Lessons captured in `03-phase-a-kyverno-investigation.md`:**

- Validate the premise (request vs status fields) BEFORE designing
  the mechanism
- Distinguish status fields from spec fields, especially in
  annotations
- Production validation surfaces architectural errors faster than
  design review
- labops scripts execute on the substrate host, not from agent pods

**Files committed:**

- `apnex/labops` master @ c7df642:
  - `kyverno/install`, `prepare`, `remove`, `policy-default-metallb-pool.yaml`, `README.md`
  - `.gitignore` (excluded accidentally-committed `.claude/settings.local.json`)
- `apnex/kate` main (this commit):
  - `docs/research/platform-migration/03-phase-a-kyverno-investigation.md`
  - `docs/research/platform-migration/01-design-journal.md` (entry 008)
  - `docs/research/platform-migration/05-open-questions.md` (Q-A1..A6 resolved, phase marked cancelled)

**Consequences for sequence:**

| Order | Phase | Status |
|---|---|---|
| 1 | D — Custom image audit | ✓ DONE |
| 2 | C — Backup discipline | ✓ DONE |
| 3 | A — Kyverno bootstrap | ✗ CANCELLED (premise wrong) |
| 4 | B — Component vip.yaml | NEXT (now a verification step) |
| 5 | E — Integration continuity | |
| 6 | F — Doc sweep | |
| 7 | G — Cutover | |

---

## Entry 007 — 2026-05-26 — PV Retain durability confirmed; cascade=orphan pattern documented

**Trigger:** User question after Phase C — "Setting PVs to Retain - won't
be overridden by Argo - because the PVCs are unchanged?"

**Verified on live cluster:**
- PVCs ARE ArgoCD-tracked (hermes-data has `tracking-id`
  annotation; data-postgres-0 doesn't because it's STS-generated)
- PVs are NOT ArgoCD-tracked (only `local.path.provisioner` annotations)
- Both PVs still show `RECLAIM: Retain` — patch sticks
- PVC manifests have no `persistentVolumeReclaimPolicy` field (PV-level
  concept) so there's nothing for ArgoCD to "fix back to default"

**Two important nuances surfaced and documented in
`02-backup-procedures.md`:**

1. **Retain = data recovery, not data continuity.** If the PVC is
   deleted-and-recreated, the old PV becomes Released-but-orphaned;
   new PVC gets a new empty PV. Manual rebinding required to recover.
2. **StatefulSet PVCs are sneakier.** `data-postgres-0` is created by
   `volumeClaimTemplates`, so ArgoCD can't accidentally prune it
   directly. But `kubectl delete sts` with `--cascade=foreground` or a
   separate `kubectl delete pvc` would bypass both protections.

**New cutover safety invariant added to procedures doc:**

> Never set `prune: true` on ArgoCD Applications that own PVCs, until
> the PVCs themselves have been migrated to a custom StorageClass with
> Retain default.

**Phase 4 handoff pattern documented:** use
`kubectl delete application <name> -n argocd --cascade=orphan` to
remove the labops-owned Application without deleting any children.
The new kate-owned Application then adopts them by name+namespace on
next reconcile. No object is ever deleted during the handoff.

**Files updated:**
- `02-backup-procedures.md` — § "Cutover insurance" expanded to cover
  ArgoCD tracking analysis, Retain vs continuity distinction, sync
  discipline invariant, and the `--cascade=orphan` handoff pattern

**Consequences:**
- Phase 4 plan now has an explicit, named safety pattern
  (`--cascade=orphan`) rather than relying on vague "be careful"
- The "custom StorageClass with Retain default" deferred work (tracked
  in offsite roadmap doc) gains a second motivation: it makes future
  cutovers safer-by-default, not just current-PV-safer

---

## Entry 006 — 2026-05-26 — Phase C resolved: backups working, PVs patched

**What:** Six Q-C questions answered. Two PVs (hermes-data,
data-postgres-0) patched live from `Delete` to `Retain` reclaim policy
as cutover insurance. Two production backup scripts written, debugged
through three iterations, and verified end-to-end with byte-exact
integrity checks.

**PV reclaim patches applied:**
- `pvc-a9187042-...` (hermes-data) → Retain
- `pvc-d7844fdd-...` (data-postgres-0) → Retain

**Backups verified:**
- `/root/backups/hermes/hermes-*.tar.gz` — 346 MB, gzip integrity OK,
  13063 files, SQLite snapshots present, state.db verified to contain
  79 sessions + 7711 messages intact
- `/root/backups/honcho/honcho-*.sql.gz` — 53 MB, pg_dump
  transactionally consistent

**Three operational lessons discovered (captured in journal,
verification doc, and procedures doc):**

1. Live SQLite + tar = corrupt snapshot. Use `sqlite3.backup()` API.
   In-pod: `/opt/hermes/.venv/bin/python` has sqlite3 stdlib.
2. GNU tar exits 1 (warning, archive usable) for "files differ as we
   read", which `set -e` treats as fatal. Explicit RC handling needed.
3. `kubectl cp` truncates large files. ALWAYS use `kubectl exec --
   cat | <dest>` for any binary transfer > 50MB.

**Per user direction:**
- Backup target: NUC `/root/backups/` for now
- Off-host (Backblaze B2): designed in `02-backup-offsite-roadmap.md`,
  deferred until system finalised
- No scheduled backups yet — manual only until system is finalised
- Substrate-level PV protection (custom StorageClass with Retain
  default): tracked in offsite roadmap doc for future labops work

**Files created/updated in apnex/kate:**
- `kate/scripts/backup-hermes.sh` — production-ready, ~80 lines
- `kate/scripts/backup-honcho.sh` — production-ready, ~25 lines
- `kate/docs/research/platform-migration/02-backup-procedures.md` —
  comprehensive procedure doc with restore commands
- `kate/docs/research/platform-migration/02-backup-offsite-roadmap.md` —
  the deferred Option (b) design
- `kate/docs/research/platform-migration/02-backup-verification-2026-05-26.md` —
  first-run verification log with all three iteration lessons

**Outstanding:**
- Restore procedures documented but NOT TESTED. Should be done before
  cutover. Suggested: parallel test namespace, restore, query verify.

**Consequences:**
- Phase C / 3a substantially complete; Risk 1 + Risk 2 are now in
  manageable shape
- Two of three "biggest unknowns" (D, C) are now closed
- Phase ordering proceeds to A / 2 (labops Kyverno bootstrap) next
- One residual phase-C task: restore testing (small, can be folded
  into Phase E or done independently)

---

## Entry 005 — 2026-05-26 — Phase D resolved: Risk 3 is LOW, cutover NOT blocked

**What:** Audited the custom container image. All six Q-D questions
resolved in one investigation pass.

**Image:** `localhost/hermes-agent:v2026.5.16-voice`. Built locally via
`apnex/hermes/image/build.sh` from a self-documenting Dockerfile that
layers two distinct concerns atop the stock upstream image:

1. **Audio/voice stack** (PR-able, universal) — PortAudio, ALSA,
   sounddevice, faster-whisper, edge-tts, discord.py + PyNaCl + davey
   for voice channel support
2. **Apnex-specific dev capability** (NOT PR-able, lab-specific) —
   kubectl for cluster admin, /usr/local/bin/nuc SSH-back-to-host
   wrapper, gh CLI + system-wide git credential helper, system git
   identity hermes/kate@apnex.local

**Why this matters:** The originally-feared scenario was "nobody
remembers why these patches exist, audit is needed before cutover."
Reality is the opposite — the Dockerfile is exceptionally
self-documenting, every modification has an explicit comment block
explaining what and why. The build process is simple and reproducible.

**Decisions:**

- **Risk 3 reclassified: LOW.** Does NOT block cutover.
- **Keep the fork image.** The apnex-specific layer alone makes the
  fork mandatory even if the entire audio stack were upstreamed
  tomorrow.
- **Kate's manifests unchanged.** `apnex/hermes/manifests/deployment.yaml`
  already references the fork image; no Phase 4 changes needed for
  this aspect.

**Residual concerns (NOT blockers, documented for future):**
- Image build is manual (no CI) — acceptable for lab
- Image lives only on k3s node containerd — acceptable for single-node
- Base image pin requires manual bump-and-rebuild — could benefit from
  a small `hermes/image/README.md` documenting the upgrade procedure

**Consequences:**
- Phase D / 3b complete, faster than expected
- Phase ordering proceeds to C / 3a (backup discipline) next
- One less unknown gating Phase 4

---

## Entry 004 — 2026-05-26 — Session halt; resumption documentation in place

**What:** Session ends here. Created `docs/research/platform-migration/`
folder with canonical 4-file layout and `docs/SESSION-RESUME.md` top-level
pointer.

**Why:** Each phase from here onwards (D/3b first) is substantial enough
to deserve a dedicated session. Resumption needs to be friction-free.

**Consequences:** Next session can pick up cold by:
1. Reading `kate/docs/SESSION-RESUME.md` (the "where am I")
2. Reading `kate/docs/research/platform-migration/05-open-questions.md`
   (the "what's actively in flight")
3. Reading the relevant phase section in `kate/docs/architecture.md`
   for full context

Phase D (custom image audit) is the next planned work.
