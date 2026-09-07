# productivity

Personal productivity and self-hosted utilities.

Every app here has its PVCs backed up to MinIO via
[VolSync](../volsync-system/README.md). The one exception is BookStack's MariaDB datadir,
which is deliberately not replicated — a six-hourly logical dump is backed up instead. See
[the plan doc](../../../docs/plans/2026-09-07-vikunja-and-bookstack.md).

| App | Description | Manifest |
| --- | --- | --- |
| [bookstack](https://www.bookstackapp.com/) | Wiki: shelves → books → chapters → pages. Its own single MariaDB instance (datadir on `openebs-hostpath`, dumped to the NAS claim six-hourly), uploads and dumps sharing one RWX `nfs-csi` claim. | [ks.yaml](./bookstack/ks.yaml) |
| [forgejo](https://forgejo.org/) | Self-hosted git forge: repositories, issues, PRs, package registry. Own CNPG Postgres, shared dragonfly for cache/session/queue, repository tree on a static `Retain` NFS PV, git-over-SSH on its own LoadBalancer address. | [ks.yaml](./forgejo/ks.yaml) |
| [mealie](https://mealie.io/) | Recipe manager and meal planner (data on a static `Retain` NFS PV). | [ks.yaml](./mealie/ks.yaml) |
| [paperless](https://docs.paperless-ngx.com/) | Document archive: OCRs incoming scans and indexes them. Own CNPG Postgres, shared dragonfly broker, Gotenberg + Tika sidecars for Office/e-mail parsing, documents on a static `Retain` NFS PV. | [ks.yaml](./paperless/ks.yaml) |
| [vikunja](https://vikunja.io/) | Task manager: projects, tasks, due dates, labels, and a CalDAV endpoint under `/dav` that the household phones subscribe to. Own role on the shared CNPG Postgres, attachments on `nfs-csi`. | [ks.yaml](./vikunja/ks.yaml) |
| [wallos](https://github.com/ellite/Wallos) | Subscription and recurring-payment tracker. | [ks.yaml](./wallos/ks.yaml) |
