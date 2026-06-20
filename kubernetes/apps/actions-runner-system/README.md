# actions-runner-system

Self-hosted [GitHub Actions](https://github.com/actions/actions-runner-controller)
runners so this repo's workflows can execute inside the cluster. This namespace uses a
single [`ks.yaml`](./ks.yaml) that wires up both apps below.

| App | Description | Manifest |
| --- | --- | --- |
| [actions-runner-controller](https://github.com/actions/actions-runner-controller) | Controller (`gha-runner-scale-set-controller`) that manages ephemeral self-hosted runners. | [kustomization.yaml](./actions-runner-controller/kustomization.yaml) |
| [runner-scale-set](https://github.com/actions/actions-runner-controller) | The `gha-runner-scale-set` (`home-ops-runner`) that spins up runner pods to execute workflows. | [kustomization.yaml](./runner-scale-set/kustomization.yaml) |
