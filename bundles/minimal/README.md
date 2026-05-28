# kate / bundles/minimal

Hermes agent only — no honcho memory, no voice, no discord. The minimal
viable kate install for any Kubernetes substrate with a default
StorageClass.

## What this bundle deploys

- **hermes** (apnex/hermes) — substrate-agnostic manifests, image
  `australia-southeast1-docker.pkg.dev/labops-389703/kate/hermes-agent:v2026.5.16-voice`
  (allUsers public pull from GCP Artifact Registry).
- Kustomize overlay on the bundle directory that drops three ConfigMap
  files: `config.yaml.tpl` (memory block stripped), `honcho.json.tpl`
  (`enabled: false`), `wanted-plugins.yaml` (empty list — honcho-tuned
  plugin never syncs).

Nothing else. No honcho namespace, no MetalLB Service, no discord gateway,
no voice mounts.

## Variables

The operator must supply these before installing the bundle. The Install
section below covers how; this table is the inventory you reason from.

| Name | Kind | Required? | Scope | How generated | Lands in |
|---|---|---|---|---|---|
| `LITELLM_BASE_URL` | config | yes | shared across N deployments | operator-supplied | `hermes-secrets` Secret |
| `LITELLM_MODEL` | config | yes | shared across N deployments | operator-supplied | `hermes-secrets` Secret |
| `LITELLM_API_KEY` | secret | yes | shared across N deployments | operator-supplied | `hermes-secrets` Secret |
| `API_SERVER_KEY` | secret | yes | **unique per deployment** | generated (`openssl rand -hex 32`) | `hermes-secrets` Secret |
| `HERMES_PEER_NAME` | config | optional | per deployment | operator-supplied; defaults to `default-user` if absent | `hermes-secrets` Secret (key optional) |

Reading the table:
- **`secret + shared`** rows (`LITELLM_API_KEY`) — one copy of the value
  serves every cluster you stand up. Natural fit for a central store.
- **`secret + per-deployment`** rows (`API_SERVER_KEY`) — unique per
  cluster; generated, not retrieved. Could be auto-generated in-cluster.
- **`config`** rows (`LITELLM_*`, `HERMES_PEER_NAME`) — non-sensitive;
  could live in a ConfigMap (or even in the bundle for `shared` values)
  rather than a Secret. Currently grouped with secrets for one-shape
  operator workflow.

## Prerequisites

- Kubernetes cluster with ArgoCD installed
- A default StorageClass (the hermes PVC has no `storageClassName`, so
  the cluster default is used)
- Outbound internet (image pull from public AR; reachable LLM endpoint)
- LLM endpoint that supports tool-calling (`POST /chat/completions` with
  `tools` returns `tool_calls`)

## Install

```sh
# 1. Namespace + Secret (out-of-band; not in GitOps yet)
kubectl create namespace hermes

export LITELLM_BASE_URL="https://your-llm-router/v1"
export LITELLM_MODEL="your-default-model"
export LITELLM_API_KEY="sk-your-key"
export API_SERVER_KEY="$(openssl rand -hex 32)"

kubectl -n hermes create secret generic hermes-secrets \
  --from-literal=LITELLM_BASE_URL="$LITELLM_BASE_URL" \
  --from-literal=LITELLM_MODEL="$LITELLM_MODEL" \
  --from-literal=LITELLM_API_KEY="$LITELLM_API_KEY" \
  --from-literal=API_SERVER_KEY="$API_SERVER_KEY"

# 2. The bundle — generates one ArgoCD Application (hermes) from
#    services.yaml; hermes Application points at THIS directory, where
#    kustomization.yaml bases on apnex/hermes//manifests + overlays.
kubectl apply -f https://raw.githubusercontent.com/apnex/kate/main/bundles/minimal/services.appset.yaml
```

## Verify

```sh
kubectl -n argocd get applicationset kate-minimal       # exists
kubectl -n argocd get app hermes                        # Synced / Healthy
kubectl -n hermes get pod                               # 1/1 Running
kubectl -n hermes exec deploy/hermes -- ls /opt/data/plugins  # empty (no honcho-tuned)
curl -H "Authorization: Bearer $API_SERVER_KEY" "http://<vip>:8642/v1/models"
```

## Teardown

```sh
kubectl -n argocd delete applicationset kate-minimal    # prune cascades
kubectl delete ns hermes                                # also drops the PVC + retained PV
```

The PVC's PV uses the cluster default StorageClass. If that SC is `Retain`
(labops convention), the underlying directory survives; `kubectl delete pv
<name>` + manual `rm -rf` to fully reclaim.

## See also

- [`../README.md`](../README.md) — bundle authoring + index
- [`../../docs/architecture.md`](../../docs/architecture.md) — three-layer sovereignty model, component
  violations, why minimal looks the way it does
- [`../default/README.md`](../default/README.md) — for the full apnex-NUC-style install (voice +
  discord + honcho memory)
