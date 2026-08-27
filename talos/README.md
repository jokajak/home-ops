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

> **Declared, not yet installed.** `install.image` is only read at install or
> upgrade time, and a Talos upgrade does not rewrite it, so changing a schematic
> here does nothing until a node is next upgraded or reinstalled. As of
> 2026-08-17 all six nodes still run the empty schematic `376567988…` while
> declaring `9e8cc193…` / `ee21ef4a…`; `intel-ucode` and the Pi overlay land at
> the next upgrade. This is also why the fleet ran the empty schematic for so
> long — each upgrade carried forward whatever was already installed.

The Raspberry Pi schematic omits the `net.ifnames=0` kernel argument. Interface
selection still works because `all/20-link-alias.yaml.tpl` matches on bus path
rather than interface name — and that glob is per-node (`.Node.Data.busPath`),
so it must match the real hardware. A Pi 4's onboard NIC is `fd580000.ethernet`;
an x86 NIC matches `0*`. **Getting this wrong leaves the node with no network
after apply**, because the alias binds nothing and `LinkConfig` has no interface
to address.

[rpi]: https://www.talos.dev/v1.8/talos-guides/install/single-board-computers/rpi_generic/

## Applied to the whole fleet — 2026-08-16

All six nodes now run this configuration. The apply is a **reboot** wherever
`install.*` changes, and it moves networking out of `machine.network.interfaces`
into separate `HostnameConfig`/`LinkAliasConfig`/`LinkConfig`/`VLANConfig`
documents. Verified afterwards on each node: static address held, `ethSel0` and
`ethSel0.50` present, default route via the gateway.

Two things worth knowing before the next apply:

- **`Ready` is not sufficient verification.** Cilium can take several minutes to
  reinstall `auto-direct-node-routes` after a reboot, during which the node looks
  healthy but its pods are unreachable from the rest of the cluster. Check that
  each node has one peer route per other node:
  `kubectl exec -n kube-system <cilium-pod> -c cilium-agent -- ip route | grep -c '^10.42..*via'`
- **The alias rename breaks anything referencing the old interface name.** The
  multus `iot-vlan` NetworkAttachmentDefinition had `master: eth0.50`, which no
  longer exists; it is now `ethSel0.50`. Pods attaching to that NAD fail sandbox
  creation until it matches.

## Versions are declarative-only

`talosVersion` and `kubernetesVersion` in `topf.yaml` describe what `topf apply`
would write. Actual upgrades are driven in-cluster by
[tuppr](../kubernetes/apps/system-upgrade/tuppr/), so these fields can drift
behind the running fleet. Don't read them as the source of truth.

As of 2026-08-16 they match: `talosVersion: v1.13.4` and
`kubernetesVersion: v1.35.6` on all six nodes. Applying `topf` was in fact what
finally moved `foyer-dell-3040` off v1.34.1 — tuppr's `KubernetesUpgrade` had
been wedged for 49 days, so the kubelet image came from `topf.yaml` instead.

The SOPS creation rule for `topf.yaml` uses `mac_only_encrypted: true`. This
keeps the encrypted addresses authenticated while allowing Renovate to update
the intentionally plaintext version fields without breaking the MAC. No
external value resolver is required.

[plan]: ../docs/plans/2026-08-10-talos-consolidation-and-topf.md
[sops-partial]: ../.sops.yaml
