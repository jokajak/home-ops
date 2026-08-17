# Issue Tracker

> Living list of known issues and follow-ups not yet resolved. Add entries as
> they're found; move to **Resolved** with a date when fixed. Severity: High
> (broken / data-risk), Med (degraded / decision needed), Low (cleanup / nice-to-have).

Numbers are stable and never reused; resolved entries are deleted, leaving gaps.
`talos/README.md` cross-references these by number.

| # | Issue | Area | Severity | Status |
|---|-------|------|----------|--------|
| 2 | Grafana dashboards may still reference removed CNPG metric names | observability | Low | Verify |
| 4 | Repo-root `kubeconfig` client cert expired | tooling | Low | Open |
| 5 | Immich asset metadata gap Feb 8 → Jun 14 | immich | Low | Open |
| 14 | `basement-dell-sff` is dead and not yet replaced | talos | Med | Open |

---

## 2. Grafana dashboards may still reference removed CNPG metric names — Low (verify)

After the Barman Cloud Plugin migration, backup status is reported via
`barman_cloud_cloudnative_pg_io_*` metrics; the in-core `cnpg_collector_*` metrics (and the
cluster `firstRecoverabilityPoint`/`lastSuccessfulBackup` fields) no longer update.

**The alerting half is confirmed working** (2026-08-16):
`count(barman_cloud_cloudnative_pg_io_last_available_backup_timestamp)` returns 10 series, so the
`CNPGBackupFailed` / `CNPGBackupTooOld` alerts in the postgres `cluster/prometheusrule.yaml`
evaluate against real data rather than an empty vector.

- **Remaining:** audit Grafana dashboards for panels still querying the old `cnpg_collector_*`
  names, which would render empty.

## 4. Repo-root `kubeconfig` client cert expired — Low

`./kubeconfig` has a client cert that expired 2026-03-30 (`Unauthorized`); `~/.kube/config`
works. Regenerate the repo kubeconfig (talos task) or standardize on `~/.kube/config`, and
beware a stale `KUBECONFIG` env pointing at the repo file.

## 5. Immich asset metadata gap Feb 8 → Jun 14 — Low

The restored Immich DB is from the Feb 8 dump; any assets added 2026-02-08 → 2026-06-14
aren't in the metadata. Image **files** are safe on NFS. If any were added in that window, a
library re-scan/re-import can recover them. (Likely none — Immich was broken for most of it.)

## 14. `basement-dell-sff` is dead and not yet replaced — Med

Confirmed 2026-08-15. The node will not boot and its drive reports unrecoverable sectors. It is
**not coming back without a reinstall on new hardware/disk**, so this is a permanent topology
change rather than an outage to wait out.

- **Control-plane capacity is restored.** It was one of three control-plane nodes, which left etcd
  with three voting members and only two reachable — quorum intact, fault tolerance zero. Its etcd
  member was removed and `basement-lenovo-m910q` was promoted in its place (drain → `talosctl
  reset` → rejoin, since Talos cannot convert a worker in place), returning etcd to three healthy
  members on 2026-08-16. `topf.yaml` now lists dell-sff as a **worker**, so when it is rebuilt it
  rejoins as one and never touches etcd again.
- `openebs-hostpath` is node-local, so its disk took four PVCs with it. Three were CNPG replicas
  and were rebuilt from healthy primaries (`default/home-assistant-db-2`, `default/immich-database-1`,
  and `database/postgres-1`). The fourth, `ai/open-webui-data`, had no replica and no backup, so
  open-webui was removed from the repo entirely rather than restored (2026-08-16); Flux prunes its
  HelmRelease, ExternalSecret and PVC. The `ai` namespace stays for future work.
- **`database/postgres` was a full outage** (0/3 ready) because `postgres-1` — the primary — lived
  on this disk. Recovery is recorded below; the `authentik` database survived intact at 136 MB.

**When it is rebuilt:**

- `topf.yaml` already lists it as a `worker`, so a fresh install joins as one. Nothing else needs
  changing first.
- A reinstall is the *cleanest* way onto the current baseline: it writes the declared schematic
  and Talos version directly, with no in-place migration to go wrong. `basement-lenovo-m910q` and
  `basement-rpi4-chocolate` both took this path successfully.
- It will need `install.disk` to match its replacement hardware. The tree hardcodes `/dev/sda` in
  `all/00-install.yaml` for every node; if the new disk enumerates differently, add a per-node
  override at `node/basement-dell-sff/00-install.yaml`.

### Fallout: `basement-rpi4-peach` had stale nameservers — resolved 2026-08-16

Peach rejoined the cluster but nothing scheduled there could pull an image:

```
Failed to pull image "...": dial tcp: lookup ghcr.io on 127.0.0.53:53: server misbehaving
```

Talos hostDNS was running and answering, but forwarding to a stale upstream — the live config
predating the repo's patches, the same drift that made the whole migration necessary. The network
itself was fine: querying the intended resolver directly from a pod on peach resolved correctly,
which is the test that separates "wrong config" from "unreachable resolver". Peach was also on its
*static* address, so only its nameservers had drifted.

- **Fix applied:** a targeted `talosctl patch mc` on `machine.network.nameservers`, which
  reconciles live and needs no reboot. `topf.yaml`'s declared `nameservers` were then found to be
  stale too — neither declared resolver answered — and were corrected, so a future apply
  reinforces the fix rather than reverting it.

> **Diagnosing this is misleading.** Kubelet's image-pull backoff stretches to ~25 minutes, so
> pods keep reporting the old DNS error long after DNS is fixed. Check the age of the `Pulling`
> event, not the text of the `Failed` one, and delete the pods to reset the backoff before
> concluding a fix did not work.

### Fallout: the openebs provisioner wedges silently — 2026-08-16

`openebs-localpv-provisioner` had 31 restarts and was hot-looping on
`v1 Endpoints is deprecated in v1.33+` warnings every ~2s while draining no work. Even once
peach could pull images again, it never created the `init-pvc-…` helper, so `postgres-2`'s PVC
sat `Pending` and reported only the generic `create process timeout after 120 seconds`.

`kubectl rollout restart deploy -n openebs-system openebs-localpv-provisioner` cleared it and the
PVC bound within seconds. Worth suspecting whenever an `openebs-hostpath` PVC is `Pending` with
no helper pod in `openebs-system` — the provisioner reports itself `Running` and `1/1` throughout.

Also seen: openebs `cleanup-pvc-*` helpers stick in `Terminating` forever when their node is
gone, and must be `--force --grace-period=0` deleted.

### `database/postgres` recovery — 2026-08-15

Recorded because the failure mode is non-obvious and likely to recur with node-local storage.

With the primary's disk gone, CNPG deadlocked: both surviving replicas started as standbys
waiting on the `postgres-rw` service, which still resolved to the deleted `postgres-1`, while the
operator refused to promote either — `"Wrong target primary, the chosen one is not active or not
present"` — because neither could become *active* without a primary to stream from. `cnpg promote`
cannot break this; it is built for promoting an already-healthy replica.

The fix was to stop the operator so its reconcile loop could not revert a status edit:

```console
$ kubectl scale deploy -n database cloudnative-pg --replicas=0
$ kubectl patch cluster -n database postgres --subresource=status --type=merge \
    -p '{"status":{"currentPrimary":"postgres-3","targetPrimary":"postgres-3"}}'
$ kubectl scale deploy -n database cloudnative-pg --replicas=1
```

> **Do not delete the instance pod while the operator is scaled to zero.** CNPG instance pods are
> created by the operator, not by a StatefulSet, so nothing recreates them. Scale the operator
> back up and let it rebuild the pod against the patched status.

Both replicas held the identical LSN (`37/B6000028`, timeline 4), so the choice between them was
arbitrary; the promoted instance replayed to `37/BA000000`, ahead of its last checkpoint. Backups
had been stalled 12 days and resumed on their own once a target pod existed.

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
  reverted to memory. (VM ingestion of its metrics was confirmed working 2026-08-17.)
- **Postgres cluster kept**: Authentik now consumes it, so the decommission question is closed.

See `docs/plans/2026-06-14-cnpg-barman-cloud-plugin-migration.md` and the immich restore
handoff for details.
