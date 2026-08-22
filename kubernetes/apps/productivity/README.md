# productivity

Personal productivity and self-hosted utilities.

Every app here is backed up to MinIO via [VolSync](../volsync-system/README.md).

| App | Description | Manifest |
| --- | --- | --- |
| [forgejo](https://forgejo.org/) | Self-hosted git forge: repositories, issues, PRs, package registry. Own CNPG Postgres, shared dragonfly for cache/session/queue, repository tree on a static `Retain` NFS PV, git-over-SSH on its own LoadBalancer address. | [ks.yaml](./forgejo/ks.yaml) |
| [mealie](https://mealie.io/) | Recipe manager and meal planner (data on a static `Retain` NFS PV). | [ks.yaml](./mealie/ks.yaml) |
| [paperless](https://docs.paperless-ngx.com/) | Document archive: OCRs incoming scans and indexes them. Own CNPG Postgres, shared dragonfly broker, Gotenberg + Tika sidecars for Office/e-mail parsing, documents on a static `Retain` NFS PV. | [ks.yaml](./paperless/ks.yaml) |
| [wallos](https://github.com/ellite/Wallos) | Subscription and recurring-payment tracker. | [ks.yaml](./wallos/ks.yaml) |
