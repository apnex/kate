# kate / bundles/default

The full apnex-NUC-style install: hermes agent + honcho memory + voice
wiring + discord wiring + host-shell access. The opinionated kate stack
as currently run on the obpc NUC.

## What this bundle deploys

- **hermes** (apnex/hermes) via kustomize overlay on this directory.
  Bases on the substrate-agnostic upstream manifests and adds back voice
  + discord wiring via [`voice-discord.yaml`](voice-discord.yaml). Image:
  `australia-southeast1-docker.pkg.dev/labops-389703/kate/hermes-agent:v2026.5.16-voice`
- **honcho** (apnex/honcho) — applied directly from upstream `manifests/`.
  Provides the persistent-memory backend the honcho-tuned plugin uses.
- ApplicationSet generates one Application per entry in
  [`services.yaml`](services.yaml).

## Variables

The operator must supply these before installing the bundle. Some are
the same as minimal; rows below the divider are default-only.

| Name | Kind | Required? | Scope | How generated | Lands in |
|---|---|---|---|---|---|
| `LITELLM_BASE_URL` | config | yes | per environment | operator-supplied | `hermes-config` ConfigMap |
| `LITELLM_MODEL` | config | yes | per environment | operator-supplied | `hermes-config` ConfigMap |
| `LITELLM_API_KEY` | secret | yes | per environment | operator-supplied | `hermes-credentials` Secret |
| `API_SERVER_KEY` | secret | yes | **unique per deployment** | **auto-generated in-cluster** by `hermes/manifests/init-credentials-job.yaml` (operator can override by exporting `API_SERVER_KEY` before `set-secret`) | `hermes-credentials` Secret |
| `HERMES_PEER_NAME` | config | optional | per deployment | operator-supplied; defaults to `default-user` | `hermes-config` ConfigMap (key optional) |
| --- default-only --- | | | | | |
| `DISCORD_BOT_TOKEN` | secret | optional (feature flag) | per deployment | operator-supplied; absence → Discord gateway inert | `hermes-credentials` Secret (key optional) |
| `DISCORD_ALLOWED_USERS` | config | optional | per deployment | operator-supplied (comma-sep Discord user IDs); absence → all DMs rejected | `hermes-config` ConfigMap (key optional) |
| `GH_TOKEN` | secret | optional | per environment (one GitHub PAT for many clusters is fine) | operator-supplied; absence → `gh`/git push from pod fails on private repos | `hermes-credentials` Secret (key optional) |
| `HERMES_HOST_SSH_KEY` | secret | optional (feature flag) | per deployment (matches host's authorized_keys) | operator-generated PEM private key; absence → `nuc` wrapper inert | separate `hermes-host-ssh-key` Secret |
| `LLM_OPENAI_API_KEY` | secret | yes (for honcho) | per environment | operator-supplied (same key as LITELLM_API_KEY in most configs) | separate `honcho-llm-keys` Secret in `honcho` namespace |

Honcho takes its LLM key via a **separate Secret in its own namespace**
(`honcho-llm-keys` in `honcho`). This is honcho's anti-stomp pattern — see
`apnex/honcho/manifests` for why. Practically: most operators use the
same LLM API key for both, but they live in two Secrets in two
namespaces.

## Substrate assumptions

Default inherits several host/cluster assumptions from the apnex NUC
convention. These are not operator-supplied — they're hardcoded in the
bundle's overlay or in upstream hermes. **Default will not run cleanly
on a host that doesn't match these.** See
[`../../docs/architecture.md`](../../docs/architecture.md) "Component sovereignty — known violations"
for the migration plan.

- **Single-node cluster.** Voice (`/run/user/1000` hostPath) and host
  bind-mount (`/root` hostPath) are colocation-dependent. Multi-node
  requires pinning hermes via nodeSelector.
- **PipeWire-Pulse on the host as UID 1000.** The voice overlay mounts
  `/run/user/1000` and expects the Pulse socket at
  `/run/user/1000/pulse/native` (world-rw, so the container connects
  cookie-free).
- **Host SSH server reachable at `root@192.168.1.250`.** This value is
  currently hardcoded in upstream `hermes/manifests/deployment.yaml`
  (violation #3 in the audit). `nuc` wrapper SSHes here; doesn't
  activate unless `hermes-host-ssh-key` Secret is also present.
- **Host `/root` directory exists and is readable by the kubelet.**
  Bind-mounted into the pod at `/host` so the bot can author commits in
  the operator's project tree.
- **`hermes-vm`-style hostnames are NOT assumed** — the static-PV with
  nodeAffinity that used to bake in `obpc` was deleted (violation #1
  fix). Hermes now uses dynamic PVCs via cluster default StorageClass.

## Prerequisites

- Kubernetes cluster with ArgoCD installed
- Default StorageClass (the hermes PVC has no `storageClassName`; honcho
  ships its own PVCs that may reference specific SCs — check
  `apnex/honcho/manifests`)
- Outbound internet (image pull from public AR; reachable LLM endpoint)
- LLM endpoint that supports tool-calling
- All the substrate assumptions above (otherwise voice/`nuc` fail at
  pod start — minimal or a future portable bundle is the alternative)

## Install

Prerequisite: the per-env secrets exist in GCP Secret Manager. See
[`../../docs/secrets.md`](../../docs/secrets.md) for the naming convention and one-time provisioning.
For default, populate at minimum the required keys plus the optional
ones for whichever features you want (Discord, GH, host SSH).

```sh
# 1. Populate hermes namespace from GCP Secret Manager.
./scripts/bootstrap-secrets hermes-vm   # replace with your env name

# 2. honcho namespace + LLM key Secret (anti-stomp — out-of-band)
#    Reads the same LITELLM_API_KEY from SM for parity with hermes.
kubectl create namespace honcho
LITELLM_API_KEY=$(gcloud secrets versions access latest \
  --secret="kate-hermes-vm-LITELLM_API_KEY")
kubectl -n honcho create secret generic honcho-llm-keys \
  --from-literal=LLM_OPENAI_API_KEY="$LITELLM_API_KEY"

# 3. The bundle — generates two ArgoCD Applications (hermes + honcho).
#    The sync-wave-ordered init Job auto-generates API_SERVER_KEY
#    and patches hermes-credentials before the Deployment starts.
kubectl apply -f https://raw.githubusercontent.com/apnex/kate/main/bundles/default/services.appset.yaml

# 4. Retrieve the auto-generated API_SERVER_KEY for API calls.
API_SERVER_KEY=$(kubectl -n hermes get secret hermes-credentials \
  -o jsonpath='{.data.API_SERVER_KEY}' | base64 -d)
echo "$API_SERVER_KEY"
```

## Verify

```sh
kubectl -n argocd get applicationset kate-default              # exists
kubectl -n argocd get app                                      # hermes + honcho both Synced/Healthy
kubectl -n hermes get pod                                      # 1/1 Running
kubectl -n honcho get pod                                      # postgres-0, redis, honcho, honcho-deriver
kubectl -n hermes exec deploy/hermes -- ls /opt/data/plugins   # honcho-tuned/ present
kubectl -n hermes exec deploy/hermes -- ls /run/user/1000      # voice mount populated (host-side)
curl -H "Authorization: Bearer $API_SERVER_KEY" "http://<vip>:8642/v1/models"
```

## Teardown

```sh
kubectl -n argocd delete applicationset kate-default           # prune cascades hermes + honcho
kubectl delete ns hermes honcho                                # also drops PVCs + retained PVs
```

## See also

- [`../README.md`](../README.md) — bundle authoring + index
- [`../minimal/README.md`](../minimal/README.md) — the stripped variant (hermes only, no voice/discord/honcho)
- [`../../docs/architecture.md`](../../docs/architecture.md) — three-layer sovereignty model; **read
  "Component sovereignty — known violations"** before relying on default
  on any host that isn't the apnex NUC
