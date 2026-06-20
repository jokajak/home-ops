# Issue Tracker

> Living list of known issues and follow-ups not yet resolved. Add entries as
> they're found; move to **Resolved** with a date when fixed. Severity: High
> (broken / data-risk), Med (degraded / decision needed), Low (cleanup / nice-to-have).

| # | Issue | Area | Severity | Status |
|---|-------|------|----------|--------|
| 1 | Gatus metrics ingestion into VictoriaMetrics unconfirmed | observability | Med | Verify |
| 2 | Backup alerting may use removed CNPG metric names | observability | Med | Verify |
| 3 | Immich automatic DB backups lapsed since Feb 8 | immich | Med | Verify |
| 4 | Repo-root `kubeconfig` client cert expired | tooling | Low | Open |
| 5 | Immich asset metadata gap Feb 8 → Jun 14 | immich | Low | Open |

---

## 1. Gatus metrics ingestion into VictoriaMetrics unconfirmed — Med (verify)

Gatus runs on in-memory storage (SQLite-on-PVC was attempted and reverted — see Resolved), so
VictoriaMetrics is intended to be the source of truth for uptime history/alerting. Gatus's
`/metrics` endpoint serves data and a `vmservicescrape/gatus` exists and reports `operational`,
**but a VM query for gatus series returned empty during verification** — so ingestion is not
confirmed.

- **Findings:** the vmservicescrape selector (`app.kubernetes.io/{instance,name,service}=gatus`)
  matches the gatus Service labels and port `http`; gatus `/metrics` returns `gatus_results_*`.
  VM query `count(gatus_results_total)` came back empty (could be timing, a label/job mismatch,
  or vmagent not scraping the vmservicescrape).
- **Next steps:** check vmagent targets for gatus, confirm the scrape is active, query VM for
  `gatus_results_total`, then build Grafana dashboards + VMAlert rules for uptime alerting.

## 2. Backup alerting may reference removed CNPG metric names — Med (verify)

After the Barman Cloud Plugin migration, backup/recoverability status is reported via
`barman_cloud_cloudnative_pg_io_*` metrics; the in-core `cnpg_collector_*` metrics (and the
in-core cluster `firstRecoverabilityPoint`/`lastSuccessfulBackup` fields) no longer update.

- **Done:** added `CNPGBackupFailed` / `CNPGBackupTooOld` alerts to the postgres
  `cluster/prometheusrule.yaml` using the new `barman_cloud_cloudnative_pg_io_*` timestamp
  metrics, so backup-failure alerting is no longer blind.
- **Next steps (cluster-side):** confirm the exact exported metric names against the running
  Barman plugin (`barman_cloud_cloudnative_pg_io_last_available_backup_timestamp` /
  `*_last_failed_backup_timestamp`) and that the alerts evaluate non-empty in vmalert; update any
  Grafana dashboards still referencing the old `cnpg_collector_*` names.

## 3. Immich automatic DB backups lapsed since Feb 8 — Med (verify)

Immich's own daily `pg_dumpall` backups to NFS (`/usr/src/app/upload/backups/`) stopped
2026-02-08 (when Immich broke). Now that Immich is healthy again, confirm they resume on
the next scheduled run; if not, fix the Immich backup settings.

- **Note:** CNPG plugin backups to MinIO are the primary DR; these NFS dumps are a secondary
  safety net.

## 4. Repo-root `kubeconfig` client cert expired — Low

`./kubeconfig` has a client cert that expired 2026-03-30 (`Unauthorized`); `~/.kube/config`
works. Regenerate the repo kubeconfig (talos task) or standardize on `~/.kube/config`, and
beware a stale `KUBECONFIG` env pointing at the repo file.

## 5. Immich asset metadata gap Feb 8 → Jun 14 — Low

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
- **Authentik re-enabled**: uncommented its Flux Kustomization and fixed a `namespace: default`
  override that was deploying it into `default`; now running in `security` (server + worker
  Ready), `authentik` DB auto-created by init-db, secrets from Terraform-managed Bitwarden.
- **Gatus storage decided = in-memory**: SQLite-on-PVC was attempted but reverted — the rollout
  couldn't converge within Flux's helm timeout (Recreate + `WaitForFirstConsumer` PVC + Stakater
  reloader churn), which wedged the release in `pending-upgrade`; cleared the stuck revision and
  reverted to memory. (VM ingestion of its metrics is the open item #1.)
- **Postgres cluster kept**: Authentik now consumes it, so the decommission question is closed.

See `docs/plans/2026-06-14-cnpg-barman-cloud-plugin-migration.md` and the immich restore
handoff for details.
