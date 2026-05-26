# Platform Migration — Charter

**Status:** Frozen scope (per multi-session collaboration protocol).
**Created:** 2026-05-26.
**Owner:** apnex.
**Last revised:** 2026-05-26.

---

## Mission

Migrate the apnex k3s cluster from its current state (labops directly
owning hermes/honcho/vip-* via its ArgoCD ApplicationSet registry) to
the target state (kate owns the agent platform composition; labops
owns only the substrate including ArgoCD itself and Kyverno
substrate-defaults policies).

The cutover must be **risk-controlled** — backups in place, custom
container image fully understood, live integrations (Discord, etc.)
verified to survive pod restart — before Phase 4 execution.

## Frozen scope

This research folder covers:

1. The multi-phase migration plan (Phase 2 onward; Phase 1 is complete
   and lives in `kate/docs/architecture.md`)
2. The four production cutover risks identified in this session
3. Pre-cutover due diligence work (Phases 3a/3b/3c)
4. The actual cutover execution (Phase 4) when all due diligence is green

**Out of scope:**

- Kate architecture refinement (closed; lives in `docs/architecture.md`)
- vLLM deployment (out of scope; may become a separate `gpu-substrate`
  bundle later)
- mission-kit / hermes-plugins cluster-side installation (deferred —
  likely not needed; both consumed at runtime by hermes)
- Multi-cluster / multi-environment expansion (out of scope; kate v2)

## Authority sources

- `kate/docs/architecture.md` — the authoritative architecture and
  4-phase plan, including production cutover risks section and the
  revised phase model
- This folder's `05-open-questions.md` — primary cross-session
  steering mechanism (read FIRST when resuming)
- `kate/docs/SESSION-RESUME.md` — top-level pointer; the "where am I"
  read-first file when picking up cold

## Promotion criteria

A methodology or pattern discovered during this work is candidate for
promotion to `apnex/mission-kit` ONLY when:

1. A complete worked example exists (i.e. the cutover succeeded using it)
2. The pattern is cross-project (applies beyond just kate's migration)
3. It survives at least one "could I re-explain this cold?" review

Premature promotion is a substantive process violation. Methodology
notes captured during this work live in this folder until cutover
completes and the worked example is in hand.

## Work order (approved by user 2026-05-26)

Ranked by importance — biggest unknowns first:

1. **D / Phase 3b** — Custom container image audit
2. **C / Phase 3a** — Backup discipline (hermes PVC + honcho pg_dump)
3. **A / Phase 2** — labops/kyverno bootstrap (shell-script, mirror metallb/)
4. **B / Phase 3** — Component vip.yaml (hermes + honcho)
5. **E / Phase 3c** — Live integration continuity (Discord etc.)
6. **F** — Sweep findings back into `kate/docs/architecture.md`
7. **G / Phase 4** — Coordinated cutover

D, C, A, B, E can run in parallel sessions. F precedes G. G blocks on
all of A-E being green.
