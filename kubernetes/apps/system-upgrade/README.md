# system-upgrade

Automated, Git-driven Talos Linux and Kubernetes upgrades.

| App | Description | Manifest |
| --- | --- | --- |
| [tuppr](https://github.com/home-operations/tuppr) | Controller that reconciles `TalosUpgrade` and `KubernetesUpgrade` resources to roll node OS and Kubernetes versions. | [ks.yaml](./tuppr/ks.yaml) |

The desired versions live in the `TalosUpgrade`/`KubernetesUpgrade` resources under
[`tuppr/plans/`](./tuppr/plans/) and are bumped by Renovate. tuppr version-swaps each node's
running install image, so per-node Talos schematics are preserved automatically, and it
serializes Talos vs. Kubernetes upgrades itself.

Requires `machine.features.kubernetesTalosAPIAccess` enabled for this namespace in
`talos/talconfig.yaml`.
