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
├── schematic.yaml.tpl   # image factory schematic for the x86 nodes, by role
├── schematic-rpi.yaml   # image factory schematic for the Raspberry Pi node
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
round-trip — and were verified to match the IDs already running on the fleet:

| Schematic | ID | Nodes |
| --- | --- | --- |
| `schematic.yaml.tpl` (control-plane) | `0bf2de4e…` | x86 control-plane |
| `schematic.yaml.tpl` (worker) | `1841b08a…` | x86 workers |
| `schematic-rpi.yaml` | `11452416…` | `basement-rpi4-chocolate` |

Editing a schematic file changes the node's installer image and therefore needs
a Talos upgrade, not just an apply. A brand-new schematic the factory has never
seen must be registered once with `--submit-to-factory`.

The Raspberry Pi schematic differs from the x86 worker one in two pre-existing
ways: it includes `siderolabs/nut-client`, and it omits the
`net.ifnames=0` kernel argument. Interface selection still works because
`all/20-link-alias.yaml.tpl` matches on bus path rather than interface name.

## Versions are declarative-only

`talosVersion` and `kubernetesVersion` in `topf.yaml` describe what `topf apply`
would write. Actual upgrades are driven in-cluster by
[tuppr](../kubernetes/apps/system-upgrade/tuppr/), so these fields can drift
behind the running fleet. Don't read them as the source of truth.

[plan]: ../docs/plans/2026-08-10-talos-consolidation-and-topf.md
[sops-partial]: ../.sops.yaml
