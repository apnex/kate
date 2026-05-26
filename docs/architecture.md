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

## Current state (HEAD as of 2026-05-26)

| Repo | HEAD | State |
|---|---|---|
| `apnex/kate` | `a1239b2` | Phase 1 complete: bundles/default/ uses appset+registry; **NOT yet installable** (would conflict with labops) |
| `apnex/labops` | `faf12d2` | Owns hermes/honcho/vip-hermes Application entries in argo/services.yaml; no Kyverno yet |
| `apnex/hermes` | `1960764` | manifests/ has Deployment + ClusterIP; no vip.yaml yet |
| `apnex/honcho` | (unknown) | manifests/ has Deployment + ClusterIP; no vip.yaml yet |

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

**Open design question (resolve at start of Phase 2):**

Does Kyverno install via the **shell-script bootstrap pattern** (matches
labops/metallb/install) or via the **ArgoCD registry** (matches
labops/argo/services.yaml entries)?

Arguments for shell-install:
- Matches the existing MetalLB pattern (substrate bootstrap = shell)
- No bootstrap circularity (Kyverno doesn't depend on ArgoCD being
  healthy to install)
- Substrate stays minimal in the registry

Arguments for ArgoCD-managed:
- Drift detection, version pinning, declarative upgrades
- Treats Kyverno like any other reconciled component
- Aligns with the trajectory of "everything substrate-level is also
  GitOps-managed"

**Recommendation:** ArgoCD-managed via registry. Substrate is mature
enough that drift detection on Kyverno is more valuable than the
shell-script's bootstrap-time simplicity. Document the choice
explicitly when made.

**Changes in `apnex/labops`:**

Add to `argo/services.yaml`:
```yaml
- name: kyverno
  type: helm
  repoURL: https://kyverno.github.io/kyverno/
  chart: kyverno
  revision: 3.2.6                    # pin a tested version
  namespace: kyverno

- name: kyverno-policies-labops
  type: git
  repoURL: https://github.com/apnex/labops
  gitPath: kyverno
  revision: master
  namespace: kyverno
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
- `labops/argo/services.appset.yaml` — the canonical ApplicationSet
  pattern kate mirrors
- `labops/argo/services.yaml` — labops's current registry (will shrink
  in Phase 4 cutover)
- `labops/docs/superpowers/hermes-platform-roadmap.md` — broader
  multi-session planning document (not yet read into this architecture
  doc; cross-reference when relevant)

---

## Change log

- 2026-05-26 — initial draft. Phase 1 complete, Phases 2-4 planned.
  Architecture stabilised after a multi-iteration design conversation
  that refined the substrate/composition/component boundary three times
  to its current sharp form.
