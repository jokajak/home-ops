# Issue Tracker

> Living list of known issues and follow-ups not yet resolved. Add entries as
> they're found; move to **Resolved** with a date when fixed. Severity: High
> (broken / data-risk), Med (degraded / decision needed), Low (cleanup / nice-to-have).

| # | Issue | Area | Severity | Status |
|---|-------|------|----------|--------|
| 1 | Authentik declared in Git but not deployed | security | High | Open |
| 2 | Gatus not persisting to Postgres (in-memory) | observability | Med | Open |
| 3 | Shared `postgres` cluster has no real consumers | database | Med | Decision |
| 4 | Backup alerting may use removed CNPG metric names | observability | Med | Verify |
| 5 | Immich automatic DB backups lapsed since Feb 8 | immich | Med | Verify |
| 6 | Repo-root `kubeconfig` client cert expired | tooling | Low | Open |
| 7 | Immich asset metadata gap Feb 8 → Jun 14 | immich | Low | Open |

---

## 1. Authentik declared but not deployed — High

`kubernetes/apps/security/kustomization.yaml` references `./authentik/ks.yaml`, and
the app manifests exist (`kubernetes/apps/security/authentik/`), but the cluster has
**no `authentik` Flux Kustomization, no HelmRelease, and no pods**.

- **Findings:** `kubectl get ks -A | grep authentik` → nothing; `kubectl get pods -n security`
  → no authentik. So Flux is not reconciling it (parent error, unmet `dependsOn`, or the
  ks isn't being picked up).
- **Impact:** No SSO/identity provider running. Its `ExternalSecret` expects `postgres-rw`
  and an `authentik` database that does not exist.
- **Next steps:** Inspect `kubernetes/apps/security/authentik/ks.yaml` + the security parent;
  `flux get ks -A`, `flux get hr -A` for errors. Decide: fix & deploy, or remove the
  declaration if Authentik is intentionally retired.

## 2. Gatus not persisting to Postgres — Med

Gatus is running (2/2) but uses the default **in-memory** store, so monitoring history is
lost on restart.

- **Findings:** the `gatus` database does **not** exist in the `postgres` cluster (only the
  default empty `app` DB is present); the HelmRelease has no `storage.type: postgres`
  config. The `INIT_POSTGRES_*` env in `app/externalsecret.yaml` is configured but
  ineffective (no storage wired; the DB was never created).
- **Next steps:** Decide — (a) wire Gatus storage to Postgres (set `storage.type`/DSN and
  ensure the init-db creates the `gatus` DB), or (b) drop the unused `INIT_POSTGRES_*`
  config and accept in-memory. Also clean up the stale `gatus-679ccc994-*` pod
  (0/2 Completed, ~67d old).

## 3. Shared `postgres` cluster has no real consumers — Med (decision)

The `database/postgres` CNPG cluster holds only the empty default `app` database. With
Authentik absent (#1) and Gatus not using it (#2), nothing currently depends on it.

- **Next steps:** Decide to **keep** (it's the intended home for Authentik/Gatus once #1/#2
  are fixed) or **decommission**. It was migrated to the Barman Cloud Plugin regardless, so
  it remains backed up either way.

## 4. Backup alerting may reference removed CNPG metric names — Med (verify)

After the Barman Cloud Plugin migration, backup/recoverability status is reported via
`barman_cloud_cloudnative_pg_io_*` metrics; the in-core `cnpg_collector_*` metrics (and the
in-core cluster `firstRecoverabilityPoint`/`lastSuccessfulBackup` fields) no longer update.

- **Next steps:** Verify the postgres `cluster/prometheusrule.yaml` and any Grafana
  dashboards/alerts use the new metric names, so backup-failure alerting isn't silently
  blind. Update where needed.

## 5. Immich automatic DB backups lapsed since Feb 8 — Med (verify)

Immich's own daily `pg_dumpall` backups to NFS (`/usr/src/app/upload/backups/`) stopped
2026-02-08 (when Immich broke). Now that Immich is healthy again, confirm they resume on
the next scheduled run; if not, fix the Immich backup settings.

- **Note:** CNPG plugin backups to MinIO are the primary DR; these NFS dumps are a secondary
  safety net.

## 6. Repo-root `kubeconfig` client cert expired — Low

`./kubeconfig` has a client cert that expired 2026-03-30 (`Unauthorized`); `~/.kube/config`
works. Regenerate the repo kubeconfig (talos task) or standardize on `~/.kube/config`, and
beware a stale `KUBECONFIG` env pointing at the repo file.

## 7. Immich asset metadata gap Feb 8 → Jun 14 — Low

The restored Immich DB is from the Feb 8 dump; any assets added 2026-02-08 → 2026-06-14
aren't in the metadata. Image **files** are safe on NFS. If any were added in that window, a
library re-scan/re-import can recover them. (Likely none — Immich was broken for most of it.)

---

## Recently resolved — 2026-06-14

- **Immich database recovered**: restored the Feb 8 dump, migrated vector search
  pgvecto.rs → VectorChord, Immich v2.5.5 healthy.
- **CNPG backups migrated to the Barman Cloud Plugin** (both `immich-database` and
  `postgres`); deprecated in-tree `barmanObjectStore` removed.
- **MinIO cleanup**: deleted orphaned backup prefixes `immich-v1/v2/v3` and
  `postgres-db`/`postgres16-v1`/`postgres16-v2` (~5 GB reclaimed).

See `docs/plans/2026-06-14-cnpg-barman-cloud-plugin-migration.md` and the immich restore
handoff for details.
