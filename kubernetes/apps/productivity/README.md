# productivity

Personal productivity and self-hosted utilities.

Every app here has its PVCs backed up to MinIO via
[VolSync](../volsync-system/README.md).

**Where household documentation goes.** Facts about a physical thing — model, serial,
warranty, manual, location, breaker — go in **Homebox**, one item each. Procedures — how
to fix it, how the network is laid out by role, the handover for whoever takes over the
house — go in **Outline**, linked from the item. Outline is exported weekly as markdown to
a fixed NAS path so it stays readable when the cluster is down. Real addresses and
credentials go in Bitwarden, never in either app's export path. See
[the plan doc](../../../docs/plans/2026-11-08-bookstack-to-outline-and-homebox.md).

| App | Description | Manifest |
| --- | --- | --- |
| [forgejo](https://forgejo.org/) | Self-hosted git forge: repositories, issues, PRs, package registry. Own CNPG Postgres, shared dragonfly for cache/session/queue, repository tree on a static `Retain` NFS PV, git-over-SSH on its own LoadBalancer address. | [ks.yaml](./forgejo/ks.yaml) |
| [homebox](https://homebox.software/) | House inventory: appliances and Z-Wave devices with warranty, manual, location and breaker fields, plus QR/asset-ID labels for the physical things. Own role on the shared CNPG Postgres, OIDC-only login, attachments on `nfs-csi`. | [ks.yaml](./homebox/ks.yaml) |
| [mealie](https://mealie.io/) | Recipe manager and meal planner (data on a static `Retain` NFS PV). | [ks.yaml](./mealie/ks.yaml) |
| [mygarage](https://github.com/homelabforge/mygarage) | Vehicle maintenance log: service visits, fuel and DEF fill-ups, reminders, tires and vehicle documents. Own role on the shared CNPG Postgres, uploads on `nfs-csi`. | [ks.yaml](./mygarage/ks.yaml) |
| [outline](https://www.getoutline.com/) | Knowledge base: procedures, runbooks, the household handover. Own role on the shared CNPG Postgres, shared dragonfly for queues, attachments on `nfs-csi`, OIDC-only login, MCP endpoint at `/mcp` for local agents. A weekly CronJob exports the whole wiki as markdown to a static NAS path (`outline-export`). | [ks.yaml](./outline/ks.yaml) |
| [paperless](https://docs.paperless-ngx.com/) | Document archive: OCRs incoming scans and indexes them. Own CNPG Postgres, shared dragonfly broker, Gotenberg + Tika sidecars for Office/e-mail parsing, documents on a static `Retain` NFS PV. | [ks.yaml](./paperless/ks.yaml) |
| [vikunja](https://vikunja.io/) | Task manager: projects, tasks, due dates, labels, and a CalDAV endpoint under `/dav` that the household phones subscribe to. Own role on the shared CNPG Postgres, attachments on `nfs-csi`. | [ks.yaml](./vikunja/ks.yaml) |
| [wallos](https://github.com/ellite/Wallos) | Subscription and recurring-payment tracker. | [ks.yaml](./wallos/ks.yaml) |
