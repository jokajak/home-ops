# Migration Plan: CNPG In-Tree Barman → Barman Cloud Plugin

**Date:** 2026-06-14
**Status:** Proposed (awaiting approval before implementation)
**Scope:** Both CNPG clusters — `immich-database` (`default`) and `postgres` (`database`)

## Overview

CloudNativePG's in-tree `spec.backup.barmanObjectStore` is **deprecated as of CNPG 1.26 and
removed in 1.30.0**. We currently run **1.29.1**, so backups will silently stop working the
moment the operator is bumped to 1.30. This plan migrates both clusters to the supported
**Barman Cloud Plugin** (`barman-cloud.cloudnative-pg.io`) with **no loss of backup history**,
by keeping each cluster's existing `destinationPath` and `serverName`.

This is a backup-system change affecting every database in the cluster, so it is staged:
install the plugin first and verify it's healthy, then cut over one cluster at a time, verifying
archiving recovers after each.

## Current State

| Cluster | Namespace | serverName | Creds secret | destinationPath | Compression | Retention |
|---------|-----------|------------|--------------|-----------------|-------------|-----------|
| `immich-database` | `default` | `immich-v4` | `minio-immich-pgsql` | `s3://databases/` | bzip2 | 30d |
| `postgres` | `database` | `postgres16-v3` | `minio-pgsql` | `s3://databases/` | bzip2 | 30d |

- **CNPG operator:** 1.29.1 (`kubernetes/apps/database/cloudnative-pg/app/helmrelease.yaml`, chart `0.28.2`)
- **Endpoint:** `https://s3.${SECRET_DOMAIN}` (MinIO), both clusters
- **cert-manager:** present (ACME `letsencrypt-*` ClusterIssuers exist; the plugin issues its own
  self-signed mTLS cert and does **not** use the ACME issuers)
- **MinIO buckets** managed as code in `terraform/minio/`; backup *objects* are not IaC
- Neither cluster uses `bootstrap.recovery` / `externalClusters` today, so recovery-side plugin
  wiring is out of scope (note it for any future restore).

## Target State

- A cluster-wide **`plugin-barman-cloud` v0.12.0** deployment (new Flux app under
  `kubernetes/apps/database/`), managed by cert-manager.
- One **`ObjectStore`** (`barmancloud.cnpg.io/v1`) per cluster, in the cluster's namespace,
  carrying the S3 config + retention (retention moves from the Cluster to the ObjectStore).
- Each `Cluster` references the plugin via `spec.plugins` (`isWALArchiver: true`); `spec.backup`
  is removed.
- Each `ScheduledBackup` uses `method: plugin`.
- **`serverName` and `destinationPath` unchanged** → existing `immich-v4` / `postgres16-v3`
  history continues seamlessly.

## Prerequisites

- ✅ CNPG ≥ 1.26 (we are 1.29.1; 1.27+ recommended — satisfied)
- ✅ cert-manager installed and ready
- ✅ `immich-v4` recovery point already established (base backup 2026-06-14T14:19:20Z)
- ⚠️ Confirm a current `postgres16-v3` recovery point exists before cutover (see Phase 3.0)

## Phase 1 — Install the plugin (cluster-wide)

New Flux app, e.g. `kubernetes/apps/database/cnpg-barman-plugin/` (`ks.yaml` +
`app/{helmrelease.yaml,kustomization.yaml}`), wired into the `database` namespace
`kustomization.yaml`, with `dependsOn: cluster-apps-cloudnative-pg` and cert-manager.

**Install source (confirm at implementation):** the plugin is distributed as a raw manifest
(`github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.12.0/manifest.yaml`) and as
an OCI Helm chart. The chart is **not** in the `https://cloudnative-pg.github.io/charts` index,
so this is **not** a drop-in reuse of the existing `cloudnative-pg` HelmRepository.

- **Option A (preferred, GitOps-native):** OCI HelmRelease (`OCIRepository` → chart
  `plugin-barman-cloud`), pinned to the chart version mapping to app `v0.12.0`. Renovate-friendly.
- **Option B (fallback):** vendor the pinned `v0.12.0` `manifest.yaml` into the app dir and apply
  via a Flux Kustomization. Simple and explicit; manual version bumps.

**Verify before proceeding:** plugin Deployment `Ready`, its cert-manager `Certificate` issued,
and the operator recognizes the plugin (no plugin errors in `cloudnative-pg` operator logs).

## Phase 2 — Cut over `immich-database` (`default`)

### 2.1 Create the ObjectStore
`kubernetes/apps/default/immich/app/database/objectstore.yaml`:
```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: immich-objectstore
  namespace: default
spec:
  configuration:
    destinationPath: s3://databases/
    endpointURL: https://s3.${SECRET_DOMAIN:=internal}
    serverName: immich-v4          # unchanged — preserves history
    s3Credentials:
      accessKeyId:
        name: minio-immich-pgsql
        key: minio_s3_access_key
      secretAccessKey:
        name: minio-immich-pgsql
        key: minio_s3_secret_access_key
    wal:
      compression: bzip2
      maxParallel: 2
    data:
      compression: bzip2
  retentionPolicy: 30d             # moved from Cluster.spec.backup.retentionPolicy
```
Add `objectstore.yaml` to `database/kustomization.yaml`.

### 2.2 Switch the Cluster (`database/cluster.yaml`)
- **Remove** the entire `spec.backup` block (`barmanObjectStore` + `retentionPolicy`).
- **Add**:
```yaml
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: immich-objectstore
```
This triggers a rolling update (same blip pattern as the image swaps — `immich-server` reconnects).

### 2.3 Switch the ScheduledBackup (`database/scheduledbackup.yaml`)
```yaml
spec:
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

### 2.4 Verify
- `ContinuousArchiving=True` again, archiving via plugin (new metric names — see Caveats).
- Trigger an on-demand `kind: Backup` (`method: plugin`) → completes; `firstRecoverabilityPoint`
  still set against `immich-v4`.
- `immich-server` healthy.

## Phase 3 — Cut over `postgres` (`database`)

### 3.0 Pre-check
Confirm `postgres16-v3` currently has a usable recovery point (`kubectl get cluster postgres -n
database -o jsonpath='{.status.firstRecoverabilityPoint}'`). If empty, fix in-tree archiving
first (same "Expected empty archive" class of issue is possible).

### 3.1–3.3 Same shape as Phase 2
- `ObjectStore` `postgres-objectstore` in `database` ns, `serverName: postgres16-v3`, creds
  `minio-pgsql`, retention 30d → files under
  `kubernetes/apps/database/cloudnative-pg/cluster/`.
- Edit `cluster/cluster.yaml`: remove `spec.backup`, add `spec.plugins` (`barmanObjectName:
  postgres-objectstore`).
- Edit `cluster/scheduledbackup.yaml` (if present): `method: plugin`.

### 3.4 Verify
Same checks as 2.4, against `postgres16-v3`.

## Phase 4 — Post-migration cleanup (optional, after both verified)

- Delete orphaned **postgres** prefixes in MinIO once `postgres16-v3` is confirmed healthy on the
  plugin: `postgres-db/`, `postgres16-v1/`, `postgres16-v2/` (mirror of the immich-v1/2/3 cleanup;
  verify each has no needed recovery point first).
- Update any Grafana/alerts referencing the old in-core backup metrics (renamed — see Caveats).

## Rollback

In-tree `barmanObjectStore` is still fully supported on 1.29.1, so each cutover commit is
revertible: `git revert` the per-cluster change to restore `spec.backup`/`barmanObjectStore`, and
the cluster rolls back to in-tree archiving. The plugin install (Phase 1) is additive and can stay
even if a cutover is rolled back. `serverName`/`destinationPath` are unchanged either way, so no
backup history is lost in either direction.

## Risks & Caveats

- **Rolling update per cutover** — brief primary failover per cluster; apps reconnect (observed
  fine during the image swaps).
- **Retention relocation** — retention is defined on the `ObjectStore`, not the Cluster; dropping
  `spec.backup.retentionPolicy` without setting it on the ObjectStore would disable retention.
- **Metric renames** — dashboards/alerts must move from `cnpg_collector_*` to
  `barman_cloud_cloudnative_pg_io_*` (`*_first_recoverability_point`, `*_last_failed_backup_timestamp`,
  `*_last_available_backup_timestamp`).
- **Plugin/operator version coupling** — keep plugin and CNPG operator versions compatible; bump
  the plugin before/with the eventual 1.30 operator bump.
- **kubeconform/CI** — `barmancloud.cnpg.io/v1 ObjectStore` is a new CRD; ensure its schema is
  available to `kubeconform` (CI) or add a skip/schema-location, as done for other CRDs.

## Open Questions

1. Plugin install: OCI HelmRelease (preferred) vs vendored manifest — confirm chart OCI
   coordinates + exact chart version for app `v0.12.0`.
2. Do we also want to migrate the `postgres` cluster's old prefixes cleanup (Phase 4) in the same
   change set, or defer?
3. Any external consumers of the in-core backup metrics to update before cutover?

## References

- Barman Cloud Plugin — intro: https://cloudnative-pg.io/plugin-barman-cloud/docs/intro/
- Installation: https://cloudnative-pg.io/plugin-barman-cloud/docs/installation/
- Migration guide: https://cloudnative-pg.io/plugin-barman-cloud/docs/migration/
- Plugin releases (v0.12.0): https://github.com/cloudnative-pg/plugin-barman-cloud/releases
- CNPG 1.29 docs: https://cloudnative-pg.io/docs/1.29/
