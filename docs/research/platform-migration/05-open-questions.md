# Platform Migration — Open Questions

**Primary cross-session steering mechanism.** When resuming this work
in a new session, READ THIS FILE FIRST. It captures every unknown
that's actively in flight, where to look for answers, and what each
answer changes.

**Format:** questions are grouped by phase. Each question has:
- **Q:** the question itself
- **Why:** what depends on the answer
- **Where to look:** specific files, commands, or substrates
- **Resolution:** filled in when answered (with date + entry pointer)

---

## Phase D / 3b — Custom container image audit  ✓ RESOLVED 2026-05-26 (journal entry 005)

### Q-D1: What container image is hermes currently running?

**Resolution:** `localhost/hermes-agent:v2026.5.16-voice`. Locally
built, local registry, `-voice` tag suffix denoting the audio
extension layer. `imagePullPolicy: IfNotPresent`. Declared in
`apnex/hermes/manifests/deployment.yaml` line 200.

### Q-D2: Where is the custom image built, and what's the build pipeline?

**Resolution:**
- Build files in-repo at `apnex/hermes/image/` (Dockerfile + build.sh)
- Pipeline: manual `./build.sh` — `docker build` then
  `docker save | k3s ctr -n k8s.io images import` to load directly
  into the k3s node's containerd
- No CI (`.github/workflows/` empty)
- No registry push — image lives only on the k3s node
- Tag controlled by `TAG=` env var, defaults to current version

### Q-D3: What modifications were made vs upstream `apnex/hermes` main?

**Resolution:** The Dockerfile is **exceptionally well-documented**.
Every modification has explicit purpose comments. Base image is
stock `docker.io/nousresearch/hermes-agent:v2026.5.16` (unmodified
upstream). Modifications layered atop:

**Audio/voice stack (universal, potentially upstreamable):**
- System: libportaudio2, libasound2-plugins, alsa-utils
- Python: sounddevice, numpy, faster-whisper, edge-tts
- Discord voice: discord.py, PyNaCl, davey (DAVE E2EE)

**Apnex-specific dev capability (NOT upstreamable):**
- kubectl (cluster admin via ServiceAccount)
- /usr/local/bin/nuc wrapper (SSH-back-to-host)
- gh CLI + system-wide git credential helper using gh auth
- System git identity: hermes / kate@apnex.local

**Other:**
- honcho-ai SDK pre-installed

### Q-D4: Are any modifications now upstream?

**Resolution:** Unknown precisely — but **doesn't matter for the
cutover decision**. Even if 100% of the voice stack is upstreamable,
the apnex-specific dev capability layer (kubectl/nuc/gh) means the
fork must continue. Future cleanup work could PR the voice stack
upstream; doesn't gate cutover.

### Q-D5: For modifications not upstream, are they PR-able?

**Resolution (deferred to future cleanup work):**
- Audio/voice stack: **PR-able** as optional variant or extras
- Apnex-specific (kubectl/nuc/gh): **NOT PR-able** — must remain a
  fork because they're cluster/lab specific

### Q-D6: Where will kate's manifests point — stock image or fork image?

**Resolution: Keep the fork image.** `localhost/hermes-agent:v2026.5.16-voice`
remains the deployment image. The apnex-specific dev capability layer
alone makes the fork mandatory. Kate's `apnex/hermes/manifests/deployment.yaml`
keeps the existing image reference unchanged through cutover.

### Risk 3 assessment: LOW

Original concern was "nobody remembers why these patches exist."
Reality is opposite — Dockerfile is self-documenting, build is
reproducible, modifications are intentional and understood. Phase D
does NOT block cutover.

**Residual concerns to document (NOT blockers):**
1. Image build is manual (no CI). Acceptable for lab.
2. Image lives only on k3s node containerd. If node rebuilt, must
   rebuild image. Acceptable for single-node.
3. Base image pin requires manual bump-and-rebuild. Document upgrade
   procedure in `hermes/image/README.md` (does not exist yet — could
   be a small future polish).

---

## Phase C / 3a — Backup discipline  ✓ PARTIALLY RESOLVED 2026-05-26 (journal entry 006)

### Q-C1: What PVCs exist in `hermes` namespace, and what are they bound to?

**Resolution:** Single PVC `hermes-data`, 10Gi, local-path StorageClass,
bound to PV `pvc-a9187042-3c89-475b-8bb3-92c006f6f610` at
`/var/lib/rancher/k3s/storage/pvc-a9187042-3c89-475b-8bb3-92c006f6f610_hermes_hermes-data`.
Mounted at `/opt/data` in the pod. 273MB used of 1.8TB host capacity.

### Q-C2: Does the hermes PVC have `persistentVolumeReclaimPolicy: Retain`?

**Resolution:** Originally `Delete` (local-path default). **Patched live
to `Retain` 2026-05-26** with:
```bash
kubectl patch pv pvc-a9187042-3c89-475b-8bb3-92c006f6f610 \
  -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```
Future PVCs will default back to `Delete` — fix tracked in
`02-backup-offsite-roadmap.md` § Substrate-level PV protection.

### Q-C3: Same as Q-C1 / Q-C2 but for `honcho` namespace.

**Resolution:** Single PVC `data-postgres-0` (StatefulSet's
volumeClaimTemplate), 10Gi, local-path, bound to PV
`pvc-d7844fdd-1276-4195-b384-e3bf39c27625`. Honcho stack is:
- `honcho` Deployment (API server, stateless)
- `honcho-deriver` Deployment (dialectic worker, stateless)
- `postgres` StatefulSet (pgvector/pgvector:pg17 image) — STATE
- `redis` Deployment (transient queue)

PV reclaim patched to `Retain` 2026-05-26.

### Q-C4: Where will backups be stored off-cluster?

**Resolution:** NUC host at `/root/backups/` (in-cluster trust
boundary). Per user direction, off-host migration deferred — see
`02-backup-offsite-roadmap.md` for the planned Backblaze B2 path.

### Q-C5: How is the Honcho Postgres database authenticated?

**Resolution:** Secret `postgres-credentials` (3 keys:
`POSTGRES_USER=honcho`, `POSTGRES_DB=honcho`, `POSTGRES_PASSWORD`).
envFrom on the `postgres-0` container, so `pg_dump -U "$POSTGRES_USER"
-d "$POSTGRES_DB"` works directly inside the pod via the in-pod env.

### Q-C6: Backup frequency and retention policy?

**Resolution:** Per user direction, NO scheduled backups yet. Manual
only until system is finalised. Scripts ready for cron integration
when ready. Tentative retention discussed (14 daily + 8 weekly + 6
monthly = ~12.5 GB ceiling) but not yet implemented.

### Operational reality check (added during work)

Three iterations of debugging the hermes backup revealed important
operational truths:

1. **Live SQLite + naive tar = corrupt snapshot.** Use Python
   `sqlite3.backup()` API to take MVCC-safe snapshots before tarring.
2. **GNU tar exits 1 on "some files differ as we read"** — usable
   archive per tar docs but kills `set -e` scripts. Explicit
   exit-code handling required.
3. **`kubectl cp` truncates large files** (>50MB observed). Always
   stream via `kubectl exec ... -- cat | <dest>` instead.

All three captured in `02-backup-verification-2026-05-26.md` and in
the final scripts at `kate/scripts/backup-{hermes,honcho}.sh`.

### Outstanding: Restore testing

Restore procedures are documented but have NOT been verified in
practice. Should be done before declaring Phase C truly complete.
Suggested approach: spin up a parallel test namespace, restore the
backup, verify queries.

---

## Phase A / 2 — labops Kyverno bootstrap  ✗ CANCELLED 2026-05-26 (journal entry 008)

**Outcome:** Cancelled. Live empirical validation revealed the design
premise was wrong — the target annotation
`metallb.io/ip-allocated-from-pool` is a MetalLB-written STATUS field,
not a request field. Component manifests are already pool-agnostic.
MetalLB's `autoAssign: true` IS the substrate-default mechanism;
no admission-time decoration needed.

Full investigation: `03-phase-a-kyverno-investigation.md`.
Kyverno scripts kept as OPTIONAL infrastructure in
`apnex/labops/kyverno/` for future use cases (not in default `k3s/up`).

### Q-A1: What's the right Kyverno version to pin? — RESOLVED (moot)

Implementation mirrors `metallb/install`: env-overridable
`KYVERNO_VERSION`, defaults to latest GitHub release. Pattern works,
moot now that Kyverno isn't used.

### Q-A2: Should the Kyverno policy exclude additional namespaces? — RESOLVED (moot)

Decision was: `[kube-system, kyverno, argocd, metallb-system]`. Tested
and worked (kube-system Service correctly NOT mutated). Moot now.

### Q-A3: Is `failurePolicy: Ignore` correct? — RESOLVED (moot)

Decision: Ignore (fail-open). Correct for a home lab. Moot now.

---

## Phase B / 3 — Component vip.yaml  ✓ COMPLETE 2026-05-26 (journal entry 009)

**Outcome:** Completed. Reframed from "author new vip.yaml manifests"
to "verify existing vip manifests + minor cleanup" after Phase A
established that the existing source manifests are already
substrate-portable. Scope ended up being annotation namespace
migration (`metallb.universe.tf/*` → `metallb.io/*`) plus deletion of
the abandoned `labops/stages/` directory.

Full investigation: `04-phase-b-vip-verification.md`.

### Q-B1: What's the exact set of ports each component exposes? — RESOLVED

| Service | Ports | Source manifest |
|---|---|---|
| vip-hermes | 8642 (api), 9119 (dashboard) | `apnex/labops/vip-hermes/service.yaml` |
| vip-honcho | 8000 (http) | `apnex/honcho/manifests/honcho/vip.yaml` |
| vip-argocd-server | 8472:8080 (https) | `apnex/labops/argo/argo.vip.yaml` |

All three share `192.168.1.250` via `metallb.io/allow-shared-ip: host`.

### Q-B2: Naming convention `hermes-vip` vs `vip-hermes`? — RESOLVED (keep current)

Decision: keep `vip-*` convention. Rationale:
- Already used consistently across all three Services
- ArgoCD Applications and references all use `vip-*`
- Renaming would force delete-old-create-new at cutover, increasing
  blast radius for no semantic benefit
- The convention reads naturally: "the VIP for hermes"

Cutover is unchanged — same name, ownership transfers via
`--cascade=orphan` Application handoff (per design journal entry 007).

---

## Phase E / 3c — Live integration continuity

### Q-E1: Where is Discord configuration stored?

**Why:** Determines what survives pod restart.

**Where to look:**
- `kubectl exec hermes -- cat /opt/data/config.yaml` (or wherever config lives)
- `kubectl get secret -n hermes` for token refs
- Hermes Discord plugin docs

**Resolution:** _(unanswered)_

### Q-E2: Does Discord reconnect cleanly after a pod restart today?

**Why:** Validates Phase 4 won't surprise us. If a current `kubectl
rollout restart` causes Discord pain, cutover will too.

**How to test:**
- Pick a low-traffic moment
- Announce in Discord ("brief restart, ~30s")
- `kubectl rollout restart deployment/hermes -n hermes`
- Observe Discord reconnect timing, any failure modes
- Document findings

**Resolution:** _(unanswered)_

### Q-E3: Are there other live integrations beyond Discord?

**Why:** Same survival concerns apply to anything else (Slack, Telegram,
webhooks, etc.).

**Where to look:**
- `kubectl exec hermes -- ls /opt/data/` for plugin configs
- `config.yaml` for enabled integrations

**Resolution:** _(unanswered)_

---

## Phase F — Architecture doc sweep

### Q-F1: What new sections need to be added to architecture.md based on
findings from D, C, A, B, E?

**Why:** Architecture doc is the authoritative reference. It must
incorporate everything learned during due diligence.

**Resolution:** _(deferred until D-E complete)_

---

## Phase G / 4 — Cutover execution

### Q-G1: Cutover window — when and how long?

**Why:** Need to coordinate user availability, announcement timing,
fallback availability.

**Resolution:** _(deferred until F complete)_

### Q-G2: Who validates each step is healthy before proceeding?

**Why:** Cutover has multiple commit points. Each needs verification
before the next step.

**Tentative:** User runs verification commands at each checkpoint; agent
proceeds only on confirmation.

**Resolution:** _(unanswered)_

---

## Cross-phase questions

### Q-X1: Does `labops/docs/superpowers/hermes-platform-roadmap.md` contain
prior thinking that should be cross-referenced?

**Why:** Flagged during recon but not yet read. May contain decisions
or context that affects D, C, A, B, E.

**Where to look:**
- `/host/labops/docs/superpowers/hermes-platform-roadmap.md`

**Resolution:** _(unanswered — read at start of next session if relevant)_

### Q-X2: Should any methodology discovered during this work be promoted
to `apnex/mission-kit`?

**Why:** Per user's multi-session-collaboration-protocol, promotion
requires a worked example. The worked example here is the successful
cutover itself.

**Resolution:** _(deferred until G/4 complete — promotion gate is the
cutover succeeding)_
