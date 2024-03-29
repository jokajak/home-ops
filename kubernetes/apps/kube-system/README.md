# kube-system

This directory contains the applications running in the kube-system namespace.

## coredns

[coredns](https://coredns.io/) provides dns for the cluster. It's included as an app so that the configuration can be
modified

* [coredns](./coredns/ks.yaml)

## descheduler

[descheduler](https://github.com/kubernetes-sigs/descheduler) will evict pods to force the cluster to rebalance.

* [descheduler](./descheduler/ks.yaml)

## node-feature-discovery

[node-feature-discovery](https://github.com/kubernetes-sigs/node-feature-discovery) provides annotations for nodes to
support node selection for deployments. It is mostly used for tagging nodes with custom devices attached like a
HomeAssistant SkyConnect

* [node-feature-discover](./node-feature-discovery/ks.yaml)
