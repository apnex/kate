# Backup Off-Host Roadmap — Phase C / 3a Extension

**Status:** Deferred (per user direction 2026-05-26). NUC-host backups
established first as Phase 1 / Option (a); off-host as Phase 2 /
Option (b).

This document captures the planned upgrade path so we can execute it
when motivated, without re-deriving the design.

---

## Why off-host matters

NUC-host backups protect against:
- ArgoCD pruning a PVC (the Retain reclaim policy is the primary
  defence; backup is the secondary)
- k3s storage corruption
- Operator error (`kubectl delete pvc` etc.)
- Failed cutover migrations
- Pod-level data corruption (bad write, schema migration gone wrong)

NUC-host backups do NOT protect against:
- **NUC hardware failure** (disk dies, motherboard dies, power surge)
- **NUC theft / physical destruction**
- **Site-level disaster** (fire, flood)
- **Encryption ransomware** (an attacker with root would wipe local
  backups too)

Off-host backups are necessary for true disaster recovery. The choice
of *where* off-host is the trust + cost tradeoff.

---

## Storage target options (evaluated 2026-05-26)

### Option A — S3-compatible bucket (Backblaze B2, Cloudflare R2, AWS S3)

**Pros:**
- True off-host, off-site, off-network
- Standardised tooling (rclone, restic, aws-cli)
- Versioning + lifecycle policies built-in
- Cheap (B2/R2 free tier covers hermes/honcho data sizes easily)
- Encryption at rest + in transit out of the box

**Cons:**
- Credentials need to land in a Secret (apply via `set-secret` in the
  relevant repo)
- Network dependency for backup operation
- Trust the provider not to be compromised (mitigate with client-side
  encryption — restic does this transparently)

**Recommended provider:** **Backblaze B2.** Cheapest at small scale,
S3-compatible API, generous free tier (10GB free).

### Option B — Encrypted private GitHub repo

**Pros:**
- Already have GitHub credentials wired (gh CLI + GH_TOKEN in hermes pod)
- Versioning is intrinsic (git log)
- Off-host without new credentials
- Free (private repos unlimited)

**Cons:**
- 100MB hard file limit (workable: split backups; or use git-lfs at
  cost)
- Git is not designed for binary blob storage; performance degrades
- Backup operations are slow (git clone/push of binary churn)
- Need client-side encryption (use age or gpg) — GitHub is not a
  trusted secret store

**Verdict:** workable but awkward. Better than nothing if S3 isn't
available, worse than S3 for this use case.

### Option C — Different physical machine on LAN (NAS, second server)

**Pros:**
- LAN-speed transfers (no internet dependency)
- No provider trust required
- Could co-locate with the rest of apnex infra

**Cons:**
- Requires existing/new infrastructure
- Not site-level disaster proof
- More operational burden (filesystem, RAID, the works)

**Verdict:** good supplement to off-site, not a substitute.

### Option D — Hermes Honcho user's external cloud storage (e.g. apnex
Google Drive / Dropbox)

**Pros:**
- Already paid-for storage the user trusts
- True off-site

**Cons:**
- Per-provider quirks; tooling fragmented (rclone helps)
- Trust the consumer-grade provider (privacy concerns for memory data)
- File-by-file uploads slower than block stores

**Verdict:** workable but lower priority than S3.

---

## Recommended target: Backblaze B2

When motivated, the recommended path is:

1. Create Backblaze B2 account
2. Create a bucket: `apnex-cluster-backups`
3. Create an application key with `writeFiles` permission scoped to
   that bucket
4. Store credentials in a new Secret (or extend existing
   `hermes-secrets` / `honcho-secrets`):
   ```bash
   ./set-secret B2_APPLICATION_KEY_ID
   ./set-secret B2_APPLICATION_KEY
   ```
5. Install `restic` or `rclone` in the relevant pod (or run from NUC
   host as a CronJob) — restic preferred for encrypted-by-default +
   deduplication
6. Replace the `cat | nuc "cat > ${HOST_TARGET}"` line in the manual
   backup scripts with `restic backup` to the B2 repository
7. Initialise restic repo with a strong password (stored in Secret)
8. Run initial backup, verify restoration works

**Estimated effort:** half a session. The mechanics are well-trodden.
The reason it's deferred is that the value (disaster-proofing) doesn't
justify the work until the system is finalised and we'd actually
restore from it.

---

## Substrate-level PV protection (related future work)

Independent of where backups go, we should also fix the
`local-path` StorageClass default of `Delete` reclaim policy.

**Current state:** Both existing PVs patched to `Retain`. New PVCs
would default to `Delete`.

**Fix:** Define a custom StorageClass that defaults to `Retain`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

Then update `apnex/hermes/manifests/pvc.yaml` and the honcho postgres
StatefulSet's `volumeClaimTemplates` to use `storageClassName:
local-path-retain` instead of `local-path`.

**Trade-off:** `Retain` PVs leave orphaned data on the filesystem when
PVCs are deliberately deleted. That's the whole point — manual cleanup
is the price of accident-resistance.

**Where this lives:** This is a substrate concern (modifies the cluster's
StorageClasses), so the manifest should live in `apnex/labops` under a
new `labops/storage/` folder. Add to `k3s/up` chain after `metallb/prepare`.

---

## Decision triggers

Move off-host backups from "deferred" to "in progress" when ANY of:

- A cutover (Phase 4) is imminent — want belt + braces
- A hardware change to the NUC is planned
- Data volume grows beyond ~10GB (then S3 economics shift, but still
  cheap)
- The system is declared "finalised" and operational hygiene becomes a
  priority
- An incident reveals NUC-only backups were insufficient

---

## Tracking

When the off-host work begins, create
`02-backup-offsite-implementation.md` as a sibling doc and treat this
as the design reference. Update this doc's status field at the top
when implementation starts.
