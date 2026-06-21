# apps

Every application reconciled onto the cluster by Flux, organized by namespace. Each app
follows the bjw-s pattern:

```text
kubernetes/apps/<namespace>/<app>/
├── ks.yaml                     # Flux Kustomization that points at app/
└── app/
    ├── helmrelease.yaml        # the HelmRelease (usually the app-template chart)
    └── kustomization.yaml      # resources for the app
```

Each `<namespace>/kustomization.yaml` lists its apps' `ks.yaml` files, and Flux walks
the tree from there. See each namespace's own `README.md` for the apps it contains.

| Namespace | Purpose |
| --- | --- |
| [actions-runner-system](./actions-runner-system/README.md) | Self-hosted GitHub Actions runners. |
| [cert-manager](./cert-manager/README.md) | TLS certificate issuance and renewal. |
| [database](./database/README.md) | PostgreSQL and Redis-compatible datastores. |
| [default](./default/README.md) | User-facing apps and home services. |
| [downloads](./downloads/README.md) | Media downloaders routed through the VPN. |
| [external-secrets](./external-secrets/README.md) | Syncs secrets from Bitwarden. |
| [flux-system](./flux-system/README.md) | Cluster-side Flux extensions (webhooks). |
| [games](./games/README.md) | Game servers. |
| [home-automation](./home-automation/README.md) | Smart-home / IoT apps. |
| [kube-system](./kube-system/README.md) | Core cluster components (DNS, CSI, metrics). |
| [media](./media/README.md) | Media libraries and servers. |
| [network-system](./network-system/README.md) | CNI and low-level pod networking. |
| [networking](./networking/README.md) | Ingress controllers and DNS. |
| [observability](./observability/README.md) | Metrics, logs, dashboards, monitoring. |
| [openebs-system](./openebs-system/README.md) | Local node-disk persistent storage. |
| [productivity](./productivity/README.md) | Personal productivity and utilities. |
| [security](./security/README.md) | Authentication, SSO (Authentik), and secrets management (OpenBao). |
| [storage](./storage/README.md) | Object storage (MinIO). |
| [system](./system/README.md) | Cluster-wide utilities and add-ons. |
| [system-upgrade](./system-upgrade/README.md) | Automated node OS upgrades. |
| [volsync-system](./volsync-system/README.md) | PVC backup/restore (VolSync + restic to MinIO). |
| [vpn](./vpn/README.md) | VPN egress gateway and DNS. |
