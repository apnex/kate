# Bundles

A **bundle** is an opinionated, GitOps-installable composition of the kate
platform. Each bundle is a self-contained ArgoCD app-of-apps definition:
its `root.yaml` is an Application that recursively manages every other
Application in its `applications/` folder.

## Available bundles

| Bundle | Description | Install |
|---|---|---|
| `default` | Full kate platform: hermes agent + honcho memory + LAN VIPs | `kubectl apply -f kate.yaml` (repo root) — or `bundles/default/root.yaml` directly |
| `minimal` | (planned) hermes agent only, no memory, no extras | — |
| `voice` | (planned) default + voice gateway + MCP integrations | — |

## Choosing a bundle

- **Default** for most users — the full opinionated kate experience
- **Custom bundles** when the default doesn't fit your cluster, scale, or feature needs

Bundles are mutually exclusive: install one. Switching bundles is a sync
operation, not a reinstall — change the Application's `source.path` and
ArgoCD reconciles the difference.

## Authoring a new bundle

1. Create `bundles/<name>/root.yaml` — app-of-apps Application pointing at `bundles/<name>/applications/`
2. Add Application manifests to `bundles/<name>/applications/` for each component your bundle installs
3. Document the bundle in this README's table and in `docs/bundles.md`

Bundles can reference any upstream repo (apnex/hermes, apnex/labops,
apnex/honcho, third-party charts) at any revision. Each bundle's
component selection and version pinning is its own opinion.
