# Kate Stack — Installation Guide

End-to-end bootstrap of the four-repo stack on any Kubernetes cluster.
Assumes prerequisites (k8s + ArgoCD) are already installed; this guide
covers everything from "empty ArgoCD" to "Hermes responding to Discord
DMs with persistent memory."

For prereq setup (k3s + ArgoCD bootstrap), see `apnex/labops/k3s/README.md`
and `apnex/labops/argo/install`.

## Stack overview

```
┌─────────────────────────────────────────────────────────────────┐
│ External                                                          │
│   • Your laptop, Discord client, monitoring tools                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                  (network LB │ via MetalLB / cloud LB)
                              │
┌─────────────────────────────────────────────────────────────────┐
│ Kubernetes cluster                                                │
│                                                                   │
│   ┌────────────┐    ┌────────────┐    ┌────────────────────┐    │
│   │  hermes ns │───▶│ honcho ns  │    │  argocd ns         │    │
│   │  (agent)   │    │  (memory)  │    │  (deploys all)     │    │
│   └─────┬──────┘    └─────┬──────┘    └────────────────────┘    │
└─────────┼──────────────────┼──────────────────────────────────────┘
          │                  │
          │ OpenAI-compatible│ /v1/chat/completions
          ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│ LLM proxy (external)                                              │
│   • LiteLLM router, OpenRouter, OpenAI, etc.                      │
│   • MUST support tool-calling                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before starting, verify these exist:

```sh
# 1. Kubernetes cluster reachable
kubectl cluster-info
kubectl get nodes

# 2. ArgoCD installed and healthy
kubectl -n argocd get pods | grep -E 'Running|Ready'
kubectl -n argocd get crd applications.argoproj.io applicationsets.argoproj.io

# 3. Default StorageClass set (postgres + hermes both need PVCs)
kubectl get storageclass     # one should have (default)

# 4. LoadBalancer controller running
# On-prem: MetalLB
kubectl -n metallb-system get pods
# Cloud: LB provisioned automatically by cloud provider — no check needed.

# 5. LLM proxy reachable and supports tool-calling
LLM_URL="https://your-llm-router/v1"
LLM_KEY="sk-your-key"
curl -sS -H "Authorization: Bearer $LLM_KEY" "$LLM_URL/models" | head
# Then verify tool-calling support:
curl -sS -X POST "$LLM_URL/chat/completions" \
  -H "Authorization: Bearer $LLM_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "your-model",
    "messages": [{"role":"user","content":"What time is it?"}],
    "tools": [{"type":"function","function":{"name":"get_time","description":"get current time","parameters":{"type":"object","properties":{}}}}]
  }' | grep -i tool_calls
# A successful response includes "tool_calls" in the assistant message.
```

If any prereq fails, fix it before proceeding. Do **not** start the install
hoping it'll sort itself out — every layer below depends on these working.

## Install order (TOP-DOWN)

```
Step  Layer            Repo            Why this order
─────────────────────────────────────────────────────────────────────────
1     ApplicationSet   labops          ArgoCD needs the registry pattern
                                       in place before any app can deploy
2     Honcho           honcho          Memory backend. Hermes will start
                                       crashlooping if Honcho is missing.
3     Hermes           hermes          The agent itself. Last because it
                                       depends on everything above.
4     Discord (opt)    hermes          Carve-out: extra env vars on the
                                       hermes Secret. Add post-deploy.
```

## Step 1 — Bootstrap the labops ApplicationSet

This is the registry pattern: a single ApplicationSet in `argocd` reads
`apnex/labops/argo/services.yaml` and generates one ArgoCD Application
per entry. Add an entry → app deploys. Remove an entry → app prunes.

```sh
# Apply the ApplicationSet manifest from labops
kubectl apply -n argocd -f https://raw.githubusercontent.com/apnex/labops/master/argo/services.appset.yaml

# Verify
kubectl -n argocd get applicationset services
# NAME       AGE
# services   10s
```

If you've forked labops, replace the URL with your fork's
`argo/services.appset.yaml`.

**Note:** At this point, the ApplicationSet will try to generate Apps from
whatever's already in `services.yaml`. If you forked from `apnex/labops`,
that includes pre-existing entries (`registry`, `hermes`, etc.). Either:
- Delete unwanted entries from your fork's `services.yaml` first, or
- Let them deploy and prune later.

## Step 2 — Deploy Honcho

### 2a. Create namespace + LLM key Secret (out-of-band)

```sh
kubectl create namespace honcho
kubectl -n honcho create secret generic honcho-llm-keys \
  --from-literal=LLM_OPENAI_API_KEY="$LLM_KEY"
```

The Secret is **deliberately not in Git** — ArgoCD `selfHeal: true` would
stomp a placeholder Secret on every reconcile. See
`honcho/docs/secrets.md` for the full rationale.

### 2b. Configure the LLM endpoint

In your fork of `apnex/honcho`, edit `manifests/honcho/configmap.yaml`:

```yaml
LLM_OPENAI_API_BASE: https://your-llm-router/v1
DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL: https://your-llm-router/v1
# Set model names that exist on your endpoint
```

Commit + push to your fork.

### 2c. Add Honcho to the labops registry

Edit `apnex/labops/argo/services.yaml`:

```yaml
- name: honcho
  type: git
  repoURL: https://github.com/<you>/honcho
  gitPath: manifests
  revision: main
  namespace: honcho
```

Commit + push to master. The ApplicationSet generator polls every ~3min;
force immediate sync with:

```sh
kubectl -n argocd patch applicationset services --type=merge \
  -p '{"metadata":{"annotations":{"poke":"'$(date +%s)'"}}}'
```

### 2d. Verify

```sh
kubectl -n argocd get app honcho
# honcho   Synced   Healthy

kubectl -n honcho get pods
# postgres-0           1/1 Running
# redis-...            1/1 Running
# honcho-...           1/1 Running
# honcho-deriver-...   1/1 Running

# Smoke test the API
VIP=$(kubectl -n honcho get svc vip-honcho -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s http://$VIP:8000/health
```

If any pod is crashlooping, see `honcho/docs/runbook.md` (most common
cause is LLM endpoint unreachable from inside the cluster).

## Step 3 — Deploy Hermes

### 3a. Create namespace + Secret

In your fork of `apnex/hermes`:

```sh
export LITELLM_BASE_URL="$LLM_URL"
export LITELLM_MODEL="your-default-model"
export LITELLM_API_KEY="$LLM_KEY"
export API_SERVER_KEY="$(openssl rand -hex 32)"

./set-secret
```

This creates the `hermes` namespace and applies, out-of-band:
- `hermes-config` ConfigMap (non-sensitive: LITELLM_BASE_URL, LITELLM_MODEL,
  optionally HERMES_PEER_NAME, DISCORD_ALLOWED_USERS)
- `hermes-credentials` Secret (sensitive: LITELLM_API_KEY, API_SERVER_KEY,
  optionally DISCORD_BOT_TOKEN, GH_TOKEN)

Same anti-stomp pattern as Honcho.

### 3b. Configure Honcho client

The Hermes pod needs to reach Honcho. Edit `manifests/config.yaml.tpl` (or
the equivalent in your fork) to point at the Honcho VIP:

```yaml
honcho:
  baseUrl: http://vip-honcho.honcho.svc.cluster.local:8000
  # or use the external VIP if the cluster DNS path doesn't work:
  # baseUrl: http://192.168.1.250:8000
```

Commit + push.

### 3c. Add Hermes to the labops registry

Edit `apnex/labops/argo/services.yaml`:

```yaml
- name: hermes
  type: git
  repoURL: https://github.com/<you>/hermes
  gitPath: manifests
  revision: main
  namespace: hermes

- name: vip-hermes
  type: git
  repoURL: https://github.com/<you>/labops
  gitPath: vip-hermes
  revision: master
  namespace: hermes
```

Commit + push. Force-sync as in step 2c.

### 3d. Verify

```sh
kubectl -n argocd get app hermes vip-hermes
kubectl -n hermes get pods
# hermes-...   1/1 Running

# Smoke test the API
VIP=$(kubectl -n hermes get svc vip-hermes -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H "Authorization: Bearer $API_SERVER_KEY" "http://$VIP:8642/v1/models"

# Or open the dashboard
echo "http://$VIP:9119"
```

### 3e. Smoke-test memory wiring

```sh
# Interactive session via the deployed pod
./hermes-tui chat -q "remember this fact: my favorite test number is 42"

# In a fresh session, verify recall:
./hermes-tui chat -q "what's my favorite test number?"
# Should answer 42 via Honcho recall.
```

If recall fails, check:
- `kubectl -n hermes logs deploy/hermes | grep -i honcho` — any connection errors?
- `kubectl -n honcho logs deploy/honcho-deriver | grep -iE 'observ|conclu'`
  — is the deriver processing turns?

## Step 4 — Wire Discord (optional)

See `hermes/docs/discord.md` for the gateway setup (token, allowlist,
rotation). One-time setup, then Hermes responds to your DMs.

## Cross-stack verification

End-to-end sanity check after all three layers are deployed:

```sh
# 1. ArgoCD shows everything green
kubectl -n argocd get app

# 2. Each namespace's pods are Running
kubectl -n honcho get pods
kubectl -n hermes get pods

# 3. Honcho → LLM proxy
kubectl -n honcho exec deploy/honcho -- \
  curl -sS -m 5 -H "Authorization: Bearer $LLM_KEY" "$LLM_URL/models" | head

# 4. Hermes → Honcho
kubectl -n hermes exec deploy/hermes -- \
  curl -sS -m 5 http://vip-honcho.honcho.svc.cluster.local:8000/health

# 5. Hermes → External (your laptop hits the VIP)
curl -H "Authorization: Bearer $API_SERVER_KEY" \
  "http://$(kubectl -n hermes get svc vip-hermes -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8642/v1/models"
```

All five succeed → stack is healthy.

## Common failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Honcho deriver crashloops | LLM endpoint missing tool-calling | Verify with the prereq curl probe |
| Hermes 5xx on memory calls | Honcho VIP unreachable from `hermes` ns | Check NetworkPolicies; use cluster DNS path |
| ArgoCD App stuck "OutOfSync" | git fetch race after push | Force-sync the App or wait ~3min |
| `hermes-credentials` Secret or `hermes-config` ConfigMap keeps disappearing | You put it in Git → Argo prunes it | Re-create out-of-band via `set-secret`; never commit |
| MetalLB doesn't assign a VIP | No IPAddressPool configured | See `labops/metallb/` for pool examples |
| New service VIP changed on rename | Different MetalLB pool selected | Use `metallb.universe.tf/allow-shared-ip` |

## Teardown

For full removal, see each repo's teardown doc:
- `honcho/docs/teardown.md`
- `hermes/docs/teardown.md`

Teardown order is the **reverse** of install: Hermes → Honcho → registry entries → ApplicationSet.

## Reference

- `kate/docs/installation-review/2026-05-24-gitops-layer-review.md` — audit
  of the current install workflow, including known portability gaps.
- `kate/PORTABILITY.md` (planned) — list of every hardcoded value that
  needs swapping when forking the stack to a new environment.
