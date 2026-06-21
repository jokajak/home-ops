# VolSync backups (restic → MinIO)

> Status: **IN PROGRESS** — Phases A+B done (operator live, backup+restore verified on
> matter-hub); Phase C (migrate via restore) + D (roll out) remain · 2026-06-21 · Owner: Josh ·
> Author: Luma (Claude)
>
> Closes a long-standing gap: the `storage/README` claims "restic/volsync backups" but
> VolSync was never deployed. Pattern adapted from the onedr0p/home-operations Flux
> **component** approach (`~/git/k8s-home-ops/oneDr0p-home-ops/kubernetes/components/volsync`),
> retargeted from their Ceph-snapshot + kopia-to-NFS stack to **this** cluster's nfs-csi +
> restic-to-MinIO reality. Triggered by the Phase 2 namespace migration needing a safe way to
> move PVC data (back up in old ns → restore in new ns) instead of a fragile PV rebind.

## Goal

A declarative, per-PVC backup/restore mechanism: each opted-in app gets encrypted, incremental
restic backups to MinIO (S3), and a one-line restore into a fresh PVC in **any** namespace.
First proven on `home-assistant-matter-hub`, whose move to `home-automation` becomes a
backup→restore instead of a PV rebind.

## Why restic → MinIO (vs the reference's kopia + Ceph snapshots)

The onedr0p component is the right *shape* but its backend assumes hardware we don't have:

- **No CSI snapshot class.** onedr0p uses `copyMethod: Snapshot` against `csi-ceph-blockpool`.
  This cluster is `nfs-csi` (+ `openebs-hostpath`) with **no `VolumeSnapshotClass`**, so we use
  **`copyMethod: Direct`** — the mover reads the source PVC directly. Caveat: the app isn't
  quiesced during backup; for the small, low-write config volumes in scope (matter-hub, calibre,
  wallos, unifi, zwave, esphome, HA config…) a crash-consistent file copy is fine.
- **Backend = MinIO/S3, not an NFS kopia repo.** Matches `storage/README`, reuses the existing
  `terraform/minio` bucket+cred pattern, and keeps backups off the same NAS the PVCs live on.
- **Mover = restic.** First-class in upstream `backube/volsync`; encrypted + deduplicated +
  incremental to S3. (kopia is a viable alternative — see Open decisions.)

## Current state (verified 2026-06-21)

- VolSync: **not installed** (no CRDs, no controller, no repo references).
- Snapshot controller CRDs exist, but **no `VolumeSnapshotClass`** is configured.
- MinIO: `databases`/`logs`/`backups`/`loki` buckets exist (CNPG/Barman uses `databases`).
  Buckets are provisioned by `terraform/minio` (a module per bucket → bucket + scoped IAM user
  + `minio-tf-<bucket>` Bitwarden login item).
- `nfs-csi` storageclass: `reclaimPolicy: Delete`, provisioner `nfs.csi.k8s.io`.
- matter-hub data PV already patched to **`Retain`** (2026-06-21) as an interim safety net.

## Design

### 1. Operator — `kubernetes/apps/volsync-system/`

- New `volsync-system` namespace (mirrors onedr0p; isolates the controller).
- `volsync` HelmRelease from a new **`backube` HelmRepository** (`https://backube.github.io/helm-charts/`),
  `manageCRDs: true`. Wired into `apps/` like any other namespace (ks.yaml + kustomization.yaml).

### 2. Reusable component — `kubernetes/components/volsync/`

A Flux `kind: Component` (adapted from onedr0p), all keyed on `${APP}` + `${VOLSYNC_*}` postBuild
vars. **Three** resources — the onedr0p bootstrap `pvc.yaml` (`dataSourceRef → ReplicationDestination`
auto-restore) is **omitted**, because the volume populator requires `copyMethod: Snapshot` /
a VolumeSnapshotClass, which `nfs-csi` doesn't have. With `Direct`, restore is an **explicit**
trigger (also safer — no accidental auto-clobber):

- **`replicationsource.yaml`** — hourly restic backup of PVC `${VOLSYNC_CLAIM:=${APP}}` to
  `s3:https://s3.${SECRET_DOMAIN}/backups/volsync/${APP}`, `copyMethod: Direct`, retain
  hourly:24/daily:7.
- **`replicationdestination.yaml`** — `trigger: manual: restore-once`; on trigger, provisions a
  PVC and restores the latest restic snapshot into it (used for migrations / disaster restore).
- **`externalsecret.yaml`** — builds the restic env (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD`,
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) from Bitwarden (`volsync restic` + `minio-tf-backups`).

The app keeps its own PVC; the component is purely additive. Apps opt in via their `ks.yaml`
(`VOLSYNC_CLAIM` defaults to `${APP}` — set it when the PVC name differs, e.g. matter-hub):

```yaml
spec:
  components:
    - ../../../../components/volsync
  postBuild:
    substitute:
      APP: home-assistant-matter-hub
      VOLSYNC_CLAIM: home-assistant-matter-hub-data
      VOLSYNC_CAPACITY: 1Gi
      VOLSYNC_STORAGECLASS: nfs-csi
```

> `copyMethod: Direct` is the permanent choice here, not a stopgap. csi-driver-nfs "snapshots"
> are just tarballs written back to the same Synology NFS share — not real CSI snapshots — so
> `copyMethod: Snapshot` and the `dataSourceRef` volume-populator (auto-restore-on-deploy) aren't
> meaningfully available on this storage and aren't worth pursuing.

### 3. Secrets

- **S3 creds:** reuse the **existing `backups` MinIO bucket** (verified present and unused) and
  its already-provisioned **`minio-tf-backups`** Bitwarden item (access/secret key). restic
  writes under a `volsync/${APP}` prefix. **No terraform change / no `tofu apply` needed.**
- **restic repo password:** **terraform-managed** — a `random_password` + `bitwarden_item_login`
  named **`volsync restic`** added to `terraform/bitwarden` (same pattern as `cloudnative_pg
  credentials`). No manual Bitwarden step; owner just runs `tofu apply` there. ⚠️ Losing this
  password makes the encrypted backups unrecoverable — it lives in terraform state + Bitwarden.
- The component `ExternalSecret` pulls `RESTIC_PASSWORD` from the `volsync restic` item and the
  S3 keys from `minio-tf-backups`, both via the `bitwarden-login` ClusterSecretStore.

## Phases

### Phase A — Infra
- [x] Bucket: **reuse existing `backups`** (verified present + unused) — no minio terraform change
- [x] restic password: added `volsync restic` item to `terraform/bitwarden` (IaC)
- [ ] **Owner:** `tofu apply` in `terraform/bitwarden` → creates the `volsync restic` item
- [x] Deploy operator: `apps/volsync-system/` (backube HelmRepository + HelmRelease) — built
- [x] Add `components/volsync/` (restic/Direct/S3, adapted) — built

### Phase B — Verify on matter-hub ✅ DONE 2026-06-21
- [x] Enrolled matter-hub via the component (`VOLSYNC_CLAIM=home-assistant-matter-hub-data`);
      ExternalSecret `SecretSynced`, ReplicationSource created
- [x] **Backup verified:** mover `Successful` — `snapshot 575fd214 saved` to
      `s3://backups/volsync/home-assistant-matter-hub` (3 files, 17.3 KiB); hourly schedule active
- [x] **Restore verified:** ad-hoc `ReplicationDestination` restored snapshot `575fd214` into a
      scratch PVC; contents **byte-identical** to live `/data` (same 3 files + sizes). Scratch
      resources cleaned up.

> Operator deployed + verified healthy on-cluster (volsync `0.16.0`, pod 1/1, CRDs present).

### Phase C — Migrate matter-hub via restore (replaces the PV rebind)
- [ ] Move matter-hub to `home-automation` with the volsync component; bootstrap PVC restores
      from backup; confirm Matter bridge data intact
- [ ] Retire the interim `Retain` PV + old `default` PVC

### Phase D — Roll out — ✅ first wave done 2026-06-21
- [x] Enrolled: home-assistant (568), jellyfin (568, jellyfin-config), mealie (65534),
      unifi (root), zwave-js-ui (root), esphome (root), wallos (root) — plus matter-hub + calibre
      already. All verified backing up real data (HA 4.7 GiB, jellyfin 1.2 GiB, unifi 1.1 GiB, …).
- [x] Root-owned-data apps (unifi/zwave/esphome/wallos) need `VOLSYNC_PUID/PGID: "0"` **and** the
      `volsync.backube/privileged-movers: "true"` annotation on their namespace (added to `default`
      + `productivity`). Set `VOLSYNC_PUID/PGID` to match each app's data ownership.
- Not backed up by design: immich photos (2TB on `Retain` NFS) and CNPG DBs (Barman).

## Decisions (resolved 2026-06-21)

1. **Mover: restic.** ✅
2. **Bucket: reuse existing `backups`** (no dedicated bucket, no `tofu apply`). ✅
3. **`copyMethod: Direct`** — accepted for these config-sized volumes (no app quiesce). ✅

## Reference

- Pattern source: `~/git/k8s-home-ops/oneDr0p-home-ops/kubernetes/components/volsync/` and
  `…/apps/volsync-system/`.
- Relates to [namespace reorg plan](./2026-06-20-namespace-reorganization.md) Phase 2.
