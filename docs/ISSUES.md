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
| 6 | Talos config exists twice, divergently; root copy is plaintext | talos | Med | Open |
| 7 | Kubeconform CI breaks if `FLUX_VERSION` is bumped to 2.9.x | tooling | Low | Verify |

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

## 6. Talos config exists twice, divergently; root copy is plaintext — Med

Found during the 2026-08-04 de-templating pass and deliberately left alone — this needs its own
focused change. Nothing under `talos/` or `kubernetes/talos/` was touched.

- **Two trees, and the tooling disagrees about which is real.** `talos/talconfig.yaml`
  (403 lines, 7 nodes) is what `.taskfiles/Talos` operates on via `TALOS_DIR`.
  `kubernetes/talos/` holds a stale SOPS-encrypted `talconfig.yaml` (266 lines) plus the real
  `talsecret.sops.yaml`, `cilium/`, `kubelet-csr-approver/`, `talconfig.yaml.norpi`, and seven
  empty `clusterconfig.YYYYMMDD/` snapshot dirs. `.envrc` points `TALOSCONFIG` at the *second*
  tree; the taskfiles use the first.
- **The root copy is unencrypted** and matches no rule in `.sops.yaml`. It carries node
  addresses, the API VIP, the gateway, VLAN IDs, MAC addresses and an internal hostname — exactly
  the category `CLAUDE.md` says stays out of the repo.
- **`.taskfiles/Talos` points at the wrong secret file.** `TALHELPER_SECRET_FILE` is
  `talos/talhelper.sops.yaml`; the real bundle is `kubernetes/talos/talsecret.sops.yaml`
  (`talsecret.sops.yaml` is also talhelper's own default name), so `task talos:gensecret` would
  write a new bundle to the wrong path rather than reuse the existing one.
- **`kubernetes/talos/talosconfig.20240317.1258` is a committed `os:admin` client certificate**
  (`ca`/`crt`/`key`). It **expired 2025-03-17**, so there is no live exposure and nothing to
  rotate — but it shouldn't be in the tree.
- **Version drift.** `talconfig.yaml` pins Talos v1.13.4 / Kubernetes v1.35.6 while tuppr
  (`kubernetes/apps/system-upgrade/tuppr/plans/talosupgrade.yaml`) drives the cluster at v1.13.7.
  Renovate never scanned root `talos/` — its `managerFilePatterns` only ever covered
  `kubernetes/` (and, until 2026-08-04, `ansible/`) — which is why the drift went unnoticed.

**Next steps:** pick one canonical tree, move `talsecret.sops.yaml` and the `cilium` /
`kubelet-csr-approver` kustomizations to sit beside it, fix `TALHELPER_SECRET_FILE` and
`TALOSCONFIG` to agree, add a `.sops.yaml` rule covering the surviving `talconfig.yaml`, then
`task sops:encrypt` it. Note that deleting files removes them from `HEAD`, not from history —
scrubbing history is a separate decision.

## 7. Kubeconform CI breaks if `FLUX_VERSION` is bumped to 2.9.x — Low (verify)

`.github/workflows/kubeconform.yaml` pins `FLUX_VERSION: "2.8.8"`, and `scripts/kubeconform.sh`
pipes every kustomization through `flux envsubst --strict`. Observed 2026-08-04:

- flux **2.8.8** → `bash scripts/kubeconform.sh ./kubernetes` exits **0**.
- flux **2.9.3** → fails at `kubernetes/apps/networking/nginx/certificates/` with
  `✗ variable not set (strict mode): "SECRET_DOMAIN"`.

`--strict` in 2.9.x appears to error on variables the workflow never supplies (they come from
`cluster-secrets` at reconcile time, not in CI). Renovate manages `FLUX_VERSION` via the custom
manager in `renovate.json5`, so a routine bump would turn CI red for a reason unrelated to the
PR's contents.

**Next steps:** confirm the behaviour change against flux 2.9.x release notes, then either
supply placeholder values in the workflow, drop `--strict`, or move to `flate` (see
[the realignment roadmap](./plans/2026-08-04-upstream-template-realignment.md), phase 1) which
handles substitution itself.

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
