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
| 6 | Talos config exists twice, divergently; root copy is plaintext | talos | Med | Resolved 2026-08-10 |
| 7 | Kubeconform CI breaks if `FLUX_VERSION` is bumped to 2.9.x | tooling | Low | Verify |
| 8 | Node addresses live at `HEAD` in gatus configmap + 2 design docs | security | Med | Resolved 2026-08-10 |
| 9 | `basement-rpi4-peach` aimed at a schematic with no Raspberry Pi overlay | talos | **High** | Open |
| 10 | Live machine configs are Talos v1.9.5-era; repo has not been applied since | talos | **High** | Open |
| 11 | Fleet runs the empty schematic; repo declares extensions never installed | talos | Med | Open |
| 12 | `topf apply` migrates networking to multi-doc config in one shot | talos | Med | Open |

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

**Resolved 2026-08-10.** There is one Talos tree, at `talos/`, managed by `topf`, and the node
inventory is SOPS-encrypted at rest. `kubernetes/talos/` is gone, including the expired
`os:admin` certificate. The secrets bundle was renamed to `talos/secrets.yaml`, never
regenerated, so cluster PKI is untouched.

Equivalence was proven before anything was staged: `talhelper genconfig` and `topf render` were
run against the *same* throwaway secrets bundle and the rendered machine configs diffed per node.
Six of seven are byte-identical after normalising key order; the seventh differs only in the
Raspberry Pi's installer path (`installer/` → `metal-installer/`, the Talos 1.10+ name the other
six already use). Details in
[`plans/2026-08-10-talos-consolidation-and-topf.md`](./plans/2026-08-10-talos-consolidation-and-topf.md).

Two things found along the way that made the migration more urgent than the plan assumed: the
old `talos/talconfig.yaml` **no longer parsed** under talhelper 3.1.16 (`talosImageURL` carrying a
version tag), and its RFC-6902 patch is rejected outright by Talos v1.13 multi-document configs.
The tree that looked merely divergent was in fact unusable with current tooling.

Version drift persists by design — tuppr owns upgrades, so `topf.yaml`'s version fields are
declarative-only. That is documented in `talos/README.md` rather than tracked as a bug.

Provenance is settled: `kubernetes/talos/` is the template-derived tree (this repo forked
2024-02-11, four days before upstream moved Talos out of `kubernetes/`); root `talos/` was
hand-written 2026-06-17 and matches upstream's current location only by coincidence. Note that deleting files removes them from `HEAD`, not from history.

**History:** a full audit of all 1592 commits, plus the procedure to purge, is written up in
[`plans/2026-08-04-history-purge-plaintext-topology.md`](./plans/2026-08-04-history-purge-plaintext-topology.md).
It is **planned, not executed**. Two things it establishes that matter here: the encrypted
`kubernetes/talos/talconfig.yaml` and `talsecret.sops.yaml` were **never** committed in the clear,
and the same node addresses are still live at `HEAD` in three other files — so fixing those is a
prerequisite, not a follow-up.

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

## 8. Node addresses live at `HEAD` in three files — Med

Surfaced by the 2026-08-04 history audit. Real node addresses (7 occurrences each) are on the
default branch of a **public** repository:

| File | Note |
| --- | --- |
| `kubernetes/apps/observability/gatus/app/nodes-configmap.yaml` | Live manifest — gatus monitors kubelet on `:10250` per node |
| `docs/plans/2026-02-08-cilium-gateway-api-migration.md` | Prose only |
| `docs/plans/2026-02-08-distributed-gatus-design.md` | Prose only |

This is the same data as issue #6, and it is **the blocker** on any history purge: rewriting
history while `main` still publishes these values achieves nothing.

**Resolved 2026-08-10.** All three files are clean, and so is the rest of the tree:
`git grep` for the node prefix and the VLAN prefix returns nothing at `HEAD`.

- The gatus configmap now substitutes `${SECRET_NODE_*}` from a new
  `cluster-secrets-user` Secret (`kubernetes/flux/vars/cluster-secrets-user.sops.yaml`).
  `cluster-secrets-user` was already wired into every Kustomization as an *optional*
  `substituteFrom` by `kubernetes/flux/apps.yaml`; the file simply never existed. Creating it
  needed no access to `cluster-secrets.sops.yaml`.
- Both design docs refer to nodes by name and to addresses by variable.
- `talos/talconfig.yaml`, which held the same addresses in the clear, is gone — replaced by the
  SOPS-encrypted `talos/topf.yaml` (issue #6).

> Noticed while doing this: `nodes-configmap.yaml` is **not** listed in the gatus
> `kustomization.yaml` and never has been, so those node checks have never actually run. The
> substitution is correct and will work the moment the file is added to the resources list —
> activating monitoring that has never been on is a separate decision, left to the owner.

Deleting from `HEAD` is not deleting from history; the purge remains planned and unexecuted. See
[the purge plan](./plans/2026-08-04-history-purge-plaintext-topology.md).

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
  $ topf schematic-ids   # expect 0bf2de4e…, 1841b08a…, 11452416…
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
