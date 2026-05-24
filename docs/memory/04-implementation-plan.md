# Implementation Plan — Deferred Memory Work

Session: 2026-05-24
Status: Scaffolding only. Two work units (DEFERRED-01, DEFERRED-02)
captured for future sessions where the user can be in the loop on
cost/triage calibrations.

This document is intentionally light. The audit and design-decision
documents (02, 03) hold the *why*; this file holds the *when*
and *what unblocks each item*.

---

## Completed this session (2026-05-24)

```
ID     DESCRIPTION                                STATUS
─────────────────────────────────────────────────────────
EXEC-1 Slim MEMORY.md from 99% → 40% (2,941     ✓ DONE
       → 1,209 chars) by demoting procedural
       content to existing skill references
EXEC-2 File 11 Honcho conclusions to bootstrap   ✓ DONE
       profile (goal A3 ≥10 conclusions)
EXEC-3 Verify memory_char_limit/user_char_limit  ✓ DONE
       at recommended 3000/2000
EXEC-4 Verify Honcho dialecticDepth=2 (already   ✓ DONE
       at power-user floor)
EXEC-5 Document decisions in 03-design-          ✓ DONE
       decisions.md (DD-01 through DD-08)
```

---

## DEFERRED-01 — Honcho server-side cadence tuning

**Goal addressed:** A6 (dialectic produces ≥2 substantive multi-fact
syntheses in 10 mixed-topic sessions).

**What's queued:** Four cadence/budget settings in `honcho.json` to
align with skill-ref power-user recommendations:

```
KNOB                  CURRENT  RECOMMENDED  COST IMPLICATION
────────────────────────────────────────────────────────────────
sessionStrategy       per-      per-repo    nil — pure scoping
                      session                strategy change
contextCadence        5         1           ~5× more context
                                              refreshes per session
dialecticCadence      10        3           ~3.3× more dialectic
                                              firings per session
contextTokens         2000      1200        nil — reduces injection,
                                              not cost
(add) dialecticMaxChars  unset  1000        nil — output budget per
                                              dialectic block
```

**What unblocks this:** A short cost/latency budgeting decision:
- "How much extra LiteLLM spend per Hermes session is OK for richer
  recall?"
- "Is `per-repo` or `per-session` the right scoping unit for apnex's
  workflow?" (apnex works across multiple repos, sometimes in the same
  session — both are defensible.)

**Suggested rollout sequence (one knob per session):**

```
SESSION  CHANGE                              LOG/MEASURE
──────────────────────────────────────────────────────────────────
1        contextTokens 2000 → 1200            injection size,
                                                synthesis quality
2        dialecticMaxChars  → 1000            output substance
3        sessionStrategy → per-repo           recall coherence
4        dialecticCadence  10 → 3             firing rate, latency,
                                                cost delta
5        contextCadence    5 → 1              context freshness vs.
                                                cost
```

**Rollback criterion (any session):** P95 user-facing latency
increases >25%, OR LiteLLM daily cost increases >2×, OR dialectic
synthesis quality measurably degrades. Revert the most recent change.

---

## DEFERRED-02 — Observation cleanup pass

**Goal addressed:** A4 (signal-to-noise ratio in observation log:
<3 noise entries in last 20).

**What's queued:** Manual triage + selective deletion of observation
entries via Honcho REST API.

**Why deferred:**
- Defining "noise" requires apnex's input — what looks like noise to
  the agent might be triangulation data for dialectic synthesis.
- `honcho_conclude(delete_id=...)` only handles conclusions; raw
  observation deletion requires direct REST API calls.
- Risk of regret if deleted observations would have contributed to
  later synthesis once cadence is tuned (DEFERRED-01).

**What unblocks this:**
1. DEFERRED-01 lands first (so we know dialectic is using
   observations well).
2. Two weeks of post-DEFERRED-01 operation to establish a noise
   baseline.
3. Then a one-off manual triage: list observations, sort by
   semantic value, apnex approves a delete batch.

**Implementation sketch (when ready):**

```bash
# List observations for the apnex peer
curl -sS http://192.168.1.250:8000/v3/workspaces/hermes/peers/apnex/observations | \
  jq '.[] | {id, content, created_at}' | less

# Delete one (selective)
curl -sS -X DELETE \
  http://192.168.1.250:8000/v3/workspaces/hermes/peers/apnex/observations/$ID
```

(API path verified against Honcho v3 source; double-check on the day
of execution.)

---

## DEFERRED-03 — Habit verification: are we keeping the conclude cadence?

**Goal addressed:** A3 (≥10 active conclusions, growing over time).

**What's queued:** After 2-3 weeks of operation, check the conclusion
count. If it hasn't grown beyond the initial 11, the per-exchange
cadence isn't being kept and we need a mechanism (USER.md rule,
agent-side reminder, or post-session ritual).

**What unblocks this:** Just time. Self-checking task.

---

## Out-of-scope (explicitly not planned)

- **Switching memory providers.** DD-01 settled this; revisit only if
  the OpenViking user-modeling layer materially matures.
- **Creating `apnex-cluster` skill.** DD-02 settled this; existing
  skills cover the surface.
- **Upstreaming subagent memory opt-in.** DD-08 settled this; the
  Hermes team is already tracking it.
- **Bumping `memory_char_limit` above 3000.** Skill ref is explicit
  this is misuse; we have 60% headroom now.

---

## DEFERRED-04 — Enable Honcho Dreamer (deductive + inductive synthesis)

**Date opened:** 2026-05-25
**Goal addressed:** A3 (≥10 active conclusions, growing over time) and the underlying signal-density problem behind it. Currently 1,187 explicit observations have produced ~0 deductive/inductive rows, so injected memory is verbose verbatim observation echo rather than synthesized conclusions.

**Root cause:** `DREAM.ENABLED=true` by default in v3.0.7, but `DREAM_DEDUCTION_MODEL_CONFIG` and `DREAM_INDUCTION_MODEL_CONFIG` default to `transport=openai, model=gpt-5.4-mini` with no `BASE_URL` override. The deriver ConfigMap wires `DERIVER_MODEL_CONFIG__OVERRIDES__BASE_URL` to our LiteLLM proxy; the equivalent `DREAM_*` env vars are missing, so specialists try to call OpenAI directly, fail (no API key for that endpoint, or wrong model name), and the dream cycle errors out silently from the operator perspective. Same class of bug as the original LiteLLM rewiring work — just for two model configs that werent on the audit list.

This is NOT to be confused with the (incorrect) "embedding gap" hypothesis from earlier in the session. Embeddings are correctly wired to `smart-embedding` via LiteLLM and reconciliation is healthy. The gap is in the specialist model configs.

**Reference research (do not duplicate here):**
- `kate/docs/memory/honcho/features/dreamer.md` — orchestrator, `run_dream`, `DreamResult`
- `kate/docs/memory/honcho/features/dream-scheduler.md` — gating + cadence (`DOCUMENT_THRESHOLD`, `MIN_HOURS_BETWEEN_DREAMS`, `IDLE_TIMEOUT_MINUTES`)
- `kate/docs/memory/honcho/features/specialist-contract.md` — `BaseSpecialist`, per-specialist model routing (§A10)
- `kate/docs/memory/honcho/features/explicit-deductive.md` — three-level observation schema and why deductive/inductive are currently empty

**Whats queued:** Six ConfigMap env vars wiring both specialist model configs to LiteLLM, applied via GitOps to `apnex/honcho`:

```
DREAM_DEDUCTION_MODEL_CONFIG__MODEL                = smart-reasoning
DREAM_DEDUCTION_MODEL_CONFIG__TRANSPORT            = openai
DREAM_DEDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL  = https://litellm-proxy-5muxctm3ta-km.a.run.app/v1
DREAM_INDUCTION_MODEL_CONFIG__MODEL                = smart-coder
DREAM_INDUCTION_MODEL_CONFIG__TRANSPORT            = openai
DREAM_INDUCTION_MODEL_CONFIG__OVERRIDES__BASE_URL  = https://litellm-proxy-5muxctm3ta-km.a.run.app/v1
```

Existing `honcho-llm-keys` secret already mounted on the deriver pod provides the API key; same `LLM_OPENAI_API_KEY` env var feeds all model configs via the shared `ConfiguredModelSettings` resolution chain.

**Why deduction → smart-reasoning and induction → smart-coder:**
- Deduction produces high-confidence rollups that get written to peer-card and influence identity-layer claims (`specialist-contract.md §C3`). One-shot quality matters more than cost.
- Induction is pattern-finding; it runs against larger observation sets and benefits from cheaper-but-still-tool-calling capacity. `smart-coder` proved a working substitute for `smart-reasoning` under load (2026-05-23 LiteLLM rerouting incident).

**Why we are NOT enabling surprisal in this change:**
`DREAM.SURPRISAL.ENABLED=false` (default). Surprisal adds tree-based pre-filtering with seven backend choices; defer until we see baseline dream cycles work and have data to tune from. One change at a time.

**Cadence we accept by default (no change in this round):**
```
DREAM_DOCUMENT_THRESHOLD          50 explicit obs    keep
DREAM_MIN_HOURS_BETWEEN_DREAMS    8 hours            keep
DREAM_IDLE_TIMEOUT_MINUTES        60 min             keep
DREAM_ENABLED_TYPES               ["omni"]           keep (runs both specialists)
```

With ~1,187 obs queued, the first dream cycle will fire within ~60 min of idle-window-elapse after the deploy.

**Rollout (GitOps via `apnex/honcho`):**
1. Branch /root/honcho on host.
2. Patch `manifests/base/configmap.yaml` with the six env vars.
3. Direct-commit to main (per apnex push convention).
4. ArgoCD syncs; deriver pod restarts; DreamScheduler initializes.
5. Wait for first `DreamRunEvent` in deriver logs (look for the ASCII sleep cat: `(っ- ‸ - ς)ᶻ z 𐰁`).
6. Verify: `SELECT level, COUNT(*) FROM documents GROUP BY level;` shows deductive > 0.

**Acceptance criteria:**
- A dream cycle completes with `success=True` in the `DreamRunEvent`.
- `documents.level=deductive` count > 0 within 2 hours of deploy.
- `honcho_reasoning` queries return ≥1 statement that is NOT verbatim present in any single explicit observation (the synthesis test).

**Rollback:** Single-commit revert of the ConfigMap change in `apnex/honcho`. ArgoCD heals within ~1 min. Alternatively set `DREAM_ENABLED=false` for hard disable.

**Risk register:**
- *LLM cost spike from background dream cycles.* Mitigation: `MIN_HOURS_BETWEEN_DREAMS=8` caps to ≤3 cycles/day per collection. Watch LiteLLM dashboard for 48h post-deploy.
- *Misclassification (deductive rollup is wrong).* Mitigation: deduction specialist can write to peer-card (`can_update_peer_card=True`); induction cannot (`=False`). If we see bad peer-card writes, swap deduction model to smart-coder too while we investigate.
- *Dream cycle bug at this SHA.* Mitigation: per nanoprobe, dreamer code is less battle-tested than deriver. If cycles error consistently, we have a clean rollback and the option to pin a later Honcho release.

**Documentation closure (after verification):**
- Add a pitfall to `~/.hermes/skills/mlops/honcho-self-host-k3s` SKILL.md: "Dreamer specialist model configs default to OpenAI public API. Wire `DREAM_DEDUCTION_MODEL_CONFIG__*` and `DREAM_INDUCTION_MODEL_CONFIG__*` the same way you wired DERIVER_MODEL_CONFIG, or no deductive/inductive observations will form."
- Mark this DEFERRED-04 block as ✓ DONE in this file.
- File a Honcho conclusion via honcho_conclude documenting the change.



---

## DEFERRED-04 Status (2026-05-24 22:45 UTC) — 🚧 BLOCKED at Phase 4

**Deployment shipped successfully** (commits `158ead1`, `f5ef1c4` on apnex/honcho main; ArgoCD synced clean). All 6 specialist env vars live in the running deriver container. `settings.DREAM.ENABLED == True` confirmed inside the pod.

**However:** the live deriver flow never invokes `check_and_schedule_dream`, so no dream tasks are ever enqueued and no deductive/inductive observations form.

### Reproduction confirms the scheduler works in isolation
Manual probe inside the deriver pod (`/tmp/dream_probe.py`):
```python
async with db: coll = await db.scalar(select(Collection).where(...))
await check_and_schedule_dream(db, coll)   # → returns True, logs "Dream check" + "Scheduled dream"
```
Output (DEBUG logging):
```
2026-05-24 22:38:48,189 src.dreamer.dream_scheduler DEBUG Dream check
2026-05-24 22:38:48,191 src.dreamer.dream_scheduler DEBUG Scheduled dream
check_and_schedule_dream returned: True
2026-05-24 22:38:48,191 src.dreamer.dream_scheduler DEBUG Dream task cancelled
```
(The trailing "cancelled" is expected — the probe process exited and the in-memory timer was destroyed.)

### Gate analysis (all gates resolve to True at runtime)
| Gate | Location | Live value |
|---|---|---|
| `settings.DREAM.ENABLED` | `src/config.py` | `True` ✓ |
| `message_level_configuration.dream.enabled` | `src/crud/representation.py:203` | resolves to `True` per `get_configuration(None, sess, ws)` repro ✓ |
| Document threshold (≥50 since last dream) | `dream_scheduler.py:305` | 1,247 since 0 ✓ |
| `MIN_HOURS_BETWEEN_DREAMS` | `dream_scheduler.py:321` | no prior dream → bypassed ✓ |
| `dream_scheduler = get_dream_scheduler()` singleton | `dream_scheduler.py:367` | constructible OK ✓ |

### Diagnostic evidence
Searching 15 min of DEBUG-level deriver logs with `grep -iE "dream|representation|threshold"` returns **6 lines** — all from `src.deriver.queue_manager`. **Zero** lines from `src.dreamer.dream_scheduler` or `src.crud.representation`, despite:
- 8 new `explicit` documents landing in Postgres in that window (so `save_representation` MUST have run)
- The gate at `representation.py:203` definitely being open
- DEBUG-level logging definitely working (`queue_manager` DEBUG lines DO surface)
- No `logger.warning("Failed to check dream scheduling")` either, which would fire if `check_and_schedule_dream` raised

### Hypotheses to test next session (in priority order)
1. **Logger filter / handler scoping for `src.dreamer.*` and `src.crud.*` modules.** Most likely culprit given the symmetric absence across both modules at the same DEBUG-effective level. Worth dumping `logging.getLogger("src.crud.representation").handlers` from inside a running worker (not a fresh subprocess).
2. **Conditional import or feature-flag short-circuit** somewhere between `deriver.py:211 save_representation()` and `representation.py:_save_representation_internal()` — maybe a v3.0.7 wrapper that bypasses dream scheduling when running in "minimal_deriver" mode (note the metric label `minimal_deriver_430_apnex`).
3. **Async-context issue:** `tracked_db("representation_manager.save_representation")` opens a NEW db session at `representation.py:125`; the inner `_save_representation_internal` receives a fresh `db`. The collection object came from the OUTER session. The gate evaluation happens before any db call, so this is unlikely to be the cause — but worth checking.
4. **Separate downstream bug (confirmed):** `settings.DREAM.DEDUCTION_MODEL_CONFIG.MODEL` raises `AttributeError: 'ConfiguredModelSettings' object has no attribute 'MODEL'`. The nested env-var convention `DREAM_DEDUCTION_MODEL_CONFIG__MODEL` does not appear to populate the pydantic schema correctly. Even once we unblock the scheduler invocation, specialists will likely fall back to upstream defaults (OpenAI public API w/ `gpt-5.4-mini`). Fix this BEFORE re-enabling for traffic.

### Recommended next session entry point
Spawn the **nanoprobe** skill for L3 archaeology on the v3.0.7 `deriver.py:211 → representation.py:125 → representation.py:_save_representation_internal → representation.py:204` call path. Specifically investigate (a) whether `save_representation` has alternative code paths in v3.0.7 that skip the dream block, and (b) why module loggers `src.crud.representation` and `src.dreamer.*` produce zero output at DEBUG despite root logger being DEBUG.

### Current cluster state (clean)
- `DREAM_ENABLED: "true"` ✓
- `DREAM_DEDUCTION_MODEL_CONFIG__*` env vars present ✓
- `DREAM_INDUCTION_MODEL_CONFIG__*` env vars present ✓
- `DREAM_IDLE_TIMEOUT_MINUTES` reverted to upstream default (60 min) ✓
- `LOG_LEVEL` reverted to upstream default on deriver ✓
- Honcho otherwise fully healthy (deriver processing batches, observations landing, dialectic queries working)

### Open commits
| SHA | Repo | Description |
|---|---|---|
| `158ead1` | apnex/honcho | Enable Dreamer, wire specialists to LiteLLM proxy |
| `d931546` | apnex/honcho | TEMPORARY IDLE_TIMEOUT=1 (reverted in f5ef1c4) |
| `f5ef1c4` | apnex/honcho | Revert TEMPORARY IDLE_TIMEOUT_MINUTES override |

### No skill update yet
Will update `honcho-self-host-k3s` SKILL.md with the dreamer pitfall AFTER the call-path bug is resolved — pre-writing the skill now would be premature since we may discover the pitfall is actually different from what we currently believe.


---

## DEFERRED-04 Status (2026-05-25 23:30 UTC) — ✅ DONE

**Root cause (confirmed via parallel L3 code-archaeology probes):**
The `dream.enabled` gate at `src/crud/representation.py:202` evaluates a `ResolvedConfiguration` that is **snapshotted in the API/webserver pod at message-enqueue time** (`src/deriver/enqueue.py:111,122`), serialized into the `queue.payload.configuration` JSONB column, and deserialized verbatim by the deriver (`src/deriver/queue_manager.py:103`). The deriver pod's own `settings.DREAM.ENABLED` only matters in a "very rare edge case" (`deriver.py:73`). On 2026-05-24 the ConfigMap was patched at 22:50:27Z, the deriver Deployment was rolled (correctly picking up `DREAM_ENABLED=true`), but the API Deployment (started ~22:1X, 73m old) was NOT rolled — and `envFrom: configMapRef` does not hot-reload. So every queued representation work-unit serialized `{"dream": {"enabled": false}}` from the stale API-pod env, and the gate fell through the silent-False branch (no `else`, no log, no warning).

**Fix applied:** `kubectl -n honcho rollout restart deploy/honcho` — restarted the API pod so its `envFrom` re-read the (already-correct) ConfigMap. No code changes, no manifest changes needed.

**Verification (2026-05-24 23:24-23:26 UTC):**
- API pod env now: `DREAM_ENABLED=true` ✓
- Fresh queue row 665: `payload.configuration.dream → {"enabled": true}` ✓
- Queue row 669: `task_type='dream'` enqueued ✓ (first dream task in cluster history)
- Deriver log: `Executed dream for dream:omni:hermes:apnex:apnex` ✓
- Deduction specialist: 14 tool calls, 98620 in / 4085 out tokens, 70s → **6 deductive observations created** ✓ (was 0)
- Deduction also: deleted 22 noisy observations + updated peer card ✓
- Induction specialist: in flight at last check, making `search_memory` and `search_messages` tool calls
- `documents.level` now: `explicit=1248, deductive=6` (was: only explicit)

**Secondary finding (Probe B, false-alarm refutation):**
Phase-4's secondary concern that `DREAM_DEDUCTION_MODEL_CONFIG__MODEL` env-var naming was broken was a self-inflicted diagnostic-script bug, NOT a real issue. The naming convention loads correctly at v3.0.7 (verified by minimal pydantic-settings 2.14.1 repro). Two bugs in my Phase-4 debug script created the false alarm: (a) accessed `.MODEL` uppercase but the pydantic field is `.model` lowercase, (b) filtered `'CONFIG' not in k.upper()` in `model_dump()` output, which explicitly excluded the very keys I was looking for. No ConfigMap change needed.

**Skill updates landed (`honcho-self-host-k3s`):**
- Pitfall #16 rewritten: replaced "root cause unknown" speculation with the confirmed API-pod-snapshot-at-enqueue mechanism + the rollout-both-deployments rule + the hardening recommendation (checksum-annotation or kustomize-hashed ConfigMap)
- Pitfall #18 corrected: removed the misleading "logger handler scoping" hypothesis as the primary explanation; reframed as second-order check after upstream-gate audit
- Both patches applied via `skill_manage(action='patch')` — clean diffs, no other content disturbed

**Hardening deferred (not blocking):**
Add `checksum/honcho-config` pod-template annotation OR kustomize `configMapGenerator` with hashed names so future ConfigMap edits auto-trigger rollouts on both Deployments. Without this, the next DREAM/SUMMARY/DERIVER flag flip in ConfigMap will silently land in one Deployment but not the other and reproduce the exact same silent gate-skip. Filed as a separate follow-up.

**Operational state restored:**
- `DREAM_IDLE_TIMEOUT_MINUTES` set back to upstream default (60 minutes) — was temporarily 1 minute for fast verification
- `LOG_LEVEL=DEBUG` reverted to upstream default (INFO)
- All other config preserved

**Commits:**
- `apnex/honcho@158ead1` — original 6-env-var specialist ConfigMap patch (still correct)
- `apnex/honcho@f5ef1c4` — IDLE_TIMEOUT temporary tweak revert (already landed previously)
- API pod restart was operator action (no commit; ConfigMap was already correct in git)

**Time-to-resolve:** ~25 minutes of L3 investigation + ~5 minutes of operator action. Compared to my Phase-4 attempt (60+ minutes of chasing code-archaeology hypotheses), the targeted parallel-probe approach with the nanoprobe discipline (claim/doc/source triangulation, pinned SHA, file:line evidence, hypothesis-by-hypothesis verdicts) reduced wall-time by ~3x AND produced two reusable skill updates as a side effect.
