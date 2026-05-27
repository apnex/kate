# kate / bundles/minimal — hermes config WITHOUT honcho memory.
# Replaces apnex/hermes/manifests/config.yaml.tpl via kustomize merge.
# Placeholders (@LITELLM_*@) are substituted at pod start by the
# seed-config initContainer from the hermes-secrets Secret.

model:
  provider: "custom"
  base_url: "@LITELLM_BASE_URL@"
  default: "@LITELLM_MODEL@"
  api_key: "@LITELLM_API_KEY@"

providers:
  custom:
    base_url: "@LITELLM_BASE_URL@"
    api_key: "@LITELLM_API_KEY@"

auxiliary:
  vision:           { provider: custom, model: "smart-fast" }
  web_extract:      { provider: custom, model: "smart-fast" }
  compression:      { provider: custom, model: "smart-fast" }
  session_search:   { provider: custom, model: "smart-fast" }
  skills_hub:       { provider: custom, model: "smart-fast" }
  approval:         { provider: custom, model: "smart-fast" }
  mcp:              { provider: custom, model: "smart-fast" }
  title_generation: { provider: custom, model: "smart-fast" }
  triage_specifier: { provider: custom, model: "smart-fast" }
  curator:          { provider: custom, model: "smart-fast" }

stt:
  enabled: true
  provider: local
  local:
    model: base
tts:
  provider: edge

skills:
  external_dirs:
    - /opt/data/extra-skills

# No memory: block — hermes-core falls back to its built-in local notes /
# user-profile path without a remote backend. No honcho: block — no plugin
# loaded (wanted-plugins.yaml is empty), no service to point at.
