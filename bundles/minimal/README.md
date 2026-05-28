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
| `LITELLM_BASE_URL` | config | yes | per environment (different LLM router URL per env) | operator-supplied | `hermes-config` ConfigMap |
| `LITELLM_MODEL` | config | yes | per environment (router's model alias) | operator-supplied | `hermes-config` ConfigMap |
| `LITELLM_API_KEY` | secret | yes | per environment (one key per router) | operator-supplied | `hermes-credentials` Secret |
| `API_SERVER_KEY` | secret | yes | **unique per deployment** | **auto-generated in-cluster** by `hermes/manifests/init-credentials-job.yaml` (operator can override by exporting `API_SERVER_KEY` before `set-secret`) | `hermes-credentials` Secret |
| `HERMES_PEER_NAME` | config | optional | per deployment | operator-supplied; defaults to `default-user` if absent | `hermes-config` ConfigMap (key optional) |

Reading the table:
- **Every required row is per-environment or per-deployment** — nothing is
  shared globally across all kate installs. Each LLM router (env) has its
  own URL / model alias / API key triple, so a multi-env operator
  maintains N sets of `LITELLM_*`.
- **`secret + generated`** (`API_SERVER_KEY`) is unique per deployment
  and generated, not retrieved. Could be auto-generated in-cluster by
  a one-shot Job, never leaving the cluster.
- **`config` vs `secret`** is the orthogonal cut, and is now reflected
  in two separate Kubernetes resources: non-sensitive values live in
  the `hermes-config` ConfigMap, sensitive in the `hermes-credentials`
  Secret. The operator workflow (`set-secret`) still creates both from
  the same env-var inputs — the split is internal.

## Prerequisites

- Kubernetes cluster with ArgoCD installed
- A default StorageClass (the hermes PVC has no `storageClassName`, so
  the cluster default is used)
- Outbound internet (image pull from public AR; reachable LLM endpoint)
- LLM endpoint that supports tool-calling (`POST /chat/completions` with
  `tools` returns `tool_calls`)

## Install

Prerequisite: the per-env secrets exist in GCP Secret Manager. See
[`../../docs/secrets.md`](../../docs/secrets.md) for the naming convention and one-time provisioning.

```sh
# 1. Populate cluster from GCP Secret Manager.
#    Reads kate-<env>-* from your current gcloud project, creates the
#    hermes namespace + hermes-config ConfigMap + hermes-credentials Secret.
./scripts/bootstrap-secrets hermes-vm   # replace with your env name

# 2. The bundle — generates one ArgoCD Application (hermes) from
#    services.yaml; hermes Application points at THIS directory, where
#    kustomization.yaml bases on apnex/hermes//manifests + overlays.
#    The sync-wave-ordered init Job (in upstream hermes manifests)
#    generates API_SERVER_KEY and patches it into hermes-credentials
#    before the Deployment starts.
kubectl apply -f https://raw.githubusercontent.com/apnex/kate/main/bundles/minimal/services.appset.yaml

# 3. Retrieve the auto-generated API_SERVER_KEY (operator needs it to call /v1/*)
API_SERVER_KEY=$(kubectl -n hermes get secret hermes-credentials \
  -o jsonpath='{.data.API_SERVER_KEY}' | base64 -d)
echo "$API_SERVER_KEY"   # store somewhere — bot's API auth
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
