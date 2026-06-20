# flux-system

Cluster-side extensions to the Flux GitOps engine. The core Flux components live under
[`kubernetes/flux`](../../flux); this namespace adds the pieces that run as cluster apps.

| App | Description | Manifest |
| --- | --- | --- |
| [webhooks](https://fluxcd.io/flux/guides/webhook-receivers/) | GitHub webhook `Receiver` so pushes trigger immediate Flux reconciliation instead of waiting for the poll interval. | [ks.yaml](./webhooks/ks.yaml) |
