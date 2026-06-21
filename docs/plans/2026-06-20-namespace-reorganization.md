# Kubernetes namespace reorganization

> Status: **IN PROGRESS** — Phase 0 done; Phase 1 staged in git, awaiting owner reconcile ·
> 2026-06-20 · Owner: Josh · Author: Luma (Claude)
>
> Multi-session effort. This doc is the source of truth for progress — update the
> phase checkboxes and the **Session Log** at the bottom as work proceeds. Each phase
> is meant to be one (or a few) PRs; pick up where the last session left off.

## Goal

Make the `kubernetes/apps/` namespace layout self-explanatory and reduce the `default`
grab-bag, **without ever orphaning persistent data**. Two independent tracks:

1. **Naming:** kill the `network` vs `networking` collision (different layers, near-identical names).
2. **Decomposition:** evict apps out of the 10-app `default` namespace into themed namespaces.

A third item is doc-only and already done in Phase 0: clarify that the `database`
namespace holds shared DB *infrastructure*, while per-app Postgres clusters intentionally
live next to their app.

## The load-bearing constraint (read before touching anything)

A namespace change for any app that owns a **PVC, PV, CNPG `Cluster`, or `ExternalSecret`
is a data migration, not a refactor.** Those objects are namespace-scoped. Moving an app's
manifests to a new namespace makes Flux **create them empty in the new namespace and prune
the old ones** — which deletes the old PVC binding and (for CNPG) the database. Rules:

- **Confirm `persistentVolumeReclaimPolicy: Retain` on every PV before moving its app.**
  If it's `Delete`, the PV (and NAS/local data) is destroyed when the old PVC is pruned.
- **CNPG clusters move by dump/restore, not by relocating the manifest.** Re-creating a
  `Cluster` in a new namespace is a brand-new empty cluster. Use the
  `pg_dumpall`/streamed-`psql` restore path proven in the 2026-06 Immich recovery.
- **SOPS secrets encode their target namespace** in the encrypted payload's metadata; a
  namespace move requires re-encrypting (`task sops:encrypt`) — it is not a `sed`.
- One app per PR. Rehearse rollback (re-point manifests at the old namespace) before merge.

> Why this matters here: the 2026-06 Immich outage was a CNPG cluster reset that DROPped the
> `immich` database. A careless namespace move is the same failure mode, ×N apps.

## Current state (verified 2026-06-20)

### Naming collision: two real runtime namespaces, not a folder illusion

Both are reconciled namespaces with live resources — renaming either is a migration:

| Folder | Real namespace? | What runs there | Move cost |
| --- | --- | --- | --- |
| `network` | **Yes** (`network/namespace.yaml`, prune disabled) | multus, whereabouts, node-network-operator (via `targetNamespace: network`). **cilium targets `kube-system`.** | CNI/IPAM plumbing flap; whereabouts IPAM reservations live in `kube-system` (cluster-scoped CRs), so low *data* risk but real *availability* risk |
| `networking` | **Yes** | nginx (internal/external), external-dns, k8s-gateway, echo-server | Ingress flap + LB IP churn; **SOPS secret + HelmRepositories + cert pinned to `namespace: networking`** must be re-encrypted/re-pinned |

So the council's "rename is just a folder/label change" was **wrong** — confirmed by reading
the manifests. Renaming is deferred into a gated phase below, not done as a quick fix.

### `default` is the stateful tier (10 apps)

| App | State footprint | Eviction risk |
| --- | --- | --- |
| home-assistant-matter-hub | `emptyDir` only | **None** — move freely (canary) |
| calibre | config PVC | Low (PV rebind) |
| wallos | config PVC | Low |
| mealie | config PVC + NFS | Low/Med |
| jellyfin | config PVC + media on NFS | Med |
| esphome | config PVC + NFS | Med |
| unifi | controller config PVC | Med (controller DB) |
| zwave-js-ui | config PVC + **hostPath USB Z-Wave stick** (`CharDevice`) | Med — **node-pinned**; new ns must keep the node affinity + device |
| home-assistant | **CNPG `Cluster`** + PVC + NFS | **High** — dump/restore |
| immich | **CNPG `Cluster`** + PVC + NFS (photos) | **High** — dump/restore; see 2026-06 incident |

### `database` namespace is correctly scoped, just under-documented

Holds shared infra — CNPG operator, the Barman Cloud plugin, dragonfly, and a shared
`postgres` cluster. Per-app Postgres (`immich-database`, home-assistant) lives **with the
app on purpose**: it keeps each app's data blast-radius local and avoids coupling unrelated
databases. **Do not centralize per-app CNPG into `database`.** (Phase 0 documents this.)

## Target state

- No two namespaces differ only by a trailing `-ing`. Proposed: keep `networking` (the
  app-facing one, heavily referenced) and rename `network` → **`network-system`** — it has
  fewer external references, and the `-system` suffix matches the other infra namespaces
  (`kube-system`, `openebs-system`, `external-secrets`, `actions-runner-system`).
- `default` holds at most a couple of genuinely-uncategorized apps. Themed namespaces:
  - **`home-automation`**: home-assistant, home-assistant-matter-hub, esphome, zwave-js-ui
  - **`media`**: immich, jellyfin, calibre
  - **`productivity`** (or keep in `default`): mealie, wallos
  - **`unifi`** → its own or `home-automation` (it manages the home network gear)
- `database` README clarifies the shared-infra-vs-per-app split (done in Phase 0).

## Phases

### Phase 0 — Documentation clarifications (zero-risk) — ✅ DONE 2026-06-20

- [x] `database/README.md`: shared infra vs per-app DBs note
- [x] `default/README.md`: flag the two in-namespace CNPG clusters + stateful footprint
- [x] `network/README.md` + `networking/README.md`: note both are real runtime namespaces
      and link to this plan for the rename

### Phase 1 — `network` → `network-system` rename (gated migration) — staged in git, awaiting reconcile

> **Discovered coupling (bigger than first scoped):** the rename is not confined to the
> `network` folder. Multus `NetworkAttachmentDefinition`s are namespace-scoped, and **five
> workloads in three other namespaces reference them by the `network` namespace** — so they
> were changed in the same commit:
> - `vpn/gateway`, `vpn/dns`, `downloads/qbittorrent` — `k8s.v1.cni.cncf.io/networks: network/<nad>@…`
> - `default/home-assistant`, `default/home-assistant-matter-hub` — `"namespace": "network"` (iot-vlan)
>
> Also inside the folder: every Flux `path:` (`./kubernetes/apps/network/…`), all four
> `targetNamespace: network`, the `multus/app/rbac.yaml` ServiceAccount subject, the whereabouts
> HR `sourceRef.namespace` (its HelmRepository lands in the target ns via the targetNamespace
> override), and Multus's own `"multusNamespace"` config value. cilium is untouched (targets `kube-system`).

- [x] Pre-flight: `flux-local build` + `kustomize build` confirm renamed paths resolve
- [x] `git mv network → network-system`; namespace object renamed; flip all `targetNamespace`,
      `path:`, rbac subject, whereabouts sourceRef, `multusNamespace`
- [x] Update the 5 cross-namespace NAD references (vpn ×2, downloads ×1, default ×2)
- [x] Update READMEs (`apps/README.md` row, `networking` cross-link, `network-system` title/note)
- [x] Validate: kubeconform 0 invalid/0 errors on all touched kustomizations; grep shows 0 stale refs
- [ ] **Owner: reconcile Flux** (flaps CNI control-plane: multus/whereabouts DaemonSets recreate in
      the new ns; brief window where *new* pods needing a Multus iface may fail — existing pods keep
      their interface). Pick a low-activity window.
- [ ] **Owner: post-reconcile verify** — qbittorrent VPN egress, HA reaches the IoT VLAN, multus
      NADs present in `network-system`, whereabouts IPAM intact (reservations live in `kube-system`).
- [ ] **Owner: manual cleanup** — the old `network` namespace has `prune: disabled`, so Flux will
      NOT delete it; once empty, `kubectl delete namespace network`.
- [ ] Update READMEs (`apps/README.md` table, both network READMEs)

### Phase 2 — Evict stateless/low-state apps from `default`

Order: **home-assistant-matter-hub first (emptyDir canary)**, then calibre, wallos, mealie.

- [ ] Create target namespaces (`home-automation`, `media`, `productivity`) + `namespace.yaml`
- [ ] Per app: confirm PV `Retain`, move manifests, re-encrypt any SOPS, re-pin `namespace:`,
      verify PVC re-binds to the existing PV, then prune old
- [ ] home-assistant-matter-hub (no PV — pure canary to prove the namespace wiring)
- [ ] calibre · wallos · mealie · jellyfin · esphome · unifi

### Phase 3 — Evict the CNPG apps (highest risk, last)

- [ ] **home-assistant**: scale app to 0, `pg_dumpall`, recreate `Cluster` in `home-automation`,
      restore via streamed `psql` (peer auth), verify, then prune old
- [ ] **immich**: same runbook; follow the 2026-06 restore handoff exactly (strip role
      DROP/CREATE lines, stream into primary's unix socket). Photos on NFS PVC are `Retain` —
      confirm before touching. Bump CNPG `serverName` if re-init triggers the WAL-archive guard.

## Rollback

Each phase is one PR. Rollback = revert the PR **and** (for moved stateful apps) re-point the
PVC/Cluster at the original namespace before the old objects are pruned. Never let Flux prune
the old namespace until the new one is verified healthy.

## Session Log

- **2026-06-20** — Plan created. Reviewed all `kubernetes/**/README.md`, convened a 5-member
  council, then verified the council's "zero-risk rename" claim against the manifests and
  **rejected it** (`network`/`networking` are both real runtime namespaces). Executed Phase 0
  doc clarifications. Phases 1–3 not started.
- **2026-06-20** — Phase 1 target name decided: `network` → **`network-system`** (matches the
  other `-system` infra namespaces), not `cni`.
- **2026-06-20** — Phase 1 **staged in git** (not yet reconciled). `git mv` (24 files, history
  preserved) + 5 cross-namespace NAD reference updates + 3 READMEs. Discovered the NAD coupling
  into `vpn`/`downloads`/`default` during pre-flight — wider than the original scope. Validated
  with flux-local build, kustomize build, and kubeconform (0 invalid/0 errors); grep confirms 0
  stale `network` refs.
- **2026-06-20** — **Botched first push, then fixed (with cluster access).** Commit `32c5c98`
  renamed the dirs but an atomic `git add` failure (stale `kubernetes/apps/network` pathspec)
  silently dropped EVERY content edit, so the moved ks.yaml files still pointed at the deleted
  `./network` path. On-cluster this showed as the CNI Kustomizations stuck `path not found`,
  while pods stayed healthy. Local kustomize/kubeconform had passed because they ran against the
  (correct) working tree, never the commit. Fix: commit `02268d8` landed the dropped content;
  `flux reconcile cluster-apps --with-source` then created `network-system` and migrated
  multus/whereabouts/node-network-operator (all `Ready=True`), and moved all 5 NADs.
- **2026-06-20** — Added a guard so this can't recur: `scripts/validate-ks-paths.sh` (portable,
  checks every Flux Kustomization `spec.path` resolves) wired as a pre-commit hook + CI job
  (`4581537`).
- **Still open after Phase 1:** (a) VPN consumers `vpn-gateway`/`vpn-dns`/`qbittorrent` are
  `Ready=False` blocked by a **pre-existing, unrelated** dep — `cluster-apps-external-secrets-bitwarden`
  (bitwarden ESO provider HelmRepository stuck `InProgress`); their running pods are healthy.
  (b) Duplicate multus DaemonSet: old `network/multus` (not pruned by the targetNamespace move)
  + new `network-system/multus`. **Do `kubectl delete ns network` only after** the VPN/HA
  consumers re-roll onto the `network-system` NADs (currently gated by the bitwarden issue).
