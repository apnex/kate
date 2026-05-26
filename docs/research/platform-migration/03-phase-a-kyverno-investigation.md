# Phase A — Kyverno Investigation (2026-05-26)

**Outcome:** Phase A cancelled. Kyverno scripts kept as optional
infrastructure in `apnex/labops/kyverno/` but NOT in the default
`k3s/up` bootstrap.

## What I expected to find

The Phase A plan called for installing Kyverno as substrate
infrastructure, with a ClusterPolicy that mutates LoadBalancer Services
at admission time to inject `metallb.io/ip-allocated-from-pool:
host-pool`. The premise was that this would let component manifests
ship substrate-agnostic (no pool annotation) and the substrate would
decorate them with the local pool name.

## What I actually found

**The premise was wrong.** Three discoveries while validating the policy:

### 1. The annotation I was targeting is MetalLB-written, not user-set

`metallb.io/ip-allocated-from-pool` is a **status record** that
MetalLB writes onto a Service AFTER it allocates an IP, recording
which pool was used. It is not a request annotation that the user
sets pre-allocation.

The correct request annotation is `metallb.io/address-pool` (or
`metallb.io/loadBalancerIPs` for specific IPs). Only `vip-vllm` in
the cluster uses this — it requests `vllm-pool` explicitly to avoid
the autoAssign default.

### 2. Component manifests are ALREADY substrate-agnostic

I expected to find `metallb.io/ip-allocated-from-pool: host-pool`
hardcoded into `vip-hermes` / `vip-honcho` / `vip-argocd-server`
manifests, which Phase B would have had to remove. They aren't there.

`/host/labops/vip-hermes/service.yaml` source:
```yaml
metadata:
  annotations:
    metallb.universe.tf/allow-shared-ip: host    # ← only annotation
```

The `metallb.io/ip-allocated-from-pool: host-pool` you see on the
live object is purely a MetalLB status field, written post-allocation.

### 3. MetalLB autoAssign IS the substrate-decoration layer

```
host-pool: addresses=['192.168.1.250/32'], autoAssign=True
vllm-pool: addresses=['192.168.1.251/32'], autoAssign=True
```

When a LoadBalancer Service is created with no pool annotation,
MetalLB picks the first matching `autoAssign: true` pool. This IS
the substrate-default mechanism. No admission-time decoration needed.

## Why the test "worked" in Kyverno logs but produced no effect

Kyverno's admission controller logs confirmed:
> "mutation rules from policy applied successfully ... rules=['add-host-pool-annotation']"

But the stored Service had no `metallb.io/ip-allocated-from-pool`
annotation. Two reasons:

1. **`kubectl apply`'s three-way merge stripped it.** Because the
   source manifest had `annotations: {}` and the
   `last-applied-configuration` baseline reflected that, the next
   diff stripped the Kyverno-added annotation as "drift".

2. **Even if it had stuck, MetalLB ignores it.** Setting the
   status-field annotation pre-allocation doesn't request a pool —
   MetalLB just overwrites it with its own value at allocation time
   (or in this case, ignored it because both /32 pools were already
   exhausted, so EXTERNAL-IP stayed `<pending>`).

## What I did about it

1. **Uninstalled Kyverno** from the cluster (via `labops/kyverno/remove`,
   which validates the remove script works end-to-end).
2. **Reverted `k3s/up`** — Kyverno not in the default bootstrap chain.
3. **Kept `labops/kyverno/`** as optional infrastructure for future
   use cases that genuinely need admission policies (multi-substrate
   pool defaulting, namespace conventions, sidecar generation,
   validation policies — see `labops/kyverno/README.md`).
4. **Documented the finding** here, in design journal entry 008, and
   in the labops commit message.

## Architectural consequences

| Phase | Original plan | Revised |
|---|---|---|
| A — substrate bootstrap | Kyverno + policy | **Cancelled.** Substrate already provides decoration via MetalLB autoAssign. |
| B — component manifests | Strip explicit pool annotations from `vip-hermes`/`vip-honcho` | **Already done.** Source manifests are pool-agnostic. Verify nothing else needs changing. |
| G — cutover | Same cutover, but with substrate-decoration responsibility on substrate | Same cutover, with substrate-decoration responsibility on MetalLB autoAssign defaults |

**Net effect on the migration:** Phase A drops out, Phase B becomes
a verification step, total work decreased. The substrate boundary is
slightly LESS opinionated than originally planned (relies on
MetalLB's behavior rather than an explicit policy layer) but the
substrate-portability goal is achieved either way.

## When Kyverno would still be valuable here

The scripts remain available for future use. Plausible triggers:

- **Multi-substrate environments.** If a second substrate is built
  with different pool names (e.g. `dev-pool` vs production
  `host-pool`), and components need to NOT specify a pool, then a
  per-substrate Kyverno policy could inject the right default. Until
  then, autoAssign + alphabetical ordering or `autoAssign: false`
  pinning handles it.

- **Validation policies.** Block patterns like `hostNetwork: true`,
  privileged pods, or LoadBalancer Services in namespaces that
  shouldn't have them.

- **Namespace conventions.** Auto-generate default network policies,
  resource quotas, or limit ranges per namespace.

- **Sidecar injection.** Generate observability sidecars without
  modifying source manifests.

The scripts already work end-to-end (validated 2026-05-26). When the
need arises, `bash kyverno/install && bash kyverno/prepare` and add
policy YAMLs to `labops/kyverno/`.

## Lessons captured

1. **Validate the premise before designing the mechanism.** I designed
   a four-file Kyverno bootstrap before checking that the target
   annotation was even user-settable. The first 30 seconds of `kubectl
   get svc vip-hermes -o yaml` would have shown me the annotation was
   status-only, and the whole phase would have been recognised as
   unnecessary.

2. **Distinguish status fields from spec fields, especially in
   annotations.** Kubernetes annotations frequently serve as
   side-channels for both directions (user→controller and
   controller→user). MetalLB's `address-pool` (request) vs
   `ip-allocated-from-pool` (status) is a classic example.

3. **Production validation reveals architectural errors faster than
   design review.** I would have caught this in design review only if
   I'd been more rigorous about the request-vs-status distinction;
   running the install + policy + test as production scripts caught
   it in ~5 minutes via empirical observation.

4. **The `labops/healthcheck/k8s-deployment-ready` script requires
   `jq`**, which is on the NUC host but not in the hermes pod. labops
   scripts are designed to run on the host, not from inside the
   cluster. Noted for future labops work — when running from a pod,
   ensure jq is present or call kubectl wait directly.
