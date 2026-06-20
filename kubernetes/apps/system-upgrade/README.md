# system-upgrade

Automated, Git-driven node OS upgrades.

| App | Description | Manifest |
| --- | --- | --- |
| [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller) | Orchestrates node upgrades by reconciling `Plan` resources. | [ks.yaml](./system-upgrade-controller/ks.yaml) |
| [talos](https://www.talos.dev/) | The `Plan` that upgrades Talos Linux on the nodes via the controller. | [ks.yaml](./talos/ks.yaml) |
