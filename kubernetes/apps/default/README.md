# default

User-facing applications and home services deployed to the `default` namespace.

> **This namespace holds persistent data, not just app deployments.** `immich` and
> `home-assistant` each run their own CNPG Postgres `Cluster` here, and most apps own NFS or
> local-disk PVCs (`zwave-js-ui` is even node-pinned to a USB Z-Wave stick via `hostPath`).
> Moving any of these to another namespace is a **data migration**, not a refactor — see the
> reorganization plan in [`docs/plans`](../../../docs/plans/2026-06-20-namespace-reorganization.md).

Some apps have moved to themed namespaces — calibre → [`media`](../media/README.md),
home-assistant-matter-hub → [`home-automation`](../home-automation/README.md), mealie + wallos
→ [`productivity`](../productivity/README.md).

Config PVCs here are backed up to MinIO via [VolSync](../volsync-system/README.md) (all but
immich, whose photos live on a `Retain` NFS PV; the CNPG databases back up separately via Barman).

| App | Description | Backup | Manifest |
| --- | --- | --- | --- |
| [esphome](https://esphome.io/) | Builds and manages firmware for ESP-based IoT devices. | VolSync | [ks.yaml](./esphome/ks.yaml) |
| [home-assistant](https://www.home-assistant.io/) | Home automation hub. | VolSync (config) + Barman (DB) | [ks.yaml](./home-assistant/ks.yaml) |
| [immich](https://immich.app/) | Self-hosted photo and video backup (server, microservices, and machine-learning components). | NFS `Retain` + Barman (DB) | [ks.yaml](./immich/ks.yaml) |
| [jellyfin](https://jellyfin.org/) | Media server for movies, shows, and music. | VolSync (config) | [ks.yaml](./jellyfin/ks.yaml) |
| [unifi](https://github.com/jacobalberty/unifi-docker) | Ubiquiti UniFi controller for wireless access points and home networking. | VolSync | [ks.yaml](./unifi/ks.yaml) |
| [zwave-js-ui](https://zwave-js.github.io/zwave-js-ui/) | Manages Z-Wave IoT devices over the Z-Wave wireless protocol. | VolSync | [ks.yaml](./zwave-js-ui/ks.yaml) |
