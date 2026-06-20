# kube-system

Core cluster components that run in the `kube-system` namespace. They are packaged as
apps here so their configuration can be managed in Git.

| App | Description | Manifest |
| --- | --- | --- |
| [coredns](https://coredns.io/) | In-cluster DNS; managed as an app so the config can be customized. | [ks.yaml](./coredns/ks.yaml) |
| [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs) | CSI driver that mounts NFS shares (the NAS) as PersistentVolumes. | [ks.yaml](./csi-driver-nfs/ks.yaml) |
| [kubelet-csr-approver](https://github.com/postfinance/kubelet-csr-approver) | Automatically approves kubelet serving-certificate CSRs. | [ks.yaml](./kubelet-csr-approver/ks.yaml) |
| [metrics-server](https://github.com/kubernetes-sigs/metrics-server) | Resource metrics API for `kubectl top` and the Horizontal Pod Autoscaler. | [ks.yaml](./metrics-server/ks.yaml) |
| [node-feature-discovery](https://github.com/kubernetes-sigs/node-feature-discovery) | Labels nodes with hardware features for scheduling (e.g. nodes with a Home Assistant SkyConnect). | [ks.yaml](./node-feature-discovery/ks.yaml) |
