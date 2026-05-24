# kate

`kate` is the operational journal for apnex's Hermes deployment on the obpc NUC.
It documents architecture, decisions, and runbooks across the labops + hermes +
honcho deployment stack.

This repo deploys nothing. ArgoCD ignores it. It's docs + decisions + the
"why we chose X" archive — the meta layer over the manifests.

## The repo layer-cake

```
apnex/labops           generic cluster infra (k3s, MetalLB, modules)
apnex/hermes           Hermes app deployment (manifests, config template)
apnex/honcho           Honcho app deployment (manifests, deriver, db)
apnex/kate         ←   THIS REPO: cross-cutting docs + decisions
                       + operator runbook + memory architecture
                       + the "why we chose X" archive
```

## Layout

```
kate/
├── README.md                          ← you are here
├── docs/
│   ├── 00-architecture-overview.md    ← the layer-cake + topology
│   ├── memory/                        ← memory-system architecture
│   │   ├── 00-goals.md                  what good looks like
│   │   ├── 01-research-brief.md         subagent investigation brief
│   │   ├── 02-research-findings.md      subagent report + synthesis
│   │   ├── 03-design-decisions.md       ADR-style choices
│   │   ├── 04-implementation-plan.md    phased rollout
│   │   └── 05-changelog.md              post-implementation log
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
- The `memory/` series is numbered intentionally — read in order.
- Changelog entries append-only; never rewrite history.

## Cross-references

- [labops](https://github.com/apnex/labops) — cluster infra modules
- [hermes](https://github.com/apnex/hermes) — Hermes app manifests
- [honcho](https://github.com/apnex/honcho) — Honcho memory server
