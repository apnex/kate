# Platform Migration — Open Questions

**Primary cross-session steering mechanism.** When resuming this work
in a new session, READ THIS FILE FIRST. It captures every unknown
that's actively in flight, where to look for answers, and what each
answer changes.

**Format:** questions are grouped by phase. Each question has:
- **Q:** the question itself
- **Why:** what depends on the answer
- **Where to look:** specific files, commands, or substrates
- **Resolution:** filled in when answered (with date + entry pointer)

---

## Phase D / 3b — Custom container image audit  ✓ RESOLVED 2026-05-26 (journal entry 005)

### Q-D1: What container image is hermes currently running?

**Resolution:** `localhost/hermes-agent:v2026.5.16-voice`. Locally
built, local registry, `-voice` tag suffix denoting the audio
extension layer. `imagePullPolicy: IfNotPresent`. Declared in
`apnex/hermes/manifests/deployment.yaml` line 200.

### Q-D2: Where is the custom image built, and what's the build pipeline?

**Resolution:**
- Build files in-repo at `apnex/hermes/image/` (Dockerfile + build.sh)
- Pipeline: manual `./build.sh` — `docker build` then
  `docker save | k3s ctr -n k8s.io images import` to load directly
  into the k3s node's containerd
- No CI (`.github/workflows/` empty)
- No registry push — image lives only on the k3s node
- Tag controlled by `TAG=` env var, defaults to current version

### Q-D3: What modifications were made vs upstream `apnex/hermes` main?

**Resolution:** The Dockerfile is **exceptionally well-documented**.
Every modification has explicit purpose comments. Base image is
stock `docker.io/nousresearch/hermes-agent:v2026.5.16` (unmodified
upstream). Modifications layered atop:

**Audio/voice stack (universal, potentially upstreamable):**
- System: libportaudio2, libasound2-plugins, alsa-utils
- Python: sounddevice, numpy, faster-whisper, edge-tts
- Discord voice: discord.py, PyNaCl, davey (DAVE E2EE)

**Apnex-specific dev capability (NOT upstreamable):**
- kubectl (cluster admin via ServiceAccount)
- /usr/local/bin/nuc wrapper (SSH-back-to-host)
- gh CLI + system-wide git credential helper using gh auth
- System git identity: hermes / kate@apnex.local

**Other:**
- honcho-ai SDK pre-installed

### Q-D4: Are any modifications now upstream?

**Resolution:** Unknown precisely — but **doesn't matter for the
cutover decision**. Even if 100% of the voice stack is upstreamable,
the apnex-specific dev capability layer (kubectl/nuc/gh) means the
fork must continue. Future cleanup work could PR the voice stack
upstream; doesn't gate cutover.

### Q-D5: For modifications not upstream, are they PR-able?

**Resolution (deferred to future cleanup work):**
- Audio/voice stack: **PR-able** as optional variant or extras
- Apnex-specific (kubectl/nuc/gh): **NOT PR-able** — must remain a
  fork because they're cluster/lab specific

### Q-D6: Where will kate's manifests point — stock image or fork image?

**Resolution: Keep the fork image.** `localhost/hermes-agent:v2026.5.16-voice`
remains the deployment image. The apnex-specific dev capability layer
alone makes the fork mandatory. Kate's `apnex/hermes/manifests/deployment.yaml`
keeps the existing image reference unchanged through cutover.

### Risk 3 assessment: LOW

Original concern was "nobody remembers why these patches exist."
Reality is opposite — Dockerfile is self-documenting, build is
reproducible, modifications are intentional and understood. Phase D
does NOT block cutover.

**Residual concerns to document (NOT blockers):**
1. Image build is manual (no CI). Acceptable for lab.
2. Image lives only on k3s node containerd. If node rebuilt, must
   rebuild image. Acceptable for single-node.
3. Base image pin requires manual bump-and-rebuild. Document upgrade
   procedure in `hermes/image/README.md` (does not exist yet — could
   be a small future polish).

---

## Phase C / 3a — Backup discipline

### Q-C1: What PVCs exist in `hermes` namespace, and what are they bound to?

**Why:** Confirms cutover survival logic for hermes state.

**Where to look:**
- `kubectl get pvc -n hermes`
- `kubectl describe pvc -n hermes <name>`
- `kubectl get pv | grep hermes`

**Resolution:** _(unanswered)_

### Q-C2: Does the hermes PVC have `persistentVolumeReclaimPolicy: Retain`?

**Why:** `Retain` survives PVC deletion. `Delete` does not. Critical for
cutover safety.

**Where to look:**
- `kubectl get pv <name> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'`
- `apnex/hermes/manifests/` PVC manifest (if defined in repo)

**Resolution:** _(unanswered)_

### Q-C3: Same as Q-C1 / Q-C2 but for `honcho` namespace.

**Where to look:**
- `kubectl get pvc -n honcho`
- `kubectl get statefulset -n honcho` (Postgres likely uses STS+volumeClaimTemplates)
- `apnex/honcho/manifests/`

**Resolution:** _(unanswered)_

### Q-C4: Where will backups be stored off-cluster?

**Why:** PVC integrity doesn't help if the cluster dies. Need an
independent storage target.

**Candidate options:**
- NUC host filesystem (already accessible, but same-machine = not really off-cluster)
- S3 / B2 / R2 bucket (real off-cluster)
- Some other persistent storage you trust

**Resolution:** _(unanswered)_

### Q-C5: How is the Honcho Postgres database authenticated?

**Why:** Need credentials to run `pg_dump`. If credentials are in a
Secret, easy. If they're in a config file in the pod, slightly harder.

**Where to look:**
- `kubectl get secret -n honcho`
- `apnex/honcho/manifests/` for Secret references
- Honcho's config docs

**Resolution:** _(unanswered)_

### Q-C6: Backup frequency and retention policy?

**Why:** Need to decide before scripting. Daily? Weekly? How many
generations to keep?

**Tentative:** Daily backups, retain 7 days + 4 weekly + 12 monthly.
But user input wanted before encoding.

**Resolution:** _(unanswered, pending user decision)_

---

## Phase A / 2 — labops Kyverno bootstrap

### Q-A1: What's the right Kyverno version to pin?

**Why:** Need a stable, tested version. Latest may have unknown issues.

**Where to look:**
- Kyverno release notes
- Compatibility matrix with k3s/k8s 1.28+
- Community feedback

**Tentative:** `v1.13.4` (in architecture.md draft) — verify before
committing.

**Resolution:** _(unanswered)_

### Q-A2: Should the Kyverno policy exclude additional namespaces beyond `[kube-system, kyverno, argocd, metallb-system]`?

**Why:** Any future infra namespace would also need exclusion. If we miss
one, that namespace's LoadBalancers get mutated unexpectedly.

**Candidates worth considering:**
- `cert-manager` (if added)
- `monitoring` (Prometheus/Grafana, if added)
- `ingress-*` (any future ingress controller)

**Resolution:** _(unanswered — defer until those namespaces actually exist)_

### Q-A3: Is `failurePolicy: Ignore` correct, or should it be `Fail`?

**Why:** Ignore = fail-open (cluster keeps working if Kyverno down).
Fail = fail-closed (admissions block if Kyverno down).

**Tentative:** Ignore for a home lab; Fail for production-grade.

**Resolution:** Ignore (per architecture.md draft). _(verify before deploy)_

---

## Phase B / 3 — Component vip.yaml

### Q-B1: What's the exact set of ports each component exposes?

**Why:** vip.yaml needs accurate port definitions.

**Where to look:**
- `kubectl get svc -n hermes vip-hermes -o yaml` — current ports
- `kubectl get svc -n honcho vip-honcho -o yaml` — current ports
- Cross-check with `apnex/hermes/manifests/service.yaml` (ClusterIP)

**Resolution:** _(unanswered)_

### Q-B2: Should the new Service be named `hermes-vip` (component-first)
or `vip-hermes` (current convention)?

**Why:** The current `vip-hermes` is labops's naming convention. If
ownership moves to hermes, naming convention may change. Affects cutover
(if same name → potential conflict during dual-ownership; if different
name → must delete old Service explicitly).

**Tentative:** `hermes-vip` and `honcho-vip` — component-first naming
matches "this is hermes's exposure". Forces explicit delete-old-create-new
in Phase 4 (acceptable, easier to verify).

**Resolution:** _(unanswered, tentative)_

---

## Phase E / 3c — Live integration continuity

### Q-E1: Where is Discord configuration stored?

**Why:** Determines what survives pod restart.

**Where to look:**
- `kubectl exec hermes -- cat /opt/data/config.yaml` (or wherever config lives)
- `kubectl get secret -n hermes` for token refs
- Hermes Discord plugin docs

**Resolution:** _(unanswered)_

### Q-E2: Does Discord reconnect cleanly after a pod restart today?

**Why:** Validates Phase 4 won't surprise us. If a current `kubectl
rollout restart` causes Discord pain, cutover will too.

**How to test:**
- Pick a low-traffic moment
- Announce in Discord ("brief restart, ~30s")
- `kubectl rollout restart deployment/hermes -n hermes`
- Observe Discord reconnect timing, any failure modes
- Document findings

**Resolution:** _(unanswered)_

### Q-E3: Are there other live integrations beyond Discord?

**Why:** Same survival concerns apply to anything else (Slack, Telegram,
webhooks, etc.).

**Where to look:**
- `kubectl exec hermes -- ls /opt/data/` for plugin configs
- `config.yaml` for enabled integrations

**Resolution:** _(unanswered)_

---

## Phase F — Architecture doc sweep

### Q-F1: What new sections need to be added to architecture.md based on
findings from D, C, A, B, E?

**Why:** Architecture doc is the authoritative reference. It must
incorporate everything learned during due diligence.

**Resolution:** _(deferred until D-E complete)_

---

## Phase G / 4 — Cutover execution

### Q-G1: Cutover window — when and how long?

**Why:** Need to coordinate user availability, announcement timing,
fallback availability.

**Resolution:** _(deferred until F complete)_

### Q-G2: Who validates each step is healthy before proceeding?

**Why:** Cutover has multiple commit points. Each needs verification
before the next step.

**Tentative:** User runs verification commands at each checkpoint; agent
proceeds only on confirmation.

**Resolution:** _(unanswered)_

---

## Cross-phase questions

### Q-X1: Does `labops/docs/superpowers/hermes-platform-roadmap.md` contain
prior thinking that should be cross-referenced?

**Why:** Flagged during recon but not yet read. May contain decisions
or context that affects D, C, A, B, E.

**Where to look:**
- `/host/labops/docs/superpowers/hermes-platform-roadmap.md`

**Resolution:** _(unanswered — read at start of next session if relevant)_

### Q-X2: Should any methodology discovered during this work be promoted
to `apnex/mission-kit`?

**Why:** Per user's multi-session-collaboration-protocol, promotion
requires a worked example. The worked example here is the successful
cutover itself.

**Resolution:** _(deferred until G/4 complete — promotion gate is the
cutover succeeding)_
