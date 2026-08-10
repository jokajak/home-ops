# Talos

Machine configuration for the Talos cluster, managed with
[topf](https://postfinance.github.io/topf/).

This replaced talhelper in the [topf migration][plan]. There is no
`talconfig.yaml` and no `clusterconfig/` directory any more, and no second
Talos tree under `kubernetes/`.

## Layout

```text
talos/
├── topf.yaml            # SOPS-encrypted: cluster settings + node inventory
├── secrets.yaml         # SOPS-encrypted: cluster PKI (the talhelper bundle, renamed)
├── schematic.yaml.tpl   # image factory schematic for the x86 nodes
├── schematic-rpi.yaml   # image factory schematic for the Raspberry Pi nodes
├── all/                 # patches applied to every node
├── control-plane/       # patches applied to control-plane nodes only
├── cilium/              # bootstrap-time Cilium install (task talos:apply-extras)
└── kubelet-csr-approver/
```

Patches are applied in order: `all/`, then the node's role directory, then
`node/<host>/` if it exists. Within a directory, files apply in filename order —
hence the numeric prefixes.

## Where the addresses live

Every address — node IPs, VIP, gateway, nameservers, VLAN addresses, the API
endpoint — lives in `topf.yaml` and nowhere else. That file is SOPS-encrypted
with [partial encryption][sops-partial]: the *values* are ciphered while
hostnames, roles, versions and structure stay readable, so a diff is still
reviewable.

Patches reach those values through Go templates (`.Data.*`, `.Node.Data.*`),
which is why most files here are `.yaml.tpl`.

> **`.tpl` files are not decrypted.** topf runs non-template files through a
> SOPS decrypt pipeline but skips templates, so a secret must never be written
> into a `.tpl` file directly — reference it from `topf.yaml` instead.

## Requirements

`topf` needs the **`sops` binary on `PATH`**. It shells out to `sops filestatus`
to decide whether a file is encrypted, and if `sops` is missing it silently
treats `topf.yaml` as plaintext and fails with confusing YAML parse errors. The
`task talos:*` recipes check for it up front.

Install topf with `brew install postfinance/tap/topf`, or
`task workstation:generic-linux`. There is no AUR package; on Arch use
`go install github.com/postfinance/topf/cmd/topf@latest`.

## Common tasks

```sh
task talos:nodes           # inventory and current state
task talos:render          # render machine configs locally, change nothing
task talos:diff            # what an apply would change
task talos:apply           # apply to every node (node=<regex> for one)
task talos:schematic-ids   # resolved image factory schematic IDs
```

`task talos:render` and `task talos:diff` touch no node and are the right way to
check a change before applying it.

## Image factory schematics

Schematic IDs are computed **locally** from the schematic files — no factory
round-trip:

| Schematic | ID | Nodes |
| --- | --- | --- |
| `schematic.yaml.tpl` | `9e8cc193…` | all x86 nodes |
| `schematic-rpi.yaml` | `ee21ef4a…` | `basement-rpi4-chocolate` |

Both resolve at the image factory today, so neither needs
`--submit-to-factory`. `ee21ef4a…` is the stock upstream [`rpi_generic`
schematic][rpi]; the x86 one adds `net.ifnames=0` and `siderolabs/intel-ucode`.

Editing a schematic file changes the node's installer image and therefore needs
a Talos upgrade, not just an apply. A brand-new schematic the factory has never
seen must be registered once with `--submit-to-factory`.

> **None of these are what the fleet is running.** Every node currently reports
> schematic `376567988…`, which is `customization: {}` — no system extensions at
> all. The declared schematics take effect at the next upgrade, which will
> therefore not be a no-op. See [ISSUES #11](../docs/ISSUES.md).

The Raspberry Pi schematic omits the `net.ifnames=0` kernel argument. Interface
selection still works because `all/20-link-alias.yaml.tpl` matches on bus path
rather than interface name.

## Reconciled against the live cluster — 2026-08-10

The rendered configs were diffed per node against `talosctl get machineconfig
v1alpha1`. Install disk, kubelet arguments/mounts/`nodeIP`, the containerd
`files` entry, time servers, sysctls, KubePrism, hostDNS, Talos API access, etcd
arguments, cluster networking and the `admissionControl` deletion all match
byte-for-byte. What does **not** match is recorded in
[ISSUES #9–#12](../docs/ISSUES.md); the short version:

- Live `install.image` is pinned to `v1.9.5` while the nodes run v1.13.4 — the
  running config predates this repo's patches by several Talos releases.
- `basement-rpi4-peach` is aimed at an x86 schematic with no Pi overlay
  (**#9** — fixing it needs the age key).
- `topf apply` moves networking out of `machine.network.interfaces` into
  separate `LinkConfig`/`VLANConfig`/`Layer2VIPConfig` documents. Stage it on one
  worker (**#12**).

[rpi]: https://www.talos.dev/v1.8/talos-guides/install/single-board-computers/rpi_generic/

## Versions are declarative-only

`talosVersion` and `kubernetesVersion` in `topf.yaml` describe what `topf apply`
would write. Actual upgrades are driven in-cluster by
[tuppr](../kubernetes/apps/system-upgrade/tuppr/), so these fields can drift
behind the running fleet. Don't read them as the source of truth.

As of 2026-08-10 they are **not** stale: `talosVersion: v1.13.4` matches all
seven nodes, and `kubernetesVersion: v1.35.6` matches five of seven —
`basement-dell-sff` and `foyer-dell-3040` still trail at v1.34.1. tuppr targets
v1.13.8/v1.36.3 but has not reached them: its `TalosUpgrade` sits in
`MaintenanceWindow` and its `KubernetesUpgrade` is stuck in `HealthChecking`,
because two nodes are `NotReady`. Applying this branch is therefore not a
Kubernetes downgrade.

[plan]: ../docs/plans/2026-08-10-talos-consolidation-and-topf.md
[sops-partial]: ../.sops.yaml
