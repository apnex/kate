# Bundles

A **bundle** is an opinionated, GitOps-installable composition of the kate
platform. Each bundle is a self-contained ApplicationSet + service registry:

- `services.appset.yaml` — ArgoCD ApplicationSet with a git-generator
- `services.yaml` — registry of entries; each entry becomes one Application

This mirrors the labops/argo registry pattern, deliberately. Same mental
model, different scope: labops's registry holds **substrate** services
(infrastructure that knows about this cluster); kate's registry holds
**platform** services (the opinionated agent stack composed on top).

## Available bundles

| Bundle | Description | Install entry point |
|---|---|---|
| `default` | Full kate platform: hermes agent + honcho memory | `kate.yaml` (repo root) — or `bundles/default/services.appset.yaml` directly |
| `minimal` | hermes agent only (no honcho memory) | `bundles/minimal/services.appset.yaml` |
| `voice` | (planned) default + voice gateway + MCP integrations | — |

## Choosing a bundle

- **Default** for most users — the full opinionated kate experience
- **Custom bundles** when the default doesn't fit your scale or feature needs

Bundles are mutually exclusive: install one. Switching bundles is a sync
operation, not a reinstall — change the kate Application's `source.path`
and ArgoCD reconciles the difference.

## Authoring a new bundle

1. Create `bundles/<name>/services.appset.yaml` — copy from `default/` and
   rename the ApplicationSet to `kate-<name>`
2. Create `bundles/<name>/services.yaml` — the registry of entries this
   bundle installs
3. Document the bundle in this README's table and in `docs/bundles.md`

Bundles can reference any upstream repo (apnex/hermes, apnex/honcho,
third-party charts) at any revision. Each bundle's component selection
and version pinning is its own opinion.

## Substrate boundary — what bundles do NOT express

Bundles deliberately omit substrate-specific concerns:

- **No MetalLB pool annotations** on LoadBalancer Services
- **No specific StorageClass** on PVCs (rely on cluster default)
- **No specific node selectors / tolerations** (rely on cluster topology)

These are **substrate** concerns and belong in the substrate repo (labops
or equivalent), applied via cluster-wide policies (e.g. Kyverno mutating
policies). This keeps components and bundles portable across substrates.
