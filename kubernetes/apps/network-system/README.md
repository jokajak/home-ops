# network-system

Low-level cluster networking: the CNI and the plumbing for additional pod interfaces.
(Application-facing ingress/DNS lives in [`networking`](../networking/README.md).)

> Renamed from `network` → `network-system` (matches `kube-system`, `openebs-system`, …) to
> end the near-identical `network`/`networking` collision. multus, whereabouts, and
> node-network-operator run **in this namespace**; cilium targets `kube-system`. Pods that
> attach a Multus interface reference the NADs as `network-system/<nad>` (see `vpn`,
> `downloads`, and `default/home-assistant`). See the migration plan in
> [`docs/plans`](../../../docs/plans/2026-06-20-namespace-reorganization.md).

| App | Description | Manifest |
| --- | --- | --- |
| [cilium](https://cilium.io/) | eBPF-based CNI providing pod networking, load balancing, and network policy. | [ks.yaml](./cilium/ks.yaml) |
| [multus](https://github.com/k8snetworkplumbingwg/multus-cni) | CNI meta-plugin that attaches multiple network interfaces to pods. | [ks.yaml](./multus/ks.yaml) |
| [node-network-operator](https://github.com/solidDoWant/node-network-operator) | Declaratively manages host network links on nodes. | [ks.yaml](./node-network-operator/ks.yaml) |
| [whereabouts](https://github.com/k8snetworkplumbingwg/whereabouts) | Cluster-wide IPAM for the secondary (Multus) networks. | [ks.yaml](./whereabouts/ks.yaml) |
