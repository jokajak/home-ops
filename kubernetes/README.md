# kubernetes

Everything under this directory is reconciled onto the cluster by [Flux](https://fluxcd.io/).
A push to the tracked branch is what changes cluster state — `kubectl apply` is not part
of the workflow.

| Directory | Contents |
| --- | --- |
| [apps](./apps/README.md) | All applications, grouped by namespace. Start here for an overview of what is installed and where. |
| [flux](./flux) | The Flux GitOps engine itself — `GitRepository`/`OCIRepository`/`HelmRepository` sources, cluster settings and secrets, and the root `Kustomization`s. |
| [talos](./talos/README.md) | Talos Linux machine config and factory image customizations. |
| [templates](./templates) | Shared manifest templates used across apps. |

For the apps themselves, see [`apps/README.md`](./apps/README.md), which links to a
per-namespace README listing each app with a short description and a link to its manifest.
