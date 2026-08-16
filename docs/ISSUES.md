# Issue Tracker

> Living list of known issues and follow-ups not yet resolved. Add entries as
> they're found; move to **Resolved** with a date when fixed. Severity: High
> (broken / data-risk), Med (degraded / decision needed), Low (cleanup / nice-to-have).

Numbers are stable and never reused; resolved entries are deleted, leaving gaps.
`talos/README.md` cross-references these by number.

| # | Issue | Area | Severity | Status |
|---|-------|------|----------|--------|
| 1 | Gatus reaches VictoriaMetrics, but only 1 of 17 endpoints produces series | observability | Med | Open |
| 2 | Grafana dashboards may still reference removed CNPG metric names | observability | Low | Verify |
| 4 | Repo-root `kubeconfig` client cert expired | tooling | Low | Open |
| 5 | Immich asset metadata gap Feb 8 → Jun 14 | immich | Low | Open |
| 7 | Kubeconform CI breaks if `FLUX_VERSION` is bumped to 2.9.x | tooling | Low | Verify |
| 9 | `basement-rpi4-peach` aimed at a schematic with no Raspberry Pi overlay | talos | **High** | Open |
| 10 | Live machine configs are Talos v1.9.5-era; repo has not been applied since | talos | **High** | Open |
| 11 | Fleet runs the empty schematic; repo declares extensions never installed | talos | Med | Open |
| 12 | `topf apply` migrates networking to multi-doc config in one shot | talos | Med | Open |
| 13 | `basement-rpi4-chocolate`'s static network config has never applied | talos | Med | Open |
| 14 | `basement-dell-sff` is dead; etcd is permanently at 2-of-3 | talos | **High** | Open |

---

## 1. Gatus reaches VictoriaMetrics, but only 1 of 17 endpoints produces series — Med

The original question here was whether gatus metrics reach VM at all. **They do** — verified
2026-08-16, `count(gatus_results_total)` returns 1 (it previously returned empty). Ingestion,
the vmservicescrape selector and the scrape path are all fine.

That answer exposed a sharper problem. Gatus is configured by 17 ConfigMaps labelled
`gatus.io/enabled=true`, but VM holds series for exactly **one** endpoint:

```console
$ count(count by (key) (gatus_results_total))   # => 1
$ kubectl get cm -A -l gatus.io/enabled=true | wc -l   # => 17
```

So roughly sixteen monitored endpoints are producing no uptime data, and any alerting built on
these series would be silently blind for all of them.

- **Likely causes:** the k8s-sidecar isn't loading the ConfigMaps into the gatus pod, or gatus is
  loading them but the endpoints fail before recording a result. Check the sidecar's logs and the
  merged config inside the pod before touching VM.
- **Next steps:** confirm how many endpoints gatus itself reports (`/api/v1/endpoints/statuses`)
  to split "not loaded" from "loaded but not scraped", then build dashboards/VMAlert rules once
  coverage is real. Note `nodes-configmap.yaml` is still not wired into the gatus
  `kustomization.yaml`, so node checks have never run.

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

## 9. `basement-rpi4-peach` aimed at a schematic with no Raspberry Pi overlay — High

`basement-rpi4-peach` is an **arm64 Raspberry Pi 4**, but both its live `installerImage`
annotation and the config `topf render` produces point at schematic
`1841b08a…` — the **x86 worker schematic**, which has no `siderolabs/sbc-raspberrypi`
overlay. Its sibling `basement-rpi4-chocolate` correctly resolves to `11452416…`, which does.

**Upgrading peach with that image would leave it unbootable.** Nothing has been applied, so the
hazard is latent, not active.

- **Root cause predates the topf work.** `talconfig.yaml` gave chocolate an explicit
  `talosImageURL` pinned to the rpi schematic, but gave peach
  `installerImage: "{{ .MachineConfig.MachineInstall.InstallImage }}"` — i.e. the *default*
  (x86) install image. topf translated that faithfully and so inherited the bug.
- **Decided fix:** add `schematicId: '@schematic-rpi.yaml'` to the `basement-rpi4-peach` entry
  in `talos/topf.yaml`, matching chocolate.
- **Blocked on the age key.** `topf.yaml` is SOPS partial-encrypted and SOPS MACs the whole
  document, so even this plaintext-by-regex field cannot be added without decrypting first.
  This one edit has to be made by the owner:

  ```console
  $ sops decrypt --in-place talos/topf.yaml
  # add `schematicId: '@schematic-rpi.yaml'` under the basement-rpi4-peach entry,
  # as a sibling of `role:` (same level as chocolate's)
  $ sops encrypt --in-place talos/topf.yaml
  $ topf schematic-ids   # expect exactly two: 9e8cc193… (x86) and ee21ef4a… (rpi)
  ```

- **No side effect any more.** Sharing `schematic-rpi.yaml` used to also hand peach
  `siderolabs/nut-client`; that extension was dropped under #11, so the file is now the stock
  `rpi_generic` overlay and both Pis can share it safely.

## 10. Live machine configs are Talos v1.9.5-era; repo has not been applied since — High

Every reachable node's `machine.install.image` is pinned to `:v1.9.5` (peach: `:v1.11.1`) while
the nodes actually **run Talos v1.13.4**. Several repo-declared settings are simply absent from
the running config, which is the signature of a machine config that has not been regenerated in
a long time:

| Field | Live | Repo declares |
|---|---|---|
| `install.image` tag | `v1.9.5` / `v1.11.1` | `v1.13.4` (from `talosVersion`) |
| `discovery.registries.kubernetes.disabled` | `true` | `false` (`all/08-discovery.yaml`) |
| `kubelet…featureGates.UserNamespacesSupport` | `true` | now declared — see below |
| `apiServer.disablePodSecurityPolicy` | `true` | now declared — see below |

- **Verified 2026-08-10** by rendering the topf tree against a throwaway secrets bundle and
  diffing per node against `talosctl get machineconfig v1alpha1`. Everything else matches:
  install disk, kubelet args/mounts/`nodeIP`, the containerd `files` entry, time servers,
  sysctls, KubePrism, hostDNS, Talos API access, etcd args, cluster network, and the
  `admissionControl` deletion are all byte-identical.
- `machine.features.{rbac,stableHostname,apidCheckExtKeyUsage}` disappear from the render.
  **This is cosmetic** — stock `talosctl gen config v1.13.4` does not emit them either, so they
  fall through to Talos defaults (all `true`).
- **`UserNamespacesSupport` and `disablePodSecurityPolicy` were applied out of band** — they are
  on the running nodes but appear in *neither* `talconfig.yaml` nor the original topf tree. Both
  are now declared in-repo (`all/03-kubelet.yaml.tpl`, `control-plane/03-admission.yaml`) so
  applying topf preserves them instead of silently reverting them. Confirmed present on all 7
  rendered configs (and dPSP on the 3 control-plane nodes) after the change.
- **Still open:** `install.extraKernelArgs: [net.ifnames=0]` is on the live nodes but the render
  carries `net.ifnames=0` only inside the *schematic*. The factory bakes schematic kernel args
  into the installer image, so this is believed equivalent — but it has not been proven, and the
  rpi schematic omits the arg entirely. Interface selection does not depend on it either way
  (`all/20-link-alias.yaml.tpl` matches on bus path, not interface name).
- **Also still open:** the discovery-registry row above. The repo has asked for
  `kubernetes.disabled: false` since the talhelper days and the cluster still reports `true`,
  which is further evidence the repo was never applied. `topf apply` *will* enable the Kubernetes
  discovery registry. Left as-declared deliberately rather than rewriting the repo to match a
  config that predates it.

## 11. Fleet runs the empty schematic; repo declares extensions never installed — Med

`talosctl get extensionstatus` reports schematic
`376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba` on **every** reachable node.
The image factory resolves that to `customization: {}` — no system extensions at all.

The repo declares three customized schematics carrying `crun`, `kata-containers`, `spin`,
`wasmedge`, `intel-ucode` and `nut-client`. **None of them are installed**, and
`kubectl get runtimeclass` returns nothing, so no workload consumes them.

Checked 2026-08-10, per extension:

| Extension | Justification in this cluster | Verdict |
|---|---|---|
| `crun`, `kata-containers`, `spin`, `wasmedge` | **None.** `kubectl get runtimeclass` is empty and no pod sets `runtimeClassName`, so no workload can reach an alternate runtime. | Unused |
| `nut-client` | **None.** No NUT server, UPS monitoring or `upsd` anywhere in the repo or cluster; the only hits are the schematic itself and its own docs. | Unused |
| `intel-ucode` | **Real.** Every x86 node reports `GenuineIntel`. | Keep |

**Resolved 2026-08-10 by trimming to `intel-ucode`.** The unused extensions were removed and
`intel-ucode` was widened from control-plane-only to all x86 nodes — a separate bug found while
checking, since `foyer-hp-800g3` and `basement-lenovo-m910q` are Intel *workers* and were taking
the worker schematic, so they had been getting no microcode updates.

Schematic IDs recomputed and confirmed to resolve at the factory:

| Schematic | Before | After |
| --- | --- | --- |
| x86 control-plane | `0bf2de4e…` | `9e8cc193…` (single x86 schematic now) |
| x86 worker | `1841b08a…` | `9e8cc193…` |
| Raspberry Pi | `11452416…` | `ee21ef4a…` |

`ee21ef4a…` is worth noting: it is the **stock upstream `rpi_generic` schematic**, and it is the
exact ID cited in a comment at `talconfig.yaml:76`, linking the Talos SBC docs. `nut-client` was
accretion that had drifted the Pi off that documented baseline; dropping it restored it.

The first `topf`-driven upgrade is still not a no-op — it installs `intel-ucode` where nothing is
installed today — but the delta is now one extension rather than six. Stage it on one worker first.

## 12. `topf apply` migrates networking to multi-doc config in one shot — Med

The live nodes carry **only** the `v1alpha1` document — `talosctl get machineconfig` lists a
single id. The topf render emits `v1alpha1` **plus** five new-style documents
(`HostnameConfig`, `LinkAliasConfig`, `LinkConfig`, `VLANConfig`, `Layer2VIPConfig`), and moves
addresses, routes, VLAN and the control-plane VIP out of `machine.network.interfaces` — which the
rendered `v1alpha1` no longer contains.

This is the single riskiest part of applying the branch: it rewrites node networking, including
the VIP the API server is reached through, on **all seven nodes**.

- **Do not apply fleet-wide.** Use `--nodes-filter` and start with one worker that is not
  `basement-rpi4-peach` (see #9) — `foyer-hp-800g3` is the natural candidate.
- **The cluster is not currently healthy enough for this.** As of 2026-08-10, `basement-dell-sff`
  (control-plane) and `basement-rpi4-chocolate` are `NotReady`, leaving 2 of 3 control-plane
  nodes up. Neither could be reached for config comparison, so they are also the two nodes whose
  drift is *unmeasured*. Restore them before touching networking.

## 13. `basement-rpi4-chocolate`'s static network config has never applied — Med

Found 2026-08-10 while verifying that the new `cluster-secrets-user` Secret carries real node
addresses. Six of seven entries match the live cluster exactly. Chocolate does not.

- The repo (both `topf.yaml` and the new Secret) carries chocolate's **configured static
  address**, in the same contiguous block as every other node.
- The node's last-reported `InternalIP` in Kubernetes is a **different address, from the DHCP
  range** — so the static network config in this repo was not in effect the last time it booted.
- It is currently unreachable on **both** addresses (`talosctl` times out on port 50000) and its
  Kubernetes conditions are `Ready=Unknown (NodeStatusUnknown)` — the kubelet has stopped posting
  status entirely. `NetworkUnavailable=False (CiliumIsUp)` is stale, left over from when it was
  last healthy.

This is consistent with #10: the running machine configs predate this repo's patches by several
Talos releases, so it is unsurprising that a node is not on the address the repo assigns it.

**Consequences:**

- `topf apply` targets nodes by the `ip` in `topf.yaml`. For chocolate that address does not
  currently answer, so it will fail against this node regardless of anything else.
- The address in the Secret is therefore also what a future gatus node check would probe. If the
  node is brought back on DHCP rather than its static address, that check would report a false
  failure. (Moot today — `nodes-configmap.yaml` is still not wired into the gatus
  `kustomization.yaml`; see #1.)

**Next steps:** get the node physically back up first, then confirm which address it comes up on.
If it lands on DHCP again, its static config genuinely never applied and `topf apply` against
that one node — once reachable — is the fix. Do not treat the repo's address as wrong and edit it
to match the DHCP lease; the static address is the intent.

**Answered 2026-08-15.** The node is back `Ready` and came up on the **DHCP address again**, well
outside the contiguous static block the repo assigns. That settles it: chocolate's static network
config has never taken effect, exactly as suspected. `topf apply` against this one node is the
fix, and the repo's address stays as-is.

> **Do not stage the `topf apply` here, though.** Chocolate now hosts `postgres-3`, the primary of
> the `database/postgres` cluster recovered on 2026-08-15 (see #14) — and for a period it was the
> *only* copy of that data. Rebuild the other replicas first, or stage on a worker holding no
> stateful workload. `topf apply` also migrates networking to multi-doc config in one shot (#12),
> which is precisely the change most likely to strand a node whose static config has never
> applied.

## 14. `basement-dell-sff` is dead; etcd is permanently at 2-of-3 — High

Confirmed 2026-08-15. The node will not boot and its drive reports unrecoverable sectors. It is
**not coming back without a reinstall on new hardware/disk**, so this is a permanent topology
change rather than an outage to wait out.

- It is one of **three control-plane nodes**. etcd therefore has three voting members with only
  two reachable: quorum holds, but **fault tolerance is zero** — a single further control-plane
  failure takes the API server down. Removing the dead member does not help; a two-member cluster
  still needs both.
- `openebs-hostpath` is node-local, so its disk took four PVCs with it. Three were CNPG replicas
  and were rebuilt from healthy primaries (`default/home-assistant-db-2`, `default/immich-database-1`,
  and `database/postgres-1`). The fourth, `ai/open-webui-data`, had no replica and no backup, so
  open-webui was removed from the repo entirely rather than restored (2026-08-16); Flux prunes its
  HelmRelease, ExternalSecret and PVC. The `ai` namespace stays for future work.
- **`database/postgres` was a full outage** (0/3 ready) because `postgres-1` — the primary — lived
  on this disk. Recovery is recorded below; the `authentik` database survived intact at 136 MB.

**Consequences for the topf work:**

- `topf.yaml` carries this node as one of its three `control-plane` entries. That entry is still
  correct as *intent*, but no `topf apply` can reach the node until it is rebuilt.
- The rebuild is an **opportunity, not just a cost**: a fresh install writes the declared
  schematic and Talos version directly, so it sidesteps both the v1.9.5-era drift (#10) and the
  risky in-place multi-doc networking migration (#12) for this node. It is the cleanest possible
  first application of the new configuration — a node that is being reinstalled anyway cannot be
  stranded by the migration.
- Restoring real fault tolerance means either reinstalling this node as control-plane or promoting
  an existing worker. That is a topology decision the owner has not yet made, and it should be
  made **before** the reinstall, since it determines the node's role in `topf.yaml`.

### Fallout: `basement-rpi4-peach` had stale nameservers — resolved 2026-08-16

Peach rejoined the cluster but nothing scheduled there could pull an image:

```
Failed to pull image "...": dial tcp: lookup ghcr.io on 127.0.0.53:53: server misbehaving
```

Talos hostDNS was running and answering, but forwarding to a stale upstream — **another instance
of #10**, the live config predating the repo's patches. The network itself was fine: querying the
intended resolver directly from a pod on peach resolved correctly, which is the test that
separates "wrong config" from "unreachable resolver". Peach was also on its *static* address
(unlike chocolate, #13), so only its nameservers had drifted.

- **Fix applied:** a targeted `talosctl patch mc` on `machine.network.nameservers`. Prefer this
  over a full `topf apply`, which would additionally trigger the multi-doc networking migration
  (#12) and write an x86 installer reference onto an arm64 Pi (#9). Nameservers reconcile live,
  so no reboot is needed.
- **Check while `topf.yaml` is decrypted for #9:** confirm its `nameservers` value is the correct
  resolver. That field is encrypted, so it has not been verified — if it holds the same stale
  address, a future `topf apply` re-breaks DNS on *every* node.

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
  reverted to memory. (VM ingestion of its metrics is the open item #1.)
- **Postgres cluster kept**: Authentik now consumes it, so the decommission question is closed.

See `docs/plans/2026-06-14-cnpg-barman-cloud-plugin-migration.md` and the immich restore
handoff for details.
