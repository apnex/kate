# kate — architecture

**Status:** living document. Last revised 2026-05-26.
**Audience:** future sessions of this work, contributors, anyone installing kate.

This document captures the architectural reasoning behind kate's structure
and the multi-phase migration plan that takes the apnex k3s cluster from
its current state (labops owns hermes/honcho/vip-* directly) to the
target state (kate owns the agent platform, labops owns only the
substrate).

---

## Vision

**kate is an opinionated, GitOps-installable agent platform on Kubernetes.**

Three load-bearing words:

- **Opinionated** — kate picks the components (Honcho for memory, Hermes
  for the agent harness, mission-kit for skills, hermes-plugins for
  capabilities) and the integration shape. A user installs kate, not
  "a collection of things."
- **Platform** — kate is the umbrella product. The individual repos
  (hermes, honcho, mission-kit, labops, hermes-plugins) are *components*
  it composes. None of them is the install target on its own.
- **GitOps-installable** — install is "point ArgoCD at kate.yaml and
  walk away." Drift detection, rollback, declarative everything.

Pre-requisite: a Kubernetes cluster with ArgoCD already installed. Kate
does not bring up the cluster — that's the substrate's responsibility
(see [Boundaries](#boundaries) below). The reference substrate is
`apnex/labops`, but kate is designed to be substrate-agnostic.

---

## Boundaries

Three repositories, three knowledge domains, **no overlap**:

| Repo | Owns | Knowledge |
|---|---|---|
| **Substrate** (`apnex/labops`) | The cluster and its infra primitives | "This cluster has MetalLB with `host-pool` at 192.168.1.250. Any LoadBalancer Service in this cluster should get my pool annotations." |
| **Composition** (`apnex/kate`) | Which components compose the platform | "Install hermes and honcho. I don't care what cluster this is." |
| **Component** (`apnex/hermes`, `apnex/honcho`) | What each workload IS | "I am hermes. I need a Deployment, a ClusterIP, and a LoadBalancer. I don't care about MetalLB pools." |

**The boundary is sharp:** substrate-awareness lives only in the
substrate. Components express what they are. Compositions express what
to install. Substrates decorate at admission time with substrate-specific
opinions.

This is what makes kate portable. The same `kate.yaml` can install on
apnex/labops (gets MetalLB host-pool annotations), on a cloud k8s cluster
(gets cloud LB annotations from a different substrate's policies), or on
a kind/minikube dev cluster (no policies, LBs stay pending — harmless).

---

## The four-repo composition model

```
                       ┌─────────────────────────────┐
                       │      apnex/labops           │
                       │   (substrate)               │
                       │                             │
                       │  • k3s + MetalLB + storage  │
                       │  • ArgoCD installation      │
                       │  • Registry mechanism       │
                       │    (ApplicationSet 'services')
                       │  • Kyverno + substrate      │
                       │    defaults policies        │
                       │                             │
                       │  argo/services.yaml:        │
                       │    - kyverno                │
                       │    - kyverno-policies-labops│
                       │    - (any future infra)     │
                       └──────────────┬──────────────┘
                                      │
                                      │  ArgoCD installed,
                                      │  Kyverno mutating LBs
                                      │  at admission
                                      ↓
                       ┌─────────────────────────────┐
                       │       apnex/kate            │
                       │   (composition)             │
                       │                             │
                       │  kate.yaml                  │
                       │     ↓                       │
                       │  bundles/default/           │
                       │    services.appset.yaml ───────────┐
                       │    services.yaml            │      │
                       │      - hermes               │      │
                       │      - honcho               │      │
                       └─────────────────────────────┘      │
                                                            │
                                                            │  one Application
                                                            │  per registry entry
                                                            ↓
                       ┌─────────────────────────────────────────────┐
                       │  Component repos (apnex/hermes, apnex/honcho)│
                       │                                             │
                       │  manifests/                                 │
                       │    deployment.yaml   (workload)             │
                       │    service.yaml      (ClusterIP)            │
                       │    vip.yaml          (LoadBalancer —        │
                       │                       NO MetalLB annotations)│
                       │                                             │
                       │  Substrate-agnostic. Kyverno injects pool   │
                       │  annotations at admission time.             │
                       └─────────────────────────────────────────────┘
```

### Mechanism details

**The substrate registry pattern** (labops/argo/services.appset.yaml):

ArgoCD ApplicationSet with a `git-generator` reads
`labops/argo/services.yaml`. Every entry becomes one ArgoCD Application,
templated uniformly (auto-sync, self-heal, prune, retry). Both `git` and
`helm` source types supported via `templatePatch`.

**Kate mirrors this pattern** in `kate/bundles/default/services.appset.yaml`:

Identical structure, kate-specific naming (`kate-default` ApplicationSet,
reads kate's own registry). Adopting the labops pattern keeps the mental
model uniform across the two layers — anyone who understands one
understands the other.

**Bundles as alternative compositions.** Each `bundles/<name>/` folder
is a self-contained alternative install: same shape, different registry
contents. Switching bundles is a single sync operation (change the kate
Application's `source.path`).

**Substrate defaults via Kyverno.** A cluster-wide `ClusterPolicy` in
labops mutates `Service` admissions: if `type: LoadBalancer` and no
`metallb.universe.tf/address-pool` annotation, inject `host-pool` plus
`allow-shared-ip: host`. Components stay clean; substrate decorates.

Escape hatch: Services that explicitly set `address-pool` (e.g. vLLM's
`vllm-pool`) are not mutated. The default applies; explicit overrides
win.

---

## Component sovereignty — known violations

The boundaries above are aspirational. As of 2026-05-27, component repos
(currently `apnex/hermes`; `apnex/honcho` not yet audited) assert things
that belong to either the substrate or the bundle. The audit was forced
into visibility by building the first non-default bundle (`bundles/minimal/`):
each variant beyond `default` re-exposes the leaks, and fixing them at
the right layer is what makes "minimal vs default vs advanced" meaningful
rather than a series of patches papering over upstream coupling.

```
                    ┌──────────────────────────────────────┐
                    │  Currently leaked into hermes:       │
                    │                                      │
                    │  ┌──────────────────────────────┐    │
  substrate ──→     │  │ pv.yaml: nodeAffinity=obpc   │    │  ←── belongs to substrate
                    │  └──────────────────────────────┘    │      (dynamic SC, cluster
                    │                                      │       default binding)
                    │  ┌──────────────────────────────┐    │
  component ──→     │  │ deployment.yaml:             │    │  ←── belongs to component
                    │  │   image: localhost/…         │    │      (registry-published
                    │  └──────────────────────────────┘    │       image)
                    │                                      │
                    │  ┌──────────────────────────────┐    │
  operator   ──→    │  │ deployment.yaml:             │    │  ←── belongs to operator
                    │  │   HERMES_HOST_SSH_TARGET=… │    │      (Secret-supplied,
                    │  │   (hardcoded NUC IP)         │    │       optional; default
                    │  └──────────────────────────────┘    │       inert)
                    │                                      │
                    │  ┌──────────────────────────────┐    │
  bundle     ──→    │  │ deployment.yaml:             │    │  ←── belongs to bundle
                    │  │   /run/user/1000 + /root     │    │      (voice-bundle-only
                    │  │   hostPath mounts            │    │       overlay; non-voice
                    │  └──────────────────────────────┘    │       bundles get no mount)
                    │                                      │
                    │  apnex/hermes/manifests/             │
                    └──────────────────────────────────────┘
```

| # | Violation | Currently in | Should live in | Status |
|---|---|---|---|---|
| 1 | Static PV with `nodeAffinity: obpc` | `hermes/manifests/pv.yaml` | Cluster default SC; hermes uses dynamic PVC | In progress |
| 2 | `image: localhost/hermes-agent:…` | `hermes/manifests/deployment.yaml` | Public registry image; bundle can pin a tag | In progress |
| 3 | `HERMES_HOST_SSH_TARGET=root@192.168.1.250` | `hermes/manifests/deployment.yaml` | Optional `hermes-secrets` key; default empty → `nuc` inert | Planned |
| 4 | `/run/user/1000` + `/root` hostPath mounts | `hermes/manifests/deployment.yaml` | Voice-bundle overlay only; non-voice bundles drop the mounts | Planned |

Order-of-attack rationale: **#2 first** (publish a registry image — one push
unblocks every non-NUC cluster instantly); **#1 second** (drop the static PV
and rely on the cluster default SC — minimal bundle then runs anywhere
substrate-clean); **#3 and #4** are quality-of-life cleanups that sharpen
the operator and bundle boundaries respectively.

---

## Current state (HEAD as of 2026-05-27)

| Repo | HEAD | State |
|---|---|---|
| `apnex/kate` | `757e911` | `bundles/default` + `bundles/minimal` (hermes-only, honcho-disabled overlay); substrate boundary documented |
| `apnex/labops` | `2dd7e0b` | Substrate-only after the split: `argo/install` is platform-only (`services.appset.yaml` + `services.yaml` deleted); script preamble + profile.d PATH fix + StorageClass `Retain`; no Kyverno yet |
| `apnex/hermes` | `a88fc8a` | `manifests/` + top-level `vip.yaml` (moved from labops); the four component-sovereignty violations above are not yet fixed |
| `apnex/honcho` | (unchanged) | not audited yet |

**Live cluster:**
- 3 ArgoCD Applications: `hermes`, `honcho`, `vip-hermes` (managed by labops's ApplicationSet)
- 1 ungoverned Service: `vip-honcho` (manually applied from `labops/vip-honcho/`, NOT in registry)
- MetalLB pools: `host-pool` (192.168.1.250), `vllm-pool` (192.168.1.251)

---

## Migration plan — four phases

### Phase 1 — kate-side architecture ✓ DONE

**What:** Rewrite kate's bundle layout to use ApplicationSet+registry
pattern, mirroring labops.

**Files in `apnex/kate`:**
- `kate.yaml` — install entry (Application pointing at bundles/default/)
- `bundles/default/services.appset.yaml` — ApplicationSet (kate-default)
- `bundles/default/services.yaml` — 2-entry registry: hermes + honcho
- `bundles/README.md` — bundle authoring + substrate boundary docs

**Live impact:** None. Committed and pushed but not applied. Applying
today would create duplicate Applications and conflict with labops.

**Commit:** `a1239b2`.

---

### Phase 2 — labops adds Kyverno + default-pool policy

**Goal:** Substrate gains the ability to decorate LoadBalancer Services
with MetalLB annotations at admission time, so components can ship
substrate-agnostic vip.yaml manifests.

**Design decision (resolved 2026-05-26): shell-script bootstrap pattern.**

Kyverno installs via shell scripts in `labops/kyverno/` (mirroring
`labops/metallb/`), NOT via the ArgoCD registry. Reasoning:

- **MetalLB precedent:** MetalLB is the existing model — it MUST be
  shell-bootstrapped because ArgoCD itself requires MetalLB (for
  argocd-server LoadBalancer access). Kyverno follows the same model
  for consistency, even though it doesn't have the same hard bootstrap
  dependency.
- **Substrate layer is shell-imperative; kate layer is ArgoCD-declarative.**
  This sharpens the substrate/composition boundary: everything before
  ArgoCD is shell, everything via ArgoCD is kate's territory.
- **Bootstrap ordering becomes rigid and explicit:**
  `k3s/install → metallb/install → metallb/prepare → kyverno/install →
  kyverno/prepare → argo/install`.
- **Consequence:** After Phase 4 cutover, labops's `argo/services.yaml`
  registry may be **empty or near-empty**. The ArgoCD registry mechanism
  lives in labops, but every entry in it belongs to kate. This is
  the correct boundary — labops owns the mechanism, kate owns the
  contents.

**Changes in `apnex/labops`:**

Create `labops/kyverno/install` (shell, idempotent kubectl apply of
Kyverno upstream manifests — likely the helm-templated install YAML
or the official `install.yaml` from the Kyverno releases page; pin
the version):

```bash
#!/bin/bash
## module: kyverno/install
## purpose: install Kyverno policy engine for substrate-level admission policies
## inputs:  KUBECONFIG, KYVERNO_VERSION (optional pin override)
## needs:   healthcheck/k8s-local

KYVERNO_VERSION="${KYVERNO_VERSION:-v1.13.4}"  # pin a tested version
kubectl apply -f "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/install.yaml"
```

Create `labops/kyverno/prepare` (shell, applies the default-pool
ClusterPolicy after Kyverno is healthy):

```bash
#!/bin/bash
## module: kyverno/prepare
## purpose: apply Kyverno ClusterPolicies for substrate defaults
## needs:   healthcheck/k8s-deployment-ready (kyverno-admission-controller)

run healthcheck/k8s-deployment-ready kyverno-admission-controller kyverno
kubectl apply -f "${LABOPS_ROOT}/kyverno/policy-default-metallb-pool.yaml"
```

Create `labops/kyverno/policy-default-metallb-pool.yaml`:
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: default-metallb-pool
spec:
  background: false              # only mutate at admission, no churn
  failurePolicy: Ignore          # if Kyverno down, admission proceeds
  rules:
    - name: inject-host-pool
      match:
        any:
          - resources:
              kinds: [Service]
              namespaceSelector:
                matchExpressions:
                  - { key: kubernetes.io/metadata.name, operator: NotIn,
                      values: [kube-system, kyverno, argocd, metallb-system] }
      preconditions:
        all:
          - key: "{{ request.object.spec.type || '' }}"
            operator: Equals
            value: LoadBalancer
          - key: "{{ request.object.metadata.annotations.\"metallb.universe.tf/address-pool\" || '' }}"
            operator: Equals
            value: ""
      mutate:
        patchStrategicMerge:
          metadata:
            annotations:
              metallb.universe.tf/address-pool: host-pool
              metallb.universe.tf/allow-shared-ip: host
```

**Verification steps:**
1. After Kyverno + policy install, create a test LoadBalancer Service
   without annotations in a non-excluded namespace
2. Confirm `kubectl get svc <name> -o yaml` shows the injected annotations
3. Confirm MetalLB allocates from `host-pool`

**Live impact:** Kyverno controller pods running. Existing vip-* Services
unchanged (`background: false` means no churn). Policy is dormant until
new admissions occur.

---

### Phase 3 — component repos add substrate-agnostic vip.yaml

**Goal:** Components own their full deployment surface, with no
substrate awareness.

**Changes in `apnex/hermes`:**

Create `manifests/vip.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: hermes-vip
  namespace: hermes
  # NO metallb.* annotations — substrate-specific defaults are
  # injected by the substrate's admission policy (see labops).
spec:
  type: LoadBalancer
  selector:
    app: hermes
  ports:
    - { name: api, port: 8642, targetPort: 8642 }
    - { name: dashboard, port: 9119, targetPort: 9119 }
```

**Changes in `apnex/honcho`:**

Create `manifests/vip.yaml` with the same shape, honcho-specific
selector and ports (port 8000).

**Live impact:** None initially. These manifests aren't consumed by
anything until Phase 4's cutover. The hermes/honcho Applications in
labops's registry still point at `manifests/` and will pick up the new
vip.yaml on next sync — but the existing vip-hermes/vip-honcho Services
already exist with hardcoded annotations, so the new vip.yaml will
either create a duplicate (different name) or be a no-op.

**Naming detail:** vip.yaml's `metadata.name` must differ from the
existing `vip-hermes`/`vip-honcho` Service names, otherwise dual
ownership creates conflict. Recommend `hermes-vip` and `honcho-vip`.
(Phase 4 will delete the old vip-hermes/vip-honcho Services as part
of cutover.)

---

### Phase 4 — coordinated cutover

**Goal:** Transfer Application ownership from labops to kate; remove
hardcoded VIP manifests; let Kyverno take over annotation injection.

**Sequence:**

1. **labops change (commit, don't push):** Remove `hermes`, `vip-hermes`,
   `honcho` entries from `argo/services.yaml`. Add comment noting
   workloads moved to kate. Remove `labops/vip-hermes/` directory.

2. **Pre-cutover orphan-delete (safety):**
   ```bash
   kubectl delete application -n argocd hermes honcho vip-hermes --cascade=orphan
   ```
   `--cascade=orphan` keeps the underlying Deployments/Services running.
   Brief Application-absent window; workloads unaffected.

3. **Apply kate:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/apnex/kate/main/kate.yaml
   ```
   kate.yaml creates the `kate` Application, which creates `kate-default`
   ApplicationSet, which creates 2 Applications: `hermes` and `honcho`.
   These adopt the still-running workloads.

4. **Push labops change:** labops's registry now has only Kyverno
   entries. Its ApplicationSet drops the (already-deleted) hermes/honcho
   entries from its purview. Clean.

5. **Delete legacy VIP Services to force re-admission via Kyverno:**
   ```bash
   kubectl delete svc -n hermes vip-hermes
   kubectl delete svc -n honcho vip-honcho
   ```
   ArgoCD reconciles the kate-managed Applications, which now include
   the substrate-agnostic vip.yaml. New LoadBalancer Services are
   admitted; Kyverno injects `host-pool` + `allow-shared-ip: host`
   annotations; MetalLB allocates IPs from host-pool (likely the same
   192.168.1.250 since it's a shared-IP pool).

   Brief LB unavailability per service (seconds). Acceptable in a lab.

6. **Verification:**
   - `kubectl get applications -n argocd` shows kate, kate-default,
     hermes, honcho (kate-owned), kyverno, kyverno-policies-labops
     (labops-owned). No vip-* Applications.
   - `kubectl get svc -A` shows hermes-vip and honcho-vip with
     `metallb.universe.tf/address-pool: host-pool` annotations injected
     by Kyverno.
   - `tui.sh` connects to hermes-vip's IP successfully.

**Rollback plan:** If anything goes wrong at step 3 or 5, revert by:
- `kubectl delete -f https://raw.githubusercontent.com/apnex/kate/main/kate.yaml`
- Revert labops push (or git revert + push)
- Re-apply the original vip-hermes/vip-honcho Service manifests manually

Workloads survive throughout because of `--cascade=orphan` and the
fact that Deployments are independent of their Application wrappers.

---

## Production cutover risks (added 2026-05-26)

Phase 4 was originally drafted as a self-contained architectural
operation. Reality check identified four operational risks that span
beyond the kate/labops boundary and must be addressed before cutover
is safe. These risks are not unique to cutover — they are standing
operational concerns of running Hermes/Honcho on k8s — but cutover
forces them into focus.

### Risk 1 — Hermes session state preservation

**What's at stake:**
- Active conversation transcripts (SQLite, likely under `/opt/data/`)
- Skill library (loaded skills, user-created additions)
- Memory and user profile (MEMORY.md, USER.md — durable agent notes)
- Configuration (config.yaml, model registry, custom providers)
- Local artifacts (cron jobs, peer card cache, audio cache)

**Where it lives in the pod (to verify):**
- `/opt/data/` — almost certainly PVC-mounted, survives pod restarts
- `/opt/hermes/` — code, ephemeral, comes from image

**Cutover survival logic:** PVCs are persistent by name+namespace.
When the kate-owned `hermes` Application replaces the labops-owned
one, the PVC binding is preserved because both Applications declare
the same name. ArgoCD does NOT delete PVCs unless explicitly
configured to (`prune: true` on PVCs is a separate concern, usually
skipped).

**Pre-cutover verification:**
- `kubectl get pvc -n hermes` — what PVCs exist, what they're bound to
- Read `apnex/hermes/manifests/` PVC manifest — confirm `ReclaimPolicy: Retain`
- Read `apnex/hermes/manifests/deployment.yaml` — volumeMount paths

**Backup discipline (independent of cutover):**
- `kubectl exec hermes -- tar czf /tmp/hermes-backup.tar.gz /opt/data/`
- `kubectl cp hermes:/tmp/hermes-backup.tar.gz <off-cluster>/`
- Schedule (daily) + verify (test restoration)

### Risk 2 — Honcho state preservation

**What's at stake:**
- Postgres database (peers, sessions, observations, dialectic
  representations, peer cards — months of memory)
- Vector embeddings
- Worker queue state (transient, can be lost)

**Cutover survival logic:** Same as hermes. PVC bound to Postgres pod
survives Application ownership transfer.

**Pre-cutover verification:**
- `kubectl get pvc -n honcho` — PVC state
- `kubectl get statefulset -n honcho` — Postgres deployment shape
- Read `apnex/honcho/manifests/` for PVC ReclaimPolicy

**Backup discipline:**
- `kubectl exec honcho-postgres-0 -- pg_dump -U <user> <db> > honcho-$(date).sql`
- Encrypt + push off-cluster
- Test restoration before relying on it

### Risk 3 — Custom container image

**The biggest unknown.** Hermes is currently running a custom-built
image because modifications were made to plugins and audio
(provenance unclear). Possible outcomes after audit:

| Classification | Action | Likelihood |
|---|---|---|
| Modifications now upstream | Switch to stock image, retire custom build | unknown |
| Modifications unique but PR-able | Submit PRs, plan migration | unknown |
| Modifications must remain a fork | Document fork, keep custom build, kate points at fork image | unknown |
| Nobody remembers what or why | BLOCK cutover until audited | possible |

**Audit work required:**
1. What image is currently used? (`kubectl get pod -n hermes -o yaml | grep image:`)
2. Where is it built? (registry, build pipeline, source repo, Dockerfile)
3. Diff custom Dockerfile vs upstream `apnex/hermes`
4. Diff any patched source files vs upstream
5. Cross-check git history for the "why" of each modification
6. Classify each modification (stock/forkable/PR-able/fork-required)

**This is a separate work stream from kate architecture and must
complete before Phase 4.**

### Risk 4 — Live integrations (Discord, others)

**What's at stake:**
- Discord bot token (in `hermes-secrets`, survives via Secret)
- Channel-to-topic mappings (location TBD — config? DB? PVC?)
- Active webhooks
- Voice channel connections
- Reaction handlers, slash command registrations

**Cutover survival logic:** Configuration that lives in PVC or
Secret/ConfigMap survives by the same name+namespace logic. The
unique concern is **reconnection** — Discord client must re-establish
session on pod restart.

**Pre-cutover verification:**
- Where does Discord config live? Read `config.yaml`
- Channel mappings in DB (PVC) or env (Secret)?
- Any persistent webhook URLs registered with Discord?

**Cutover-time discipline:**
- Announce in Discord ("going down ~5min for infra cutover")
- Execute cutover
- Verify Discord reconnects cleanly
- Send "back up" message as smoke test

---

## Revised phase model with risk-mitigation subdivisions

The original 4-phase plan grows pre-cutover due-diligence phases:

```
Phase 1 — kate architecture (✓ DONE — commits a1239b2, 10670fc)
Phase 2 — labops Kyverno (shell-script substrate, k3s/up integration)
Phase 3 — component vip.yaml additions

─── PRE-CUTOVER DUE DILIGENCE (new) ───
Phase 3a — backup discipline established
   - hermes PVC backup procedure (scripted, tested, off-cluster)
   - honcho pg_dump backup procedure (scripted, tested, off-cluster)
   - restoration tested at least once
Phase 3b — custom image audit
   - diff custom Dockerfile vs upstream
   - classify each modification
   - decide: retire / PR / keep fork
   - if keep fork: ensure kate manifests point at fork image
Phase 3c — live integration verification
   - Discord state inventory (where does what live)
   - test pod restart in current setup
   - validates cutover won't surprise us

─── CUTOVER ───
Phase 4 — coordinated cutover (with announcement + rollback)
```

Phases 3a, 3b, 3c can run in any order and in parallel — they are
independent risk-mitigation streams.

## Approved execution sequence (2026-05-26)

Ranked by **importance** (biggest unknowns first), as approved by user:

| Order | Phase | Why this order |
|---|---|---|
| 1 | **D / 3b** — Custom image audit | Biggest unknown, biggest risk, longest lead time. If audit reveals "nobody knows why these patches exist," cutover blocks until resolved. |
| 2 | **C / 3a** — Backup discipline | Should exist anyway; prerequisite for any risky operation. |
| 3 | **A / 2** — labops/kyverno bootstrap | Architecturally needed; well-scoped (copy metallb/ pattern). |
| 4 | **B / 3** — Component vip.yaml | Pure manifest writing; no live changes. |
| 5 | **E / 3c** — Integration continuity | Final polish before cutover. |
| 6 | **F** — Architecture doc update | Sweep all findings back into this doc. |
| 7 | **G / 4** — Cutover | Only when all above are green. |

The labels D/C/A/B/E/F/G are stable session-resumption pointers used
in the cutover-risks research folder (see Related artifacts below).

---

## Open architectural questions (to be resolved before relevant phase)

### Q1 — IP allocation strategy after cutover

Today vip-hermes and vip-honcho share `192.168.1.250` via
`allow-shared-ip: host`. After cutover, the new hermes-vip and honcho-vip
Services will request the same shared IP. MetalLB should allocate
identically (same pool, same shared-IP key) — but worth verifying in a
test environment first.

### Q2 — bundles/default's substrate assumptions

The "default" bundle assumes labops's substrate is present (MetalLB +
Kyverno default-pool policy). Should this be explicitly documented as a
bundle-level pre-req, or should kate ship multiple bundles per substrate
(e.g. `default-labops`, `default-cloud`, `default-minimal`)?

**Tentative answer:** Document as a pre-req. Multi-bundle-per-substrate
proliferation is YAGNI until a real second substrate exists.

### Q3 — Future component additions (mission-kit, hermes-plugins, etc.)

Several apnex repos may eventually want a slot in kate's bundles:
- `apnex/mission-kit` — skill library (does it need cluster-side
  installation, or is it consumed by hermes at runtime via skill-sync?)
- `apnex/hermes-plugins` — capability plugins (likely runtime-loaded by
  hermes, not cluster-installed)

Both probably don't need ArgoCD Applications. Worth confirming when each
becomes relevant.

### Q4 — Multi-cluster / multi-environment scaling

Kate currently assumes one cluster, one substrate, one default install.
A future "kate v2" might support installing different bundles into
different clusters from one ArgoCD instance. Out of scope for now.

---

## Related artifacts

- `kate/bundles/README.md` — bundle authoring guide (lighter, more
  practical than this doc)
- `kate/docs/research/platform-migration/` — research folder for the
  cutover work; canonical 4-file layout (charter, journal, thematic
  docs, open questions). **Read `05-open-questions.md` first when
  resuming.**
- `kate/docs/SESSION-RESUME.md` — top-level resumption pointer; the
  "read this first" file when picking up cold
- `labops/metallb/` — the shell-bootstrap pattern Kyverno will mirror
- `labops/docs/superpowers/hermes-platform-roadmap.md` — broader
  multi-session planning document (not yet read into this architecture
  doc; cross-reference when relevant)

---

## Change log

- 2026-05-27 — added "Component sovereignty — known violations" section
  with the four-violation table surfaced during the `bundles/minimal/`
  build. Refreshed the Current State repo table with 2026-05-27 commit
  hashes (kate `757e911`, labops `2dd7e0b`, hermes `a88fc8a`). Removed
  Related-artifacts pointers to the now-deleted `labops/argo/services.yaml`
  and `services.appset.yaml` (the substrate split that landed in labops
  `99df4c2` deleted both — kate's own bundles/*/services.appset.yaml are
  the canonical registry references now).
- 2026-05-26 (rev 2) — added production cutover risks (1-4), revised
  phase model with 3a/3b/3c subdivisions, recorded approved execution
  sequence (D, C, A, B, E, F, G — ranked by importance), updated
  Phase 2 to record shell-script bootstrap decision (vs ArgoCD-managed),
  added pointers to research/platform-migration/ folder.
- 2026-05-26 — initial draft. Phase 1 complete, Phases 2-4 planned.
  Architecture stabilised after a multi-iteration design conversation
  that refined the substrate/composition/component boundary three times
  to its current sharp form.
