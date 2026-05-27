# kate

`kate` is the operational journal for apnex's Hermes deployment on the obpc NUC.
It documents architecture, decisions, and runbooks across the labops + hermes +
honcho deployment stack.

This repo deploys nothing. ArgoCD ignores it. It's docs + decisions + the
"why we chose X" archive — the meta layer over the manifests.

## The repo layer-cake

```
apnex/labops           substrate — k3s, MetalLB, storage, ArgoCD platform
apnex/hermes           component — Hermes app deployment manifests + image
apnex/honcho           component — Honcho app deployment manifests + db
apnex/kate         ←   composition — opinionated bundles + cross-cutting
                       docs + decisions; bundles/<name>/ is GitOps-installable
                       via ArgoCD; docs/ is the "why we chose X" archive
```

For the full three-layer sovereignty model (substrate / composition /
component), the four known boundary violations, and the migration plan:
see [`docs/architecture.md`](docs/architecture.md). For bundle authoring
conventions: see [`bundles/README.md`](bundles/README.md).

## Layout

```
kate/
├── README.md                          ← you are here
├── docs/
│   ├── 00-architecture-overview.md    ← the layer-cake + topology
│   ├── memory/                        ← memory-system research + planning
│   │   ├── 00-goals.md                  what good looks like + folder charter
│   │   ├── 01-research-brief.md         subagent investigation brief
│   │   ├── 02-research-findings.md      subagent report + synthesis
│   │   ├── 03-design-decisions.md       ADR-style choices
│   │   ├── 04-implementation-plan.md    phased rollout
│   │   └── substrate-landscape.md       reference: alternatives survey
│   ├── operations/                    ← runbooks
│   │   ├── boot-sequence.md             linger, initContainers, why
│   │   ├── litellm-routing.md           models, fallbacks, TF location
│   │   └── metallb-conventions.md       shared-IP pattern, gotchas
│   └── decisions/                     ← ADR-style, one file per decision
│       ├── 0001-honcho-as-memory.md
│       ├── 0002-self-host-litellm.md
│       └── ...
└── scripts/                            (optional helpers)
```

## Conventions

- Markdown only — keep it readable on github.com directly.
- Each `decisions/` file follows lightweight ADR: Context, Decision,
  Consequences, Status, Date.
- The numbered `memory/` files (00–04) are a one-time design arc — read in order.
  Unnumbered files in the same folder are standalone reference docs.

## Cross-references

- [labops](https://github.com/apnex/labops) — cluster infra modules
- [hermes](https://github.com/apnex/hermes) — Hermes app manifests
- [honcho](https://github.com/apnex/honcho) — Honcho memory server
