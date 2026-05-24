# Hierarchical configuration

## §A Tier 1 — Claim

§A1 Settings split across per-domain classes (`DBSettings`, `LLMSettings`, `DeriverSettings`, `DialecticSettings`, `DreamSettings`, …), each pinned to an `env_prefix`.

§A2 Source precedence (highest → lowest): init kwargs, env vars, `.env` file, `config.toml`, file secrets, defaults.

§A3 `config.toml` is loaded once at process start into module-global `TOML_CONFIG`; `HONCHO_CONFIG_TOML_DISABLED=1` skips the load.

§A4 TOML keys mapped via fixed `SECTION_MAP` (e.g. `DERIVER_` → `[deriver]`, `VECTOR_STORE_` → `[vector_store]`, empty prefix → `[app]`).

§A5 Nested settings (model config, fallback config) use `env_nested_delimiter="__"` — e.g. `DERIVER__MODEL_CONFIG__MODEL=…`.

§A6 Nested env partial-override is patched up by `_fill_defaults_for_nested_field`: when an env var sets one sub-field of a nested model, the remaining sub-fields are filled from the factory default rather than left unset.

§A7 Each model that owns a `MODEL_CONFIG` block runs a `@model_validator(mode="before")` `_merge_model_config_defaults` to apply §A6.

§A8 Field-level validation rejects bad combinations at load time (e.g. `REPRESENTATION_BATCH_MAX_TOKENS` ≤ `MAX_INPUT_TOKENS`; `POOL_SIZE` 1–1000; `WORKERS` 1–100).

§A9 Dialectic config carries a per-reasoning-level map (`DialecticLevelSettings` for minimal/low/medium/high/max), each with its own `MODEL_CONFIG` slot defaulted from a single factory.

## §B Tier 2 — Source

§B1 `src/config.py` lines 41-57: `load_toml_config` + module-global `TOML_CONFIG`.

§B2 Lines 470-516: `_fill_defaults_for_nested_field` implementation.

§B3 Lines 520-576: `TomlConfigSettingsSource` (custom pydantic-settings source).

§B4 Lines 526-543: `SECTION_MAP` mapping env-prefix → TOML section.

§B5 Lines 585-601: `HonchoSettings.settings_customise_sources` defining the §A2 precedence tuple.

§B6 Lines 729-800: `DeriverSettings` (representative domain class with nested model config and cross-field validator).

§B7 Lines 856-991: `DialecticSettings` + `_default_dialectic_levels` (per-level map).

## §C Tier 3 — Analytical

§C1 **Sealed section taxonomy.** `SECTION_MAP` is a closed enumeration; an unknown `env_prefix` quietly resolves to `prefix.lower()` rather than failing — a new domain class added without updating the map will silently miss TOML overrides.

§C2 **TOML loaded once, never reloaded.** Operators changing `config.toml` must restart the process; runtime config drift is not supported.

§C3 **Env wins over TOML.** An env var set in a container manifest will silently override a TOML value committed to the repo, which is the desired ordering for k8s/Cloud Run deploys but invisible to readers of `config.toml` alone.

§C4 **Partial-nested env trap.** Without §A6, setting only `DERIVER__MODEL_CONFIG__MODEL` would zero out the sibling `transport` field. The pre-validator preserves operator intent at the cost of additional surface.

§C5 **Per-domain factory duplication.** Several settings classes (`DeriverSettings`, `DreamSettings.deduction`, `DreamSettings.induction`, `SummarySettings`, dialectic per-level) each carry their own `_MODEL_CONFIG_DEFAULT` staticmethod. There is no global model default; changing the fleet-wide default model means editing every factory.
