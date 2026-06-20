# network

Low-level cluster networking: the CNI and the plumbing for additional pod interfaces.
(Application-facing ingress/DNS lives in [`networking`](../networking/README.md).)

| App | Description | Manifest |
| --- | --- | --- |
| [cilium](https://cilium.io/) | eBPF-based CNI providing pod networking, load balancing, and network policy. | [ks.yaml](./cilium/ks.yaml) |
| [multus](https://github.com/k8snetworkplumbingwg/multus-cni) | CNI meta-plugin that attaches multiple network interfaces to pods. | [ks.yaml](./multus/ks.yaml) |
| [node-network-operator](https://github.com/solidDoWant/node-network-operator) | Declaratively manages host network links on nodes. | [ks.yaml](./node-network-operator/ks.yaml) |
| [whereabouts](https://github.com/k8snetworkplumbingwg/whereabouts) | Cluster-wide IPAM for the secondary (Multus) networks. | [ks.yaml](./whereabouts/ks.yaml) |
