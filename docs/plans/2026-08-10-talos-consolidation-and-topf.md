# Talos: consolidate the two trees by migrating to topf

> Status: **PLANNED — not executed** · 2026-08-10 · Owner: Josh · Author: Claude
>
> Resolves [`ISSUES.md`](../ISSUES.md) **#6** (two divergent Talos trees, root copy in plaintext)
> and unblocks **#8** (node addresses at `HEAD`), which is itself the prerequisite for
> [the history purge](./2026-08-04-history-purge-plaintext-topology.md).
>
> Nothing here has been applied. No Talos file has been modified.

## Context

Two Talos trees exist and the tooling disagrees about which is real: `.taskfiles/Talos` operates
on repo-root `talos/` via `TALOS_DIR`, while `.envrc` points `TALOSCONFIG` at
`kubernetes/talos/clusterconfig/`. Deciding a winner looked like the task. It isn't.

### Provenance — settled, so it need not be re-litigated

| Tree | Origin | Evidence |
| --- | --- | --- |
| `kubernetes/talos/` | **Template-derived.** The layout upstream used when this repo was forked | This repo's own history contains `bootstrap/templates/kubernetes/talos/talconfig.yaml.j2`, which also generated the `cilium/` and `kubelet-csr-approver/` subdirs still present |
| `talos/` | **Hand-written**, 2026-06-17, `ceec330 chore(talos): align talconfig to running fleet` | First appearance of the path in this repo; no template ever rendered there |

The repo was created **2024-02-11**. Upstream moved Talos out of `kubernetes/` on
**2024-02-15** — four days later. That accident of timing is the whole story: this fork froze on
the pre-move layout, then a hand-made tree appeared at the post-move location two years on,
without ever passing through the intermediate one.

Upstream's rendered location, from its own history (3370 commits):

| Location | Period | Tool |
| --- | --- | --- |
| `kubernetes/talos/` | → 2024-02-15 | talhelper |
| `kubernetes/bootstrap/talos/` | 2024-02-15 → 2025-02-19 | talhelper |
| `talos/` | 2025-02-19 → today | talhelper, then **topf** from 2026-07-21 |

This repo never had `kubernetes/bootstrap/` at all — which is why `task flux:bootstrap` applied
`{{.KUBERNETES_DIR}}/bootstrap` against a directory that never existed here. It was inherited
dead from the template and could never have worked. (Fixed in `a0f42f9`.)

### Why this is a migration, not a choice

[topf](https://postfinance.github.io/topf/) reads **all** non-template files — `topf.yaml`
included — through a SOPS-decrypt pipeline:

> TOPF reads all non-template files (including `topf.yaml` itself) through a two-stage pipeline:
> **SOPS decryption** — if a file is SOPS-encrypted, it is decrypted automatically.
>
> — `docs/configuration-model.md`, "Secret Resolution"

So the entire node inventory — addresses, MACs, VIP, endpoint — can be **encrypted at rest** and
topf decrypts transparently on use. That is strictly better than anything talhelper offers, where
`talconfig.yaml` is either plaintext (today's problem) or encrypted-and-opaque (the
`kubernetes/talos/` copy, which is why it went stale).

Which means: don't pick a winner between the trees. **Build `talos/` as a topf tree and delete
`kubernetes/talos/`.** Consolidation and the topf migration are one move, and the migration is
what actually fixes the plaintext problem.

> **Corollary, easy to get wrong:** `.tpl` files **skip** the decrypt pipeline. No secret may live
> in a template. Templates reference `.Data.<key>` / `.Node.Data.<key>`, resolved from the already
> decrypted `topf.yaml`.

### The risk that usually kills a Talos tool swap is retired

Regenerating a Talos secrets bundle means new cluster PKI, which means rebuilding the cluster.
topf's own migration guide closes this:

> Move your existing Talos secrets bundle `talsecret.sops.yaml` to `secrets.yaml`. It is
> compatible with TOPF. Simply keep it in the same directory.
>
> — `docs/migration-from-talhelper.md`, step 5

Confirmed by inspection: `kubernetes/talos/talsecret.sops.yaml` is a stock Talos `SecretsBundle`
(`cluster.id`, `cluster.secret`, `secrets.bootstraptoken`, `secrets.secretboxencryptionsecret`,
`trustdinfo.token`, `certs.{etcd,k8s,k8saggregator,k8sserviceaccount,os}`) — the same structure
topf loads via `providers.LoadSecretsBundle`. **The bundle is renamed, never regenerated.**

## Migration inventory

Measured from `talos/talconfig.yaml` (403 lines):

| Item | Count | Becomes |
| --- | --- | --- |
| Nodes | 7 | `topf.yaml` `nodes:` — `host` / `ip` / `role` / `schematicId` / `data` |
| `patches:` blocks | 2 (controlPlane, worker) | files under `all/`, `control-plane/`, `worker/` |
| RFC-6902 patches (`op:`) | 1 | strategic merge with `$patch: delete` |
| Distinct schematics | 2 (rpi4 overlay, x86) | per-node `schematicId` |
| Secrets bundle | 1 | renamed to `secrets.yaml`, contents untouched |

Per-node network detail — address, VIP, routes, VLAN, MAC, install disk — moves out of the node
list and into patch files. In topf the node list is an inventory; the machine config lives in
patches.

Target layout, mirroring upstream:

```text
talos/
├── topf.yaml              # SOPS-encrypted: cluster + node inventory
├── secrets.yaml           # SOPS-encrypted: the existing bundle, renamed
├── all/                   # every node
├── control-plane/         # controllers only
├── cilium/                # salvaged, still used by apply-extras
└── kubelet-csr-approver/  # salvaged
```

## Phases

Each is independently shippable. Phases 1–3 touch no running node.

### 1. Stand up the topf tree beside the old one — and prove it renders identically

Write `talos/topf.yaml` plus the `all/` and `control-plane/` patches. Then:

```sh
talhelper genconfig                 # existing tool, existing output
topf render --output ./rendered     # new tool
# diff the two sets of machine configs, per node
```

**This is the crux of the plan.** If the rendered machine configs match, the migration is
provably behaviour-preserving before a single node is touched. Any diff is a translation bug
found at zero cost. Nothing is applied in this phase — resolve every diff, or an intentional and
documented one, before proceeding.

### 2. Move the secrets bundle and salvage what is still used

- `kubernetes/talos/talsecret.sops.yaml` → `talos/secrets.yaml` (git mv; contents unchanged).
- `kubernetes/talos/{cilium,kubelet-csr-approver}/` → `talos/` — `task talos:apply-extras`
  already runs from `TALOS_DIR` and expects them there.

### 3. Encrypt

Add `.sops.yaml` rules for `talos/topf.yaml` and `talos/secrets.yaml`, then `task sops:encrypt`.

> The age private key is not available to the agent — **the owner runs the encrypt step.** Confirm
> `ENC[AES256_GCM` appears in both files before committing. Sequence this so the plaintext
> `topf.yaml` is never committed unencrypted; if that is awkward, write it outside the repo and
> `git add` only after encrypting.

### 4. Cut the tooling over

- Replace the talhelper recipes in `.taskfiles/Talos/Taskfile.yaml` with topf equivalents:
  `apply`, `apply-node`, `diff`, `nodes`, `render`, `upgrade`, `upgrade-node`, `upgrade-k8s`.
- Fix `TALOSCONFIG` in `.envrc` — it points at `kubernetes/talos/clusterconfig/`, a tree that is
  being deleted. Upstream uses `talos/talosconfig`.
- Add `topf` to `.taskfiles/Workstation/{Brewfile,Archfile}`; drop `talhelper`.
- Note `TALHELPER_SECRET_FILE` is already wrong today — it names `talos/talhelper.sops.yaml`,
  a file that has never existed in this repo. It disappears with the cutover rather than needing
  a fix.

### 5. Delete `kubernetes/talos/`

The stale encrypted `talconfig.yaml`, `talconfig.yaml.norpi`, `apps/helmfile.yaml`, `README.md`
(fold its factory-schematic notes into `talos/README.md`), the seven empty
`clusterconfig.YYYYMMDD/` dirs, and `talosconfig.20240317.1258` — the `os:admin` cert that expired
2025-03-17.

Also drop the `kubernetes/talos/*` entries from `.gitignore` and the
`kubernetes/talos/talconfig.yaml filter=git-sops` line from `.gitattributes`.

> Deletion clears `HEAD`, not history. See
> [the purge plan](./2026-08-04-history-purge-plaintext-topology.md).

### 6. Fix ISSUES #8 — the last plaintext addresses at `HEAD`

With `topf.yaml` encrypted, the only node addresses left on the default branch are
`kubernetes/apps/observability/gatus/app/nodes-configmap.yaml` (7, a live manifest) and the two
2026-02-08 design docs (7 each). Move the configmap onto a `${SECRET_*}` substitution from
`cluster-secrets` — populating the variable *before* pushing the manifest, or the Kustomization
will not reconcile — and redact the docs to `<node-N>` placeholders.

This closes #8 and is the prerequisite for any history purge.

## Risks

**`topf apply` talks to live nodes.** Mitigated by phase 1 being render-and-diff only, and by
topf's built-in diff-and-confirm on apply. Use `topf apply --dry-run` and `apply-node` to roll one
node at a time; do controllers last.

**Version fields become declarative-only.** tuppr owns Talos and Kubernetes upgrades in-cluster
(`kubernetes/apps/system-upgrade/tuppr/`), so `topf.yaml`'s `talosVersion` / `kubernetesVersion`
will drift behind the fleet exactly as `talconfig.yaml` does today (v1.13.4 vs the fleet's
v1.13.8). Not a regression — but don't mistake those fields for the source of truth.

**Encrypting `topf.yaml` puts it out of Renovate's reach.** Costs nothing: Renovate's
`managerFilePatterns` only ever covered `kubernetes/`, so root `talos/` was never scanned. That is
precisely why the drift above went unnoticed.

**Reversibility.** Because the secrets bundle is untouched and phase 1 proves render equivalence,
backing out means restoring `talconfig.yaml` and re-running `talhelper genconfig`. Keep the
talhelper tree in git until phase 5, and phase 5 only after a successful `topf apply`.

## Verification

- [ ] Phase 1 render diff resolved — `topf render` output matches `talhelper genconfig` per node
- [ ] `topf nodes` reaches all 7 nodes
- [ ] `secrets.yaml` is the same bundle — cluster PKI unchanged, `talosctl -n <node> version` works
- [ ] Both `topf.yaml` and `secrets.yaml` contain `ENC[AES256_GCM` before commit
- [ ] `task k8s:kubeconform`, `yamllint .`, `pre-commit run --all-files` clean
- [ ] `git grep` finds no node address, MAC, or internal hostname anywhere at `HEAD`
- [ ] Cluster healthy after apply: `talosctl health`, `kubectl get nodes`, `flux get ks -A`
- [ ] ISSUES #6 and #8 closed; the purge plan's step 1 marked satisfied
