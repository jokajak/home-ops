# system

Cluster-wide utilities and operational add-ons.

| App | Description | Manifest |
| --- | --- | --- |
| [descheduler](https://github.com/kubernetes-sigs/descheduler) | Evicts pods to force the scheduler to rebalance the cluster. | [ks.yaml](./descheduler/ks.yaml) |
| [generic-device-plugin](https://github.com/squat/generic-device-plugin) | Exposes host devices (e.g. USB) to pods as schedulable resources. | [ks.yaml](./generic-device-plugin/ks.yaml) |
| priority-classes | Two `PriorityClass` objects ranking household services so the scheduler can preempt: `household-critical` (Home Assistant and its dependencies) above `household-important` (Immich) above everything else at the default 0. | [ks.yaml](./priority-classes/ks.yaml) |
| [reloader](https://github.com/stakater/Reloader) | Restarts workloads when their `ConfigMap`/`Secret` changes. | [ks.yaml](./reloader/ks.yaml) |
| [spegel](https://github.com/spegel-org/spegel) | Stateless, cluster-local OCI registry mirror for peer-to-peer image pulls. | [ks.yaml](./spegel/ks.yaml) |
