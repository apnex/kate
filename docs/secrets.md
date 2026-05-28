# Secrets — supply mechanism

Kate's per-deployment values (operator-supplied credentials + per-env
config like LLM router URLs) are sourced from the operator's
**preferred backing store** — never committed to the kate repo,
never hardcoded into manifests, never assumed.

## Contract

Two layers, cleanly separated:

```
┌──────────────────────────────────────────────────────────────────┐
│  POPULATOR (operator's choice — varies per backing store)        │
│                                                                  │
│  Prints `export KEY=value` lines to stdout.                      │
│  Operator evaluates into their shell.                            │
│                                                                  │
│  Examples shipped here:                                          │
│    kate/scripts/load-from-gcp <env>      ← GCP Secret Manager    │
│                                                                  │
│  Others operators can write (one per backing store):             │
│    load-from-vault, load-from-sops, load-from-1password,         │
│    load-from-file ~/secrets/<env>.env, ...                       │
└──────────────────────────────┬───────────────────────────────────┘
                               │  exports populate the shell
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│  UNIFORM APPLY (identical across all backends)                   │
│                                                                  │
│  apnex/hermes/set-secret                                         │
│                                                                  │
│  Reads env vars, creates `hermes-config` ConfigMap +             │
│  `hermes-credentials` Secret in the kubectl-current cluster.     │
│  Same command everywhere. No backend knowledge.                  │
└──────────────────────────────────────────────────────────────────┘
```

The point: **the apply step is identical across backends.** The
populator step varies; the operator picks the populator that matches
where their secrets live. Operators with no helper (e.g. running on a
laptop with `pass` or 1Password CLI) can `export FOO=$(pass show
.../foo)` manually and skip the helper entirely — `set-secret` doesn't
care how the env vars got there.

## Required + optional keys (per env)

These are the env vars `hermes/set-secret` consumes — populators
should print exports for these names:

| Key | Required? | Notes |
|---|---|---|
| `LITELLM_BASE_URL` | yes | per-env LLM router URL |
| `LITELLM_MODEL` | yes | router's model alias |
| `LITELLM_API_KEY` | yes | router's auth |
| `HERMES_PEER_NAME` | optional | honcho peer identity; default `default-user` |
| `DISCORD_BOT_TOKEN` | optional | Discord gateway opt-in (default bundle only) |
| `DISCORD_ALLOWED_USERS` | optional | DM allowlist (default bundle only) |
| `GH_TOKEN` | optional | `gh` CLI + git push from pod |
| `HERMES_HOST_SSH_KEY` | optional | PEM key for `nuc` host-shell |

`API_SERVER_KEY` is intentionally NOT here — it's generated in-cluster
by `apnex/hermes/manifests/init-credentials-job.yaml`.

## Per-deployment operator workflow

Two steps. The first varies per backend; the second is identical.

```sh
# 1. Populate env vars (pick the one that matches your backing store):

#    GCP Secret Manager:
eval "$(./scripts/load-from-gcp hermes-vm)"

#    Local file (POSIX shell, KEY=VALUE per line):
source ~/secrets/hermes-vm.env

#    Manual:
export LITELLM_BASE_URL="https://your-llm/v1"
export LITELLM_MODEL="your-model"
export LITELLM_API_KEY="sk-..."

# 2. Apply (identical across all backends):
curl -fsSL https://raw.githubusercontent.com/apnex/hermes/main/set-secret | bash
```

## Per-backend setup

### GCP Secret Manager (using `load-from-gcp`)

One-time provisioning is in `apnex/hermes-test/base/secrets.tf` — a
Terraform module that creates the secret CONTAINERS (no values). After
`terraform apply`, the operator adds values:

```sh
echo -n "https://my-llm.example.com/v1" \
  | gcloud secrets versions add kate-hermes-vm-LITELLM_BASE_URL --data-file=-

echo -n "my-default-model" \
  | gcloud secrets versions add kate-hermes-vm-LITELLM_MODEL --data-file=-

echo -n "sk-real-key" \
  | gcloud secrets versions add kate-hermes-vm-LITELLM_API_KEY --data-file=-

# + optional keys
```

Naming convention in GCP SM: `kate-<env>-<KEY>`. Rotation =
`gcloud secrets versions add` with a new value; `load-from-gcp`
always reads `latest`.

### Local file

No infrastructure required. Operator maintains `~/secrets/<env>.env`:

```
LITELLM_BASE_URL=https://my-llm/v1
LITELLM_MODEL=my-model
LITELLM_API_KEY=sk-real-key
# optional...
```

`source` it in step 1.

### Other backends

Write a one-screen script that prints `export KEY=value` lines to
stdout (use `printf '%q'` for shell-safe quoting). Drop it next to
`load-from-gcp`. No coordination needed — the uniform apply step
doesn't know or care.

## Why this shape

- **Backend-pluggable**: every operator's secret-storage preference
  works. GCP users have a helper; non-GCP operators are first-class.
- **The apply step is one well-tested script** (`hermes/set-secret`).
  Backends don't get to re-invent it.
- **Composable**: each populator does one thing (print exports).
  Standard shell composition (`eval`, `source`, pipes) glues them.
- **No central dispatcher** to maintain or extend per backend.

## Auth model

| Principal | Needs |
|---|---|
| Operator running `load-from-gcp` | `gcloud` auth + `secretmanager.secretAccessor` on the per-env secrets, kubectl context on the target cluster |
| Operator using `source ~/secrets/<env>.env` | filesystem access + kubectl context |
| Operator with manual `export` | shell access + kubectl context |

The `set-secret` step needs only the kubectl context.

## Rotation

Rotation is a manual step at the populator's layer:
1. Update the backing store (`gcloud secrets versions add ...`, edit
   the local file, rotate the Vault path, etc.).
2. Re-populate the shell (eval / source / export).
3. Re-run `set-secret`.
4. Roll the workload: `kubectl rollout restart deploy/hermes -n hermes`.

A future `rotate-secrets` convenience script could collapse 3+4 into
one command. ESO (External Secrets Operator) would automate the whole
chain at the cost of in-cluster infrastructure — defer until per-
cluster rotation visibility actually matters.

## Why NOT a one-step `bootstrap-from-gcp <env>` wrapper

Tempting (the GCP user does one command), but it breaks the
"identical workflow across backends" property: non-GCP operators
would still have a two-step workflow. Keeping everyone on two
steps makes the contract honest. Operators who want one-step can
trivially write their own alias or function — outside the repo,
in their shell rc.
