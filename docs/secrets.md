# Secrets — supply mechanism

Kate's per-deployment values (operator-supplied credentials + per-env
config like LLM router URLs) are sourced from **GCP Secret Manager**,
NOT from environment variables typed at the command line and NOT from
the kate repo. Everything is per-environment; nothing committed.

## Naming convention

All per-env values live under a flat naming scheme in GCP SM:

```
kate-<env-name>-<KEY>
```

`<env-name>` is the operator's name for a deployment (e.g.
`hermes-vm`, `obpc`, `dev`, `prod`). `<KEY>` matches the env-var name
in the hermes manifests (e.g. `LITELLM_API_KEY`).

Example for env `hermes-vm`:

| SM secret name | Required? | Notes |
|---|---|---|
| `kate-hermes-vm-LITELLM_BASE_URL` | yes | per-env LLM router URL |
| `kate-hermes-vm-LITELLM_MODEL` | yes | router's model alias |
| `kate-hermes-vm-LITELLM_API_KEY` | yes | router's auth |
| `kate-hermes-vm-HERMES_PEER_NAME` | optional | honcho peer identity; default `default-user` |
| `kate-hermes-vm-DISCORD_BOT_TOKEN` | optional | Discord gateway opt-in (default bundle only) |
| `kate-hermes-vm-DISCORD_ALLOWED_USERS` | optional | DM allowlist (default bundle only) |
| `kate-hermes-vm-GH_TOKEN` | optional | `gh` CLI + git push from pod |
| `kate-hermes-vm-HERMES_HOST_SSH_KEY` | optional | PEM key for `nuc` host-shell |

`API_SERVER_KEY` is intentionally NOT in this list — it's generated
in-cluster by `apnex/hermes/manifests/init-credentials-job.yaml`.

## One-time provisioning per environment

The secret CONTAINERS (no values) can be Terraform-provisioned. See
`apnex/hermes-test/base/secrets.tf` for a reference module. Once the
containers exist, the operator adds values out-of-band — these never
get committed anywhere:

```sh
echo -n "https://my-llm.example.com/v1" \
  | gcloud secrets versions add kate-hermes-vm-LITELLM_BASE_URL --data-file=-

echo -n "my-default-model" \
  | gcloud secrets versions add kate-hermes-vm-LITELLM_MODEL --data-file=-

echo -n "sk-real-key" \
  | gcloud secrets versions add kate-hermes-vm-LITELLM_API_KEY --data-file=-

# + optional ones
```

Rotation = `gcloud secrets versions add` with the new value. Old
versions remain; the bootstrap script always reads `latest`.

## Per-deployment apply

The `bootstrap-secrets` script reads from SM and creates the cluster's
`hermes-config` ConfigMap + `hermes-credentials` Secret (delegating to
hermes's `set-secret`):

```sh
./scripts/bootstrap-secrets hermes-vm
```

Then apply the bundle:

```sh
kubectl apply -f https://raw.githubusercontent.com/apnex/kate/main/bundles/minimal/services.appset.yaml
```

Two commands. No credential typing. SM is the single source of truth.

## Auth model

| Principal | Needs |
|---|---|
| Operator running `bootstrap-secrets` | `gcloud` auth + `secretmanager.secretAccessor` on the per-env secrets in the current gcloud project, kubectl context on the target cluster |
| Future deploy SA (optional) | Same scoped to a service account if delegating from CI |

Project owners have `secretAccessor` transitively, so personal-infra
operators typically need no explicit IAM bindings. Add
`google_secret_manager_secret_iam_member` resources in `secrets.tf` when
delegating.

## Why SM (vs alternatives)

- **vs env vars typed at apply**: source of truth lives somewhere
  durable, survives shell history loss, doesn't require operator to
  remember per-env values.
- **vs committed-to-git encrypted secrets (SOPS, sealed-secrets)**:
  per-env values change per cluster; SM matches the per-env axis
  naturally, no KMS-key juggling. Repo stays public-safe — nothing
  per-deployment ever gets committed.
- **vs External Secrets Operator (ESO)**: ESO is the auto-rotation
  upgrade path from this script. For now, `bootstrap-secrets` is a
  one-shot pull on the operator's machine — simpler, no in-cluster
  controller. Move to ESO when per-cluster rotation visibility matters.
